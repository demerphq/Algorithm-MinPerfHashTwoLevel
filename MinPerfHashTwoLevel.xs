#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"
#include "stadtx_hash.h"
#include <sys/mman.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <assert.h>

#ifndef STADTX_SEED_BYTES
#define STADTX_SEED_BYTES (sizeof(U64) * 2)
#endif
#ifndef STADTX_STATE_BYTES
#define STADTX_STATE_BYTES (sizeof(U64) * 4)
#endif

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

#define MPH_KEYSV_VARIANT           10
#define MPH_KEYSV_COMPUTE_FLAGS     11
#define MPH_KEYSV_STATE             12
#define MPH_KEYSV_SOURCE_HASH       13
#define MPH_KEYSV_BUF_LENGTH        14
#define MPH_KEYSV_BUCKETS           15

#define COUNT_MPH_KEYSV 16

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
#define MPH_MOUNT_ERROR_CORRUPT_OFFSETS (-8)
#define MPH_MOUNT_ERROR_CORRUPT_TABLE   (-9)
#define MPH_MOUNT_ERROR_CORRUPT_STR_BUF (-10)

typedef struct {
    SV *sv;
    U32 hash;
} sv_with_hash;

typedef struct {
    sv_with_hash keysv[COUNT_MPH_KEYSV];
} my_cxt_t;

#define MPH_INIT_KEYSV(idx, str) STMT_START {                           \
    MY_CXT.keysv[idx].sv = newSVpvn((str ""), (sizeof(str) - 1));       \
    PERL_HASH(MY_CXT.keysv[idx].hash, (str ""), (sizeof(str) - 1));     \
} STMT_END

#define hv_fetch_ent_with_keysv(hv,keysv_idx,lval)                      \
    hv_fetch_ent(hv,MY_CXT.keysv[keysv_idx].sv,lval,MY_CXT.keysv[keysv_idx].hash);

#define hv_store_ent_with_keysv(hv,keysv_idx,val_sv)                    \
    hv_store_ent(hv,MY_CXT.keysv[keysv_idx].sv,val_sv,MY_CXT.keysv[keysv_idx].hash);

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
        x= h2 ^ xor_val;                                        \
        /*x = ((x >> 16) ^ x) * 0x45d9f3b;                        \
        x = ((x >> 16) ^ x) * 0x45d9f3b;                        \
        x = (x >> 16) ^ x;*/                                      \
        x %= bucket_count;                                      \
} STMT_END

struct mph_header {
    U32 magic_num;
    U32 variant;
    U32 num_buckets;
    U32 state_ofs;

    U32 table_ofs;
    U32 key_flags_ofs;
    U32 val_flags_ofs;
    U32 str_buf_ofs;

    U64 table_checksum;
    U64 str_buf_checksum;
};

struct mph_bucket {
    union {
        U32 xor_val;
        I32 index;
    };
    U32 key_ofs;
    U32 val_ofs;
    U16 key_len;
    U16 val_len;
};

struct mph_obj {
    size_t bytes;
    struct mph_header *header;
    int fd;
};

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

#define sv_set_from_bucket(sv,strs,ofs,len,idx,flags,bits) \
STMT_START {                                            \
    U8 *ptr;                                            \
    U8 is_utf8;                                         \
    if (ofs) {                                          \
        ptr= (strs) + (ofs);                            \
        GETBITS(is_utf8,flags,idx,bits);                \
    } else {                                            \
        ptr= 0;                                         \
        is_utf8= 0;                                     \
    }                                                   \
    /* note that sv_setpvn() will cause the sv to       \
     * become undef if ptr is 0 */                      \
    sv_setpvn_mg((sv),ptr,len);                         \
    if (is_utf8 > 1) {                                  \
        sv_utf8_upgrade(sv);                            \
    }                                                   \
    else                                                \
    if (is_utf8) {                                      \
        SvUTF8_on(sv);                                  \
    }                                                   \
    else                                                \
    if (ptr) {                                          \
        SvUTF8_off(sv);                                 \
    }                                                   \
} STMT_END

