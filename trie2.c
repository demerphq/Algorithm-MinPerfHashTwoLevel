#include <stdint.h>
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"
#include <sys/mman.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <assert.h>
#include "mph2l.h"
#include "roundup.h"
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <stdio.h>
#include "trie2.h"

/* Part of this code implements a trie like data structure with 3 node
 * types, a mono type, managing the transition for a single codepoint,
 * a "small" state managing the transition for 3 codepoints, and a
 * full state managing the transition with more than 3 codepoints.
 * Any accepting state must be either "small" or "large".
 * mono states are represented by a "next pointer" and a "key", accounting
 * for 5 bytes, a small state takes 20 bytes, and a large state takes
 * 1028 bytes. Because a trie is a directed acyclic graph we can safely
 * upgrade nodes as we encounter them, so most nodes in the trie end up
 * being fairly efficiently used.
 *
 * We use this trie structure to implement a version of LZ compression
 * by implementing a dictionary that maps strings to ids in the dictionary.
 * We initialize the trie and our dictionary (virtually) such that the ids
 * 0-255 represent their relevant characters (essentially implementing identity)
 * and 256 represents the empty string. Our dictionary is represented during
 * compression by the state of the trie, and during decompression by a dictionary
 * of pairs of ids, the first of which is given the id 257.
 * We then consume our input stream using the trie to find the longest pair
 * of strings that are known (and can thus be mapped to a pair of ids), we
 * then "emit" the pair we found, and add the string that the codepair represents
 * to the trie, and continue.
 *
 * So for instance if the first string we compress starts with "AB" then
 * the first codepair entry (257) will be:
 *
 *      257: 65, 66
 *
 * and we would add a mapping of "AB" => 257 to the trie.
 *
 * If the string continued "ABAB" we would then emit:
 *
 *      258: 257, 257
 *
 * and we would add a mapping of "ABAB" => 258 to the trie.
 *
 * As we are encoding a set of strings and not a single stream of data we need
 * a mechanism to specify the end of string. We could use a specific codepoint for
 * this, and indeed normal compression occasionally requires the use of the virtual
 * empty string codepoint 256 as the last codepoint in the sequence to ensure that
 * the string is compressed into an even number of tokens, but adding a full on stop
 * code ends up reducing compression performance quite a bit. Instead we reserve a
 * single bit of the id space to denote that the codepoint is the last in a sequence.
 *
 * Thus if we encode "foo foo" we would get:
 *
 *    257: "f", "o"
 *    258: "o", " ",
 *    259: 257, "o"!
 *
 * where the exclamation point represents the stop bit. This means that if we decompress
 * codepair 257, 258, 259 when we decode the right hand element of 259 we would notice
 * the stop bit and not proceded to decode 260.
 *
 * This mechanism is complemented by adding all full strings we add to the dictionary
 * as compressed sequences of pairs also as a single token, and we use another bit for
 * this purpose. So lets say the next word compressed is "foo foo foo foo.", after adding
 * "foo foo" as a above, we would also have registered a mapping of "foo foo" to 257+, where
 * the + represents the "run to stop" flag. This would then mean "foo foo foo foo." would
 * compress as the following sequence (again using + and ! for the relevant flags).
 *
 *    260: 257+," "
 *    261: 257+,"."!
 *
 * And "foo foo foo foo." would be added to the dictionary as 260+. This process is repeated
 * for all the strings we have to compress, reducing each string down to a unique identifier.
 *
 * For code points 0 up to 1<<22-1 we use a 6 byte (2x24 bit) representation, after which
 * we switch to an 8 byte (2x32 bit) representation. Which gives us support for up to 2^30
 * codepairs in theory. If you wonder why we dont support smaller size representations, the
 * answer is that we only "waste" about 1<<16 bytes for the potentially shorter codepairs,
*  which is not enough to justify the complexiy and performance optimisations to eliminate
*  the wasted space. On the other hand, in my test data sets all of the compressed data
*  fit well under the 24 bit capacity, and the larger amount of "wasted" space justifies
*  using the 24/48 bit codepair representation.
 *
 */

U32
codepair_array_size(struct codepair_array *codepair_array) {
    return codepair_array->short_info.next * sizeof(struct short_codepair)
          + codepair_array->long_info.next * sizeof(struct long_codepair);
}

static inline
U32
grow_alloc(U32 v, U32 prealloc) {
    if (!v) {
        return prealloc;
    }
    else if (v < (1<<17)) {
        return (v << 1);
    }
    return v + (1<<17);
}

static inline
void
get_short_codepair(struct short_codepair *short_codepair, U32 *codea, U32 *codeb) {
    if (1) {
        /* load the 6 bytes into a single U64 register (hopefully), then split out
         * the low and high 24 bits */
        U64 recodeab= *((U64 *)short_codepair);
        *codea= recodeab & 0xFFFFFF;
        *codeb= (recodeab >> 24) & 0xFFFFFF;
    } else {
        *codea= (short_codepair->codea[0] <<  0)|
                (short_codepair->codea[1] <<  8)|
                (short_codepair->codea[2] << 16);

        *codeb= (short_codepair->codeb[0] <<  0)|
                (short_codepair->codeb[1] <<  8)|
                (short_codepair->codeb[2] << 16);
    }
}


