#ifndef _TRIE2_H
#define _TRIE2_H
#include <stdint.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <stdio.h>

#define TRACE 0
#define TTRACE (TRACE>1 && debug)

#define CODE_NONE   0
#define CODE_MONO   1
#define CODE_SMALL  2
#define CODE_FULL   3

static const char *codes[4]={
    "NONE",
    "MONO",
    "SMALL",
    "FULL"
};

#if 0
#define U8 uint8_t
#define I32 int32_t
#define U32 uint32_t
#define STRLEN uint32_t
#define Zero(p,count,type) bzero((p), (count) * sizeof(type))
#define Renew(p,count,type) (p)= realloc((p), (count) * sizeof(type))
#define Newxz(p,count,type) (p)= calloc((count), sizeof(type))
#define STR_WITH_LEN(s) "" s "", sizeof(s)-1
#define croak(x) do {   \
    warn(x "\n");     \
    exit(1);            \
} while (0)

#endif

#define TOP_BITS 30
#define IDX_MASK ((1<<TOP_BITS)-1)
#define SHIFT_CODE(x) ((x) << TOP_BITS)
#define GET_CODE(x) ((x) >> TOP_BITS)
#define GET_IDX(x) ((x) & IDX_MASK)
#define STATE(code,idx) (SHIFT_CODE(code) | idx)
#define PREALLOC        (1<<16)
#define PREALLOC_MONO   (1<<16)
#define PREALLOC_SMALL  (1<<10)
#define PREALLOC_LARGE  (1<<10)

#define CODEPAIR_STOP_FLAG                  (1<<0)
#define CODEPAIR_MULTI_FLAG                 (1<<1)
#define CODEPAIR_FLAGS                      2
#define CODEPAIR_FLAG_MASK                  ((1<<CODEPAIR_FLAGS)-1)
#define CODEPAIR_IDX(id)                    (id >> CODEPAIR_FLAGS)
#define CODEPAIR_ID_IS_MULTI(id)            (id & CODEPAIR_MULTI_FLAG)
#define CODEPAIR_ID_IS_STOP(id)             (id & CODEPAIR_STOP_FLAG)
#define CODEPAIR_ENCODE_IDX(flags,idx)      ((idx << CODEPAIR_FLAGS) | (flags & CODEPAIR_FLAG_MASK))
#define MAX_SHORT_CODEPAIR_IDX              ((1<<(24-CODEPAIR_FLAGS))-1)
#define MAX_LONG_CODEPAIR_IDX               ((1<<(32-CODEPAIR_FLAGS))-1)
#define EMPTY_CODEPAIR_IDX                  256
#define FIRST_CODEPAIR_IDX                  257
#define NUM_SHORT_CODEPAIRS                 ((MAX_SHORT_CODEPAIR_IDX+1)-FIRST_CODEPAIR_IDX)
#define SHORT_CODEPAIR_BYTES                (NUM_SHORT_CODEPAIRS*sizeof(struct short_codepair))
#define SHORT_CODEPAIR_BYTES_PADDED         ( (SHORT_CODEPAIR_BYTES % 8) \
                                              ? SHORT_CODEPAIR_BYTES + (8-(SHORT_CODEPAIR_BYTES % 8)) \
                                              : SHORT_CODEPAIR_BYTES )

struct full_state {
    U32 trans[1 << 8];
    U32 value;
};

struct small_state {
    U8 key_count;
    U8 keys[3];
    U32 trans[3];
    U32 value;
};

struct buf_info {
    U32 allocated;
    U32 last;
    U32 next;
};

struct trie {
    U32 first_state;
    U32 accepting_states;
    U32 max_len;
    U32 states;
    U32 str_len;

    U8  *mono_state_keys;
    U32 *mono_state_trans;
    struct buf_info mono_state_info;

    struct small_state *small_state;
    struct buf_info small_state_info;

    struct full_state *full_state;
    struct buf_info full_state_info;
};

struct short_codepair {
    U8 codea[3];
    U8 codeb[3];
};

struct long_codepair {
    U32 codea;
    U32 codeb;
};

struct codepair_array_frozen {
    U32 magic;
    U32 next_codepair_id;
    U32 short_info_next;
    U32 long_info_next;
    U32 short_bytes;
    U32 long_bytes;
    char data[0];
};

struct codepair_array {
    U32 next_codepair_id;
    struct buf_info short_info;
    struct buf_info long_info;
    struct short_codepair *short_pairs;
    struct long_codepair *long_pairs;
    struct codepair_array_frozen *frozen_source;
    IV last_decode_cpid;
};

struct compressor {
    struct codepair_array codepair_array;
    struct trie trie;
};

U32 codepair_array_size(struct codepair_array *codepair_array);
U32 grow_alloc(U32 v);
void set_short_codepair(struct short_codepair *short_codepair, const U32 codea, const U32 codeb);
void set_long_codepair(struct long_codepair *long_codepair, const U32 codea, const U32 codeb);
static inline void get_short_codepair(struct short_codepair *short_codepair, U32 *codea, U32 *codeb);
static inline void get_long_codepair(struct long_codepair *long_codepair, U32  * const codea, U32 * const codeb);
static inline void get_codepair_for_idx(struct codepair_array *codepair_array, U32 id, U32 * const codea, U32 * const codeb);

U32 append_long_codepair_array(struct codepair_array *codepair_array, const U32 codea, const U32 codeb);
U32 append_short_codepair_array(struct codepair_array *codepair_array, const U32 codea, const U32 codeb);
U32 append_codepair_array(struct codepair_array *codepair_array, const U32 codea, const U32 codeb);
U32 get_next_codepair_id(struct codepair_array *codepair_array);
U32 codepair_array_init(struct codepair_array *codepair_array);
U32 codepair_array_freeze(struct codepair_array *codepair_array, struct codepair_array_frozen *frozen, U32 debug);
void codepair_array_unfreeze(struct codepair_array *codepair_array, struct codepair_array_frozen *frozen);
U32 new_mono_state(struct trie *trie);
void free_mono_state(struct trie *trie, U32 idx);
U32 new_small_state(struct trie *trie);
void free_small_state(struct trie *trie, U32 idx);
U32 new_full_state(struct trie *trie);
U32 upgrade_small_state(struct trie *trie, U32 idx);
U32 upgrade_mono_state(struct trie *trie, U32 idx);
void trie_ensure_space( struct trie *trie, STRLEN len);
void trie_insert(struct trie *trie, U8 *str, STRLEN len, U32 value, U32 debug);
U32 trie_lookup_prefix(struct trie *trie, U8 *str, U8 *str_end, U32 *matched_len);
U32 trie_lookup_prefix2(struct trie *trie, U8 *str, U8 *str_end, U32 *codeb, U32 *pair_length);
void trie_init( struct trie *trie);
void trie_free( struct trie *trie);
void codepair_array_free( struct codepair_array *codepair_array);
char * u8_as_str(U8 *str, U8 cp);
void trie_dump( struct trie *trie, U32 state, U32 depth);
U32 compressor_init(struct compressor *compressor);
U32 compressor_free(struct compressor *compressor);
U32 compress_string(struct compressor *compressor, U8 *str, STRLEN len);

char * decode_cpid_recursive(pTHX_ struct codepair_array *codepair_array, U32 id, char **buf, char *buf_end, int depth);
char * decode_cpid_len_into_sv(pTHX_ struct codepair_array *codepair_array, U32 id, U32 len, SV *sv);
int cpid_eq_sv(pTHX_ struct codepair_array *codepair_array, U32 id, U32 len, SV *sv);

#endif

