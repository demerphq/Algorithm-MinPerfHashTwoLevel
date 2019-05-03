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
#define COUNT_MPH_KEYSV 10

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



#define sv_set_from_bucket(sv,strs,ofs,len,idx,flags,bits) \
STMT_START {                                            \
    U8 *ptr;                                            \
    U8 is_utf8;                                         \
    if (ofs) {                                          \
        ptr= (strs) + (ofs);                            \
        is_utf8= (*((flags)+(((idx)*(bits))>>3))>>(((idx)*(bits))&7))&((1<<bits)-1); \
    } else {                                            \
        ptr= 0;                                         \
        is_utf8= 0;                                     \
    }                                                   \
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
            index = (h2 ^ bucket->xor_val) % mph->num_buckets;
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

void
mph_mmap(pTHX_ char *file, struct mph_obj *obj) {
    struct stat st;
    int fd = open(file, O_RDONLY, 0);
    void *ptr;
    if (fd < 0)
        croak("failed to open '%s' for read", file);
    fstat(fd,&st);
    ptr = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED | MPH_MAP_POPULATE, fd, 0);
    if (ptr == MAP_FAILED) {
        croak("failed to create mapping to file '%s'", file);
    }
    obj->bytes= st.st_size;
    obj->header= (struct mph_header*)ptr;
    obj->fd= fd;
}

void 
mph_munmap(struct mph_obj *obj) {
    munmap(obj->header,obj->bytes);
    close(obj->fd);
}

void
normalize_with_flags(pTHX_ SV *sv, SV *normalized_sv, SV *is_utf8_sv, int downgrade) {
    if (SvROK(sv)) {
        croak("not expecting a reference in downgrade_with_flags()");
    }
    sv_setsv(normalized_sv,sv);
    if (SvPOK(sv) && SvUTF8(sv)) {
        if (downgrade)
            sv_utf8_downgrade(normalized_sv,1);
        if (SvUTF8(normalized_sv)) {
            SvUTF8_off(normalized_sv);
            sv_setiv(is_utf8_sv,1);
        } else {
            sv_setiv(is_utf8_sv,2);
        }
    } else {
        sv_setiv(is_utf8_sv, 0);
    }
}

#define MY_CXT_KEY "Algorithm::MinPerfHashTwoLevel::_stash" XS_VERSION

START_MY_CXT

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
        croak("state vector must be at exactly %d bytes",(int)STADTX_SEED_BYTES);
    }
    RETVAL= stadtx_hash_with_state(state_pv,str_pv,str_len);
}
    OUTPUT:
        RETVAL