void
set_short_codepair(struct short_codepair *short_codepair, const U32 codea, const U32 codeb) {
    short_codepair->codea[0]= ((codea >>  0) & 0xFF);
    short_codepair->codea[1]= ((codea >>  8) & 0xFF);
    short_codepair->codea[2]= ((codea >> 16) & 0xFF);

    short_codepair->codeb[0]= ((codeb >>  0) & 0xFF);
    short_codepair->codeb[1]= ((codeb >>  8) & 0xFF);
    short_codepair->codeb[2]= ((codeb >> 16) & 0xFF);
}


void
set_long_codepair(struct long_codepair *long_codepair, const U32 codea, const U32 codeb) {
    long_codepair->codea= codea;
    long_codepair->codeb= codeb;
}


void
get_long_codepair(struct long_codepair *long_codepair, U32  * const codea, U32 * const codeb) {
    *codea= long_codepair->codea;
    *codeb= long_codepair->codeb;
}



U32
append_long_codepair_array(struct codepair_array *codepair_array, const U32 codea, const U32 codeb) {
    U32 next= codepair_array->long_info.next++;
    if (codepair_array->long_info.next >= codepair_array->long_info.allocated) {
        U32 new_allocated= grow_alloc(codepair_array->long_info.allocated,PREALLOC_CODEPAIR);
        Renew(codepair_array->long_pairs, new_allocated, struct long_codepair);
        codepair_array->long_info.allocated= new_allocated;
    }
    set_long_codepair(codepair_array->long_pairs + next, codea, codeb);
    return next;
}

U32
append_short_codepair_array(struct codepair_array *codepair_array, const U32 codea, const U32 codeb) {
    U32 next= codepair_array->short_info.next++;
    if (codepair_array->short_info.next >= codepair_array->short_info.allocated) {
        U32 new_allocated= grow_alloc(codepair_array->short_info.allocated,PREALLOC_CODEPAIR);
        Renew(codepair_array->short_pairs, new_allocated, struct short_codepair);
        codepair_array->short_info.allocated= new_allocated;
    }
    set_short_codepair(codepair_array->short_pairs + next, codea, codeb);
    return next;
}

U32
append_codepair_array(struct codepair_array *codepair_array, const U32 codea, const U32 codeb) {
    U32 next= codepair_array->next_codepair_id++;
    if (next < MAX_SHORT_CODEPAIR_IDX) {
        append_short_codepair_array(codepair_array, codea, codeb);
    } else if (next < MAX_LONG_CODEPAIR_IDX) {
        append_long_codepair_array(codepair_array, codea, codeb);
    } else {
        croak("too many codepoints!");
    }
    return next;
}

static inline void
get_codepair_for_idx(struct codepair_array *codepair_array, U32 id, U32 * const codea, U32 * const codeb) {
    if (id < MAX_SHORT_CODEPAIR_IDX) {
        get_short_codepair(codepair_array->short_pairs + (id - FIRST_CODEPAIR_IDX), codea, codeb);
    } else {
        get_long_codepair(codepair_array->long_pairs + (id - MAX_SHORT_CODEPAIR_IDX), codea, codeb);
    }
}

U32
get_next_codepair_id(struct codepair_array *codepair_array) {
    return codepair_array->next_codepair_id;
}

U32
codepair_array_init(struct codepair_array *codepair_array) {
    Zero(codepair_array,1,struct codepair_array);
    Newxz(codepair_array->short_pairs,PREALLOC,struct short_codepair);
    codepair_array->short_info.allocated= PREALLOC;
    codepair_array->next_codepair_id= FIRST_CODEPAIR_IDX;
}

U32
codepair_array_freeze(struct codepair_array *codepair_array, struct codepair_array_frozen *frozen, U32 debug) {
    U32 short_bytes= codepair_array->short_info.next * sizeof(struct short_codepair);
    U32 long_bytes= codepair_array->long_info.next * sizeof(struct short_codepair);
    U32 bytes= sizeof(struct codepair_array_frozen) + short_bytes + long_bytes;

    if (frozen) {
        if (debug) {
            warn("|Compression needs %8u bytes %8u + %8u (%8u * %8u) + %8u (%8u * %8u)\n",
                bytes,
                (U32)sizeof(struct codepair_array_frozen),
                short_bytes,
                (U32)sizeof(struct short_codepair), codepair_array->short_info.next,
                long_bytes,
                (U32)sizeof(struct long_codepair), codepair_array->long_info.next
            );
            warn("|next_codepair_id= %8u\n", codepair_array->next_codepair_id);
            warn("|first_codepair_id= %8u\n", FIRST_CODEPAIR_IDX);

            warn("|codepair frozen=%p data=%p offset=%ld\n", frozen, frozen->data, frozen->data - (char *)frozen);
        }
        frozen->magic= 19720428;
        frozen->next_codepair_id= codepair_array->next_codepair_id;
        frozen->short_info_next= codepair_array->short_info.next;
        frozen->long_info_next= codepair_array->long_info.next;
        frozen->short_bytes= short_bytes;
        frozen->long_bytes= long_bytes;

        Copy((char *)(codepair_array->short_pairs), frozen->data, short_bytes, char);
        if (long_bytes)
            Copy((char *)codepair_array->long_pairs, frozen->data + short_bytes, long_bytes, char);
    }
    return bytes;
}

void
codepair_array_unfreeze(struct codepair_array *codepair_array, struct codepair_array_frozen *frozen) {
    Zero(codepair_array,1, struct codepair_array);
    codepair_array->frozen_source= frozen;
    if (frozen->magic != 19720428)
        croak("Bad magic in frozen codepair_array: %d", frozen->magic);

    codepair_array->next_codepair_id= frozen->next_codepair_id;
    codepair_array->short_info.next= frozen->short_info_next;
    codepair_array->long_info.next= frozen->long_info_next;

    codepair_array->short_pairs= (struct short_codepair *)frozen->data;
    if (frozen->long_info_next)
        codepair_array->long_pairs= (struct long_codepair *)(frozen->data + frozen->short_bytes);
    codepair_array->last_decode_cpid=-1;
}





