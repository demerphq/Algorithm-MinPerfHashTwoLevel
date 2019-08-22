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

#define DEBUGF 0
#define FAST_SV_CONSTRUCT 0

MPH_STATIC_INLINE void
sv_set_utf8_flags(pTHX_ SV *sv, const U32 idx, const U8 *flags, const U32 bits, const U8 utf8_default, const U8 utf8_default_shift) {
    U8 is_utf8;
    if (utf8_default) {
        is_utf8= utf8_default >> utf8_default_shift;
    } else {
        GETBITS(is_utf8,flags,idx,bits);
    }
    if (is_utf8) {
        if (is_utf8 > 1)
            sv_utf8_upgrade(sv);
        else
            SvUTF8_on(sv);
    }
    else
    {
        SvUTF8_off(sv);
    }
}



MPH_STATIC_INLINE void
sv_set_from_bucket_extra(pTHX_ SV *sv, U8 *strs, const U32 ofs, const U32 len, const U32 idx, const U8 *flags, const U32 bits, const U8 utf8_default, const U8 utf8_default_shift, const int fast) {
    U8 *ptr;
    U8 is_utf8;
    if (ofs) {
        ptr= (strs) + (ofs);
    } else {
        ptr= 0;
        is_utf8= 0;
    }
    /* note that sv_setpvn() will cause the sv to
     * become undef if ptr is 0 */
    if (fast && ptr && is_utf8 < 1) {
        if (!SvOK(sv)) {
            sv_upgrade(sv,SVt_PV);
            SvLEN_set(sv,0);
            SvPOK_on(sv);
            SvREADONLY_on(sv);
        }
        if (SvLEN(sv)==0) {
            SvPV_set(sv,ptr);
            SvCUR_set(sv,len);
        } else {
            sv_setpvn((sv),ptr,len);
        }
    } else {
        sv_setpvn((sv),ptr,len);
    }
    if (ptr)
        sv_set_utf8_flags(sv, idx, flags, bits, utf8_default, utf8_default_shift);
}

void
sv_set_from_str_len_idx( pTHX_ SV *got_sv, struct mph_header *mph, const U32 bucket_idx, const U32 str_len_idx ) {
    U8 *strs= STR_BUF_PTR(mph);
    U8 *key_flags= KEY_FLAGS_PTR(mph);
    struct str_len *str_len= STR_LEN_PTR(mph);

    U8 utf8_flags= mph->utf8_flags;
    str_len+=str_len_idx;

    sv_set_from_bucket_extra(aTHX_ got_sv, strs, str_len->ofs, str_len->len, bucket_idx, key_flags,
        2, utf8_flags & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT, FAST_SV_CONSTRUCT);
}

MPH_STATIC_INLINE void
sv_set_from_bucket(pTHX_ SV *sv, U8 *strs, const U32 ofs, const U32 len, const U32 idx, const U8 *flags, const U32 bits, const U8 utf8_default, const U8 utf8_default_shift) {
    sv_set_from_bucket_extra(aTHX_ sv, strs, ofs, len, idx, flags,bits, utf8_default, utf8_default_shift, 0);
}

void
triple_set_val(pTHX_ struct mph_obj *obj, struct mph_triple_bucket *bucket, U32 bucket_idx, SV *val_sv) {
    struct codepair_array *codepair_array= &obj->codepair_array;
    struct mph_header *mph= obj->header;
    struct str_len *str_len= STR_LEN_PTR(mph);
    U8 utf8_flags= obj->header->utf8_flags;
    U32 ofs;
    I32 len;

    if (!bucket) {
        struct mph_header *mph= obj->header;
        bucket= (struct mph_triple_bucket *)((char *)mph + mph->table_ofs);
        bucket += bucket_idx;
    }
    str_len += bucket->v_idx;
    ofs= str_len->ofs;
    len= str_len->len;

    if (len < 0) {
        len= -len;
        //warn("|calling decode_cpid(%u) len=%u v_idx=%u", ofs, len, bucket->v_idx);
        //FIXME: XXX: set utf8 flags properly
        decode_cpid_len_into_sv(aTHX_ codepair_array, ofs, len, val_sv);
        sv_set_utf8_flags(aTHX_ val_sv,
                            bucket_idx, VAL_FLAGS_PTR(mph), 1,
                            utf8_flags & MPH_VALS_ARE_SAME_UTF8NESS_MASK, MPH_VALS_ARE_SAME_UTF8NESS_SHIFT);
    } else {
        U8 *strs= (U8 *)mph + mph->str_buf_ofs;
        sv_set_from_bucket(aTHX_ val_sv, strs, ofs, len,
                            bucket_idx, VAL_FLAGS_PTR(mph), 1,
                            utf8_flags & MPH_VALS_ARE_SAME_UTF8NESS_MASK, MPH_VALS_ARE_SAME_UTF8NESS_SHIFT);
    }
}


MPH_STATIC_INLINE void
triple_set_key_fast(pTHX_ struct codepair_array *codepair_array, char *strs, char *key_flags, U32 ofs, I32 len, U32 bucket_idx, SV *key_sv, U8 utf8_flags) {
    if (len < 0) {
        len= -len;
        decode_cpid_len_into_sv(aTHX_ codepair_array, ofs, len, key_sv);
        sv_set_utf8_flags(aTHX_ key_sv,
                            bucket_idx, key_flags, 1,
                            utf8_flags & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT);
    } else {
        sv_set_from_bucket(aTHX_ key_sv, strs, ofs, len,
                            bucket_idx, key_flags, 1,
                            utf8_flags & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT);
    }
}

void
triple_set_key(pTHX_ struct mph_obj *obj, U32 str_len_idx, struct mph_triple_bucket *bucket, U32 bucket_idx, SV *key_sv) {
    struct mph_header *mph= obj->header;
    struct str_len *str_len= STR_LEN_PTR(mph);
    U32 ofs= str_len[str_len_idx].ofs;
    I32 len= str_len[str_len_idx].len;
    U8 utf8_flags= mph->utf8_flags;
    struct codepair_array *codepair_array= &obj->codepair_array;

    triple_set_key_fast(aTHX_ codepair_array, STR_BUF_PTR(mph), KEY_FLAGS_PTR(mph), ofs, len, bucket_idx, key_sv, utf8_flags);
}


/* returns 1 if the string in l_sv starts with the string in r_sv */
MPH_STATIC_INLINE
I32
_sv_prefix_cmp3(pTHX_ SV *l_sv, SV *r_sv, SV *r_sv_utf8) {
    STRLEN l_len;
    STRLEN r_len;
    STRLEN min_len;
    char *l_pv;
    char *r_pv;
    I32 cmp;
    if (SvUTF8(l_sv)) {
        /* left side is utf8, so use the r_sv_utf8 which should always be there */
        r_pv= SvPV_nomg(r_sv_utf8,r_len);
    } else {
        /* left side is not utf8, so use the r_sv, but if it is NULL then the RHS cannot
         * be downgraded to latin1. Which means we need to upgrade the lhs first. */
        if (r_sv) {
            /* we have a r_sv, so we can use the downgraded form. */
            r_pv= SvPV_nomg(r_sv,r_len);
        } else {
            sv_utf8_upgrade(l_sv);
            r_pv= SvPV_nomg(r_sv_utf8,r_len);
        }
    }
    l_pv= SvPV_nomg(l_sv,l_len);
    min_len = l_len < r_len ? l_len : r_len;
    /* at this point, if we get here then the l_pv and r_pv are in the same encoding */
    cmp = memcmp(l_pv,r_pv,min_len);
    if (!cmp && l_len < r_len) cmp= -1;
    return cmp;
}

I32
sv_prefix_cmp3(pTHX_ SV *l_sv, SV *r_sv, SV *r_sv_utf8) {
    return _sv_prefix_cmp3(aTHX_ l_sv, r_sv, r_sv_utf8);
}


/* we have k1, k2, k3, n1, n2
 * we need p1, p2?
 *
 * if we only have p1, search against k1.
 * if we have p1 (and thus l,r for it) and p2, search against k2.
 */



MPH_STATIC_INLINE
IV
_triple_find_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r)
{
    struct mph_header *mph= obj->header;
    struct codepair_array *codepair_array= &obj->codepair_array;
    struct str_len *str_len= STR_LEN_PTR(mph);
    U8 *strs= STR_BUF_PTR(mph);
    U8 *key_flags= KEY_FLAGS_PTR(mph);

    struct mph_triple_bucket *bucket;
    U32 num_buckets = mph->num_buckets;
    I32 cmp;
    U8 *mph_u8= (U8*)mph;
    U8 utf8_flags= mph->utf8_flags;
    char *table_start= (char *)mph + mph->table_ofs;
    U32 bucket_size= BUCKET_SIZE(mph->variant);
    IV last_m= -1;
    SV *cmp_utf8_sv= NULL;
    int p_is_utf8= SvUTF8(p1_sv) ? 1 : 0;
    struct mph_triple_bucket *first_bucket;
    SV *got_sv= sv_2mortal(newSV(0));
    SV *cmp_sv= p3_sv ? p3_sv
                      : p2_sv ? p2_sv
                              : p1_sv;

    first_bucket= (struct mph_triple_bucket *)(table_start);

    while (l <= r) {
        STRLEN got_len;
        U32 m= (l + r) / 2;
        U32 k_idx;
        bucket= (struct mph_triple_bucket *)(table_start + m * bucket_size);
        k_idx= p3_sv ? bucket->k3_idx
                     : p2_sv ? bucket->k2_idx
                             : bucket->k1_idx;

        triple_set_key_fast(aTHX_ codepair_array, strs, key_flags, str_len[k_idx].ofs, str_len[k_idx].len,
                m, got_sv, utf8_flags);
        cmp= sv_cmp(got_sv,cmp_sv);

        if (cmp < 0) {
            /* got < want - move left side to the right */
            if (p3_sv) {
                l = m + 1;
            }
            else
            if (p2_sv) {
                l = (last_bucket_by_k2(bucket) - first_bucket) + 1;
            }
            else {
                l = (last_bucket_by_k1(bucket) - first_bucket) + 1;
            }
        } else
        if (cmp > 0) {
            /* want < got - move right side to the left */
            if (p3_sv) {
                r = m - 1;
            }
            else
            if (p2_sv) {
                r= first_bucket_by_k2(bucket) - first_bucket - 1;
            } else {
                r= first_bucket_by_k1(bucket) - first_bucket - 1;
            }
        }
        else {
            /* want == got - yay! */
            if (p3_sv) {
                /* no-op */
            }
            else
            if (p2_sv) {
                m= first_bucket_by_k2(bucket) - first_bucket;
            }
            else {
                m= first_bucket_by_k1(bucket) - first_bucket;
            }
            return m;
        }

    }
    return -1;
}

