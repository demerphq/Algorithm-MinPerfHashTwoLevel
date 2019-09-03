#ifndef MPH_SEED_BYTES
#define MPH_SEED_BYTES (sizeof(U64) * 2)
#endif
#ifndef MPH_STATE_BYTES
#define MPH_STATE_BYTES (sizeof(U64) * 4)
#endif


#ifndef MPH_MAP_FLAGS
#if defined(MAP_POPULATE) && defined(MAP_PREFAULT_READ)
#define MPH_MAP_FLAGS MAP_SHARED | MAP_POPULATE | MAP_PREFAULT_READ
#elif defined(MAP_POPULATE)
#define MPH_MAP_FLAGS MAP_SHARED | MAP_POPULATE
#elif defined(MAP_PREFAULT_READ)
#define MPH_MAP_FLAGS MAP_SHARED | MAP_PREFAULT_READ
#else
#define MPH_MAP_FLAGS MAP_SHARED
#endif
#endif

#define MOUNT_ARRAY_MOUNT_IDX 0
#define MOUNT_ARRAY_SEPARATOR_IDX 1

#define MPH_F_FILTER_UNDEF          (1<<0)
#define MPH_F_DETERMINISTIC         (1<<1)
#define MPH_F_NO_DEDUPE             (1<<2)
#define MPH_F_VALIDATE              (1<<3)
#define MPH_F_HASH_ONLY             (1<<4)

#define MPH_F_IS_KEY                (1<<17)
#define MPH_F_IS_VAL                (1<<18)
#define MPH_F_COMPRESS_KEYS         (1<<19)
#define MPH_F_COMPRESS_VALS         (1<<20)

#define MPH_F_DEBUG                 (1<<30)
#define MPH_F_DEBUG_MORE            (1<<31)


#if 1
#define MPH_HASH_FOR_FETCH 0
#else
#define MPH_HASH_FOR_FETCH 1
#endif

#define MPH_MOUNT_ERROR_OPEN_FAILED     (-1)
#define MPH_MOUNT_ERROR_FSTAT_FAILED    (-2)
#define MPH_MOUNT_ERROR_TOO_SMALL       (-3)
#define MPH_MOUNT_ERROR_BAD_SIZE        (-4)
#define MPH_MOUNT_ERROR_MAP_FAILED      (-5)
#define MPH_MOUNT_ERROR_BAD_MAGIC       (-6)
#define MPH_MOUNT_ERROR_BAD_VERSION     (-7)
#define MPH_MOUNT_ERROR_BAD_OFFSETS     (-8)
#define MPH_MOUNT_ERROR_CORRUPT_TABLE   (-9)
#define MPH_MOUNT_ERROR_CORRUPT_STR_BUF (-10)
#define MPH_MOUNT_ERROR_CORRUPT_FILE    (-11)

#define MAGIC_DECIMAL 1278363728 /* PH2L */
#define MAGIC_BIG_ENDIAN_DECIMAL 1346908748

#define MPH_VALS_ARE_SAME_UTF8NESS_FLAG_BIT   1           /* 0000 0001 */
#define MPH_VALS_ARE_SAME_UTF8NESS_MASK       3           /* 0000 0011 */
#define MPH_VALS_ARE_SAME_UTF8NESS_SHIFT      1           /*  000 0001 */
#define MPH_KEYS_ARE_SAME_UTF8NESS_FLAG_BIT   4           /* 0000 0100 */
#define MPH_KEYS_ARE_SAME_UTF8NESS_MASK       (7 << 2)    /* 0001 1100 */
#define MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT      3           /*    0 0011 */

/*
#ifndef av_top_index
#define av_top_index(x) av_len(x)
#endif
*/

#ifndef MPH_STATIC_INLINE
#ifdef PERL_STATIC_INLINE
#define MPH_STATIC_INLINE PERL_STATIC_INLINE
#else
#define MPH_STATIC_INLINE static inline
#endif
#endif