U32
new_mono_state(struct trie *trie) {
    U32 idx= trie->mono_state_info.next;
    if (idx < trie->mono_state_info.last) {
        trie->mono_state_info.next= trie->mono_state_trans[idx];
        if(TRACE>1) warn("|new_mono_state => %8u reuse (last: %d alloc: %d)\n", idx,
                trie->mono_state_info.last, trie->mono_state_info.allocated);
    } else {
        trie->mono_state_info.next++;
        trie->mono_state_info.last++;
        if (trie->mono_state_info.last >= trie->mono_state_info.allocated) {
            croak("not enough space for new_small_state!");
        }
        if(TRACE>1) warn("|new_mono_state => %8u (last: %d alloc: %d)\n", idx,
                trie->mono_state_info.last, trie->mono_state_info.allocated);
    }
    trie->mono_state_trans[idx]= 0;
    trie->mono_state_keys[idx]= 0;
    trie->states++;
    return idx;
}


void
free_mono_state(struct trie *trie, U32 idx) {
    trie->mono_state_trans[idx]= trie->mono_state_info.next;
    trie->mono_state_keys[idx]= 0;
    trie->mono_state_info.next= idx;
    if(TRACE>1) warn("|free_mono_state => %8u\n", idx);
    trie->states--;
}


U32
new_small_state(struct trie *trie) {
    U32 idx= trie->small_state_info.next;
    if (idx < trie->small_state_info.last) {
        trie->small_state_info.next= trie->small_state[idx].value;
        if(TRACE>1) warn("|new_small_state => %8u reuse (last: %d alloc: %d)\n", idx,
                trie->small_state_info.last, trie->small_state_info.allocated);
    } else {
        trie->small_state_info.next++;
        trie->small_state_info.last++;
        if (trie->small_state_info.last >= trie->small_state_info.allocated) {
            croak("not enough space for new_small_state!");
        }
        if(TRACE>1) warn("|new_small_state => %8u (last: %d alloc: %d)\n", idx,
                trie->small_state_info.last, trie->small_state_info.allocated);

    }
    Zero(trie->small_state+idx,1,struct small_state);
    trie->states++;
    return idx;
}

void
free_small_state(struct trie *trie, U32 idx) {
    trie->small_state[idx].value= trie->small_state_info.next;
    trie->small_state_info.next= idx;
    trie->states--;
}

U32
new_full_state(struct trie *trie) {
    U32 idx= trie->full_state_info.next++;
    trie->full_state_info.last++;
    if (trie->full_state_info.last >= trie->full_state_info.allocated) {
        croak("not enough space for new_full_state!");
    }
    Zero(trie->full_state + idx, 1, struct full_state);
    trie->states++;
    if(TRACE>1) warn("|new_full_state => %8u (allocated: %8u)\n", idx, trie->full_state_info.allocated);
    return idx;
}

U32
upgrade_small_state(struct trie *trie, U32 idx) {
    U32 new_idx= new_full_state(trie);
    struct small_state *small= trie->small_state + idx;
    struct full_state *full= trie->full_state + new_idx;
    U32 i;
    for ( i = 0; i < small->key_count; i++) {
        full->trans[small->keys[i]]= small->trans[i];
    }
    full->value= small->value;
    free_small_state(trie, idx);
    if (TRACE>1) warn("|upgraded small %8u (%8u:%8u) => %8u (%8u:%8u)\n",
            STATE(CODE_SMALL,idx), CODE_SMALL, idx,
            STATE(CODE_FULL,new_idx), CODE_FULL, new_idx);
    return new_idx;
}

U32
upgrade_mono_state(struct trie *trie, U32 idx) {
    U32 new_idx= new_small_state(trie);
    struct small_state *small= trie->small_state + new_idx;

    small->keys[0]= trie->mono_state_keys[idx];
    small->trans[0]= trie->mono_state_trans[idx];
    small->key_count= 1;
    free_mono_state(trie, idx);
    if (TRACE>1) warn("|upgraded mono %8u (%8u:%8u) => %8u (%8u:%8u)\n",
            STATE(CODE_MONO,idx), CODE_MONO, idx,
            STATE(CODE_SMALL,new_idx), CODE_SMALL, new_idx);

    return new_idx;
}

void
trie_ensure_space( struct trie *trie, STRLEN len) {
    U32 mono_want= trie->mono_state_info.last + len;
    U32 small_want= trie->small_state_info.last + len;
    U32 full_want= trie->full_state_info.last + len;

    if (mono_want >= trie->mono_state_info.allocated) {
        U32 new_allocated= grow_alloc(mono_want,PREALLOC_MONO);
        Renew(trie->mono_state_keys, new_allocated, U8);
        Renew(trie->mono_state_trans, new_allocated, U32);
        trie->mono_state_info.allocated= new_allocated;
    }
    if (small_want >= trie->small_state_info.allocated) {
        U32 new_allocated= grow_alloc(small_want,PREALLOC_SMALL);
        Renew(trie->small_state, new_allocated, struct small_state);
        trie->small_state_info.allocated= new_allocated;
    }
    if (full_want >= trie->full_state_info.allocated) {
        U32 new_allocated= grow_alloc(full_want,PREALLOC_FULL);
        Renew(trie->full_state, new_allocated, struct full_state);
        trie->full_state_info.allocated= new_allocated;
    }
}