int
lookup_bucket(pTHX_ struct mph_header *mph, U32 index, SV *key_sv, SV *val_sv)
{
    struct mph_bucket *bucket;
    U8 *strs;
    if (index >= mph->num_buckets) {
        return 0;
    }
    bucket= (struct mph_bucket *)((char *)mph + mph->table_ofs) + index;
    strs= (U8 *)mph + mph->str_buf_ofs;
    if (key_sv) {
        sv_set_from_bucket(key_sv,strs,bucket->key_ofs,bucket->key_len,index,((U8*)mph)+mph->key_flags_ofs,2);
    }
    if (val_sv) {
        sv_set_from_bucket(val_sv,strs,bucket->val_ofs,bucket->val_len,index,((U8*)mph)+mph->val_flags_ofs,1);
    }
    return 1;
}

int
lookup_key(pTHX_ struct mph_header *mph, SV *key_sv, SV *val_sv)
{
    U8 *strs= (U8 *)mph + mph->str_buf_ofs;
    struct mph_bucket *buckets= (struct mph_bucket *) ((char *)mph + mph->table_ofs);
    struct mph_bucket *bucket;
    U8 *state= (char *)mph + mph->state_ofs;
    STRLEN key_len;
    U8 *key_pv;
    U64 h0;
    U32 h1;
    U32 index;

    if (SvUTF8(key_sv)) {
        SV *tmp= sv_2mortal(newSVsv(key_sv));
        sv_utf8_downgrade(tmp,1);
        key_sv= tmp;
    }
    key_pv= SvPV(key_sv,key_len);
    h0= stadtx_hash_with_state(state,key_pv,key_len);
    h1= h0 >> 32;
    index= h1 % mph->num_buckets;

    bucket= buckets + index;
    if (!bucket->xor_val) {
        return 0;
    } else {
        U32 h2= h0 & 0xFFFFFFFF;
        U8 *got_key_pv;
        STRLEN got_key_len;
        if ( mph->variant == 0 || bucket->index > 0 ) {
            HASH2INDEX(index,h2,bucket->xor_val,mph->num_buckets);
        } else { /* mph->variant == 1 */
            index = -bucket->index-1;
        }
        bucket= buckets + index;
        got_key_pv= strs + bucket->key_ofs;
        if (bucket->key_len == key_len && memEQ(key_pv,got_key_pv,key_len)) {
            if (val_sv) {
                sv_set_from_bucket(val_sv,strs,bucket->val_ofs,bucket->val_len,index,((U8*)mph)+mph->val_flags_ofs,1);
            }
            return 1;
        }
        return 0;
    }
}

IV
mph_mmap(pTHX_ char *file, struct mph_obj *obj, SV *error, U32 flags) {
    struct stat st;
    struct mph_header *head;
    int fd = open(file, O_RDONLY, 0);
    void *ptr;

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
    if (st.st_size % 16) {
        if (error)
            sv_setpvf(error,"file '%s' does not have a size which is a multiple of 16 bytes", file);
        return MPH_MOUNT_ERROR_BAD_SIZE;
    }
    ptr = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED | MPH_MAP_POPULATE, fd, 0);
    if (ptr == MAP_FAILED) {
        if (error)
            sv_setpvf(error,"failed to create mapping to file '%s'", file);
        return MPH_MOUNT_ERROR_MAP_FAILED;
    }

    obj->bytes= st.st_size;
    obj->header= head= (struct mph_header*)ptr;
    obj->fd= fd;
    if (head->magic_num != 1278363728) {
        if (error)
            sv_setpvf(error,"file '%s' is not a PH2L file", file);
        return MPH_MOUNT_ERROR_BAD_MAGIC;
    }
    if (head->variant>1) {
        if (error)
            sv_setpvf(error,"unknown version '%d' in '%s'", head->variant, file);
        return MPH_MOUNT_ERROR_BAD_VERSION;
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
        return MPH_MOUNT_ERROR_CORRUPT_OFFSETS;
    }
    if (flags && MPH_F_VALIDATE) {
        char *start= ptr;
        char *state_pv= start + head->state_ofs;
        char *str_buf_start= start + head->str_buf_ofs;
        char *str_buf_end= start + st.st_size;
        U64 table_checksum= stadtx_hash_with_state(state_pv, start + head->table_ofs, head->str_buf_ofs - head->table_ofs);
        U64 str_buf_checksum= stadtx_hash_with_state(state_pv, start + head->str_buf_ofs, st.st_size - head->str_buf_ofs );
        if (head->table_checksum != table_checksum) {
            if (error)
                sv_setpvf(error,"table checksum '%016lx' != '%016lx' in file '%s'",table_checksum,head->table_checksum,file);
            return MPH_MOUNT_ERROR_CORRUPT_TABLE;
        }
        if (head->str_buf_checksum != str_buf_checksum) {
            if (error)
                sv_setpvf(error,"table checksum '%016lx' != '%016lx' in file '%s'",str_buf_checksum,head->str_buf_checksum,file);
            return MPH_MOUNT_ERROR_CORRUPT_STR_BUF;
        }
    }
    return head->variant;
}