#define HASH2INDEX(x,h2,xor_val,bucket_count) STMT_START {      \
        x= h2 ^ xor_val;                                                \
        /* see: https://stackoverflow.com/a/12996028                    \
         * but we could use any similar integer hash function. */       \
        x = ((x >> 16) ^ x) * 0x45d9f3b;                                \
        x = ((x >> 16) ^ x) * 0x45d9f3b;                                \
        x = ((x >> 16) ^ x);                                            \
        x %= bucket_count;                                              \
} STMT_END

#ifndef CHAR_BITS
#define CHAR_BITS 8
#endif

#define _BITSDECL(idx,bits) \
    const U64 bitpos= idx * bits;                           \
    const U64 bytepos= bitpos / CHAR_BITS;                  \
    const U8 shift= bitpos % CHAR_BITS;                     \
    const U8 bitmask= ( 1 << bits ) - 1

#define GETBITS(into,flags,idx,bits) STMT_START {           \
    _BITSDECL(idx,bits);                                    \
    into= ((flags)[bytepos] >> shift) & bitmask;            \
} STMT_END

#define SETBITS(value,flags,idx,bits) STMT_START {          \
    _BITSDECL(idx,bits);                                    \
    const U8 v= value;                                      \
    (flags)[bytepos] &= ~(bitmask << shift);                \
    (flags)[bytepos] |= ((v & bitmask) << shift);           \
} STMT_END

#define MAX_VARIANT 7
#define MIN_VARIANT 5


#define STR_LEN_PTR(mph)        ((struct str_len *)((U8 *)mph + mph->str_len_ofs))
#define STR_BUF_PTR(mph)        ((U8 *)mph + mph->str_buf_ofs)
#define KEY_FLAGS_PTR(mph)      ((U8 *)mph + mph->key_flags_ofs)
#define VAL_FLAGS_PTR(mph)      ((U8 *)mph + mph->val_flags_ofs)
#define STATE_PTR(mph)          ((U8 *)mph + mph->state_ofs)
#define TABLE_PTR(mph)          ((U8 *)mph + mph->table_ofs)
#define BUCKET_PTR(mph)         ((struct mph_bucket *)((U8 *)mph + mph->table_ofs))
#define SORTED_BUCKET_PTR(mph)  ((struct mph_sorted_bucket *)((U8 *)mph + mph->table_ofs))
#define TRIPLE_BUCKET_PTR(mph)  ((struct mph_triple_bucket *)((U8 *)mph + mph->table_ofs))
#define NUM_BUCKETS(mph)        ((mph)->num_buckets)
#define MPH_UTF8_FLAGS(mph)     ((mph)->utf8_flags)
#define MPH_VARIANT(mph)        ((mph)->variant)
#define MPH_BUCKET_SIZE(mph)    BUCKET_SIZE(MPH_VARIANT(mph))
#define MPH_IS_SORTED(mph)      (MPH_VARIANT(mph)==6)
#define MPH_IS_TRIPLE(mph)      (MPH_VARIANT(mph)==7)


#define MPH_STR_LEN_HV_IDX 0
#define MPH_STR_LEN_NEXT_IDX 1
#define MPH_STR_LEN_UNDEF_IDX 2

#define MPH_NEG(n) ((-(n))-1)
#define MPH_FN_NEG(first_k_bucket,first_bucket,prev_bucket) MPH_NEG(prev_bucket - first_k_bucket)
#define MPH_FN_POS(first_k_bucket,first_bucket,prev_bucket) (first_k_bucket - prev_bucket)


#define BUCKET_SIZE(variant) (                                \
     ((variant) == 5) ? sizeof(struct mph_bucket) :           \
     ((variant) == 6) ? sizeof(struct mph_sorted_bucket) :    \
                        sizeof(struct mph_triple_bucket)      \
)


#define mph_any_bucket mph_triple_bucket