IV
triple_find_first_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r)
{
    return _triple_find_prefix(aTHX_ obj, p1_sv, p2_sv, p3_sv, l, r);
}

IV
triple_find_last_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r)
{
    return _triple_find_prefix(aTHX_ obj, p1_sv, p2_sv, p3_sv, l, r);
}

IV
triple_find_first_last_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r, IV *last)
{
    struct mph_header *mph= obj->header;
    IV first= _triple_find_prefix(aTHX_ obj, p1_sv, p2_sv, p3_sv, l, r);

    if (first >= 0) {
        struct mph_triple_bucket *bucket_start= (struct mph_triple_bucket *)((char *)mph + mph->table_ofs);
        struct mph_triple_bucket *first_bucket= bucket_start + first;
        if (last) {
            if (p3_sv) {
                *last= first;
            }
            else
            if (p2_sv) {
                *last= last_bucket_by_k2(first_bucket) - bucket_start;
            }
            else {
                *last= last_bucket_by_k1(first_bucket) - bucket_start;
            }
        }
    }
    return first;
}


MPH_STATIC_INLINE
IV
_find_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r, I32 cmp_val, SV *got_sv, IV *hard_r)
{
    U32 num_buckets = mph->num_buckets;
    struct mph_bucket *bucket;
    I32 cmp;
    U8 *strs;
    U8 *mph_u8= (U8*)mph;
    U8 utf8_flags= mph->utf8_flags;
    char *table_start= (char *)mph + mph->table_ofs;
    U32 bucket_size= BUCKET_SIZE(mph->variant);
    IV m= (cmp_val && l+1<r) ? (l+1) : (l+r)/2;
    IV last_m= -1;
    SV *cmp_sv= NULL;
    SV *cmp_utf8_sv= NULL;
    int p_is_utf8= SvUTF8(pfx_sv) ? 1 : 0;
    if (hard_r) *hard_r= r;

    if (!got_sv) got_sv= sv_2mortal(newSV(0));

    strs= (U8 *)mph + mph->str_buf_ofs;
    /* when "cmp_val" is 0 this is the "find the leftmost case of T in a sorted list" variant
     * of binary search, (alternatively put "find the number of items which are less
     * than T in a sorted list"), when "cmp_val" is 1 this is the "find the rightmost case of T in
     * a sorted list" variant (alternatively put "find the number of items which are more
     * than T in a sorted list").
     *
     * These algorithms deal with dupes just fine, which is what we want for prefix searches,
     * we *expect* to see many items for a given prefix.
     *
     * Unlike conventional binary searches the result is stored in 'l' not 'm'. The correct position
     * is held in l-cmp_val. (Eg, for "leftmost" the result is l, for "rightmost" the result is l-1,
     * which just happens to be the same as l - cmp_val.)
     *
     */
    while (l < r) {
        STRLEN got_len;
        bucket= (struct mph_bucket *)(table_start + m * bucket_size);

        if (m>=num_buckets) croak("m is larger than last bucket! for key '%"SVf"' l=%ld m=%ld r=%ld\n",pfx_sv,l,m,r);
        last_m= m;
        sv_set_from_bucket_extra(aTHX_ got_sv,strs,bucket->key_ofs,bucket->key_len,m,mph_u8 + mph->key_flags_ofs,2,
                                 utf8_flags & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT,FAST_SV_CONSTRUCT);
#define CMP3(cmp,got_sv,pfx_sv) STMT_START {                        \
        int g_is_utf8= SvUTF8(got_sv) ? 1 : 0;                      \
        if (p_is_utf8 == g_is_utf8) {                               \
            cmp= _sv_prefix_cmp3(aTHX_ got_sv, pfx_sv, pfx_sv);      \
        } else {                                                    \
            if (p_is_utf8) {                                        \
                if (!cmp_utf8_sv) {                                 \
                    cmp_utf8_sv= pfx_sv;                            \
                    cmp_sv= sv_2mortal(newSVsv(pfx_sv));            \
                    sv_utf8_downgrade(cmp_sv,1);                    \
                    if (SvUTF8(cmp_sv)) cmp_sv= NULL;               \
                }                                                   \
            } else {                                                \
                if (!cmp_utf8_sv) {                                 \
                    cmp_sv= pfx_sv;                                 \
                    cmp_utf8_sv=sv_2mortal(newSVsv(pfx_sv));        \
                    sv_utf8_upgrade(cmp_utf8_sv);                   \
                }                                                   \
            }                                                       \
            cmp= _sv_prefix_cmp3(aTHX_ got_sv, cmp_sv, cmp_utf8_sv); \
        }                                                           \
} STMT_END
        CMP3(cmp,got_sv,pfx_sv);
        if (DEBUGF) printf("%s l:%8ld m:%8ld r:%8ld cmp: %d pfx: %"SVf"\n", cmp_val ? "final" : "first", l, m, r, cmp, pfx_sv);

        if (cmp < cmp_val) {
            l = m + 1;
        } else {
            r = m;
            if (cmp && hard_r)
                *hard_r= r;
        }
        m= (l + r) / 2;
    }
    l -= cmp_val;
    if (l < 0 || l >= num_buckets)
        return -1;

    /* l now specifies the leftmost or rightmost position that matches the prefix,
     * but we still have to check if there actually are any elements that start with
     * the prefix, there might not be. (When there are no such items the leftmost
     * and rightmost position are the same.) */
    if (l != last_m) {
        bucket= (struct mph_bucket *)(table_start + (l * bucket_size));
        sv_set_from_bucket_extra(aTHX_ got_sv,strs,bucket->key_ofs,bucket->key_len,l,mph_u8 + mph->key_flags_ofs,2,
                                 utf8_flags & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT,FAST_SV_CONSTRUCT);

        CMP3(cmp,got_sv,pfx_sv);
    }
    if (DEBUGF) printf("%s l:%8ld m:%8ld cmp: %d %"SVf"\n\n", cmp_val ? "final" : "first", l, last_m, cmp,pfx_sv);
    return !cmp ? l : -1;
}

IV find_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r, I32 cmp_val)
{
    return _find_prefix(aTHX_ mph, pfx_sv, l, r, cmp_val, NULL, NULL);
}

IV
find_first_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r)
{
    return _find_prefix(aTHX_ mph, pfx_sv, l, r, 0, NULL, NULL);
}

IV
find_last_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r)
{
    return _find_prefix(aTHX_ mph, pfx_sv, l, r, 1, NULL, NULL);
}

IV
find_first_last_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r, IV *last)
{
    SV *got_sv= sv_2mortal(newSV(0));
    IV hard_r= r;
    IV first= _find_prefix(aTHX_ mph, pfx_sv, l, r, 0, got_sv, &hard_r);
    *last= first >= 0 ? _find_prefix(aTHX_ mph, pfx_sv, first, hard_r, 1, got_sv, NULL) : -1;
    return first;
}


int
lookup_bucket(pTHX_ struct mph_header *mph, U32 index, SV *key_sv, SV *val_sv)
{
    struct mph_bucket *bucket;
    U8 *strs;
    U8 *mph_u8= (U8*)mph;
    U8 utf8_flags= mph->utf8_flags;
    if (index >= mph->num_buckets) {
        return 0;
    }
    bucket= (struct mph_bucket *)
            ((char *)mph + mph->table_ofs + (index * BUCKET_SIZE(mph->variant)));

    strs= (U8 *)mph + mph->str_buf_ofs;
    if (val_sv) {
        sv_set_from_bucket(aTHX_ val_sv,strs,bucket->val_ofs,bucket->val_len,index,mph_u8 + mph->val_flags_ofs,1,
                                 utf8_flags & MPH_VALS_ARE_SAME_UTF8NESS_MASK, MPH_VALS_ARE_SAME_UTF8NESS_SHIFT);
    }
    if (key_sv) {
        sv_set_from_bucket(aTHX_ key_sv,strs,bucket->key_ofs,bucket->key_len,index,mph_u8 + mph->key_flags_ofs,2,
                                 utf8_flags & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT);
    }
    return 1;
}

int
lookup_key(pTHX_ struct mph_header *mph, SV *key_sv, SV *val_sv)
{
    U8 *strs= (U8 *)mph + mph->str_buf_ofs;
    char *table= ((char *)mph + mph->table_ofs);
    U32 bucket_size= BUCKET_SIZE(mph->variant);
    struct mph_sorted_bucket *bucket;
    U8 *state= STATE_PTR(mph);
    STRLEN key_len;
    U8 *key_pv;
    U64 h0;
    U32 h1;
    U32 h2;
    U32 index;
    U8 *got_key_pv;
    STRLEN got_key_len;

    if (SvUTF8(key_sv)) {
        SV *tmp= sv_2mortal(newSVsv(key_sv));
        sv_utf8_downgrade(tmp,1);
        key_sv= tmp;
    }
    key_pv= SvPV_nomg(key_sv,key_len);
    h0= mph_hash_with_state(state,key_pv,key_len);
    h1= h0 >> 32;
    index= h1 % mph->num_buckets;

    bucket= (struct mph_sorted_bucket *)(table + (index * bucket_size));
    if (!bucket->xor_val)
        return 0;

    h2= h0 & 0xFFFFFFFF;
    if ( bucket->index < 0 ) {
        index = -bucket->index-1;
    } else {
        HASH2INDEX(index,h2,bucket->xor_val,mph->num_buckets);
    }
    bucket= (struct mph_sorted_bucket *)(table + (index * bucket_size));

    if (mph->variant == 6) {
        index= bucket->sort_index;
        bucket= (struct mph_sorted_bucket *)(table + (index * bucket_size));
    }

    got_key_pv= strs + bucket->key_ofs;
    if (bucket->key_len == key_len && memEQ(key_pv,got_key_pv,key_len)) {
        if (val_sv) {
            U8 utf8_flags= mph->utf8_flags;
            sv_set_from_bucket(aTHX_ val_sv, strs, bucket->val_ofs, bucket->val_len, index,
                                 ((U8*)mph)+mph->val_flags_ofs, 1,
                                 utf8_flags & MPH_VALS_ARE_SAME_UTF8NESS_MASK, MPH_VALS_ARE_SAME_UTF8NESS_SHIFT);
        }
        return 1;
    }
    return 0;
}