void
mph_munmap(struct mph_obj *obj) {
    munmap(obj->header,obj->bytes);
    close(obj->fd);
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
        char *pv= SvPV(sv,pv_len);
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
_roundup(const U32 n, const U32 s) {
    const U32 r= n % s;
    if (r) {
        return n + s - r;
    } else {
        return n;
    }
}

U32 compute_max_xor_val(const U32 n, const U32 variant) {
    U32 n_copy= n;
    int n_bits= 0;

    while (n_copy) {
        if (n_copy & 1) n_bits++;
        n_copy = n_copy >> 1;
    }

    if ( n_bits > 1 ) {
        return variant ? INT32_MAX : UINT32_MAX;
    } else {
        return n;
    }
}

START_MY_CXT

I32
_compare(pTHX_ SV *a, SV *b) {
    dMY_CXT;
    HE *a_he= hv_fetch_ent_with_keysv((HV*)SvRV(a),MPH_KEYSV_KEY_NORMALIZED,0);
    HE *b_he= hv_fetch_ent_with_keysv((HV*)SvRV(b),MPH_KEYSV_KEY_NORMALIZED,0);

    return sv_cmp(HeVAL(a_he),HeVAL(b_he));
}

U32
normalize_source_hash(pTHX_ HV *source_hv, AV *keys_av, U32 compute_flags, SV *buf_length_sv, char *state_pv) {
    dMY_CXT;
    HE *he;
    U32 buf_length= 0;
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

        if (!val_sv) croak("panic: no sv for value?");
        if (!SvOK(val_sv) && (compute_flags & MPH_F_FILTER_UNDEF)) continue;

        hv= newHV();
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
        av_push(keys_av,newRV_noinc((SV*)hv));

        buf_length += normalize_with_flags(aTHX_ key_sv, key_normalized_sv, key_is_utf8_sv, 1);
        buf_length += normalize_with_flags(aTHX_ val_sv, val_normalized_sv, val_is_utf8_sv, 0);

        key_pv= (U8 *)SvPV(key_normalized_sv,key_len);
        h0= stadtx_hash_with_state(state_pv,key_pv,key_len);

        hv_store_ent_with_keysv(hv,MPH_KEYSV_H0,             newSVuv(h0));

    }
    if (buf_length_sv)
        sv_setuv(buf_length_sv, buf_length);

    /* we now know how many keys there are, and what the max_xor_val should be */
    return av_top_index(keys_av)+1;
}

