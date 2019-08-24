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
        bucket= TRIPLE_BUCKET_PTR(mph);
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
        U8 *strs= STR_BUF_PTR(mph);
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
    U8 utf8_flags= MPH_UTF8_FLAGS(mph);
    struct codepair_array *codepair_array= &obj->codepair_array;

    triple_set_key_fast(aTHX_ codepair_array, STR_BUF_PTR(mph), KEY_FLAGS_PTR(mph), ofs, len, bucket_idx, key_sv, utf8_flags);
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
    U32 num_buckets = NUM_BUCKETS(mph);
    I32 cmp;
    U8 *mph_u8= (U8*)mph;
    U8 utf8_flags= MPH_UTF8_FLAGS(mph);
    char *table_start= TABLE_PTR(mph);
    U32 bucket_size= MPH_BUCKET_SIZE(mph);
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
        struct mph_triple_bucket *bucket_start= TRIPLE_BUCKET_PTR(mph);
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

char *
triple_build_mortal_key(pTHX_ SV *p1_sv, SV *p2_sv, SV *key_sv, STRLEN *full_key_lenp, const char separator) {
    STRLEN full_key_len= SvCUR(p1_sv) + SvCUR(p2_sv) + SvCUR(key_sv) + 2;
    char *pv;
    char *cpv;

    char *ppv; /* part pv */
    STRLEN pkl; /* part key len */

    Newx(pv,full_key_len,char);
    SAVEFREEPV(pv);
    cpv= pv;

    ppv= SvPV_nomg(p1_sv,pkl);
    Copy(ppv,cpv,pkl,char);
    cpv += pkl;

    *cpv++ = separator;

    ppv= SvPV_nomg(p2_sv,pkl);
    Copy(ppv,cpv,pkl,char);
    cpv += pkl;

    *cpv++ = separator;

    ppv= SvPV_nomg(key_sv,pkl);
    Copy(ppv,cpv,pkl,char);
    *full_key_lenp= full_key_len;
}

int
triple_lookup_key_pvn(pTHX_ struct mph_obj *obj, struct mph_multilevel *ml, SV *full_key_sv, U8 *full_key_pv, STRLEN full_key_len,
        SV *val_sv, SV *leaf_sv)
{
    struct mph_header *mph= obj->header;
    struct codepair_array *codepair_array= &obj->codepair_array;
    U32 bucket_size= MPH_BUCKET_SIZE(mph);
    struct str_len *str_len= STR_LEN_PTR(mph);
    U8 *strs= STR_BUF_PTR(mph);
    struct mph_triple_bucket *first_bucket= TRIPLE_BUCKET_PTR(mph);
    struct mph_triple_bucket *bucket;
    U8 *state= STATE_PTR(mph);
    U64 h0;
    U32 h1;
    U32 h2;
    U32 index;
    U8 *got_key_pv;
    STRLEN got_key_len;
    int foundit= 0;

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
    index= h1 % NUM_BUCKETS(mph);

    bucket= first_bucket + index;
    if (!bucket->xor_val)
        return 0;

    h2= h0 & 0xFFFFFFFF;
    if ( bucket->index < 0 ) {
        index = -bucket->index-1;
    } else {
        HASH2INDEX(index,h2,bucket->xor_val,NUM_BUCKETS(mph));
    }

    bucket= first_bucket + index;
    index= bucket->sort_index;
    bucket= first_bucket + index;

    if (leaf_sv) {
        assert(ml); /* ml required when leaf_sv is provided */
        if (
            ml->k1_idx == bucket->k1_idx &&
            ml->k2_idx == bucket->k2_idx &&
            str_len_sv_eq(codepair_array, str_len, strs, bucket->k3_idx, leaf_sv)
        ) {
            foundit =1;
        }
    } else {
        U8 *pv2;
        U8 *pv3;
        U8 *full_key_end= full_key_pv + full_key_len;
        STRLEN len1, len2, len3;
        pv2= memchr(full_key_pv,ml->separator,full_key_len);
        if (!pv2) warn("key '%"SVf"' does not contain a separator", full_key_sv);
        len1= pv2 - full_key_pv;
        pv2++;
        pv3= memchr(pv2, ml->separator, full_key_end - pv2);
        if (!pv3) warn("key '%"SVf"' only contains one separator", full_key_sv);
        len2= pv3 - pv2;
        pv3++;
        len3= full_key_end - pv3;
        if (0) warn("full_key: '%.*s' p1: '%.*s' p2: '%.*s' p3: '%.*s'",
                (int)full_key_len, full_key_pv,
                (int)len1, full_key_pv,
                (int)len2, pv2,
                (int)len3, pv3);

        if (
            str_len_pv_eq(codepair_array, str_len, strs, bucket->k1_idx, full_key_pv, len1) &&
            str_len_pv_eq(codepair_array, str_len, strs, bucket->k2_idx, pv2, len2) &&
            str_len_pv_eq(codepair_array, str_len, strs, bucket->k3_idx, pv3, len3)
        ) {
            foundit= 1;
        }
    }

    if (foundit && val_sv)
        triple_set_val(aTHX_ obj, bucket, index, val_sv);

    return foundit;
}