MPH_STATIC_INLINE int
str_len_sv_eq(struct codepair_array *codepair_array, struct str_len *str_len, U8 *strs, U32 str_len_idx, SV *sv) {
    U32 got_ofs= str_len[str_len_idx].ofs;
    I32 got_len= str_len[str_len_idx].len;
    STRLEN want_len;
    U8 *want_pv= SvPV_nomg(sv,want_len);
    if (got_len < 0) {
        got_len= -got_len;
        if (got_len == want_len && cpid_eq_sv(codepair_array, got_ofs, got_len, sv))
            return 1;
        else
            return 0;
    } else {
        U8 *got_pv= strs + got_ofs;
        if (got_len == want_len && memEQ(want_pv, got_pv, want_len))
            return 1;
        else
            return 0;
    }
}


int
triple_lookup_key_pvn(pTHX_ struct mph_obj *obj, struct mph_multilevel *ml, SV *full_key_sv, U8 *full_key_pv, STRLEN full_key_len,
        SV *val_sv, SV *leaf_sv)
{
    struct mph_header *mph= obj->header;
    struct str_len *str_len= STR_LEN_PTR(mph);
    struct codepair_array *codepair_array= &obj->codepair_array;
    U8 *strs= (U8 *)mph + mph->str_buf_ofs;
    U32 bucket_size= BUCKET_SIZE(mph->variant);
    struct mph_triple_bucket *first_bucket= (struct mph_triple_bucket *)((char *)mph + mph->table_ofs);
    struct mph_triple_bucket *bucket;
    U8 *state= STATE_PTR(mph);
    U64 h0;
    U32 h1;
    U32 h2;
    U32 index;
    U8 *got_key_pv;
    STRLEN got_key_len;

    if (full_key_sv) {
        if (SvUTF8(full_key_sv)) {
            SV *tmp= sv_2mortal(newSVsv(full_key_sv));
            sv_utf8_downgrade(tmp,1);
            if (!SvUTF8(tmp))
                full_key_sv= tmp;
        }
        full_key_pv= SvPV_nomg(full_key_sv,full_key_len);
    }

    h0= mph_hash_with_state(state,full_key_pv,full_key_len);
    h1= h0 >> 32;
    index= h1 % mph->num_buckets;

    bucket= first_bucket + index;
    if (!bucket->xor_val)
        return 0;

    h2= h0 & 0xFFFFFFFF;
    if ( bucket->index < 0 ) {
        index = -bucket->index-1;
    } else {
        HASH2INDEX(index,h2,bucket->xor_val,mph->num_buckets);
    }

    bucket= first_bucket + index;
    index= bucket->sort_index;
    bucket= first_bucket + index;

    if (
        ml->k1_idx == bucket->k1_idx &&
        ml->k2_idx == bucket->k2_idx &&
        str_len_sv_eq(codepair_array, str_len, strs, bucket->k3_idx, leaf_sv)
    ) {
        if (val_sv)
            triple_set_val(aTHX_ obj, bucket, index, val_sv);

        return 1;
    }

    return 0;
}

IV
mph_mmap(pTHX_ char *file, struct mph_obj *obj, SV *error, U32 flags) {
    struct stat st;
    struct mph_header *head;
    int fd = open(file, O_RDONLY, 0);
    void *ptr;
    U32 alignment;

    if (error)
        sv_setpvs(error,"");
    if (fd < 0) {
        if (error)
            sv_setpvf(error,"file '%s' could not be opened for read", file);
        return MPH_MOUNT_ERROR_OPEN_FAILED;
    }
    if (fstat(fd,&st)==-1) {
        if (error)
            sv_setpvf(error,"file '%s' could not be fstat()ed", file);
        return MPH_MOUNT_ERROR_FSTAT_FAILED;
    }
    if (st.st_size < sizeof(struct mph_header)) {
        if (error)
            sv_setpvf(error,"file '%s' is too small to be a valid PH2L file", file);
        return MPH_MOUNT_ERROR_TOO_SMALL;
    }
    ptr = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED | MPH_MAP_POPULATE, fd, 0);
    close(fd); /* kernel holds its own refcount on the file, we do not need to keep it open */
    if (ptr == MAP_FAILED) {
        if (error)
            sv_setpvf(error,"failed to create mapping to file '%s'", file);
        return MPH_MOUNT_ERROR_MAP_FAILED;
    }

    obj->bytes= st.st_size;
    obj->header= head= (struct mph_header*)ptr;
    if (head->magic_num != MAGIC_DECIMAL) {
        if (head->magic_num == MAGIC_BIG_ENDIAN_DECIMAL) {
            if (error)
                sv_setpvf(error,"this is a big-endian machine, cant handle PH2L files here");
        }
        if (error)
            sv_setpvf(error,"file '%s' is not a PH2L file", file);
        return MPH_MOUNT_ERROR_BAD_MAGIC;
    }
    if (head->variant < MIN_VARIANT) {
        if (error)
            sv_setpvf(error,"unsupported old version '%d' in '%s'", head->variant, file);
        return MPH_MOUNT_ERROR_BAD_VERSION;
    }
    if (head->variant > MAX_VARIANT) {
        if (error)
            sv_setpvf(error,"unknown version '%d' in '%s', this variant only supports up to version %d",
                head->variant, file, MAX_VARIANT);
        return MPH_MOUNT_ERROR_BAD_VERSION;
    }
    alignment = sizeof(U64);

    if (st.st_size % alignment) {
        if (error)
            sv_setpvf(error,"file '%s' does not have a size which is a multiple of 16 bytes", file);
        return MPH_MOUNT_ERROR_BAD_SIZE;
    }
    if (
        head->table_ofs < head->state_ofs           ||
        head->key_flags_ofs < head->table_ofs       ||
        head->val_flags_ofs < head->key_flags_ofs   ||
        head->str_buf_ofs < head->val_flags_ofs     ||
        st.st_size < head->str_buf_ofs
    ) {
        if (error)
            sv_setpvf(error,"corrupt header offsets in '%s'", file);
        return MPH_MOUNT_ERROR_BAD_OFFSETS;
    }
    if (flags & MPH_F_VALIDATE) {
        char *start= ptr;
        char *state_pv= start + head->state_ofs;
        char *str_buf_start= start + head->str_buf_ofs;
        char *str_buf_end= start + st.st_size;

        U64 have_file_checksum= mph_hash_with_state(state_pv, start, st.st_size - sizeof(U64));
        U64 want_file_checksum= *((U64 *)(str_buf_end - sizeof(U64)));
        if (have_file_checksum != want_file_checksum) {
            if (error)
                sv_setpvf(error,"file checksum '%016lx' != '%016lx' in file '%s'",
                    have_file_checksum,want_file_checksum,file);
            return MPH_MOUNT_ERROR_CORRUPT_FILE;
        }
    }
    return head->variant;
}

void
_mph_munmap(struct mph_obj *obj)
{
    munmap(obj->header,obj->bytes);
}

STRLEN
normalize_with_flags(pTHX_ SV *sv, SV *normalized_sv, SV *is_utf8_sv, int downgrade) {
    STRLEN len;
    if (SvROK(sv)) {
        croak("Error: Not expecting a reference value in source hash");
    }
    sv_setsv(normalized_sv,sv);
    if (SvOK(sv)) {
        STRLEN pv_len;
        char *pv= SvPV_nomg(sv,pv_len);
        if (pv_len > 0xFFFF)
            croak("Error: String in source hash is too long to store, max length is %u got length %lu", 0xFFFF, pv_len);
        if (SvUTF8(sv)) {
            if (downgrade)
                sv_utf8_downgrade(normalized_sv,1);
            if (SvUTF8(normalized_sv)) {
                SvUTF8_off(normalized_sv);
                sv_setiv(is_utf8_sv,1);
            } else {
                sv_setiv(is_utf8_sv,2);
            }
        }
        return pv_len;
    } else {
        sv_setiv(is_utf8_sv, 0);
        return 0;
    }
}


U32
normalize_source_hash(pTHX_ HV *source_hv, AV *keys_av, U32 compute_flags, SV *buf_length_sv, char *state_pv, U32 variant, struct sv_with_hash *keyname_sv) {
    HE *he;
    U32 buf_length= 0;
    U32 ctr;

    hv_iterinit(source_hv);
    while (he= hv_iternext(source_hv)) {
        SV *val_sv= HeVAL(he);
        SV *val_normalized_sv;
        SV *val_is_utf8_sv;

        SV *key_sv;
        SV *key_normalized_sv;
        SV *key_is_utf8_sv;
        HV *hv;
        U8 *key_pv;
        STRLEN key_len;
        U64 h0;
        SV *sort_index_sv;

        if (!val_sv) croak("panic: no sv for value?");
        if (!SvOK(val_sv) && (compute_flags & MPH_F_FILTER_UNDEF)) continue;

        hv= newHV();
        av_push(keys_av,newRV_noinc((SV*)hv));

        val_normalized_sv= newSV(0);
        val_is_utf8_sv= newSVuv(0);

        key_sv= newSVhek(HeKEY_hek(he));
        key_normalized_sv= newSV(0);
        key_is_utf8_sv= newSVuv(0);

        hv_ksplit(hv,15);
        hv_store_ent_with_keysv(hv,MPH_KEYSV_KEY,            key_sv);
        hv_store_ent_with_keysv(hv,MPH_KEYSV_KEY_NORMALIZED, key_normalized_sv);
        hv_store_ent_with_keysv(hv,MPH_KEYSV_KEY_IS_UTF8,    key_is_utf8_sv);
        hv_store_ent_with_keysv(hv,MPH_KEYSV_VAL,            SvREFCNT_inc_simple_NN(val_sv));
        hv_store_ent_with_keysv(hv,MPH_KEYSV_VAL_NORMALIZED, val_normalized_sv);
        hv_store_ent_with_keysv(hv,MPH_KEYSV_VAL_IS_UTF8,    val_is_utf8_sv);
        /* install everything into the keys_av just in case normalize_with_flags() dies */

        buf_length += normalize_with_flags(aTHX_ key_sv, key_normalized_sv, key_is_utf8_sv, 1);
        buf_length += normalize_with_flags(aTHX_ val_sv, val_normalized_sv, val_is_utf8_sv, 0);

        key_pv= (U8 *)SvPV_nomg(key_normalized_sv,key_len);
        h0= mph_hash_with_state(state_pv,key_pv,key_len);

        hv_store_ent_with_keysv(hv,MPH_KEYSV_H0,             newSVuv(h0));
    }
    if (buf_length_sv)
        sv_setuv(buf_length_sv, buf_length);

    /* we now know how many keys there are, and what the max_xor_val should be */
    return av_top_index(keys_av)+1;
}