void
find_first_level_collisions(U32 bucket_count, AV *keys_av, AV *keybuckets_av, AV *h2_packed_av) {
    dMY_CXT;
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

void set_xor_val_in_buckets(pTHX_ U32 xor_val, AV *buckets_av, U32 idx1, U32 *idx_start, char *is_used, AV *keys_in_bucket_av) {
    dMY_CXT;
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
solve_collisions(pTHX_ U32 bucket_count, U32 max_xor_val, SV *idx1_packed_sv, AV *h2_packed_av, AV *keybuckets_av, U32 variant, char *is_used, U32 *idx2_start,AV *buckets_av) {
    STRLEN idx1_packed_sv_len;
    U32 *idx1_start= (U32 *)SvPV(idx1_packed_sv,idx1_packed_sv_len);
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

        h2_start= (U32 *)SvPV(h2_sv,h2_strlen);
        keys_in_bucket_count= h2_strlen / sizeof(U32);
        h2_end= h2_start + keys_in_bucket_count;

        next_xor_val:
        while (1) {
            U32 *h2_ptr= h2_start;
            U32 *idx2_ptr= idx2_start;
            if (xor_val == max_xor_val) {
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
        set_xor_val_in_buckets(aTHX_ xor_val, buckets_av, idx1, idx2_start, is_used, keys_in_bucket_av);
    }
    return 0;
}

U32
place_singletons(pTHX_ U32 bucket_count, SV *idx1_packed_sv, AV *keybuckets_av, char *is_used, U32 *idx2_start, AV *buckets_av) {
    STRLEN idx1_packed_sv_len;
    U32 *idx1_start= (U32 *)SvPV(idx1_packed_sv,idx1_packed_sv_len);
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
        if (singleton_pos == bucket_count)
            return idx1 + 1;

        xor_val= (U32)(-singleton_pos-1);
        got= av_fetch(keybuckets_av, idx1, 0);
        if (!got)
            croak("panic: no keybuckets_av for idx %u",idx1);
        keys_in_bucket_av= (AV *)SvRV(*got);
        *idx2_start= singleton_pos;
        set_xor_val_in_buckets(aTHX_ xor_val, buckets_av, idx1, idx2_start, is_used, keys_in_bucket_av);
    }
    return 0;
}

U32
solve_collisions_by_length(pTHX_ U32 bucket_count, U32 max_xor_val, AV *by_length_av, AV *h2_packed_av, AV *keybuckets_av, U32 variant, AV *buckets_av) {
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

        if (len_idx == 1 && variant) {
            bad_idx= place_singletons(aTHX_ bucket_count, *idx1_packed_sv, keybuckets_av,
                is_used, idx2_start, buckets_av);
        } else {
            bad_idx= solve_collisions(aTHX_ bucket_count, max_xor_val, *idx1_packed_sv, h2_packed_av, keybuckets_av,
                variant, is_used, idx2_start, buckets_av);
        }
    }
    return bad_idx;
}

#define MY_CXT_KEY "Algorithm::MinPerfHashTwoLevel::_stash" XS_VERSION

#define SETOFS(i,he,table,key_ofs,key_len,str_buf_start,str_buf_pos,str_buf_end,str_ofs_hv)    \
STMT_START {                                                                \
        if (he) {                                                           \
            SV *sv= HeVAL(he);                                              \
            if (SvOK(sv)) {                                                 \
                STRLEN pv_len;                                              \
                char *pv;                                                   \
                SV *ofs_sv;                                                 \
                if (flags & MPH_F_NO_DEDUPE) {                              \
                    ofs_sv= NULL;                                           \
                } else {                                                    \
                    HE *ofs= hv_fetch_ent(str_ofs_hv,sv,1,0);               \
                    ofs_sv= ofs ? HeVAL(ofs) : NULL;                        \
                    if (!ofs_sv)                                            \
                        croak("panic: out of memory getting str ofs for " #he "for %u",i);  \
                }                                                           \
                if (ofs_sv && SvOK(ofs_sv)){                                \
                    table[i].key_ofs= SvUV(ofs_sv);                         \
                    table[i].key_len= sv_len(sv);                           \
                } else {                                                    \
                    pv= SvPV(sv,pv_len);                                    \
                    table[i].key_len= pv_len;                               \
                    if (pv_len) {                                           \
                        table[i].key_ofs= str_buf_pos - str_buf_start;      \
                        if (str_buf_pos + pv_len > str_buf_end)             \
                            croak("panic: string buffer too small in SETOFS, something went horribly wrong."); \
                        Copy(pv,str_buf_pos,pv_len,char);                   \
                        str_buf_pos += pv_len;                              \
                    } else {                                                \
                        table[i].key_ofs= 1;                                \
                    }                                                       \
                    if (ofs_sv)                                             \
                        sv_setuv(ofs_sv,table[i].key_ofs);                  \
                }                                                           \
            } else {                                                        \
                table[i].key_ofs= 0;                                        \
                table[i].key_len= 0;                                        \
            }                                                               \
        } else {                                                            \
            croak("no " #he " for %u",i);                                   \
        }                                                                   \
} STMT_END


MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Algorithm::MinPerfHashTwoLevel

BOOT:
{
  {
    MY_CXT_INIT;
    MPH_INIT_KEYSV(MPH_KEYSV_IDX,"idx");
    MPH_INIT_KEYSV(MPH_KEYSV_H1_KEYS,"h1_keys");
    MPH_INIT_KEYSV(MPH_KEYSV_XOR_VAL,"xor_val");
    MPH_INIT_KEYSV(MPH_KEYSV_H0,"h0");
    MPH_INIT_KEYSV(MPH_KEYSV_KEY,"key");
    MPH_INIT_KEYSV(MPH_KEYSV_KEY_NORMALIZED,"key_normalized");
    MPH_INIT_KEYSV(MPH_KEYSV_KEY_IS_UTF8,"key_is_utf8");
    MPH_INIT_KEYSV(MPH_KEYSV_VAL,"val");
    MPH_INIT_KEYSV(MPH_KEYSV_VAL_NORMALIZED,"val_normalized");
    MPH_INIT_KEYSV(MPH_KEYSV_VAL_IS_UTF8,"val_is_utf8");

    MPH_INIT_KEYSV(MPH_KEYSV_VARIANT,"variant");
    MPH_INIT_KEYSV(MPH_KEYSV_COMPUTE_FLAGS,"compute_flags");
    MPH_INIT_KEYSV(MPH_KEYSV_STATE,"state");
    MPH_INIT_KEYSV(MPH_KEYSV_SOURCE_HASH,"source_hash");
    MPH_INIT_KEYSV(MPH_KEYSV_BUF_LENGTH,"buf_length");
    MPH_INIT_KEYSV(MPH_KEYSV_BUCKETS,"buckets");
  }
}

UV
hash_with_state(str_sv,state_sv)
        SV* str_sv
        SV* state_sv
    PROTOTYPE: $$
    CODE:
{
    STRLEN str_len;
    STRLEN state_len;
    U8 *state_pv;
    U8 *str_pv= (U8 *)SvPV(str_sv,str_len);
    state_pv= (U8 *)SvPV(state_sv,state_len);
    if (state_len != STADTX_STATE_BYTES) {
        croak("Error: state vector must be at exactly %d bytes",(int)STADTX_SEED_BYTES);
    }
    RETVAL= stadtx_hash_with_state(state_pv,str_pv,str_len);
}
    OUTPUT:
        RETVAL


SV *
seed_state(base_seed_sv)
        SV* base_seed_sv
    PROTOTYPE: $
    CODE:
{
    STRLEN seed_len;
    STRLEN state_len;
    U8 *seed_pv;
    U8 *state_pv;
    SV *seed_sv;
    if (!SvOK(base_seed_sv))
        croak("Error: seed must be defined");
    if (SvROK(base_seed_sv))
        croak("Error: seed should not be a reference");
    seed_sv= base_seed_sv;
    seed_pv= (U8 *)SvPV(seed_sv,seed_len);

    if (seed_len != STADTX_SEED_BYTES) {
        if (SvREADONLY(base_seed_sv)) {
            if (seed_len < STADTX_SEED_BYTES) {
                warn("seed passed into seed_state() is readonly and too short, argument has been right padded with %d nulls",
                    (int)(STADTX_SEED_BYTES - seed_len));
            }
            else if (seed_len > STADTX_SEED_BYTES) {
                warn("seed passed into seed_state() is readonly and too long, using only the first %d bytes",
                    (int)STADTX_SEED_BYTES);
            }
            seed_sv= sv_2mortal(newSVsv(base_seed_sv));
        }
        if (seed_len < STADTX_SEED_BYTES) {
            sv_grow(seed_sv,STADTX_SEED_BYTES+1);
            while (seed_len < STADTX_SEED_BYTES) {
                seed_pv[seed_len] = 0;
                seed_len++;
            }
        }
        SvCUR_set(seed_sv,STADTX_SEED_BYTES);
        seed_pv= (U8 *)SvPV(seed_sv,seed_len);
    } else {
        seed_sv= base_seed_sv;
    }

    RETVAL= newSV(STADTX_STATE_BYTES+1);
    SvCUR_set(RETVAL,STADTX_STATE_BYTES);
    SvPOK_on(RETVAL);
    state_pv= (U8 *)SvPV(RETVAL,state_len);
    stadtx_seed_state(seed_pv,state_pv);
}
    OUTPUT:
        RETVAL


UV
compute_xs(self_hv)
        HV *self_hv
    PREINIT:
        dMY_CXT;
    PROTOTYPE: \%\@
    CODE:
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

    RETVAL = 0;

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
        state_pv= (U8 *)SvPV(state_sv,state_len);
        if (state_len != STADTX_STATE_BYTES) {
            croak("Error: state vector must be at exactly %d bytes",(int)STADTX_SEED_BYTES);
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

    /**** build an array of hashes in keys_av based on the normalized contents of source_hv */
    keys_av= (AV *)sv_2mortal((SV*)newAV());
    bucket_count= normalize_source_hash(aTHX_ source_hv, keys_av, compute_flags, buf_length_sv, state_pv);
    max_xor_val= compute_max_xor_val(bucket_count,variant);

    /* if the caller wants deterministic results we sort the keys_av
     * before we compute collisions - depending on the order we process
     * the keys we might resolve the collisions differently */
    if (compute_flags & MPH_F_DETERMINISTIC)
        sortsv(AvARRAY(keys_av),bucket_count,_compare);

    /**** find the collisions from the data we just computed, build an AoAoH and AoS of the
     **** collision data */
    keybuckets_av= (AV*)sv_2mortal((SV*)newAV()); /* AoAoH - hashes from keys_av */
    h2_packed_av= (AV*)sv_2mortal((SV*)newAV());  /* AoS - packed h1 */
    find_first_level_collisions(aTHX_ bucket_count, keys_av, keybuckets_av, h2_packed_av);

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
        
    RETVAL= solve_collisions_by_length(aTHX_ bucket_count, max_xor_val, by_length_av, h2_packed_av, keybuckets_av, 
        variant, buckets_av);
}
    OUTPUT:
        RETVAL



MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Tie::Hash::MinPerfHashTwoLevel::OnDisk

SV *
packed(version_sv,buf_length_sv,state_sv,comment_sv,flags,buckets_av)
        SV* version_sv
        SV* buf_length_sv
        SV* state_sv
        SV* comment_sv
        AV *buckets_av
        U32 flags
    PREINIT:
        dMY_CXT;
    PROTOTYPE: $$$$$\@
    CODE:
{
    U32 buf_length= SvUV(buf_length_sv);
    U32 bucket_count= av_top_index(buckets_av) + 1;
    U32 header_rlen= _roundup(sizeof(struct mph_header),16);
    STRLEN state_len;
    char *state_pv= SvPV(state_sv, state_len);
    
    U32 state_rlen= _roundup(state_len,16);
    U32 table_rlen= _roundup(sizeof(struct mph_bucket) * bucket_count,16);
    U32 key_flags_rlen= _roundup((bucket_count * 2 + 7 ) / 8,16);
    U32 val_flags_rlen= _roundup((bucket_count + 7) / 8,16);
    U32 str_rlen= _roundup(buf_length + 2 + (SvOK(comment_sv) ? sv_len(comment_sv)+1 : 1),16);

    U32 total_size=
        + header_rlen
        + state_rlen
        + table_rlen
        + key_flags_rlen
        + val_flags_rlen
        + str_rlen
    ;

    HV *str_ofs_hv= (HV *)sv_2mortal((SV*)newHV());
    SV *sv_buf;
    char *start;
    struct mph_header *head;
    char *state;
    struct mph_bucket *table;
    char *key_flags;
    char *val_flags;
    char *str_buf_start;
    char *str_buf_end;
    char *str_buf_pos;
    U32 i;
    STRLEN pv_len;
    char *pv;
    
    sv_buf= newSV(total_size);
    SvPOK_on(sv_buf);
    SvCUR_set(sv_buf,total_size);
    start= SvPVX(sv_buf);
    Zero(start,total_size,char);
    head= (struct mph_header *)start;

    head->magic_num= 1278363728;
    head->variant= SvUV(version_sv);
    head->num_buckets= bucket_count;
    head->state_ofs= header_rlen;
    head->table_ofs= head->state_ofs + state_rlen;
    head->key_flags_ofs= head->table_ofs + table_rlen;
    head->val_flags_ofs= head->key_flags_ofs + key_flags_rlen;
    head->str_buf_ofs= head->val_flags_ofs + val_flags_rlen;

    state= start + head->state_ofs;
    table= (struct mph_bucket *)(start + head->table_ofs);
    key_flags= start + head->key_flags_ofs;
    val_flags= start + head->val_flags_ofs;
    str_buf_start= start + head->str_buf_ofs;
    str_buf_end= start + total_size;
    str_buf_pos= str_buf_start + 2;

    Copy(state_pv,state,state_len,char);
    pv= SvPV(comment_sv,pv_len);
    Copy(pv,str_buf_pos,pv_len+1,char);
    str_buf_pos += pv_len + 1;

    for (i= 0; i < bucket_count; i++) {
        SV **got= av_fetch(buckets_av,i,0);
        HV *hv= (HV *)SvRV(*got);
        HE *key_normalized_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_KEY_NORMALIZED,0);
        HE *key_is_utf8_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_KEY_IS_UTF8,0);
        HE *val_normalized_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_VAL_NORMALIZED,0);
        HE *val_is_utf8_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_VAL_IS_UTF8,0);
        HE *xor_val_he= hv_fetch_ent_with_keysv(hv,MPH_KEYSV_XOR_VAL,0);

        if (xor_val_he) {
            table[i].xor_val= SvUV(HeVAL(xor_val_he));
        } else {
            table[i].xor_val= 0;
        }
        SETOFS(i,key_normalized_he,table,key_ofs,key_len,str_buf_start,str_buf_pos,str_buf_end,str_ofs_hv);
        SETOFS(i,val_normalized_he,table,val_ofs,val_len,str_buf_start,str_buf_pos,str_buf_end,str_ofs_hv);
        if (key_is_utf8_he) {
            UV u= SvUV(HeVAL(key_is_utf8_he));
            SETBITS(u,key_flags,i,2);
        } else {
            croak("panic: out of memory? no key_is_utf8_he for %u",i);
        }
        if (val_is_utf8_he) {
            UV u= SvUV(HeVAL(val_is_utf8_he));
            SETBITS(u,val_flags,i,1);
        } else {
            croak("panic: out of memory? no val_is_utf8_he for %u",i);
        }
    }
    {
        U32 actual_size= str_buf_pos - start;
        U32 r= actual_size % 16;
        if (r) {
            U32 add = 16 - r;
            str_buf_pos += add;
            actual_size += add;
        }
        SvCUR_set(sv_buf, actual_size);
        SvPOK_on(sv_buf);
        if (0)
            warn ("original estimate: %d actual: %d saved:%i\n", total_size, actual_size, (int)(total_size - actual_size));
    }
    head->table_checksum= stadtx_hash_with_state(state_pv, start + head->table_ofs, head->str_buf_ofs - head->table_ofs);
    head->str_buf_checksum= stadtx_hash_with_state(state_pv, str_buf_start, str_buf_pos - str_buf_start);
    RETVAL= sv_buf;
}
    OUTPUT:
        RETVAL

