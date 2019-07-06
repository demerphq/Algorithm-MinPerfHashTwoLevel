#ifndef MPH_SEED_BYTES
#define MPH_SEED_BYTES (sizeof(U64) * 2)
#endif
#ifndef MPH_STATE_BYTES
#define MPH_STATE_BYTES (sizeof(U64) * 4)
#endif

#define U64 U64TYPE

#ifndef MPH_MAP_POPULATE
#ifdef MAP_POPULATE
#define MPH_MAP_POPULATE MAP_POPULATE
#else
#define MPH_MAP_POPULATE MAP_PREFAULT_READ
#endif
#endif

#define MPH_KEYSV_IDX               0
#define MPH_KEYSV_H1_KEYS           1
#define MPH_KEYSV_XOR_VAL           2
#define MPH_KEYSV_H0                3
#define MPH_KEYSV_KEY               4
#define MPH_KEYSV_KEY_NORMALIZED    5
#define MPH_KEYSV_KEY_IS_UTF8       6
#define MPH_KEYSV_VAL               7
#define MPH_KEYSV_VAL_NORMALIZED    8
#define MPH_KEYSV_VAL_IS_UTF8       9
#define MPH_KEYSV_SORT_INDEX        10

#define MPH_KEYSV_VARIANT           11
#define MPH_KEYSV_COMPUTE_FLAGS     12
#define MPH_KEYSV_STATE             13
#define MPH_KEYSV_SOURCE_HASH       14
#define MPH_KEYSV_BUF_LENGTH        15
#define MPH_KEYSV_BUCKETS           16
#define MPH_KEYSV_MOUNT             17

#define COUNT_MPH_KEYSV 18

#define MPH_INIT_KEYSV(idx, str) STMT_START {                           \
    MY_CXT.keyname_sv[idx].sv = newSVpvn((str ""), (sizeof(str) - 1));       \
    PERL_HASH(MY_CXT.keyname_sv[idx].hash, (str ""), (sizeof(str) - 1));     \
} STMT_END

#define MPH_INIT_ALL_KEYSV() STMT_START {\
    MY_CXT_INIT;                                                \
    MPH_INIT_KEYSV(MPH_KEYSV_IDX,"idx");                        \
    MPH_INIT_KEYSV(MPH_KEYSV_H1_KEYS,"h1_keys");                \
    MPH_INIT_KEYSV(MPH_KEYSV_XOR_VAL,"xor_val");                \
    MPH_INIT_KEYSV(MPH_KEYSV_H0,"h0");                          \
    MPH_INIT_KEYSV(MPH_KEYSV_KEY,"key");                        \
    MPH_INIT_KEYSV(MPH_KEYSV_KEY_NORMALIZED,"key_normalized");  \
    MPH_INIT_KEYSV(MPH_KEYSV_KEY_IS_UTF8,"key_is_utf8");        \
    MPH_INIT_KEYSV(MPH_KEYSV_VAL,"val");                        \
    MPH_INIT_KEYSV(MPH_KEYSV_VAL_NORMALIZED,"val_normalized");  \
    MPH_INIT_KEYSV(MPH_KEYSV_VAL_IS_UTF8,"val_is_utf8");        \
    MPH_INIT_KEYSV(MPH_KEYSV_SORT_INDEX,"sort_index");          \
                                                                \
    MPH_INIT_KEYSV(MPH_KEYSV_VARIANT,"variant");                \
    MPH_INIT_KEYSV(MPH_KEYSV_COMPUTE_FLAGS,"compute_flags");    \
    MPH_INIT_KEYSV(MPH_KEYSV_STATE,"state");                    \
    MPH_INIT_KEYSV(MPH_KEYSV_SOURCE_HASH,"source_hash");        \
    MPH_INIT_KEYSV(MPH_KEYSV_BUF_LENGTH,"buf_length");          \
    MPH_INIT_KEYSV(MPH_KEYSV_BUCKETS,"buckets");                \
    MPH_INIT_KEYSV(MPH_KEYSV_MOUNT,"mount");                    \
} STMT_END

#define MPH_F_FILTER_UNDEF          (1<<0)
#define MPH_F_DETERMINISTIC         (1<<1)
#define MPH_F_NO_DEDUPE             (1<<2)
#define MPH_F_VALIDATE              (1<<3)

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

#define hv_fetch_ent_with_keysv(hv,keysv_idx,lval)                      \
    hv_fetch_ent(hv,keyname_sv[keysv_idx].sv,lval,keyname_sv[keysv_idx].hash);

#define hv_store_ent_with_keysv(hv,keysv_idx,val_sv)                    \
    hv_store_ent(hv,keyname_sv[keysv_idx].sv,val_sv,keyname_sv[keysv_idx].hash);

#define hv_copy_with_keysv(hv1,hv2,keysv_idx) STMT_START {              \
    HE *got_he= hv_fetch_ent_with_keysv(hv1,keysv_idx,0);               \
    if (got_he) {                                                       \
        SV *got_sv= HeVAL(got_he);                                      \
        hv_store_ent_with_keysv(hv2,keysv_idx,got_sv);                  \
        SvREFCNT_inc(got_sv);                                           \
    }                                                                   \
} STMT_END

#define hv_setuv_with_keysv(hv,keysv_idx,uv)                            \
STMT_START {                                                            \
    HE *got_he= hv_fetch_ent_with_keysv(hv,keysv_idx,1);                \
    if (got_he) sv_setuv(HeVAL(got_he),uv);                             \
} STMT_END

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