void
add_sort_index(pTHX_ AV *keys_av, struct sv_with_hash *keyname_sv) {
    IV idx;
    for (idx= av_top_index(keys_av); idx >= 0; idx--) {
        SV **got_hvref= av_fetch(keys_av,idx,0);
        HV *hv;
        HE *got_he;
        SV *got_sv;

        got_hvref= av_fetch(keys_av,idx,0);
        if (!got_hvref)
            croak("no HV in array in add_sort_index?!");

        hv= (HV *)SvRV(*got_hvref);
        got_he= hv_fetch_ent_with_keysv(hv, MPH_KEYSV_SORT_INDEX, 1);
        if (!got_he)
            croak("no HE in HV in add_sort_index?!");
        got_sv= HeVAL(got_he);

        if (!got_sv)
            croak("no sv in HE?");
        sv_setuv(got_sv, idx);
    }
}

void
find_first_level_collisions(pTHX_ U32 bucket_count, AV *keys_av, AV *keybuckets_av, AV *h2_packed_av, struct sv_with_hash *keyname_sv) {
    U32 i;
    for (i=0; i<bucket_count;i++) {
        U64 h0;
        U32 h1;
        U32 h2;
        U32 idx1;
        SV **got_psv;
        SV* h0_sv;
        HE* h0_he;
        HV *hv;
        AV *av;
        got_psv= av_fetch(keys_av,i,0);
        if (!got_psv || !SvROK(*got_psv)) croak("panic: bad item in keys_av");
        hv= (HV *)SvRV(*got_psv);
        h0_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_H0,0);
        if (!h0_he) croak("panic: no h0_he?");
        h0_sv= HeVAL(h0_he);
        h0= SvUV(h0_sv);

        h1= h0 >> 32;
        h2= h0 & 0xFFFFFFFF;
        idx1= h1 % bucket_count;
        got_psv= av_fetch(h2_packed_av,idx1,1);
        if (!got_psv)
            croak("panic: out of memory creating new h2_packed_av element");
        if (!SvPOK(*got_psv))
            sv_setpvs(*got_psv,"");
        sv_catpvn(*got_psv, (char *)&h2, 4);

        got_psv= av_fetch(keybuckets_av,idx1,1);
        if (!got_psv)
            croak("panic: out of memory creating new keybuckets_av element");

        if (!SvROK(*got_psv)) {
            av= newAV();
            sv_upgrade(*got_psv,SVt_RV);
            SvRV_set(*got_psv,(SV *)av);
            SvROK_on(*got_psv);
        } else {
            av= (AV *)SvRV(*got_psv);
        }

        av_push(av,newRV_inc((SV*)hv));
    }
}

AV *
idx_by_length(pTHX_ AV *keybuckets_av) {
    U32 i;
    U32 keybuckets_count= av_top_index(keybuckets_av) + 1;
    AV *by_length_av= (AV*)sv_2mortal((SV*)newAV());
    for( i = 0 ; i < keybuckets_count ; i++ ) {
        SV **got= av_fetch(keybuckets_av,i,0);
        AV *keys_av;
        SV *keys_ref;
        AV *target_av;
        IV len;
        if (!got) continue;
        keys_av= (AV *)SvRV(*got);
        len= av_top_index(keys_av) + 1;
        if (len<1) continue;

        got= av_fetch(by_length_av,len,1);
        if (SvPOK(*got)) {
            sv_catpvn(*got,(char *)&i,4);
        } else {
            sv_setpvn(*got,(char *)&i,4);
        }
    }
    return by_length_av;
}

void set_xor_val_in_buckets(pTHX_ U32 xor_val, AV *buckets_av, U32 idx1, U32 *idx_start, char *is_used, AV *keys_in_bucket_av, struct sv_with_hash *keyname_sv) {
    U32 *idx2;
    HV *idx1_hv;
    U32 i;
    U32 keys_in_bucket_count= av_top_index(keys_in_bucket_av) + 1;

    SV **buckets_rvp= av_fetch(buckets_av, idx1, 1);
    if (!buckets_rvp) croak("panic: out of memory in buckets_av lvalue fetch");
    if (!SvROK(*buckets_rvp)) {
        idx1_hv= newHV();
        if (!idx1_hv) croak("panic: out of memory creating new hash in buckets_av idx %u",idx1);
        sv_upgrade(*buckets_rvp,SVt_RV);
        SvRV_set(*buckets_rvp,(SV *)idx1_hv);
        SvROK_on(*buckets_rvp);
    } else {
         idx1_hv= (HV *)SvRV(*buckets_rvp);
    }

    hv_setuv_with_keysv(idx1_hv,MPH_KEYSV_XOR_VAL,xor_val);
    hv_setuv_with_keysv(idx1_hv,MPH_KEYSV_H1_KEYS,keys_in_bucket_count);

    /* update used */
    for (i= 0, idx2= idx_start; i < keys_in_bucket_count; i++,idx2++) {
        HV *idx2_hv;
        HV *keys_hv;

        SV **keys_rvp;
        SV **buckets_rvp;

        keys_rvp= av_fetch(keys_in_bucket_av, i, 0);
        if (!keys_rvp) croak("panic: no key_info in bucket %d", i);
        keys_hv= (HV *)SvRV(*keys_rvp);

        buckets_rvp= av_fetch(buckets_av, *idx2, 1);
        if (!buckets_rvp) croak("panic: out of memory in lvalue fetch to buckets_av");

        if (!SvROK(*buckets_rvp)) {
            sv_upgrade(*buckets_rvp,SVt_RV);
        } else {
            idx2_hv= (HV *)SvRV(*buckets_rvp);

            hv_copy_with_keysv(idx2_hv,keys_hv,MPH_KEYSV_XOR_VAL);
            hv_copy_with_keysv(idx2_hv,keys_hv,MPH_KEYSV_H1_KEYS);
            SvREFCNT_dec(idx2_hv);
        }

        SvRV_set(*buckets_rvp,(SV*)keys_hv);
        SvROK_on(*buckets_rvp);
        SvREFCNT_inc(keys_hv);

        hv_setuv_with_keysv(keys_hv,MPH_KEYSV_IDX,*idx2);

        is_used[*idx2] = 1;
    }
}

U32
solve_collisions(pTHX_ U32 bucket_count, U32 max_xor_val, SV *idx1_packed_sv, AV *h2_packed_av, AV *keybuckets_av, U32 variant, char *is_used, U32 *idx2_start,AV *buckets_av, struct sv_with_hash *keyname_sv) {
    STRLEN idx1_packed_sv_len;
    U32 *idx1_start= (U32 *)SvPV_nomg(idx1_packed_sv,idx1_packed_sv_len);
    U32 *idx1_ptr;
    U32 *idx1_end= idx1_start + (idx1_packed_sv_len / sizeof(U32));

    for (idx1_ptr= idx1_start; idx1_ptr < idx1_end; idx1_ptr++) {
        U32 idx1= *idx1_ptr;
        SV *h2_sv;
        AV *keys_in_bucket_av;
        U32 xor_val= 0;
        STRLEN h2_strlen;
        U32 *h2_start;
        STRLEN keys_in_bucket_count;
        U32 *h2_end;
        SV **got;

        got= av_fetch(h2_packed_av, idx1, 0);
        if (!got)
            croak("panic: no h2_buckets for idx %u",idx1);
        h2_sv= *got;

        got= av_fetch(keybuckets_av, idx1, 0);
        if (!got)
            croak("panic: no keybuckets_av for idx %u",idx1);
        keys_in_bucket_av= (AV *)SvRV(*got);

        h2_start= (U32 *)SvPV_nomg(h2_sv,h2_strlen);
        keys_in_bucket_count= h2_strlen / sizeof(U32);
        h2_end= h2_start + keys_in_bucket_count;

        next_xor_val:
        while (1) {
            U32 *h2_ptr= h2_start;
            U32 *idx2_ptr= idx2_start;
            if (xor_val == max_xor_val) {
                warn("panic: failed to resolve collision idx1: %d\n",idx1);
                while (h2_ptr < h2_end)
                    warn("hash: %016x\n", *h2_ptr++);
                return idx1 + 1;
            } else {
                xor_val++;
            }
            while (h2_ptr < h2_end) {
                U32 idx2;
                U32 *check_idx;
                HASH2INDEX(idx2,*h2_ptr,xor_val,bucket_count);
                if (is_used[idx2])
                    goto next_xor_val;
                for (check_idx= idx2_start; check_idx < idx2_ptr; check_idx++) {
                    if (*check_idx == idx2)
                        goto next_xor_val;
                }
                *idx2_ptr= idx2;
                h2_ptr++;
                idx2_ptr++;
            }
            break;
        }
        set_xor_val_in_buckets(aTHX_ xor_val, buckets_av, idx1, idx2_start, is_used, keys_in_bucket_av,keyname_sv);
    }
    return 0;
}

U32
place_singletons(pTHX_ U32 bucket_count, SV *idx1_packed_sv, AV *keybuckets_av, char *is_used, U32 *idx2_start, AV *buckets_av, struct sv_with_hash *keyname_sv) {
    STRLEN idx1_packed_sv_len;
    U32 *idx1_start= (U32 *)SvPV_nomg(idx1_packed_sv,idx1_packed_sv_len);
    U32 *idx1_ptr;
    U32 *idx1_end= idx1_start + (idx1_packed_sv_len / sizeof(U32));

    U32 singleton_pos= 0;

    for (idx1_ptr= idx1_start; idx1_ptr < idx1_end; idx1_ptr++) {
        U32 idx1= *idx1_ptr;
        AV *keys_in_bucket_av;
        U32 xor_val;
        SV **got;

        while (singleton_pos < bucket_count && is_used[singleton_pos]) {
            singleton_pos++;
        }
        if (singleton_pos == bucket_count) {
            warn("panic: failed to place singleton! idx: %d",idx1);
            return idx1 + 1;
        }

        xor_val= (U32)(-singleton_pos-1);
        got= av_fetch(keybuckets_av, idx1, 0);
        if (!got)
            croak("panic: no keybuckets_av for idx %u",idx1);
        keys_in_bucket_av= (AV *)SvRV(*got);
        *idx2_start= singleton_pos;
        set_xor_val_in_buckets(aTHX_ xor_val, buckets_av, idx1, idx2_start, is_used, keys_in_bucket_av, keyname_sv);
    }
    return 0;
}