SV*
mount_file(file_sv,error_sv,flags)
        SV* file_sv
        SV* error_sv
        U32 flags
    PROTOTYPE: $$$
    CODE:
{
    struct mph_obj obj;
    STRLEN file_len;
    char *file_pv= SvPV(file_sv,file_len);
    IV mmap_status= mph_mmap(aTHX_ file_pv, &obj, error_sv, flags);
    if (mmap_status < 0) {
        XSRETURN_UNDEF;
    }
    /* copy obj into a new SV which we can return */
    RETVAL= newSVpvn((char *)&obj,sizeof(struct mph_obj));
    SvPOK_on(RETVAL);
    SvREADONLY_on(RETVAL);
}
    OUTPUT:
        RETVAL

void
unmount_file(mount_sv)
        SV* mount_sv
    PROTOTYPE: $
    CODE:
{
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
    mph_munmap(obj);
    SvOK_off(mount_sv);
}


UV
num_buckets(mount_sv)
        SV* mount_sv
    PROTOTYPE: $
    CODE:
{
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
    RETVAL= obj->header->num_buckets;
}
    OUTPUT:
        RETVAL

int
fetch_by_index(mount_sv,index,...)
        SV* mount_sv
        U32 index
    PROTOTYPE: $$;$$
    CODE:
{
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
    SV* key_sv= items > 2 ? ST(2) : NULL;
    SV* val_sv= items > 3 ? ST(3) : NULL;
    if (items > 4)
       croak("Error: passed too many arguments to "
             "Tie::Hash::MinPerfHashTwoLevel::OnDisk::fetch_by_index(mount_sv, index, key_sv, val_sv)");
    RETVAL= lookup_bucket(aTHX_ obj->header,index,key_sv,val_sv);
}
    OUTPUT:
        RETVAL

int
fetch_by_key(mount_sv,key_sv,...)
        SV* mount_sv
        SV* key_sv
    PROTOTYPE: $$;$
    CODE:
{
    SV* val_sv= items > 2 ? ST(2) : NULL;
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
    if (items > 3)
       croak("Error: passed too many arguments to "
             "Tie::Hash::MinPerfHashTwoLevel::OnDisk::fetch_by_key(mount_sv, index, key_sv)");
    RETVAL= lookup_key(aTHX_ obj->header,key_sv,val_sv);
}
    OUTPUT:
        RETVAL