void
trie_insert(struct trie *trie, U8 *str, STRLEN len, U32 value, U32 debug) {
    U32 state= trie->first_state;

    U8 *str_end= str + len;
    U8 *str_ptr= str;
    U32 *state_src= NULL;
    U32 *rest= NULL;
    U32 idx;
    U32 code;
    U8 ch;
    if (TTRACE) warn("|trie_insert: '%.*s'\n", (int)len, str);
    trie_ensure_space(trie, len+1);

    while ( str_ptr < str_end ) {
        idx= GET_IDX(state);
        code= GET_CODE(state);
        ch= *str_ptr++;
        if (TTRACE) warn("|ins|a| state: %8u code: %-5s idx: %8u ch = '%c'\n", state, codes[code], idx, ch);

        switch (code) {
        case CODE_MONO: {
            if (trie->mono_state_keys[idx] == ch) {
                state_src= &trie->mono_state_trans[idx];
                state= trie->mono_state_trans[idx];
                break;
            } else {
                idx= upgrade_mono_state(trie,idx);
                code= CODE_SMALL;
                *state_src= state= STATE(code,idx);
                /* FALLTHROUGH */
            }
        }
        case CODE_SMALL:{
            struct small_state *small= trie->small_state + idx;
            U32 next_state= 0;
            switch (small->key_count & 0x3) {
                case 3: if(small->keys[2] == ch) { state_src= &small->trans[2]; next_state= small->trans[2]; break; }
                case 2: if(small->keys[1] == ch) { state_src= &small->trans[1]; next_state= small->trans[1]; break; }
                case 1: if(small->keys[0] == ch) { state_src= &small->trans[0]; next_state= small->trans[0]; break; }
                case 0: break;
            }
            if (next_state) {
                state= next_state;
                break;
            } else if (small->key_count < 3) {
                small->keys[small->key_count]= ch;
                state_src= &small->trans[small->key_count];
                small->key_count++;
                goto DONE;
            } else {
                idx= upgrade_small_state(trie,idx);
                code= CODE_FULL;
                *state_src= state= STATE(code,idx);
                /* FALLTHROUGH */
            }
        }
        case CODE_FULL: {
            struct full_state *full= trie->full_state + idx;
            U32 next_state= full->trans[ch];
            state_src= &full->trans[ch];
            if (next_state) {
                state= next_state;
                break;
            } else {
                goto DONE;
            }
        }
        case CODE_NONE:
            croak("CODE_NONE - trie_insert");
        }
    }
    DONE:
    for ( ; str_ptr < str_end; str_ptr++) {
        idx= new_mono_state(trie);
        *state_src= state= STATE(CODE_MONO,idx);
        ch= *str_ptr;
        if (TTRACE) warn("|ins|b| state: %8u code: %-5s idx: %8u ch = '%c'\n", state, codes[CODE_MONO], idx, ch);
        trie->mono_state_keys[idx]= ch;
        trie->mono_state_trans[idx]= 0;
        state_src= &trie->mono_state_trans[idx];
    }
    if (!*state_src) {
        idx= new_small_state(trie);
        code= CODE_SMALL;
        *state_src= state= STATE(code, idx);
        trie->small_state[idx].value= value;
        trie->accepting_states++;
        trie->str_len += len;
        if (TTRACE) warn("|store %d in %8u (%8u:%8u) (null case)\n", value, state, code, idx);
    } else {
        idx= GET_IDX(state);
        code= GET_CODE(state);
        if (TTRACE) warn("|ins|c| state: %8u code: %-5s idx: %8u accepting\n", state, codes[code], idx);

        switch (code) {
            case CODE_MONO: {
                idx= upgrade_mono_state(trie,idx);
                code= CODE_SMALL;
                *state_src= state= STATE(code,idx);
                /* FALLTHROUGH */
            }
            case CODE_SMALL: {
                struct small_state *small= trie->small_state + idx;
                if (!small->value) {
                    small->value = value;
                    trie->accepting_states++;
                    trie->str_len += len;
                }
                if (TRACE>1) warn("|store %d in %8u (%8u:%8u)\n", value, state, code, idx);
                break;
            }
            case CODE_FULL: {
                struct full_state *full= trie->full_state + idx;
                if (!full->value) {
                    full->value = value;
                    trie->accepting_states++;
                    trie->str_len += len;
                }
                break;
            }
            case CODE_NONE:
                croak("CODE_NONE - trie_insert final");
        }
    }
    if (trie->max_len < len)
        trie->max_len= len;
}