U32
solve_collisions_by_length(pTHX_ U32 bucket_count, U32 max_xor_val, AV *by_length_av, AV *h2_packed_av, AV *keybuckets_av, U32 variant, AV *buckets_av, struct sv_with_hash *keyname_sv) {
    U32 bad_idx= 0;
    I32 singleton_pos= 0;
    IV len_idx;
    char *is_used;
    U32 *idx2_start;

    /* this is used to quickly tell if we have used a particular bucket yet */
    Newxz(is_used,bucket_count,char);
    SAVEFREEPV(is_used);

    /* used to keep track the indexes that a set of keys map into
     * stored in an SV just because - we actually treat it as an array of U32 */
    Newxz(idx2_start, av_top_index(by_length_av)+1, U32);
    SAVEFREEPV(idx2_start);

    /* now loop through and process the keysets from most collisions to least */
    for (len_idx= av_top_index(by_length_av); len_idx > 0 && !bad_idx; len_idx--) {
        SV **idx1_packed_sv= av_fetch(by_length_av, len_idx, 0);
        /* deal with the possibility that there are gaps in the length grouping,
         * for instance we might have some 13 way collisions and some 11 way collisions
         * without any 12-way collisions. (this should be rare - but is possible) */
        if (!idx1_packed_sv || !SvPOK(*idx1_packed_sv))
            continue;

        if (len_idx == 1) {
            bad_idx= place_singletons(aTHX_ bucket_count, *idx1_packed_sv, keybuckets_av,
                is_used, idx2_start, buckets_av, keyname_sv);
        } else {
            bad_idx= solve_collisions(aTHX_ bucket_count, max_xor_val, *idx1_packed_sv, h2_packed_av, keybuckets_av,
                variant, is_used, idx2_start, buckets_av, keyname_sv);
        }
    }
    return bad_idx;
}

struct sv_with_hash MPH_SORT_KEY;
I32
sv_cmp_hash(pTHX_ SV *a, SV *b) {
    HE *a_he= hv_fetch_ent((HV*)SvRV(a),MPH_SORT_KEY.sv,0,MPH_SORT_KEY.hash);
    HE *b_he= hv_fetch_ent((HV*)SvRV(b),MPH_SORT_KEY.sv,0,MPH_SORT_KEY.hash);
    SV *a_sv= HeVAL(a_he);
    SV *b_sv= HeVAL(b_he);
    return sv_cmp(a_sv,b_sv);
}

SV *MPH_CMP_A_SV;
SV *MPH_CMP_B_SV;
U8 MPH_CMP_SEPARATOR;
I32
sv_cmp_hash_with_sep(pTHX_ SV *a, SV *b) {
    HE *a_he= hv_fetch_ent((HV*)SvRV(a),MPH_SORT_KEY.sv,0,MPH_SORT_KEY.hash);
    HE *b_he= hv_fetch_ent((HV*)SvRV(b),MPH_SORT_KEY.sv,0,MPH_SORT_KEY.hash);
    SV *a_sv= HeVAL(a_he);
    SV *b_sv= HeVAL(b_he);

    STRLEN a_len, b_len;
    U8 *a_pv1= SvPV(a_sv,a_len);
    U8 *a_end= a_pv1 + a_len;

    U8 *b_pv1= SvPV(b_sv,b_len);
    U8 *b_end= b_pv1 + b_len;
    U8 separator= MPH_CMP_SEPARATOR;
    I32 diff;
    if (SvUTF8(a_sv))
        SvUTF8_on(MPH_CMP_A_SV);
    else
        SvUTF8_off(MPH_CMP_A_SV);
    if (SvUTF8(b_sv))
        SvUTF8_on(MPH_CMP_B_SV);
    else
        SvUTF8_off(MPH_CMP_B_SV);

    {
        U8 *a_pv2= memchr(a_pv1, separator, a_end - a_pv1);
        U8 *b_pv2= memchr(b_pv1, separator, b_end - b_pv1);
        if (!a_pv2) croak("missing first separator in '%.*s'", (int)a_len, a_pv1);
        if (!b_pv2) croak("missing first separator in '%.*s'", (int)b_len, b_pv1);
        sv_setpvn(MPH_CMP_A_SV, a_pv1, a_pv2 - a_pv1);
        sv_setpvn(MPH_CMP_B_SV, b_pv1, b_pv2 - b_pv1);
        diff = sv_cmp(MPH_CMP_A_SV,MPH_CMP_B_SV);
        a_pv2++;
        b_pv2++;

        if (!diff) {
            U8 *a_pv3= memchr(a_pv2, separator, a_end - a_pv2);
            U8 *b_pv3= memchr(b_pv2, separator, b_end - b_pv2);
            if (!a_pv3) croak("missing first separator in '%.*s'", (int)a_len, a_pv1);
            if (!b_pv3) croak("missing first separator in '%.*s'", (int)b_len, b_pv1);
            sv_setpvn(MPH_CMP_A_SV, a_pv2, a_pv3 - a_pv2);
            sv_setpvn(MPH_CMP_B_SV, b_pv2, b_pv3 - b_pv2);
            a_pv3++;
            b_pv3++;

            diff = sv_cmp(MPH_CMP_A_SV,MPH_CMP_B_SV);
            if (!diff) {
                sv_setpvn(MPH_CMP_A_SV, a_pv3, a_end - a_pv3);
                sv_setpvn(MPH_CMP_B_SV, b_pv3, b_end - b_pv3);
                diff = sv_cmp(MPH_CMP_A_SV,MPH_CMP_B_SV);
            }
        }
    }

    return diff;
}



UV
_compute_xs(pTHX_ HV *self_hv, struct sv_with_hash *keyname_sv)
{
    U8 *state_pv;
    STRLEN state_len;
    HE *he;

    IV len_idx;

    U32 bucket_count;
    U32 max_xor_val;
    U32 i;

    U32 variant;
    U32 compute_flags;

    SV* buf_length_sv;

    HV* source_hv;

    AV *buckets_av;
    AV *keys_av;
    AV *by_length_av;
    AV *keybuckets_av;
    AV *h2_packed_av;
    SV *separator_sv= NULL;


    /**** extract the various reference data we need from $self */

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_VARIANT,0);
    if (he) {
        variant= SvUV(HeVAL(he));
    } else {
        croak("panic: no variant in self?");
    }

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_COMPUTE_FLAGS,0);
    if (he) {
        compute_flags= SvUV(HeVAL(he));
    } else {
        croak("panic: no compute_flags in self?");
    }

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_STATE,0);
    if (he) {
        SV *state_sv= HeVAL(he);
        state_pv= (U8 *)SvPV_nomg(state_sv,state_len);
        if (state_len != MPH_STATE_BYTES) {
            croak("Error: state vector must be at exactly %d bytes",(int)MPH_SEED_BYTES);
        }
    } else {
        croak("panic: no state in self?");
    }

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_BUF_LENGTH,1);
    if (he) {
        buf_length_sv= HeVAL(he);
    } else {
        croak("panic: out of memory in lvalue fetch for 'buf_length' in self");
    }

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_SOURCE_HASH,0);
    if (he) {
        source_hv= (HV*)SvRV(HeVAL(he));
    } else {
        croak("panic: no source_hash in self");
    }

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_BUCKETS,1);
    if (he) {
        SV *rv= HeVAL(he);
        if (SvROK(rv)) {
            AV *old_buckets_av= (AV*)SvRV(rv);
            SvREFCNT_dec(old_buckets_av);
        } else {
            sv_upgrade(rv, SVt_RV);
        }
        buckets_av= newAV();
        SvRV_set(rv,(SV*)buckets_av);
        SvROK_on(rv);
    } else {
        croak("panic: out of memory in lvalue fetch for 'buckets' in self");
    }

    he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_KEYS_AV,1);
    if (he) {
        SV *rv= HeVAL(he);
        if (SvROK(rv)) {
            AV *old_keys_av= (AV*)SvRV(rv);
            SvREFCNT_dec(old_keys_av);
        } else {
            sv_upgrade(rv, SVt_RV);
        }
        keys_av= newAV();
        SvRV_set(rv,(SV*)keys_av);
        SvROK_on(rv);
    } else {
        croak("panic: out of memory in lvalue fetch for 'buckets' in self");
    }

    hv_fetch_sv_with_keysv(separator_sv,self_hv,MPH_KEYSV_SEPARATOR,0);

    /**** build an array of hashes in keys_av based on the normalized contents of source_hv */
    bucket_count= normalize_source_hash(aTHX_ source_hv, keys_av, compute_flags, buf_length_sv, state_pv, variant, keyname_sv);
    max_xor_val= INT32_MAX;

    /* if the caller wants deterministic results we sort the keys_av
     * before we compute collisions - depending on the order we process
     * the keys we might resolve the collisions differently */
    if ((compute_flags & MPH_F_DETERMINISTIC) || variant >= 6) {
        /* XXX: fixme: should this use the normalized key? I think it should. */
        MPH_SORT_KEY.sv= keyname_sv[MPH_KEYSV_KEY].sv;
        MPH_SORT_KEY.hash= keyname_sv[MPH_KEYSV_KEY].hash;
        if (variant == 7) {
            if (!separator_sv) croak("'separator' is a required parameter for variant 7");
            MPH_CMP_A_SV= sv_newmortal(); sv_grow(MPH_CMP_A_SV,10);
            MPH_CMP_B_SV= sv_newmortal(); sv_grow(MPH_CMP_B_SV,10);
            MPH_CMP_SEPARATOR= SvPV_nomg_nolen(separator_sv)[0];
            sortsv(AvARRAY(keys_av),bucket_count,sv_cmp_hash_with_sep);
        } else {
            sortsv(AvARRAY(keys_av),bucket_count,sv_cmp_hash);
        }
        if (variant >= 6)
            add_sort_index(aTHX_ keys_av, keyname_sv);
    }

    /**** find the collisions from the data we just computed, build an AoAoH and AoS of the
     **** collision data */
    keybuckets_av= (AV*)sv_2mortal((SV*)newAV()); /* AoAoH - hashes from keys_av */
    h2_packed_av= (AV*)sv_2mortal((SV*)newAV());  /* AoS - packed h1 */
    find_first_level_collisions(aTHX_ bucket_count, keys_av, keybuckets_av, h2_packed_av, keyname_sv);

    /* Sort the buckets by size by constructing an AoS, with the outer array indexed by length,
     * and the inner string being the list of items of that length. (Thus the contents of index
     * 0 is empty/undef).
     * The end result is we can process the collisions from the most keys to a bucket to the
     * least in O(N) and not O(N log2 N).
     *
     * the length of the array (av_top_index+1) reflect the number of items in the bucket
     * with the most collisions - we use this later to size some of our data structures.
     */
    by_length_av= idx_by_length(aTHX_ keybuckets_av);

    return solve_collisions_by_length(aTHX_ bucket_count, max_xor_val, by_length_av, h2_packed_av, keybuckets_av,
        variant, buckets_av, keyname_sv);
}