UV
hash_with_state_normalized(n_sv,state_sv,source_hv,h2_packed_av,keybuckets_av,by_length_av)
        SV* n_sv
        HV* source_hv
        SV* state_sv
        AV* h2_packed_av
        AV* keybuckets_av
        AV* by_length_av
    PROTOTYPE: $$\%\@\@\@
    CODE:
{
    U8 *state_pv;
    STRLEN state_len;
    HE *he;
    UV n= SvUV(n_sv);
    state_pv= (U8 *)SvPV(state_sv,state_len);
    hv_iterinit(source_hv);

    while (he= hv_iternext(source_hv)) {
        U8 *key_pv;
        STRLEN key_len;
        U64 h0;
        U32 h1;
        U32 h2;
        U32 idx1;
        SV **got_psv;

        SV *key_sv= newSVhek(HeKEY_hek(he));
        SV *key_normalized_sv= newSV(0);
        SV *key_is_utf8_sv= newSVuv(0);

        SV *val_sv= HeVAL(he);
        SV *val_normalized_sv= newSV(0);
        SV *val_is_utf8_sv= newSVuv(0);

        normalize_with_flags(aTHX_ key_sv, key_normalized_sv, key_is_utf8_sv, 1);
        normalize_with_flags(aTHX_ val_sv, val_normalized_sv, val_is_utf8_sv, 0);

        key_pv= (U8 *)SvPV(key_normalized_sv,key_len);
        if (state_len != STADTX_STATE_BYTES) {
            croak("state vector must be at exactly %d bytes",(int)STADTX_SEED_BYTES);
        }
        h0= stadtx_hash_with_state(state_pv,key_pv,key_len);
        h1= h0 >> 32;
        h2= h0 & 0xFFFFFFFF;
        idx1= h1 % n;
        got_psv= av_fetch(h2_packed_av,idx1,1);
        if (!got_psv)
            croak("panic, out of memory?");
        if (!SvPOK(*got_psv))
            sv_setpvs(*got_psv,"");
        sv_catpvn(*got_psv, (char *)&h2, 4);

        {
            AV *av;
            SV *ref_sv= newSViv(0);
            HV *hv= newHV();

            got_psv= av_fetch(keybuckets_av,idx1,1);
            if (!got_psv)
                croak("oom");

            if (!SvROK(*got_psv)) {
                av= newAV();
                SvRV_set(*got_psv,(SV *)av);
                SvROK_on(*got_psv);
            } else {
                av= (AV *)SvRV(*got_psv);
            }

            SvRV_set(ref_sv,(SV*)hv);
            SvROK_on(ref_sv);
            av_push(av,ref_sv);
            hv_ksplit(hv,10);
            hv_store_ent_with_keysv(hv,MPH_KEYSV_H0,             newSVuv(h0));
            hv_store_ent_with_keysv(hv,MPH_KEYSV_KEY,            SvREFCNT_inc_simple_NN(key_sv));
            hv_store_ent_with_keysv(hv,MPH_KEYSV_KEY_NORMALIZED, SvREFCNT_inc_simple_NN(key_normalized_sv));
            hv_store_ent_with_keysv(hv,MPH_KEYSV_KEY_IS_UTF8,    SvREFCNT_inc_simple_NN(key_is_utf8_sv));
            hv_store_ent_with_keysv(hv,MPH_KEYSV_VAL,            SvREFCNT_inc_simple_NN(val_sv));
            hv_store_ent_with_keysv(hv,MPH_KEYSV_VAL_NORMALIZED, SvREFCNT_inc_simple_NN(val_normalized_sv));
            hv_store_ent_with_keysv(hv,MPH_KEYSV_VAL_IS_UTF8,    SvREFCNT_inc_simple_NN(val_is_utf8_sv));
        }
    }
    {
        U32 i;

        for( i = 0 ; i < n ; i++ ) {
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
            if (SvROK(*got)) {
                target_av= (AV*)SvRV(*got);
            } else {
                target_av= newAV();
                SvRV_set(*got, (SV*)target_av);
                SvROK_on(*got);
            }
            av_push(target_av, newSVuv(i));
        }
    }
    RETVAL = 1;
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
        croak("seed must be defined");
    if (SvROK(base_seed_sv))
        croak("seed should not be a reference");
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
calc_xor_val(bucket_count,max_xor_val,used_sv,used_pos_sv,idx1_av,buckets_av,keybuckets_av,h2_buckets_av)
    U32 bucket_count
    U32 max_xor_val
    SV *used_sv
    SV *used_pos_sv
    AV *idx1_av
    AV *buckets_av
    AV *keybuckets_av
    AV *h2_buckets_av
    PREINIT:
        dMY_CXT;
    PROTOTYPE: $$$\@\@\@\@
    CODE:
{
    IV idx1_idx;
    IV top_idx1= av_top_index(idx1_av);

    U32 idx1;
    SV *h2_sv;
    AV *keys_av;

    SV *idx_sv;
    char *used;
    STRLEN used_len;

    if (top_idx1 < 0) croak("empty index array?");

    if (!SvPOK(used_sv)) {
        sv_setpvs(used_sv,"");
        sv_grow(used_sv,bucket_count);
        SvCUR_set(used_sv,bucket_count);
        SvPOK_on(used_sv);
        used= SvPV_force(used_sv,used_len);
        Zero(used,bucket_count,char);
    } else {
        used= SvPV_force(used_sv,used_len);
    }

    idx_sv= sv_2mortal(newSV(20));
    SvPOK_on(idx_sv);
    SvCUR_set(idx_sv,0);
    RETVAL = 0;

    for (idx1_idx=0; idx1_idx <= top_idx1; idx1_idx++) {
        SV **got= av_fetch(idx1_av, idx1_idx, 0);
        if (!got)
            croak("panic: no idx1_av element for idx %ld",idx1_idx);
        idx1= SvUV(*got);

        got= av_fetch(h2_buckets_av, idx1, 0);
        if (!got)
            croak("panic: no h2_buckets for idx %u",idx1);
        h2_sv= *got;

        got= av_fetch(keybuckets_av, idx1, 0);
        if (!got)
            croak("panic: no keybuckets_av for idx %u",idx1);
        keys_av= (AV *)SvRV(*got);

        {
            U32 xor_val= 0;
            STRLEN h2_strlen;
            U32 *h2_start= (U32 *)SvPV(h2_sv,h2_strlen);
            STRLEN h2_count= h2_strlen / sizeof(U32);
            U32 *h2_end= h2_start + h2_count;
            U32 *idx_start;

            SvGROW(idx_sv,h2_strlen);
            SvCUR_set(idx_sv,h2_strlen);
            idx_start= (U32 *)SvPVX(idx_sv);

            if (h2_count == 1 && SvOK(used_pos_sv)) {
                I32 pos= SvIV(used_pos_sv);
                while (pos < bucket_count && used[pos]) {
                    pos++;
                }
                SvIV_set(used_pos_sv,pos);
                if (pos == bucket_count) {
                    xor_val= 0;
                } else {
                    *idx_start= pos;
                    pos = -pos-1;
                    xor_val= (U32)pos;
                }
            } else {
                next_xor_val:
                while (1) {
                    U32 *h2_ptr= h2_start;
                    U32 *idx_ptr= idx_start;
                    if (xor_val == max_xor_val) {
                        xor_val= 0;
                        break;
                    } else {
                        xor_val++;
                    }
                    while (h2_ptr < h2_end) {
                        U32 i= (*h2_ptr ^ xor_val) % bucket_count;
                        U32 *check_idx;
                        if (used[i])
                            goto next_xor_val;
                        for (check_idx= idx_start; check_idx < idx_ptr; check_idx++) {
                            if (*check_idx == i)
                                goto next_xor_val;
                        }
                        *idx_ptr= i;
                        h2_ptr++;
                        idx_ptr++;
                    }
                    break;
                }
            }
            if (xor_val) {
                U32 *idx2;
                HV *idx1_hv;
                U32 i;

                SV **buckets_rvp= av_fetch(buckets_av, idx1, 1);
                if (!buckets_rvp) croak("out of memory in buckets_av lvalue fetch");
                if (!SvROK(*buckets_rvp)) {
                    idx1_hv= newHV();
                    if (!idx1_hv) croak("out of memory creating new hash reference");
                    sv_upgrade(*buckets_rvp,SVt_RV);
                    SvRV_set(*buckets_rvp,(SV *)idx1_hv);
                    SvROK_on(*buckets_rvp);
                } else {
                     idx1_hv= (HV *)SvRV(*buckets_rvp);
                }

                hv_setuv_with_keysv(idx1_hv,MPH_KEYSV_XOR_VAL,xor_val);
                hv_setuv_with_keysv(idx1_hv,MPH_KEYSV_H1_KEYS,h2_count);

                /* update used */
                for (i= 0, idx2= idx_start; i < h2_count; i++,idx2++) {
                    HV *idx2_hv;
                    HV *keys_hv;

                    SV **keys_rvp;
                    SV **buckets_rvp;

                    keys_rvp= av_fetch(keys_av, i, 0);
                    if (!keys_rvp) croak("no key_info in bucket %d", i);
                    keys_hv= (HV *)SvRV(*keys_rvp);

                    buckets_rvp= av_fetch(buckets_av, *idx2, 1);
                    if (!buckets_rvp) croak("out of memory?");

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

                    used[*idx2] = 1;
                }
            } else {
                RETVAL = idx1 + 1;
                break;
            }
        }
    }
}
    OUTPUT:
        RETVAL

MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Tie::Hash::MinPerfHashTwoLevel::OnDisk

SV*
mount_file(file_sv)
        SV* file_sv
    PROTOTYPE: $
    CODE:
{
    struct mph_obj obj;
    STRLEN file_len;
    char *file_pv= SvPV(file_sv,file_len);
    mph_mmap(aTHX_ file_pv,&obj);
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