U32
trie_lookup_prefix(struct trie *trie, U8 *str, U8 *str_end, U32 *matched_len) {
    U32 state= trie->first_state;
    U32 next_state;

    U8 *str_ptr= str;
    U32 idx;
    U32 code;
    U8 ch;
    U32 value= CODEPAIR_ENCODE_IDX(0,EMPTY_CODEPAIR_IDX);
    *matched_len= 0;

    if (TRACE>1) warn("|fetch: '%*.*s'\n", (int)(str_end - str), (int)(str_end - str), str);

    for ( ; state && str_ptr < str_end; str_ptr++ ) {
        idx= GET_IDX(state);
        code= GET_CODE(state);
        ch= *str_ptr;
        next_state= 0;

        switch (code) {
            case CODE_MONO: {
                if (trie->mono_state_keys[idx] == ch)
                    next_state= trie->mono_state_trans[idx];
                break;
            }
            case CODE_SMALL:{
                struct small_state *small= trie->small_state + idx;
                if (small->value) {
                    *matched_len= str_ptr - str;
                    value= small->value;
                }
                switch (small->key_count & 0x3) {
                    case 3: if(small->keys[2] == ch) { next_state= small->trans[2]; break; }
                    case 2: if(small->keys[1] == ch) { next_state= small->trans[1]; break; }
                    case 1: if(small->keys[0] == ch) { next_state= small->trans[0]; break; }
                    case 0: break;
                }
                break;
            }
            case CODE_FULL: {
                struct full_state *full= trie->full_state + idx;
                if (full->value) {
                    *matched_len= str_ptr - str;
                    value= full->value;
                }
                next_state= full->trans[ch];
                break;
            }
            case CODE_NONE:
                croak("CODE_NONE main loop");
        }
        if (TRACE>1) warn("|lp| state: %8u code: %-5s idx: %8u ch = '%c' v = %8u ns = %8u\n", state, codes[code], idx, ch, value, next_state);
        state= next_state;
    }
    if (state) {
        idx= GET_IDX(state);
        code= GET_CODE(state);

        switch (code) {
            case CODE_MONO: break;
            case CODE_SMALL: {
                struct small_state *small= trie->small_state + idx;
                if (small->value) {
                    *matched_len= str_ptr - str;
                    value= small->value;
                }
                break;
            }
            case CODE_FULL: {
                struct full_state *full= trie->full_state + idx;
                if (full->value) {
                    *matched_len= str_ptr - str;
                    value= full->value;
                }
                break;
            }
            case CODE_NONE:
                croak("CODE_NONE");
        }
    }
    if (TRACE>1) warn("|lp| state: %8u code: %-5s idx: %8u v = %8u\n", state, codes[code], idx, value);
    return value;
}



#define HANDLE_VALUE(vexpr) do {                                            \
    if (vexpr) {                                                            \
        U32 codea_length= str_ptr - str;                                    \
        U32 codea= (vexpr);                                                 \
        U32 codeb_length;                                                   \
        U32 codeb;                                                          \
        U32 this_length;                                                    \
        if (TRACE>1) warn("|codea=%8u\n",codea);                           \
        codeb= trie_lookup_prefix(trie, str_ptr, str_end, &codeb_length);   \
        this_length= codea_length + codeb_length;                           \
        if ( this_length >= best_length ) {                                 \
            best_length= this_length;                                       \
            best_codea= codea;                                              \
            best_codeb= codeb;                                              \
            if (TRACE>1) warn("|codea= %8u codeb=%8u len:%8u (best)\n", codea, codeb, codea_length + codeb_length);\
        } else {                                                            \
            if (TRACE>1) warn("|codea= %8u codeb=%8u len:%8u\n",codea, codeb, codea_length + codeb_length);\
        }                                                                   \
    }                                                                       \
} while (0)

U32
trie_lookup_prefix2(struct trie *trie, U8 *str, U8 *str_end, U32 *codeb, U32 *pair_length) {
    U8 *str_ptr;
    struct small_state *small;
    struct full_state *full;
    U32 best_codea= CODEPAIR_ENCODE_IDX(0,EMPTY_CODEPAIR_IDX);
    U32 best_codeb= CODEPAIR_ENCODE_IDX(0,EMPTY_CODEPAIR_IDX);
    U32 best_length= 0;
    U32 state= trie->first_state;

    if (TRACE>1) {
        int len= str_end - str;
        warn("|trie_lookup_prefix2: '%.*s' (len:%8u)\n", len, str, len);
    }

    for ( str_ptr= str ; state && str_ptr < str_end; str_ptr++ ) {
        U32 idx= GET_IDX(state);
        U32 code= GET_CODE(state);
        U32 ch= *str_ptr;
        U32 next_state= 0;

        switch (code & 0x3) {
            case CODE_MONO:
                if (trie->mono_state_keys[idx] == ch)
                    next_state= trie->mono_state_trans[idx];
                break;
            case CODE_SMALL:
                small= trie->small_state + idx;
                HANDLE_VALUE(small->value);
                switch (small->key_count & 0x3) {
                    case 3: if(small->keys[2] == ch) { next_state= small->trans[2]; break; }
                    case 2: if(small->keys[1] == ch) { next_state= small->trans[1]; break; }
                    case 1: if(small->keys[0] == ch) { next_state= small->trans[0]; break; }
                    case 0: break;
                }
                break;
            case CODE_FULL:
                full= trie->full_state + idx;
                HANDLE_VALUE(full->value);
                next_state= full->trans[ch];
                break;
            case CODE_NONE:
                croak("CODE_NONE main loop");
                break;
        }
        if (TRACE>1) warn("|lup2| state: %8u code: %-5s idx: %8u ch: '%c' bca: %8u bcb: %8u bl: %8u ns: %8u\n",
                state, codes[code], idx, ch, best_codea, best_codeb, best_length, next_state);
        state= next_state;
    }
    if (state) {
        U32 idx= GET_IDX(state);
        U32 code= GET_CODE(state);
        switch (code & 0x3) {
            case CODE_MONO:
                break;
            case CODE_SMALL:
                small= trie->small_state + idx;
                HANDLE_VALUE(small->value);
                break;
            case CODE_FULL:
                full= trie->full_state + idx;
                HANDLE_VALUE(full->value);
                break;
            case CODE_NONE:
                croak("CODE_NONE");
                break;
        }
        if (TRACE>1) warn("|lup2| state: %8u code: %-5s idx: %8u bca: %8u bcb: %8u bl: %8u\n",
                state, codes[code], idx, best_codea, best_codeb, best_length);
    }
    if (TRACE>1) warn("|lup2| return %8u.%8u len:%8u\n", best_codea, best_codeb, best_length);
    *codeb= best_codeb;
    *pair_length= best_length;
    return best_codea;
}