SV *
_seed_state(pTHX_ SV *base_seed_sv)
{
    STRLEN seed_len;
    STRLEN state_len;
    U8 *seed_pv;
    U8 *state_pv;
    SV *seed_sv;
    SV *ret_sv;

    if (!SvOK(base_seed_sv))
        croak("Error: seed must be defined");
    if (SvROK(base_seed_sv))
        croak("Error: seed should not be a reference");
    seed_sv= base_seed_sv;
    seed_pv= (U8 *)SvPV_nomg(seed_sv,seed_len);

    if (seed_len != MPH_SEED_BYTES) {
        if (SvREADONLY(base_seed_sv)) {
            if (seed_len < MPH_SEED_BYTES) {
                warn("seed passed into seed_state() is readonly and too short, argument has been right padded with %d nulls",
                    (int)(MPH_SEED_BYTES - seed_len));
            }
            else if (seed_len > MPH_SEED_BYTES) {
                warn("seed passed into seed_state() is readonly and too long, using only the first %d bytes",
                    (int)MPH_SEED_BYTES);
            }
            seed_sv= sv_2mortal(newSVsv(base_seed_sv));
        }
        if (seed_len < MPH_SEED_BYTES) {
            sv_grow(seed_sv,MPH_SEED_BYTES+1);
            while (seed_len < MPH_SEED_BYTES) {
                seed_pv[seed_len] = 0;
                seed_len++;
            }
        }
        SvCUR_set(seed_sv,MPH_SEED_BYTES);
        seed_pv= (U8 *)SvPV_nomg(seed_sv,seed_len);
    } else {
        seed_sv= base_seed_sv;
    }

    ret_sv= newSV(MPH_STATE_BYTES+1);
    SvCUR_set(ret_sv,MPH_STATE_BYTES);
    SvPOK_on(ret_sv);
    state_pv= (U8 *)SvPV_nomg(ret_sv,state_len);
    mph_seed_state(seed_pv,state_pv);
    return ret_sv;
}

UV
_hash_with_state_sv(pTHX_ SV *str_sv, SV *state_sv)
{
    STRLEN str_len;
    STRLEN state_len;
    U8 *state_pv;
    U8 *str_pv= (U8 *)SvPV_nomg(str_sv,str_len);
    state_pv= (U8 *)SvPV_nomg(state_sv,state_len);
    if (state_len != MPH_STATE_BYTES) {
        croak("Error: state vector must be at exactly %d bytes",(int)MPH_SEED_BYTES);
    }
    return mph_hash_with_state(state_pv,str_pv,str_len);
}

void
str_len_init(struct str_len_obj *str_len_obj, struct compressor *compressor) {
    Zero(str_len_obj,1,struct str_len_obj);
    str_len_obj->compressed_hv= (HV *)sv_2mortal((SV *)newHV());
    str_len_obj->uncompressed_hv= (HV *)sv_2mortal((SV *)newHV());
    str_len_obj->next= 1; /* we reserve 0 for undef */
    str_len_obj->compressor= compressor;
}

U32
str_len_add(pTHX_ struct str_len_obj *str_len_obj, struct str_buf *str_buf, char *pv, U32 len, U32 flags) {
    struct str_len *str_len= str_len_obj->str_len;
    U32 next= str_len_obj->next;
    SV **svp;
    SV *sv;
    U32 ofs;
    U32 compress;

    if (!pv) return 0; /* str_len == 0 is reserved for undef and str_buf=NULL means undef */

    if (flags & MPH_F_IS_KEY) {
        compress= flags & MPH_F_COMPRESS_KEYS;
    } else {
        compress= flags & MPH_F_COMPRESS_VALS;
    }
    if (compress) {
        /* first check the uncompressed bucket to see if we have seen it,
         * if we have then we use it, if not then we add it to the compressed bucket */
        svp= hv_fetch(str_len_obj->uncompressed_hv,pv,len,0);
        if (!svp)
            svp= hv_fetch(str_len_obj->compressed_hv,pv,len,1);
    } else {
        svp= hv_fetch(str_len_obj->uncompressed_hv,pv,len,1);
    }
    if (!svp) croak("out of memory");
    sv= *svp;

    if (str_len) {
        if (!SvOK(sv) || SvIV(sv)<0) {
            U32 count= str_len_obj->count;
            if (0) printf("str_len adding len %-6u '%.*s'\n",len,20,pv);
            if (next >= count) {
                croak("too many str_len elements?!");
                /* NOT-REACHED */
            }
            if (str_len_obj->longest < len)
                str_len_obj->longest= len;
            if (compress){
                if (str_len_obj->longest_compressed < len)
                    str_len_obj->longest_compressed= len;
                str_len[next].len= -len;
                str_len[next].ofs= compress_string(str_len_obj->compressor,pv,len);
                str_len_obj->compressed_count++;
            }
            else {
                if (str_len_obj->longest_uncompressed < len)
                    str_len_obj->longest_uncompressed= len;
                str_len[next].len= len;
                str_len[next].ofs= str_buf_add_from_pvn(aTHX_ str_buf, pv, len, flags);
                str_len_obj->uncompressed_count++;
            }
            sv_setiv(sv,next);
            str_len_obj->next++;
        }
        return SvIV(sv);
    } else {
        if (!SvOK(sv)) {
            str_len_obj->next++;
            sv_setiv(sv,-1);
        }
        return next;
    }
}

void str_len_obj_dump(pTHX_ struct str_len_obj *str_len_obj) {
    warn("|str_len_obj=%p\n", str_len_obj);
    warn("|str_len_obj->compressed_hv: %p\n",   str_len_obj->compressed_hv);
    warn("|str_len_obj->uncompressed_hv: %p\n", str_len_obj->uncompressed_hv);
    warn("|str_len_obj->compressor: %p\n", str_len_obj->compressor);
    warn("|str_len_obj->str_len: %p\n", str_len_obj->str_len);

    warn("|str_len_obj->count: %u\n", str_len_obj->count);
    warn("|str_len_obj->next: %u\n", str_len_obj->next);
    warn("|str_len_obj->longest: %u\n", str_len_obj->longest_compressed);
    warn("|str_len_obj->compressed_count: %u\n", str_len_obj->compressed_count);
    warn("|str_len_obj->longest_compressed: %u\n", str_len_obj->longest_compressed);
    warn("|str_len_obj->uncompressed_count: %u\n", str_len_obj->uncompressed_count);
    warn("|str_len_obj->longest_uncompressed: %u\n", str_len_obj->longest_uncompressed);
    warn("|\n");
}


I32
sv_cmp_len_desc_lex_asc(pTHX_ SV * const a, SV * const b) {
    I32 ret= SvCUR(b) - SvCUR(a);
    if (!ret)
        ret= sv_cmp(a,b);
    return ret;
}

I32
sv_cmp_len_asc_lex_asc(pTHX_ SV * const a, SV * const b) {
    I32 ret= SvCUR(a) - SvCUR(b);
    if (!ret)
        ret= sv_cmp(a,b);
    return ret;
}