#define MAX_VARIANT 6
#define MIN_VARIANT 5

struct sv_with_hash {
    SV *sv;
    U32 hash;
};

typedef struct {
    struct sv_with_hash keyname_sv[COUNT_MPH_KEYSV];
} my_cxt_t;

struct mph_header {
    U32 magic_num;
    U32 variant;
    U32 num_buckets;
    U32 state_ofs;

    U32 table_ofs;
    U32 key_flags_ofs;
    U32 val_flags_ofs;
    U32 str_buf_ofs;

    union {
        U64 table_checksum;
        U64 general_flags;
    };
    union {
        U64 str_buf_checksum;
    };
};

#define BUCKET_FIELDS   \
    union {             \
        U32 xor_val;    \
        I32 index;      \
    };                  \
    U32 key_ofs;        \
    U32 val_ofs;        \
    U16 key_len;        \
    U16 val_len

struct mph_bucket {
    BUCKET_FIELDS;
};

struct mph_sorted_bucket {
    BUCKET_FIELDS;
    U32 sort_index;
};


struct mph_obj {
    size_t bytes;
    struct mph_header *header;
};

#include "mph_hv_macro.h"
#include "mph_siphash.h"

MPH_STATIC_INLINE void
sv_set_from_bucket(pTHX_ SV *sv, U8 *strs, const U32 ofs, const U32 len, const U32 idx, const U8 *flags, const U32 bits, const U8 utf8_default, const U8 utf8_default_shift) {
    U8 *ptr;
    U8 is_utf8;
    if (ofs) {
        ptr= (strs) + (ofs);
        if (utf8_default) {
            is_utf8= utf8_default >> utf8_default_shift;
        } else {
            GETBITS(is_utf8,flags,idx,bits);
        }
    } else {
        ptr= 0;
        is_utf8= 0;
    }
    /* note that sv_setpvn() will cause the sv to
     * become undef if ptr is 0 */
    sv_setpvn_mg((sv),ptr,len);
    if (is_utf8 > 1) {
        sv_utf8_upgrade(sv);
    }
    else
    if (is_utf8) {
        SvUTF8_on(sv);
    }
    else
    if (ptr) {
        SvUTF8_off(sv);
    }
}

MPH_STATIC_INLINE int
lookup_bucket(pTHX_ struct mph_header *mph, U32 index, SV *key_sv, SV *val_sv)
{
    struct mph_bucket *bucket;
    U8 *strs;
    U8 *mph_u8= (U8*)mph;
    U64 gf= mph->general_flags;
    if (index >= mph->num_buckets) {
        return 0;
    }
    bucket= (struct mph_bucket *)
            ((char *)mph + mph->table_ofs + (index * (mph->variant == 5
                                                      ? sizeof(struct mph_bucket)
                                                      : sizeof(struct mph_sorted_bucket))));

    strs= (U8 *)mph + mph->str_buf_ofs;
    if (val_sv) {
        sv_set_from_bucket(aTHX_ val_sv,strs,bucket->val_ofs,bucket->val_len,index,mph_u8 + mph->val_flags_ofs,1,
                                 gf & MPH_VALS_ARE_SAME_UTF8NESS_MASK, MPH_VALS_ARE_SAME_UTF8NESS_SHIFT);
    }
    if (key_sv) {
        sv_set_from_bucket(aTHX_ key_sv,strs,bucket->key_ofs,bucket->key_len,index,mph_u8 + mph->key_flags_ofs,2,
                                 gf & MPH_KEYS_ARE_SAME_UTF8NESS_MASK, MPH_KEYS_ARE_SAME_UTF8NESS_SHIFT);
    }
    return 1;
}

MPH_STATIC_INLINE int
lookup_key(pTHX_ struct mph_header *mph, SV *key_sv, SV *val_sv)
{
    U8 *strs= (U8 *)mph + mph->str_buf_ofs;
    char *table= ((char *)mph + mph->table_ofs);
    U32 bucket_size= (mph->variant == 5) ? sizeof(struct mph_bucket) : sizeof(struct mph_sorted_bucket);
    struct mph_sorted_bucket *bucket;
    U8 *state= (char *)mph + mph->state_ofs;
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
    key_pv= SvPV(key_sv,key_len);
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
            U64 gf= mph->general_flags;
            sv_set_from_bucket(aTHX_ val_sv, strs, bucket->val_ofs, bucket->val_len, index,
                                 ((U8*)mph)+mph->val_flags_ofs, 1,
                                 gf & MPH_VALS_ARE_SAME_UTF8NESS_MASK, MPH_VALS_ARE_SAME_UTF8NESS_SHIFT);
        }
        return 1;
    }
    return 0;
}

UV _compute_xs(pTHX_ HV *self_hv, struct sv_with_hash *keyname_sv);
SV *_seed_state(pTHX_ SV *base_seed_sv);
UV _hash_with_state_sv(pTHX_ SV *str_sv, SV *state_sv);
SV *_packed_xs(U32 variant, SV *buf_length_sv, SV *state_sv, SV* comment_sv, U32 flags, AV *buckets_av, struct sv_with_hash *keyname_sv);
SV *_mount_file(SV *file_sv, SV *error_sv, U32 flags);
void _mph_munmap(struct mph_obj *obj);