void
trie_init( struct trie *trie) {
    U8 init_buf[2]= {0,0};
    U32 i;
    Zero(trie,1,struct trie);

    Newxz(trie->mono_state_keys,PREALLOC_MONO, U8);
    Newxz(trie->mono_state_trans,PREALLOC_MONO, U32);
    trie->mono_state_info.allocated= PREALLOC_MONO;

    Newxz(trie->small_state, PREALLOC_SMALL, struct small_state);
    trie->small_state_info.allocated= PREALLOC_SMALL;

    Newxz(trie->full_state, PREALLOC_FULL, struct full_state);
    trie->full_state_info.next= 1;
    trie->full_state_info.last= 1;
    trie->full_state_info.allocated= PREALLOC_FULL;
    trie->states= 1;

    trie->first_state= SHIFT_CODE(CODE_FULL);
    for (i=0; i<=255; i++) {
        init_buf[0]= i;
        trie_insert(trie, init_buf, 1, CODEPAIR_ENCODE_IDX(0,i), 0);
    }
}

void
trie_free( struct trie *trie) {
    Safefree(trie->mono_state_keys);
    Safefree(trie->mono_state_trans);
    Safefree(trie->small_state);
    Safefree(trie->full_state);
    Zero(trie,1,struct trie);
}

void
codepair_array_free( struct codepair_array *codepair_array) {
    if (codepair_array->long_pairs)
        Safefree(codepair_array->long_pairs);
    if (codepair_array->short_pairs)
        Safefree(codepair_array->short_pairs);
    Zero(codepair_array,1,struct codepair_array);
}


char *
u8_as_str(U8 *str, U8 cp) {
    if (cp>=32 && cp < 128) {
        sprintf(str,"'%c'",cp);
    } else {
        sprintf(str,"%8u",cp);
    }
    return str;
}

U8 key_str[5]= {0,0,0,0,0};
void
trie_dump( struct trie *trie, U32 state, U32 depth) {
    U32 i;
    if (!depth) {
        warn("|TRIE first_state: %8u states: %8u accepting_states: %8u max_len: %8u str_len: %8u\n",
                trie->first_state, trie->states, trie->accepting_states, trie->max_len, trie->str_len);
    }
    while (state) {
        U32 code= GET_CODE(state);
        U32 idx= GET_IDX(state);
        warn("||%*sstate: %8u code: %-5s idx: %8u - ",depth,"",state,codes[code],idx);
        switch (code & 0x3) {
            case CODE_NONE: warn("|NONE\n");
                return;
            case CODE_MONO:
                warn("|MONO key= %s\n", u8_as_str(key_str,trie->mono_state_keys[idx]));
                state= trie->mono_state_trans[idx];
                depth++;
                break;
            case CODE_SMALL: {
                struct small_state *small= trie->small_state + idx;
                warn("|SMALL keys=%8u value=%8u\n", small->key_count, small->value);
                for (i=0; i < small->key_count; i++) {
                    warn("||%*skey= %s\n",depth+1,"",u8_as_str(key_str,small->keys[i]));
                    if (small->trans[i])
                        trie_dump(trie, small->trans[i], depth+1);
                }
                return;
            }
            case CODE_FULL: {
                struct full_state *full= trie->full_state + idx;
                warn("|FULL value=%d\n", full->value);
                for (i= 0; i < (1<<8); i++) {
                    if (full->trans[i]) {
                        warn("||%*skey= %s\n",depth+1, "", u8_as_str(key_str,i));
                        trie_dump(trie, full->trans[i], depth+1);
                    }
                }
                return;
            }
        }
    }
}

U32
compressor_init(struct compressor *compressor) {
    Zero(compressor,1, struct compressor);
    trie_init(&(compressor->trie));
    codepair_array_init(&(compressor->codepair_array));
}

U32
compressor_free(struct compressor *compressor) {
    trie_free(&(compressor->trie));
    codepair_array_free(&(compressor->codepair_array));
}