IV
_packed_xs(pTHX_ SV *buf_sv, U32 variant, SV *buf_length_sv, SV *state_sv, SV* comment_sv, U32 flags, AV *buckets_av, struct sv_with_hash *keyname_sv, AV* keys_av, SV *separator_sv)
{
    U32 buf_length= SvUV(buf_length_sv);
    U32 bucket_count= av_top_index(buckets_av) + 1;
    U32 header_rlen= _roundup(sizeof(struct mph_header),16);
    STRLEN state_len;
    char *state_pv= SvPV_nomg(state_sv, state_len);

    U32 alignment= sizeof(U64);
    U32 state_rlen= _roundup(state_len,alignment);
    U32 bucket_size= BUCKET_SIZE(variant);
    U32 table_rlen= _roundup(bucket_size * bucket_count, alignment);
    U32 key_flags_rlen= _roundup((bucket_count * 2 + 7 ) / 8, alignment);
    U32 val_flags_rlen= _roundup((bucket_count + 7) / 8, alignment);
    U32 str_rlen= _roundup( buf_length
                            + 2
                            + ( SvOK(comment_sv) ? sv_len(comment_sv) + 1 : 1 )
                            + ( 2 + 8 ),
                            alignment );

    U32 total_size;
    char *start;
    char *end_pos;
    struct compressor compressor;

    struct mph_header *head;
    char *key_flags;
    char *val_flags;
    IV i;
    STRLEN pv_len;
    char *pv;
    U32 key_is_utf8_count[3]={0,0,0};
    U32 val_is_utf8_count[2]={0,0};
    U32 used_flags;
    U32 the_flag;
    IV key_is_utf8_generic=-1;
    IV val_is_utf8_generic=-1;
    char *table;
    char *state;
    struct str_buf str_buf_rec;
    struct str_buf *str_buf= &str_buf_rec;
    AV *second_pass_av= variant > 5 ? keys_av : buckets_av;
    struct str_len_obj str_len_objs;
    struct str_len_obj *str_len_obj= &str_len_objs;
    char separator;

    U32 last_k1;
    U32 last_k2;
    U32 first_k1_bucket;
    U32 first_k2_bucket;
    U32 str_len_rlen= 0;
    U32 pass = 0;
    U32 debug= flags & MPH_F_DEBUG;
    U32 debug_more= flags & MPH_F_DEBUG_MORE;

    for (i= 0; i < bucket_count; i++) {
        SV **got= av_fetch(buckets_av,i,0);
        HV *hv= (HV *)SvRV(*got);
        HE *key_is_utf8_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_KEY_IS_UTF8,0);
        HE *val_is_utf8_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_VAL_IS_UTF8,0);
        key_is_utf8_count[SvUV(HeVAL(key_is_utf8_he))]++;
        val_is_utf8_count[SvUV(HeVAL(val_is_utf8_he))]++;
    }
    used_flags= 0;
    if (key_is_utf8_count[0]) { the_flag= 0; used_flags++; }
    if (key_is_utf8_count[1]) { the_flag= 1; used_flags++; }
    if (key_is_utf8_count[2]) { the_flag= 2; used_flags++; }
    if (used_flags == 1) {
        key_is_utf8_generic= the_flag;
        key_flags_rlen= 0;
    }
    if (variant>6 && key_flags_rlen) croak("keys must be of uniform UTF8ness for a triple hash");

    used_flags= 0;
    if (val_is_utf8_count[0]) { the_flag= 0; used_flags++; }
    if (val_is_utf8_count[1]) { the_flag= 1; used_flags++; }
    if (used_flags == 1) {
        val_is_utf8_generic= the_flag;
        val_flags_rlen= 0;
    }
    if (variant > 6) {
        /* absolute worst case, every string component is unique  3 per key + 1 val */
        str_len_rlen= _roundup(sizeof(struct str_len) * 4 * bucket_count + 1, alignment);
        compressor_init(&compressor);
        str_len_init(&str_len_objs, &compressor);
    }


    total_size=
        + header_rlen
        + state_rlen
        + table_rlen
        + key_flags_rlen
        + val_flags_rlen
        + str_len_rlen          /* new in variant 7 */
        + str_rlen
        + sizeof(compressor)
        + 1024                  /* for good measure */
    ;

    sv_grow(buf_sv,total_size);
    SvPOK_on(buf_sv);
    SvCUR_set(buf_sv,total_size);
    start= SvPVX(buf_sv);
    Zero(start,total_size,char);
    head= (struct mph_header *)start;

    head->magic_num= 1278363728;
    head->variant= variant;
    head->num_buckets= bucket_count;
    head->state_ofs= header_rlen;
    head->table_ofs= head->state_ofs + state_rlen;
    head->key_flags_ofs= head->table_ofs + table_rlen;
    head->val_flags_ofs= head->key_flags_ofs + key_flags_rlen;
    if (variant > 6) {
        head->str_len_ofs= head->val_flags_ofs + val_flags_rlen;
        head->str_buf_ofs= 0;
        if (!SvOK(separator_sv)) croak("separator is a required parameter with variant 7");
        separator= SvPV_nolen(separator_sv)[0];
        head->separator= separator;
    } else {
        head->str_buf_ofs= head->val_flags_ofs + val_flags_rlen;
    }

    if (val_is_utf8_generic >= 0)
        head->utf8_flags |= (MPH_VALS_ARE_SAME_UTF8NESS_FLAG_BIT | (val_is_utf8_generic << MPH_VALS_ARE_SAME_UTF8NESS_SHIFT));
    if (key_is_utf8_generic >= 0)
        head->utf8_flags |= (MPH_KEYS_ARE_SAME_UTF8NESS_FLAG_BIT | (key_is_utf8_generic << MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT));

    state= start + head->state_ofs;
    table= start + head->table_ofs;

    key_flags= start + head->key_flags_ofs;
    val_flags= start + head->val_flags_ofs;

    Copy(state_pv,state,state_len,char);

    for (i= 0; i < bucket_count; i++) {
        SV **got= av_fetch(buckets_av,i,0);
        HV *hv= (HV *)SvRV(*got);
        HE *xor_val_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_XOR_VAL,0);
        HE *sort_index_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_SORT_INDEX,0);
        U32 sort_index= sort_index_he ? SvUV(HeVAL(sort_index_he)) : i;
        struct mph_sorted_bucket *bucket= (struct mph_sorted_bucket *)(table + (i * bucket_size));

        if (xor_val_he) {
            bucket->xor_val= SvUV(HeVAL(xor_val_he));
        } else {
            bucket->xor_val= 0;
        }
        if (variant > 5)
            bucket->sort_index= sort_index;
    }

    /* setting this to MPH_F_HASH_ONLY enables logic that bulk adds the strings
     * in a known order. */
RETRY:
    pass++;
    if (debug_more) warn("|pass #%d\n",pass);
    if (variant < 7) {
        str_buf_init(str_buf, start, start + head->str_buf_ofs, start + total_size);
        str_buf_add_from_sv(aTHX_ str_buf,comment_sv,NULL,0);
        str_buf_cat_char(aTHX_ str_buf,0);
    } else {
        last_k1= 0;
        last_k2= 0;
        first_k1_bucket= 0;
        first_k2_bucket= 0;
    }

    for (i= 0; i < bucket_count; i++) {
        SV **got= av_fetch(second_pass_av,i,0);
        HV *hv= (HV *)SvRV(*got);
        HE *key_normalized_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_KEY_NORMALIZED,0);
        HE *val_normalized_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_VAL_NORMALIZED,0);

        if (variant > 6) {
            /* split the sv into three - add the chunks */
            char *pv1;
            char *pv2;
            char *pv3;
            char *pvv;
            char *kend;
            STRLEN l1,l2,l3,kl,vl;
            SV *key_normalized_sv= HeVAL(key_normalized_he);
            SV *val_normalized_sv= HeVAL(val_normalized_he);
            struct mph_triple_bucket *bucket= (struct mph_triple_bucket *)(table + (i * bucket_size));

            pvv= SvOK(val_normalized_sv) ? SvPV_nomg(val_normalized_sv,vl) : 0;
            pv1= SvPV_nomg(key_normalized_sv,kl);

            kend= pv1+kl;
            pv2= memchr(pv1,separator,kend-pv1);
            if (!pv2) croak("no separator in key! %"SVf" len: %lu", key_normalized_sv, kl);
            l1= pv2 - pv1;
            pv2++;
            pv3= memchr(pv2,separator,kend-pv2);
            if (!pv3) croak("only one separator in key!");
            l2= pv3 - pv2;
            pv3++;
            l3= kend - pv3;

            /* now we have three chunks, pv1, pv2, pv3 and l1, l2, l3, and with kl being the length of
             * the full key with separators */
            bucket->k1_idx= str_len_add(aTHX_ str_len_obj, str_buf, pv1, l1, flags | MPH_F_IS_KEY);
            bucket->k2_idx= str_len_add(aTHX_ str_len_obj, str_buf, pv2, l2, flags | MPH_F_IS_KEY);
            bucket->k3_idx= str_len_add(aTHX_ str_len_obj, str_buf, pv3, l3, flags | MPH_F_IS_KEY);
            bucket->v_idx=  str_len_add(aTHX_ str_len_obj, str_buf, pvv, vl, flags | MPH_F_IS_VAL);
        } else {
            struct mph_sorted_bucket *bucket= (struct mph_sorted_bucket *)(table + (i * bucket_size));

            bucket->key_ofs= str_buf_add_from_he(aTHX_ str_buf,key_normalized_he,&bucket->key_len,flags);
            bucket->val_ofs= str_buf_add_from_he(aTHX_ str_buf,val_normalized_he,&bucket->val_len,flags);
        }

        if ( key_is_utf8_generic < 0) {
            HE *key_is_utf8_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_KEY_IS_UTF8,0);
            if (key_is_utf8_he) {
                UV u= SvUV(HeVAL(key_is_utf8_he));
                SETBITS(u,key_flags,i,2);
            } else {
                croak("panic: out of memory? no key_is_utf8_he for %ld",i);
            }
        }
        if ( val_is_utf8_generic < 0 ) {
            HE *val_is_utf8_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_VAL_IS_UTF8,0);
            if (val_is_utf8_he) {
                UV u= SvUV(HeVAL(val_is_utf8_he));
                SETBITS(u,val_flags,i,1);
            } else {
                croak("panic: out of memory? no val_is_utf8_he for %ld",i);
            }
        }
    }
    if (variant > 6) {
        if (!str_len_objs.str_len) { /* first pass */
            str_len_objs.count= str_len_objs.next; /* one larger than str_count */
            str_len_objs.next= 1;
            str_len_objs.str_len= (struct str_len *)(start + head->str_len_ofs);
            str_len_objs.str_len[0].ofs= 0; /* set ofs and len at once */
            str_len_objs.str_len[0].len= 0; /* set ofs and len at once */
            head->str_buf_ofs= head->str_len_ofs + sizeof(struct str_len) * str_len_objs.count;

            str_buf_init(str_buf, start, start + head->str_buf_ofs, start + total_size);
            str_buf_add_from_sv(aTHX_ str_buf,comment_sv,NULL,0);
            str_buf_cat_char(aTHX_ str_buf, 0);

            if ((flags & (MPH_F_COMPRESS_KEYS|MPH_F_COMPRESS_VALS)) != (MPH_F_COMPRESS_KEYS|MPH_F_COMPRESS_VALS)) {
                AV *uncompressed_av= (AV *)sv_2mortal((SV *)newAV());

                HV *hv= str_len_objs.uncompressed_hv;
                HE *he;
                IV str_count;
                hv_iterinit(hv);
                while (he= hv_iternext(hv)) {
                    SV *key= newSVhek(HeKEY_hek(he));
                    av_push(uncompressed_av, key);
                }
                str_count= av_top_index(uncompressed_av)+1;
                if (debug_more) {
                    warn("|uncompressed strings: %ld\n",str_count);
                    warn("|Starting trigram overlap detection.\n");
                }

                (void)trigram_add_strs_from_av(aTHX_ uncompressed_av, str_buf);
                if (debug_more)
                    warn("|Adding to str_len structure.\n");
                /* now add the string to the str_len in alphabetical order
                 * this makes our key tables have pleasing properties */
                sortsv(AvARRAY(uncompressed_av),str_count,Perl_sv_cmp);
                for(i = 0 ; i < str_count ; i++ ) {
                    SV **svp= av_fetch(uncompressed_av,i,0);
                    SV *sv= *svp;
                    STRLEN len;
                    char *pv= SvPV_nomg(sv,len);
                    str_len_add(aTHX_ str_len_obj, str_buf, pv, len, flags | MPH_F_IS_KEY);
                }
            }
            goto RETRY;
        } /* end first pass */
        else { /* second pass */
            struct mph_triple_bucket *first_bucket= (struct mph_triple_bucket *)(table);
            struct mph_triple_bucket *last_bucket= first_bucket + bucket_count - 1;
            struct mph_triple_bucket *bucket;
            if (bucket_count == 1) {
                first_bucket->n1= MPH_FN_NEG(first_bucket,first_bucket,first_bucket);
                first_bucket->n2= MPH_FN_NEG(first_bucket,first_bucket,first_bucket);
            } else {
                struct mph_triple_bucket *end_bucket= last_bucket+1;
                struct mph_triple_bucket *first_k1_bucket= first_bucket;
                struct mph_triple_bucket *first_k2_bucket= first_bucket;
                struct mph_triple_bucket *prev_bucket= first_bucket;

                for (bucket= first_bucket + 1; bucket <= last_bucket; bucket++) {
                    if (bucket->k1_idx != first_k1_bucket->k1_idx) {
                        prev_bucket->n1= MPH_FN_NEG(first_k1_bucket,first_bucket,prev_bucket);
                        prev_bucket->n2= MPH_FN_NEG(first_k2_bucket,first_bucket,prev_bucket);
                        first_k1_bucket= first_k2_bucket= bucket;
                    }
                    else
                    if (bucket->k2_idx != first_k2_bucket->k2_idx) {
                        prev_bucket->n2= MPH_FN_NEG(first_k2_bucket,first_bucket,prev_bucket);
                        first_k2_bucket= bucket;
                    }
                    prev_bucket= bucket;
                }
                prev_bucket->n1= MPH_FN_NEG(first_k1_bucket,first_bucket,prev_bucket);
                prev_bucket->n2= MPH_FN_NEG(first_k2_bucket,first_bucket,prev_bucket);

                first_k1_bucket= first_k2_bucket= last_bucket;

                for (bucket= last_bucket - 1; bucket >= first_bucket; bucket--) {
                    if (bucket->n1) {
                        first_k1_bucket= first_k2_bucket= bucket;
                    }
                    else
                    if (bucket->n2) {
                        bucket->n1= MPH_FN_POS(first_k1_bucket,first_bucket,bucket);
                        first_k2_bucket= bucket;
                    }
                    else {
                        bucket->n1= MPH_FN_POS(first_k1_bucket,first_bucket,bucket);
                        bucket->n2= MPH_FN_POS(first_k2_bucket,first_bucket,bucket);
                    }
                }
            }
            if (debug_more)
                str_len_obj_dump(str_len_obj);

        } /*second pass*/
    } /* variant=6 handling */

    U32 sblen= 0;
    U32 codepair_frozen_size= 0;
    U32 next_codepair_id= 0;
    if (variant > 6) {
        char *frozen_pv;
        struct codepair_array_frozen *frozen;

        codepair_frozen_size= codepair_array_freeze(&compressor.codepair_array,NULL,debug);
        sblen= str_buf_len(str_buf);
        frozen_pv= str_buf_aligned_alloc(str_buf,codepair_frozen_size,8);
        if (!frozen_pv)
            croak("not enough memory? need codepair_frozen_size: %u", codepair_frozen_size);
        head->codepair_ofs= frozen_pv - start;
        frozen= (struct codepair_array_frozen *)frozen_pv;
        codepair_array_freeze(&compressor.codepair_array,frozen,debug);
        next_codepair_id= frozen->next_codepair_id;
        compressor_free(&compressor);
    }
    SvCUR_set(buf_sv, str_buf_finalize(aTHX_ str_buf, alignment, state));
    SvPOK_on(buf_sv);

    if (debug_more) {
        warn("|str_len.next: %d str_buf.len: %d with codepairs: %d\n",
                str_len_obj->next, sblen, str_buf_len(str_buf));
        warn("|state_ofs= %u\n", head->state_ofs);
        warn("|table_ofs= %u\n", head->table_ofs);
        warn("|key_flags_ofs= %u\n", head->key_flags_ofs);
        warn("|val_flags_ofs= %u\n", head->val_flags_ofs);
        warn("|str_len_ofs= %u\n", head->str_len_ofs);
        warn("|str_buf_ofs= %u\n", head->str_buf_ofs);
        warn("|codepairs: %u size: %u\n", next_codepair_id, codepair_frozen_size);
        warn("|refcount=%u\n", SvREFCNT(buf_sv));
        warn("|final_length= %lu (alloc= %lu)\n", SvCUR(buf_sv), SvLEN(buf_sv));
    }
    return SvCUR(buf_sv);
}