#define DEBUGF 0
#define FAST_SV_CONSTRUCT 0

#include "mph2l_struct.h"
#include "mph2l_keys.h"
#include "str_buf.h"
#include "triple.h"
#include "trie2.h"

UV _compute_xs(pTHX_ HV *self_hv, struct sv_with_hash *keyname_sv);
SV *_seed_state(pTHX_ SV *base_seed_sv);
UV _hash_with_state_sv(pTHX_ SV *str_sv, SV *state_sv);
IV _packed_xs(pTHX_ SV *buf_sv, U32 variant, SV *buf_length_sv, SV *state_sv, SV* comment_sv, U32 flags, AV *buckets_av, struct sv_with_hash *keyname_sv, AV * keys_av, SV *separator_sv);
SV *_mount_file(SV *file_sv, SV *error_sv, U32 flags);
void _mph_munmap(struct mph_obj *obj);
int lookup_bucket(pTHX_ struct mph_header *mph, U32 index, SV *key_sv, SV *val_sv);
int lookup_key(pTHX_ struct mph_header *mph, SV *key_sv, SV *val_sv);

IV find_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r, I32 cmp_val);
IV find_first_last_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r, IV *last);
IV find_last_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r);
IV find_first_prefix(pTHX_ struct mph_header *mph, SV *pfx_sv, IV l, IV r);

I32 sv_prefix_cmp3(pTHX_ SV *l_sv, SV *r_sv, SV *r_sv_utf8);
I32 sv_cmp_hash(pTHX_ SV *a, SV *b);

void trigram_add_strs_from_av(pTHX_ AV *uncompressed_av, struct str_buf *str_buf);


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

MPH_STATIC_INLINE void
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
sv_set_from_bucket(pTHX_ SV *sv, U8 *strs, const U32 ofs, const U32 len, const U32 idx, const U8 *flags,
        const U32 bits, const U8 utf8_default, const U8 utf8_default_shift) {
    sv_set_from_bucket_extra(aTHX_ sv, strs, ofs, len, idx, flags,bits, utf8_default, utf8_default_shift, 0);
}

MPH_STATIC_INLINE
int
cpid_eq_pvn(pTHX_ struct codepair_array *codepair_array, const U32 id, const U32 len, char *pvc, const U32 pv_len) {
    return pv_len == len &&
           !cpid_cmp_pv_recursive_stack(aTHX_ codepair_array, id, &pvc, pvc + pv_len, 0);
}

MPH_STATIC_INLINE
int
cpid_eq_sv(pTHX_ struct codepair_array *codepair_array, const U32 id, const U32 len, SV *want_sv) {
    char *want_pv;
    STRLEN want_len;
    want_pv= SvPV_nomg(want_sv,want_len);

    return cpid_eq_pvn(aTHX_ codepair_array, id, len, want_pv, want_len);
}

MPH_STATIC_INLINE
int
str_len_pv_eq(struct codepair_array *codepair_array, struct str_len *str_len, U8 *strs, U32 str_len_idx, char *want_pv, STRLEN want_len) {
    U32 got_ofs= str_len[str_len_idx].ofs;
    I32 got_len= str_len[str_len_idx].len;
    if (got_len < 0) {
        got_len= -got_len;
        return cpid_eq_pvn(codepair_array, got_ofs, got_len, want_pv, want_len);
    } else {
        U8 *got_pv= strs + got_ofs;
        return got_len == want_len && memEQ(want_pv, got_pv, want_len);
    }
}

MPH_STATIC_INLINE
int
str_len_sv_eq(struct codepair_array *codepair_array, struct str_len *str_len, U8 *strs, U32 str_len_idx, SV *sv) {
    STRLEN want_len;
    U8 *want_pv= SvPV_nomg(sv,want_len);
    return str_len_pv_eq(codepair_array, str_len, strs, str_len_idx, want_pv, want_len);
}