U32
compress_string(struct compressor *compressor, U8 *str, STRLEN len) {
    struct trie *trie= &(compressor->trie);
    struct codepair_array *codepair_array= &(compressor->codepair_array);
    U32 codea,codeb,newcode,matched_len;
    U8 *str_ptr= str;
    U8 *str_end= str + len;
    U8 *new_str_ptr;
    U32 first_codepair_id= get_next_codepair_id(codepair_array);
    U32 next_codepair_id= first_codepair_id;
    U32 codeb_is_empty;
    if (!len) {
        return CODEPAIR_ENCODE_IDX(0,EMPTY_CODEPAIR_IDX);
    } else if (len==1) {
        return CODEPAIR_ENCODE_IDX(0,*str);
    }
    while (str_ptr < str_end) {
        codea= trie_lookup_prefix2(trie, str_ptr, str_end, &codeb, &matched_len);
        codeb_is_empty= (CODEPAIR_IDX(codeb) == EMPTY_CODEPAIR_IDX);
        if ( codeb_is_empty && (first_codepair_id == next_codepair_id) ) {
            return codea;
        }
        new_str_ptr= str_ptr + matched_len;
        if ( new_str_ptr >= str_end )
            codeb |= CODEPAIR_STOP_FLAG;
        newcode= append_codepair_array(codepair_array, codea, codeb);
        if (TRACE>1) {
            warn("|>>> %10u => %10u%s %10u%s l: %4u '%.*s'%s\n",
                newcode,
                CODEPAIR_IDX(codea), CODEPAIR_ID_IS_MULTI(codea) ? "+" : " ",
                CODEPAIR_IDX(codeb), (CODEPAIR_ID_IS_MULTI(codeb) && CODEPAIR_ID_IS_STOP(codeb)) ? "+." :
                                      CODEPAIR_ID_IS_MULTI(codeb)                    ? "+ " :
                                      CODEPAIR_ID_IS_STOP(codeb)                     ? ". " : "  ",
                matched_len,
                matched_len, str_ptr,
                CODEPAIR_ID_IS_STOP(codeb) ? "|" : "");
        }
        if ( !codeb_is_empty )
            trie_insert(trie, str_ptr, matched_len, CODEPAIR_ENCODE_IDX(0,newcode), 1);
        str_ptr= new_str_ptr;
        next_codepair_id++;
    }
    if (next_codepair_id - first_codepair_id > 1)
        trie_insert(trie, str, len, CODEPAIR_ENCODE_IDX(CODEPAIR_MULTI_FLAG,first_codepair_id), 1);
    return CODEPAIR_ENCODE_IDX(CODEPAIR_MULTI_FLAG,first_codepair_id);
}

#define APPEND_CPIDX(id, idx, buf, buf_end) STMT_START {        \
    if (idx < EMPTY_CODEPAIR_IDX) {                             \
        if (TRACE>1) warn("|%*s id: %8u idx: %8u append '%c'\n", depth,"", id, idx, idx);\
        **buf= idx;                                             \
        buf[0]++;                                               \
    }                                                           \
} STMT_END

#define DECODE_CPID(id, buf, buf_end) STMT_START {              \
    U32 idx= CODEPAIR_IDX(id);                                  \
    if (idx <= EMPTY_CODEPAIR_IDX) {                            \
        APPEND_CPIDX(id, idx, buf, buf_end);                    \
    } else {                                                    \
        (void)decode_cpid_recursive(aTHX_ codepair_array, id, buf, buf_end, depth+1); \
    }                                                           \
} STMT_END

char *
decode_cpid_recursive(pTHX_ struct codepair_array *codepair_array, U32 code, char **buf, char *buf_end, int depth) {
    char *buf_start= *buf;
    while (*buf < buf_end) {
        U32 idx= CODEPAIR_IDX(code);
        if (TRACE)
            warn("|%*s-code: %8u idx: %8u\n", depth, "", code, idx);
        if (idx <= EMPTY_CODEPAIR_IDX) {
            APPEND_CPIDX(code, idx, buf, buf_end);
            break;
        }
        else
        if (idx > codepair_array->next_codepair_id) {
            croak("idx overflow in decode_cpid_recursive, got code: %u idx: %u max_idx= %u",
                    code, idx, codepair_array->next_codepair_id);
        }
        else {
            U32 codea, codeb;

            if (CODEPAIR_ID_IS_MULTI(code)) {
                do {
                    get_codepair_for_idx(codepair_array, idx, &codea, &codeb);
                    if (TRACE) {
                        code= CODEPAIR_ENCODE_IDX(0,idx);
                        warn("|%*s+code: %8u idx: %8u => codea: %8u (%8u) codeb: %8u (%8u)\n",
                                depth, "", code, idx, codea, CODEPAIR_IDX(codea), codeb, CODEPAIR_IDX(codeb));
                    }
                    DECODE_CPID(codea,buf,buf_end);
                    DECODE_CPID(codeb,buf,buf_end);
                    idx++;
                } while (!CODEPAIR_ID_IS_STOP(codeb));
                break;
            } else {
                get_codepair_for_idx(codepair_array, idx, &codea, &codeb);
                if (TRACE)
                    warn("|%*s code: %8u idx: %8u => codea: %8u (%8u) codeb: %8u (%8u)\n",
                            depth, "", code, idx, codea, CODEPAIR_IDX(codea), codeb, CODEPAIR_IDX(codeb));
                DECODE_CPID(codea,buf,buf_end);
                code= codeb;
                /* continue */
            }
        }
    }
    if (TRACE && depth == 0)
        warn("|\n");
    return buf_start;
}

#define DECODE_CPID_STACK(code) STMT_START {                    \
    U32 idx= CODEPAIR_IDX(code);                                \
    if (idx <= EMPTY_CODEPAIR_IDX) {                            \
        APPEND_CPIDX(code, idx, buf, buf_end);                  \
    } else {                                                    \
        (void)decode_cpid_recursive_stack(aTHX_ codepair_array, code, buf, buf_end, depth+1); \
    }                                                           \
} STMT_END