SV *
_mount_file(SV *file_sv, SV *error_sv, U32 flags)
{
    struct mph_obj obj;
    STRLEN file_len;
    char *file_pv= SvPV_nomg(file_sv,file_len);
    IV mmap_status;

    Zero(&obj,1,struct mph_obj);
    mmap_status= mph_mmap(aTHX_ file_pv, &obj, error_sv, flags);
    SV *retval;
    if (mmap_status < 0) {
        return NULL;
    }
    if (obj.header->variant == 7) {
        codepair_array_unfreeze(&obj.codepair_array,(struct codepair_array_frozen *)((char *)obj.header + obj.header->codepair_ofs));
    }

    /* copy obj into a new SV which we can return */
    retval= newSVpvn((char *)&obj,sizeof(struct mph_obj));
    SvPOK_on(retval);
    SvREADONLY_on(retval);
    return retval;
}


#define hv_fetchx(hv, key, klen, lval,hash)                             \
    ((SV**) hv_common_key_len((hv), (key), (klen), (lval)               \
                              ? (HV_FETCH_JUST_SV | HV_FETCH_LVALUE)    \
                              : HV_FETCH_JUST_SV, NULL, (hash)))

#define NGRAM_LEN 3
void
trigram_add_strs_from_av(pTHX_ AV *uncompressed_av, struct str_buf* str_buf ) {
    HV *tri_hv= (HV *)sv_2mortal((SV *)newHV());
    HV *tmp_hv= (HV *)sv_2mortal((SV *)newHV());
    HV *cache_hv= str_buf->hv;
    SV **packed_cache;
    IV str_count= av_top_index(uncompressed_av)+1;
    IV i;

    //warn("|trigram_add_str(%"SVf")\n", str_sv);
    //

    Newxz(packed_cache,(1<<24),SV *);
    SAVEFREEPV(packed_cache);
    /* first add the string to str_buf in order of longest to shortest
     * if str_buf gains the ability to pack strings tighter then we win */
    sortsv(AvARRAY(uncompressed_av),str_count,sv_cmp_len_desc_lex_asc);
    for(i = 0 ; i < str_count ; i++ ) {
        HE *he;
        STRLEN str_len;
        int search= 1;
        int do_add= 1;
        SV *str_sv= AvARRAY(uncompressed_av)[i];
        U8 *str_pv= SvPV(str_sv,str_len);
        SV *idx_sv;
        IV pos;
        U32 hash;
        SV *tri_sv;
        SV **svp;
        U32 fast_hash;

        if (str_len == 0)
            continue;
        SV **cached_svp= hv_fetch(cache_hv,str_pv,str_len,1);
        if (SvOK(*cached_svp))
            continue;

        hv_clear(tmp_hv);
        if (str_len < 3) {
            pos= str_buf_add_from_pvn(str_buf,str_pv,str_len,MPH_F_NO_DEDUPE);
            sv_setiv(*cached_svp, pos);
            continue;
        } else {
            U32 o;
            for (o=0; o <= str_len - NGRAM_LEN; o++) {
                fast_hash= *((U32 *)(str_pv+o)) & 0xFFFFFF; /* little endian x86 */
                //fast_hash += ( (U32)str_pv[o+2] << 16 );
                //fast_hash += ( (U32)str_pv[o+1] <<  8 );
                //fast_hash += ( (U32)str_pv[o+0] <<  0 );

                tri_sv= packed_cache[fast_hash];

                PERL_HASH(hash,str_pv+o,3);
                svp= hv_fetchx(tmp_hv,str_pv+o,3,1,hash);
                if (!SvOK(*svp)) {
                    if (!tri_sv) {
                        SV **tri_svp= hv_fetchx(tri_hv,str_pv + o, 3, 1, hash);
                        tri_sv= *tri_svp;
                        sv_upgrade(tri_sv,SVt_RV);
                        SvRV_set(tri_sv,(SV*)newAV());
                        SvROK_on(tri_sv);
                        search= 0;
                        packed_cache[fast_hash]= tri_sv;
                    }
                    sv_setsv(*svp, tri_sv);
                }
            }
        }
        if (search) {
            AV *best_av1= NULL;
            AV *best_av2= NULL;
            IV i= 0;
            IV j= 0;
            IV best_top1= 0;
            IV best_top2= 0;
            SV **best_svs1= NULL;
            SV **best_svs2= NULL;

            hv_iterinit(tmp_hv);
            while (he= hv_iternext(tmp_hv)) {
                if (HeKLEN(he) == NGRAM_LEN || str_len<NGRAM_LEN) {
                    AV *av= (AV *)SvRV(HeVAL(he));
                    IV top= av_top_index(av);
                    if (!best_av1 || top < best_top1) {
                        best_av2= best_av1;
                        best_top2= best_top1;
                        best_av1= av;
                        best_top1= top;
                    }
                    else
                    if (!best_av2 || top < best_top2) {
                        best_av2= av;
                        best_top2= top;
                    }
                }
            }
            if (!best_av2) {
                best_av2= best_av1;
                best_top2= best_top1;
            }

            best_svs1= AvARRAY(best_av1);
            best_svs2= AvARRAY(best_av2);
            while (i <= best_top1 && j <= best_top2) {
                IV a= SvIV(best_svs1[i]);
                IV b= SvIV(best_svs2[j]);
                while (a<b) {
                    i++;
                    if (i <= best_top1)
                        a= SvIV(best_svs1[i]);
                    else
                        goto do_add;
                }

                while ( b < a ) {
                    j++;
                    if (j <= best_top2)
                        b= SvIV(best_svs2[j]);
                    else
                        goto do_add;
                }

                if ( a == b ) {
                    SV *this_sv= AvARRAY(uncompressed_av)[a];
                    STRLEN this_len;
                    char *this_pv= SvPV_nomg(this_sv,this_len);
                    char *at_pv= memmem(this_pv, this_len, str_pv, str_len);
                    if (at_pv) {
                        SV **best_ofs_sv= hv_fetch(cache_hv,this_pv,this_len,0);
                        sv_setiv(*cached_svp,SvIV(*best_ofs_sv) + at_pv - this_pv);
                        do_add= 0;
                        break;
                    }
                    i++;
                    j++;
                }
            }
        }

        if (do_add) {
          do_add:
            idx_sv= newSViv(i);

            pos= str_buf_add_from_pvn(str_buf,str_pv,str_len,MPH_F_NO_DEDUPE);
            sv_setiv(*cached_svp,pos);

            hv_iterinit(tmp_hv);
            while (he= hv_iternext(tmp_hv)) {
                STRLEN tri_len;
                char *tri_pv= HePV(he,tri_len);
                AV *av= (AV *)SvRV(HeVAL(he));
                if (HeKLEN(he)<0) croak("sv key!?");
                if (HeKLEN(he) == NGRAM_LEN || av_top_index(av) < 0 ) {
                    av_push(av,SvREFCNT_inc(idx_sv));
                }
            }
            SvREFCNT_dec(idx_sv);

        }
    }
}

