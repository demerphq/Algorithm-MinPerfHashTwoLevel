#ifndef _MPH2L_KEYS_H
#define _MPH2L_KEYS_H
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
#define MPH_KEYSV_ITER_IDX          18
#define MPH_KEYSV_LEFTMOST_IDX      19
#define MPH_KEYSV_RIGHTMOST_IDX     20
#define MPH_KEYSV_PREFIX            21
#define MPH_KEYSV_PREFIX_UTF8       22
#define MPH_KEYSV_PREFIX_LATIN1     23
#define MPH_KEYSV_FETCH_KEY_FIRST   24
#define MPH_KEYSV_LEVEL             25
#define MPH_KEYSV_LEVELS            26
#define MPH_KEYSV_FAST_PROPS        27
#define MPH_KEYSV_KEYS_AV           28
#define MPH_KEYSV_SEPARATOR         29

#define COUNT_MPH_KEYSV 30

#define MPH_INIT_KEYSV(idx, str) STMT_START {                           \
    MY_CXT.keyname_sv[idx].sv = newSVpvn((str ""), (sizeof(str) - 1));       \
    PERL_HASH(MY_CXT.keyname_sv[idx].hash, (str ""), (sizeof(str) - 1));     \
} STMT_END

typedef struct {
    struct sv_with_hash keyname_sv[COUNT_MPH_KEYSV];
} my_cxt_t;

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
    MPH_INIT_KEYSV(MPH_KEYSV_ITER_IDX,"iter_idx");              \
    MPH_INIT_KEYSV(MPH_KEYSV_LEFTMOST_IDX,"leftmost_idx");      \
    MPH_INIT_KEYSV(MPH_KEYSV_RIGHTMOST_IDX,"rightmost_idx");    \
    MPH_INIT_KEYSV(MPH_KEYSV_PREFIX,"prefix");                  \
    MPH_INIT_KEYSV(MPH_KEYSV_PREFIX_UTF8,"prefix_utf8");        \
    MPH_INIT_KEYSV(MPH_KEYSV_PREFIX_LATIN1,"prefix_latin1");    \
    MPH_INIT_KEYSV(MPH_KEYSV_FETCH_KEY_FIRST,"fetch_key_first");\
    MPH_INIT_KEYSV(MPH_KEYSV_LEVEL,"level");                    \
    MPH_INIT_KEYSV(MPH_KEYSV_LEVELS,"levels");                  \
    MPH_INIT_KEYSV(MPH_KEYSV_FAST_PROPS,"_fast_props");         \
    MPH_INIT_KEYSV(MPH_KEYSV_KEYS_AV,"_keys_av");               \
    MPH_INIT_KEYSV(MPH_KEYSV_SEPARATOR,"separator");            \
} STMT_END

#define hv_fetch_ent_with_keysv(hv,keysv_idx,lval)                      \
    hv_fetch_ent(hv,keyname_sv[keysv_idx].sv,lval,keyname_sv[keysv_idx].hash)

#define hv_fetch_sv_with_keysv(sv,hv,keysv_idx,lval) STMT_START {               \
    HE *got_he= hv_fetch_ent_with_keysv(hv,keysv_idx,lval);                     \
    if (got_he) {                                                               \
        sv= HeVAL(got_he);                                                      \
    } else {                                                                    \
        if (lval) croak("failed to fetch item in hv_fetch_sv_with_keysv()");    \
        sv= NULL;                                                               \
    }                                                                           \
} STMT_END

#define hv_delete_ent_with_keysv(hv,keysv_idx) \
    hv_delete_ent(hv,keyname_sv[keysv_idx].sv,0,keyname_sv[keysv_idx].hash)


#define hv_store_ent_with_keysv(hv,keysv_idx,val_sv)                    \
    hv_store_ent(hv,keyname_sv[keysv_idx].sv,val_sv,keyname_sv[keysv_idx].hash)

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

#endif /* _MPH2L_KEYS_H */