#define MAX_CODESTACK 32
char *
decode_cpid_recursive_stack(pTHX_ struct codepair_array *codepair_array, U32 code, char **buf, char *buf_end, int depth) {
    char *buf_start= *buf;
    U32 stack[MAX_CODESTACK];
    int top= 0;
    stack[top]= code;
    U32 idx;

    while (top >= 0 && *buf < buf_end) {
        code= stack[top--];

        new_code:
        idx= CODEPAIR_IDX(code);
        if (TRACE)
            warn("|%*s-code: %8u idx: %8u\n", depth, "", code, idx);
        if (idx <= EMPTY_CODEPAIR_IDX) {
            APPEND_CPIDX(code, idx, buf, buf_end);
        }
        else
#if 0
        if (idx > codepair_array->next_codepair_id) {
            croak("idx overflow in decode_cpid_recursive, got code: %u idx: %u max_idx= %u",
                    code, idx, codepair_array->next_codepair_id);
        }
        else
#endif
        if (CODEPAIR_ID_IS_MULTI(code)) {
            U32 codea, codeb;
            do {
                get_codepair_for_idx(codepair_array, idx, &codea, &codeb);
                if (TRACE) {
                    code= CODEPAIR_ENCODE_IDX(0,idx);
                    warn("|%*s+code: %8u idx: %8u => codea: %8u (%8u) codeb: %8u (%8u)\n",
                            depth, "", code, idx, codea, CODEPAIR_IDX(codea), codeb, CODEPAIR_IDX(codeb));
                }
                DECODE_CPID_STACK(codea);
                DECODE_CPID_STACK(codeb);
                idx++;
            } while (!CODEPAIR_ID_IS_STOP(codeb));
        }
        else {
            top++;
            if (top>=MAX_CODESTACK) {
                U32 codea;
                top--;
                if (TRACE) warn("|stack overflow - recursing");
                get_codepair_for_idx(codepair_array, idx, &codea, &code );
                DECODE_CPID_STACK(codea);
            } else {
                get_codepair_for_idx(codepair_array, idx, &code, stack + top);
            }
            goto new_code;
        }
    }
    if (TRACE && depth == 0)
        warn("|\n");
    return buf_start;
}


char *
decode_cpid_len_into_sv(pTHX_ struct codepair_array *codepair_array, U32 id, U32 len, SV *sv) {
    char *pvc;
    sv_grow(sv,len);
    SvCUR_set(sv,len);
    SvPOK_on(sv);
    pvc= SvPV_nomg_nolen(sv);
    /* note - after this call pvc no longer points at the start of the string - it points at the end */
    return decode_cpid_recursive_stack(aTHX_ codepair_array, id, &pvc, pvc + len, 0);
}


#define CPIDX_CMP(id, idx, buf, buf_end) STMT_START {       \
    if (idx < EMPTY_CODEPAIR_IDX) {                         \
        ret= **buf - idx;                                   \
        if (TRACE>1) warn("|%*s id: %8u idx: %8u append '%c'\n", depth,"", id, idx, idx);\
        if (ret)                                            \
            goto eq_done;                                   \
        else                                                \
            buf[0]++;                                       \
    }                                                       \
} STMT_END

#define CPID_CMP_PV_STACK(code) STMT_START {                    \
    U32 idx= CODEPAIR_IDX(code);                                \
    if (idx <= EMPTY_CODEPAIR_IDX) {                            \
        CPIDX_CMP(code, idx, buf, buf_end);                     \
    } else {                                                    \
        ret= cpid_cmp_pv_recursive_stack(aTHX_ codepair_array, code, buf, buf_end, depth+1); \
        if (ret) goto eq_done;                                  \
    }                                                           \
} STMT_END

#define MAX_CODESTACK 32
int
cpid_cmp_pv_recursive_stack(pTHX_ struct codepair_array *codepair_array, U32 code, char **buf, char *buf_end, int depth) {
    char *buf_start= *buf;
    U32 stack[MAX_CODESTACK];
    int top= 0;
    stack[top]= code;
    U32 idx;
    int ret= 0;

    while (top >= 0 && *buf < buf_end) {
        code= stack[top--];

        new_code:
        idx= CODEPAIR_IDX(code);
        if (TRACE)
            warn("|%*s-code: %8u idx: %8u\n", depth, "", code, idx);
        if (idx <= EMPTY_CODEPAIR_IDX) {
            CPIDX_CMP(code, idx, buf, buf_end);
        }
        else
#if 0
        if (idx > codepair_array->next_codepair_id) {
            croak("idx overflow in decode_cpid_recursive, got code: %u idx: %u max_idx= %u",
                    code, idx, codepair_array->next_codepair_id);
        }
        else
#endif
        if (CODEPAIR_ID_IS_MULTI(code)) {
            U32 codea, codeb;
            do {
                get_codepair_for_idx(codepair_array, idx, &codea, &codeb);
                if (TRACE) {
                    code= CODEPAIR_ENCODE_IDX(0,idx);
                    warn("|%*s+code: %8u idx: %8u => codea: %8u (%8u) codeb: %8u (%8u)\n",
                            depth, "", code, idx, codea, CODEPAIR_IDX(codea), codeb, CODEPAIR_IDX(codeb));
                }
                CPID_CMP_PV_STACK(codea);
                CPID_CMP_PV_STACK(codeb);
                idx++;
            } while (!CODEPAIR_ID_IS_STOP(codeb));
        }
        else {
            top++;
            if (top>=MAX_CODESTACK) {
                U32 codea;
                top--;
                if (TRACE) warn("|stack overflow - recursing");
                get_codepair_for_idx(codepair_array, idx, &codea, &code );
                CPID_CMP_PV_STACK(codea);
            } else {
                get_codepair_for_idx(codepair_array, idx, &code, stack + top);
            }
            goto new_code;
        }
    }
    eq_done:
    if (TRACE && depth == 0)
        warn("|\n");
    return ret;
}

