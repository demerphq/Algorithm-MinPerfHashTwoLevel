#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"
#include "mph2l.h"

/* all the interesting stuff is in mph2l.c */

#define MY_CXT_KEY "Algorithm::MinPerfHashTwoLevel::_stash" XS_VERSION
START_MY_CXT

I32 setup_fast_props(pTHX_ HV *self_hv, AV *mount_av, struct mph_header *mph, struct sv_with_hash *keyname_sv, SV *fast_props_sv) {
    SV *sv;
    SV **svp;
    struct mph_multilevel ml;

    if (MPH_IS_TRIPLE(mph)) {
        ml.p1_sv= NULL;
        ml.p1_utf8_sv= NULL;
        ml.p1_latin1_sv= NULL;
        ml.p2_sv= NULL;
        ml.p2_utf8_sv= NULL;
        ml.p2_latin1_sv= NULL;
        ml.level = 1;
        ml.levels = 3;
        ml.fetch_key_first = 0;
    } else {
        hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_PREFIX,1);
        ml.prefix_sv= SvREFCNT_inc(sv);
        ml.prefix_utf8_sv= NULL;
        ml.prefix_latin1_sv= NULL;

        hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_LEVEL,1);
        ml.level= SvIV(sv);

        hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_LEVELS,1);
        ml.levels= SvIV(sv);
    
        hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_FETCH_KEY_FIRST,1);
        ml.fetch_key_first= SvIV(sv);
    }

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_LEFTMOST_IDX,1);
    ml.leftmost_idx= SvIV(sv);

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_RIGHTMOST_IDX,1);
    ml.rightmost_idx= SvIV(sv);

    svp= av_fetch(mount_av,MOUNT_ARRAY_SEPARATOR_IDX,0);
    ml.separator= SvPV_nomg_nolen(*svp)[0];

    sv_setpvn(fast_props_sv,(char *)&ml,sizeof(struct mph_multilevel));
    ml.converted= 1;
}

#define dFAST_PROPS \
    struct mph_multilevel *ml; \
    SV *fast_props_sv

#define GET_FAST_PROPS(self_hv) STMT_START {                                    \
    hv_fetch_sv_with_keysv(fast_props_sv, self_hv, MPH_KEYSV_FAST_PROPS,1);     \
    if (!SvOK(fast_props_sv))                                                   \
        setup_fast_props(aTHX_ self_hv, mount_av, obj->header, keyname_sv, fast_props_sv);   \
    ml= (struct mph_multilevel *)SvPV_nomg_nolen(fast_props_sv);                     \
} STMT_END

#define dMOUNT        \
    struct mph_obj *obj= NULL;  \
    SV *mount_rv;               \
    AV *mount_av;               \
    SV *mount_sv

#define GET_MOUNT_AND_OBJ_RV(mount_rv)                              \
STMT_START {                                                        \
    SV **mount_svp;                                                 \
    if (!SvROK(mount_rv)) croak("expecting an RV");                 \
    mount_av= (AV *)SvRV(mount_rv);                                 \
    mount_svp= av_fetch(mount_av,MOUNT_ARRAY_MOUNT_IDX,0);          \
    mount_sv= *mount_svp;                                           \
    obj= (struct mph_obj *)SvPV_nomg_nolen(mount_sv);               \
} STMT_END

#define GET_MOUNT_AND_OBJ(self_hv)                                  \
STMT_START {                                                        \
    SV **mount_svp;                                                 \
    HE *mount_he;                                                   \
                                                                    \
    mount_he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_MOUNT,0);   \
    if (!mount_he)                                                  \
        croak("must be mounted to use this function");              \
                                                                    \
    mount_rv= HeVAL(mount_he);                                      \
    GET_MOUNT_AND_OBJ_RV(mount_rv);                                 \
} STMT_END

U8 HEX[16]= {'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'};
char *
sv_hex(pTHX_ SV *sv, U8 *buf, STRLEN len) {
    U8 *pv;
    U8 *opv;
    U8 *buf_end= buf + len;
    STRLEN l;
    sv_upgrade(sv,SVt_PV);
    sv_grow(sv,len*2+1);
    SvPOK_on(sv);
    SvCUR_set(sv,len*2);
    opv= pv= (U8 *)SvPVX(sv);
    while (buf < buf_end) {
        U8 lo= *buf & 0xF;
        U8 hi= *buf >> 4;
        buf++;
        *pv = HEX[hi]; pv++;
        *pv = HEX[lo]; pv++;
    }
    *pv= 0;
    return opv;
}


MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Algorithm::MinPerfHashTwoLevel

BOOT:
{
    MPH_INIT_ALL_KEYSV();
}

UV
hash_with_state(str_sv,state_sv)
        SV* str_sv
        SV* state_sv
    PROTOTYPE: $$
    CODE:
{
    RETVAL= _hash_with_state_sv(aTHX_ str_sv, state_sv);
}
    OUTPUT:
        RETVAL


SV *
seed_state(base_seed_sv)
        SV* base_seed_sv
    PROTOTYPE: $
    CODE:
{
    RETVAL= _seed_state(aTHX_ base_seed_sv);
}
    OUTPUT:
        RETVAL


UV
compute_xs(self_hv)
        HV *self_hv
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    PROTOTYPE: \%\@
    CODE:
{
    RETVAL= _compute_xs(aTHX_ self_hv, keyname_sv);
}
    OUTPUT:
        RETVAL



MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Tie::Hash::MinPerfHashTwoLevel::OnDisk

IV
packed_xs(buf_sv, variant, buf_length_sv, state_sv,comment_sv,flags,separator_sv,buckets_av,keys_av)
        SV *buf_sv
        U32 variant
        SV* buf_length_sv
        SV* state_sv
        SV* comment_sv
        U32 flags
        SV *separator_sv
        AV *buckets_av
        AV *keys_av
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    PROTOTYPE: $$$$$$$\@\@
    CODE:
{
    RETVAL= _packed_xs(
        aTHX_ buf_sv, variant, buf_length_sv, state_sv, comment_sv, flags, buckets_av, keyname_sv, keys_av, separator_sv);
}
    OUTPUT:
        RETVAL

IV
find_first_prefix(mount_sv,pfx_sv,...)
        SV* mount_sv
        SV* pfx_sv
    ALIAS:
            find_last_prefix = 1
    PROTOTYPE: $$;$$
    CODE:
{
    IV l;
    IV r;
    struct mph_obj *obj= (struct mph_obj *)SvPV_nomg_nolen(mount_sv);
    if (items > 2)
        l= SvIV(ST(2));
    else
        l= 0;
    if (items > 3)
        r= SvIV(ST(3))+1;
    else
        r= obj->header->num_buckets;
    if (items > 4)
        croak("too many arguments!");
    RETVAL= find_prefix(aTHX_ obj->header, pfx_sv, l, r, ix);
}
    OUTPUT:
        RETVAL

IV
find_first_last_prefix(mount_sv,pfx_sv,last_sv,...)
        SV* mount_sv
        SV* pfx_sv
        SV* last_sv
    PROTOTYPE: $$$;$$
    CODE:
{
    IV l;
    IV r;
    IV last;
    struct mph_obj *obj= (struct mph_obj *)SvPV_nomg_nolen(mount_sv);
    if (items > 3)
        l= SvIV(ST(3));
    else
        l= 0;
    if (items > 4)
        r= SvIV(ST(4))+1;
    else
        r= obj->header->num_buckets;
    if (items > 5)
        croak("too many arguments!");
    RETVAL= find_first_last_prefix(aTHX_ obj->header, pfx_sv, l, r, &last);
    sv_setiv(last_sv, last);
}
    OUTPUT:
        RETVAL



IV
fetch_by_index(mount_sv,index,...)
        SV* mount_sv
        U32 index
    PROTOTYPE: $$;$$
    CODE:
{
    struct mph_obj *obj= (struct mph_obj *)SvPV_nomg_nolen(mount_sv);
    SV* key_sv= items > 2 ? ST(2) : NULL;
    SV* val_sv= items > 3 ? ST(3) : NULL;
    if (items > 4)
       croak("Error: passed too many arguments to "
             "Tie::Hash::MinPerfHashTwoLevel::OnDisk::fetch_by_index(mount_sv, index, key_sv, val_sv)");
    RETVAL= lookup_bucket(aTHX_ obj->header,index,key_sv,val_sv);
}
    OUTPUT:
        RETVAL

IV
fetch_by_key(mount_sv,key_sv,...)
        SV* mount_sv
        SV* key_sv
    PROTOTYPE: $$;$
    CODE:
{
    SV* val_sv= items > 2 ? ST(2) : NULL;
    struct mph_obj *obj= (struct mph_obj *)SvPV_nomg_nolen(mount_sv);
    if (items > 3)
       croak("Error: passed too many arguments to "
             "Tie::Hash::MinPerfHashTwoLevel::OnDisk::fetch_by_key(mount_sv, index, key_sv)");
    RETVAL= lookup_key(aTHX_ obj->header,key_sv,val_sv);
}
    OUTPUT:
        RETVAL


SV *
get_comment(self_sv)
        SV* self_sv
    ALIAS:
            get_hdr_magic_num = 1
            get_hdr_variant = 2
            get_hdr_num_buckets = 3
            get_hdr_state_ofs = 4
            get_hdr_table_ofs = 5
            get_hdr_key_flags_ofs = 6
            get_hdr_val_flags_ofs = 7
            get_hdr_str_buf_ofs = 8
            get_hdr_table_checksum = 9
            get_hdr_str_buf_checksum = 10
            get_hdr_state = 11
            get_hdr_separator = 12
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    PROTOTYPE: $
    CODE:
{
    dMOUNT;
    char *start;

    if (!SvROK(self_sv)) croak("expecting a reference argument");
    if (SvTYPE(SvRV(self_sv)) == SVt_PVHV) {
        HV *self_hv= (HV *)SvRV(self_sv);
        GET_MOUNT_AND_OBJ(self_hv);
    } else if (SvTYPE(SvRV(self_sv)) == SVt_PVAV) {
        GET_MOUNT_AND_OBJ_RV(self_sv);
    }

    start= (char *)obj->header;
    switch(ix) {
        case  0: RETVAL= newSVpv(start + obj->header->str_buf_ofs + 2,0); break;
        case  1: RETVAL= newSVuv(obj->header->magic_num); break;
        case  2: RETVAL= newSVuv(obj->header->variant); break;
        case  3: RETVAL= newSVuv(obj->header->num_buckets); break;
        case  4: RETVAL= newSVuv(obj->header->state_ofs); break;
        case  5: RETVAL= newSVuv(obj->header->table_ofs); break;
        case  6: RETVAL= newSVuv(obj->header->key_flags_ofs); break;
        case  7: RETVAL= newSVuv(obj->header->val_flags_ofs); break;
        case  8: RETVAL= newSVuv(obj->header->str_buf_ofs); break;
        case  9: RETVAL= newSVuv(obj->header->table_checksum); break;
        case 10: RETVAL= newSVuv(obj->header->str_buf_checksum); break;
        case 11: RETVAL= newSVpvn(start + obj->header->state_ofs, MPH_STATE_BYTES); break;
        case 12: RETVAL= newSVpvn(&obj->header->separator, 1); break;
    }
}
    OUTPUT:
        RETVAL

MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk

SV *
NEXTKEY(self_hv,...)
        HV* self_hv
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    ALIAS:
            FIRSTKEY = 1
    CODE:
{
    char *separator_pos;

    IV status;
    SV *nextkey_sv= newSV(0);
    int was_latin1= 0;

    STRLEN nextkey_len;
    char *nextkey_pv;
    
    SV *this_prefix_sv;
    STRLEN this_prefix_len;
    char *this_prefix_pv;

    dMOUNT;
    dFAST_PROPS;

    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);

    if (ix) /* FIRSTKEY */
        ml->iter_idx= ml->leftmost_idx;

        /* fetch the next key */
    if (ml->iter_idx <= ml->rightmost_idx)
        status= lookup_bucket(aTHX_ obj->header, ml->iter_idx, nextkey_sv, NULL);
    else
        status= 0;

    if (!status)
        XSRETURN_UNDEF;

    this_prefix_sv= ml->prefix_sv;

    if (SvUTF8(nextkey_sv)) {
        if (!SvUTF8(ml->prefix_sv)) {
            if (!ml->prefix_utf8_sv) {
                SV *prefix_utf8_sv;
                if (ml->converted) {
                    hv_fetch_sv_with_keysv(prefix_utf8_sv,self_hv,MPH_KEYSV_PREFIX_UTF8,1);
                    sv_setsv(prefix_utf8_sv,ml->prefix_sv);
                    SvREFCNT_inc(prefix_utf8_sv);
                } else {
                    prefix_utf8_sv= newSVsv(ml->prefix_sv);
                }
                sv_utf8_upgrade(prefix_utf8_sv);
                ml->prefix_utf8_sv= prefix_utf8_sv;
            }
            this_prefix_sv= ml->prefix_utf8_sv;
        }
    } else {
        if (SvUTF8(ml->prefix_sv)) {
            if (!ml->prefix_latin1_sv) {
                SV *prefix_latin1_sv;
                if (ml->converted) {
                    hv_fetch_sv_with_keysv(prefix_latin1_sv,self_hv,MPH_KEYSV_PREFIX_LATIN1,1);
                    sv_setsv(prefix_latin1_sv,ml->prefix_sv);
                    SvREFCNT_inc(prefix_latin1_sv);
                } else {
                    prefix_latin1_sv= newSVsv(ml->prefix_sv);
                }
                sv_utf8_downgrade(prefix_latin1_sv,1);
                ml->prefix_latin1_sv= prefix_latin1_sv;
            }
            /* might not be downgradable! */
            if (SvUTF8(ml->prefix_latin1_sv)) {
                sv_utf8_upgrade(nextkey_sv);
                was_latin1 = 1;
            } else {
                this_prefix_sv= ml->prefix_latin1_sv;
            }
        }
    }
    /* at this point prefix_sv and nextkey_sv have the same utf8ness 
     * which is why we can pass the same var into both the latin1 and utf8 slot */

    /* if this key does not match */
    if (sv_prefix_cmp3(aTHX_ nextkey_sv,this_prefix_sv,this_prefix_sv))
        XSRETURN_UNDEF;

    nextkey_pv= SvPV_nomg(nextkey_sv, nextkey_len);
    this_prefix_pv= SvPV_nomg(this_prefix_sv, this_prefix_len);

    separator_pos= (this_prefix_len <= nextkey_len)
                   ? memchr(nextkey_pv + this_prefix_len, ml->separator, nextkey_len - this_prefix_len)
                   : NULL;

    if (!separator_pos) {
        ml->iter_idx++;
    } else {
        SvCUR_set(nextkey_sv,separator_pos - nextkey_pv + 1);
        ml->iter_idx= 1 + find_last_prefix(aTHX_ obj->header,nextkey_sv,ml->iter_idx,ml->rightmost_idx+1);
        SvCUR_set(nextkey_sv,separator_pos - nextkey_pv);
    }
    sv_chop(nextkey_sv,nextkey_pv + this_prefix_len);
    if (was_latin1)
        sv_utf8_downgrade(nextkey_sv,1);

    RETVAL= nextkey_sv;
}
    OUTPUT:
        RETVAL

void
DESTROY(self_hv)
        HV *self_hv
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    struct mph_multilevel *ml;
    SV *fast_props_sv= hv_delete_ent_with_keysv(self_hv, MPH_KEYSV_FAST_PROPS);
    if (fast_props_sv) {
        ml= (struct mph_multilevel *)SvPV_nomg_nolen(fast_props_sv);
        if (ml->prefix_sv)
            SvREFCNT_dec(ml->prefix_sv);
        if (ml->prefix_utf8_sv)
            SvREFCNT_dec(ml->prefix_utf8_sv);
        if (ml->prefix_latin1_sv)
            SvREFCNT_dec(ml->prefix_latin1_sv);
    }
}

SV *
FETCH(self_hv, key_sv)
        HV *self_hv
        SV *key_sv
    ALIAS:
        EXISTS = 1
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    dFAST_PROPS;
    dMOUNT;
    IV found_it= 0;
    SV *fetch_key_sv;
    RETVAL= ix ? NULL : newSV(0);

    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);

    fetch_key_sv= sv_2mortal(newSVsv(ml->prefix_sv));
    sv_catsv(fetch_key_sv,key_sv);
    if (ml->fetch_key_first)
        found_it= lookup_key(aTHX_ obj->header, fetch_key_sv, RETVAL);

    if ( !found_it && ml->fetch_key_first <= 1 ) {
        IV key_rightmost_idx;
        IV key_leftmost_idx;

        sv_catpvn(fetch_key_sv,&ml->separator,1);

        key_leftmost_idx= find_first_last_prefix(aTHX_ obj->header, fetch_key_sv, ml->leftmost_idx,
            ml->rightmost_idx+1, &key_rightmost_idx);

        if (ix) {
            found_it = key_leftmost_idx >= 0;
        }
        else
        if (key_leftmost_idx >= 0) {
            HV *obj_hv= newHV();
            SV *obj_rv= newRV_noinc((SV*)obj_hv);
            HV *tie_hv= newHV();
            SV *tie_rv= newRV_noinc((SV*)tie_hv);
            SV *key_mount_rv;
            SV *key_fast_props_sv;
            struct mph_multilevel *new_ml;
            
            hv_fetch_sv_with_keysv(key_mount_rv,obj_hv,MPH_KEYSV_MOUNT,1);
            sv_setsv(key_mount_rv, mount_rv);

            hv_fetch_sv_with_keysv(key_fast_props_sv,obj_hv,MPH_KEYSV_FAST_PROPS,1);
            sv_grow(key_fast_props_sv,sizeof(struct mph_multilevel));
            SvCUR_set(key_fast_props_sv,sizeof(struct mph_multilevel));
            SvPOK_on(key_fast_props_sv);
            new_ml= (struct mph_multilevel *)SvPVX(key_fast_props_sv);

            new_ml->prefix_sv= SvREFCNT_inc(fetch_key_sv);
            new_ml->prefix_utf8_sv= NULL;
            new_ml->prefix_latin1_sv= NULL;
            new_ml->leftmost_idx= key_leftmost_idx;
            new_ml->rightmost_idx= key_rightmost_idx;
            new_ml->level= ml->level+1;
            new_ml->levels= ml->levels;
            new_ml->fetch_key_first= (new_ml->level == new_ml->levels) ? 2 :
                                     (new_ml->level == 1 || new_ml->level > new_ml->levels) ? 1 :
                                     0;
            new_ml->separator= ml->separator;
            new_ml->converted= 0;

            sv_bless(obj_rv, SvSTASH((SV *)self_hv));
	    sv_magic((SV *)tie_hv, obj_rv, PERL_MAGIC_tied, NULL, 0);

            sv_setsv(RETVAL, tie_rv);
        }
    }
    if (!RETVAL)
        RETVAL= found_it ? &PL_sv_yes : &PL_sv_no;
}
    OUTPUT:
        RETVAL

MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk

SV *
NEXTKEY(self_hv,...)
        HV* self_hv
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    ALIAS:
            FIRSTKEY = 1
    CODE:
{
    char *separator_pos;

    IV status;
    SV *nextkey_sv= newSV(0);
    int was_latin1= 0;

    STRLEN nextkey_len;
    char *nextkey_pv;

    struct mph_triple_bucket *first_bucket;

    struct mph_triple_bucket *iter_bucket;
    struct mph_triple_bucket *next_bucket;
    struct mph_header *mph;
    SV *p1_sv;
    U32 str_len_idx;

    dMOUNT;
    dFAST_PROPS;

    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);
    mph= obj->header;

    first_bucket= TRIPLE_BUCKET_PTR(mph);

    if (ix) /* FIRSTKEY */
        ml->iter_idx= ml->leftmost_idx;

    if (ml->iter_idx > ml->rightmost_idx)
        XSRETURN_UNDEF;

    iter_bucket= first_bucket + ml->iter_idx;

    if (!ml->p1_sv) {
        str_len_idx= iter_bucket->k1_idx;
        next_bucket= next_bucket_by_k1(iter_bucket);
    }
    else
    if (!ml->p2_sv) {
        str_len_idx= iter_bucket->k2_idx;
        next_bucket= next_bucket_by_k2(iter_bucket);
    }
    else
    {
        str_len_idx= iter_bucket->k3_idx;
        next_bucket= iter_bucket+1;
    }
    triple_set_key(aTHX_ obj, str_len_idx, iter_bucket, ml->iter_idx, nextkey_sv);
    ml->iter_idx= next_bucket - first_bucket;
    RETVAL= nextkey_sv;
}
    OUTPUT:
        RETVAL

void
DESTROY(self_hv)
        HV *self_hv
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    struct mph_multilevel *ml;
    SV *fast_props_sv= hv_delete_ent_with_keysv(self_hv, MPH_KEYSV_FAST_PROPS);
    if (fast_props_sv) {
        ml= (struct mph_multilevel *)SvPV_nomg_nolen(fast_props_sv);
        if (ml->p1_sv)
            SvREFCNT_dec(ml->p1_sv);
        if (ml->p1_utf8_sv)
            SvREFCNT_dec(ml->p1_utf8_sv);
        if (ml->p1_latin1_sv)
            SvREFCNT_dec(ml->p1_latin1_sv);
        if (ml->p2_sv)
            SvREFCNT_dec(ml->p2_sv);
        if (ml->p2_utf8_sv)
            SvREFCNT_dec(ml->p2_utf8_sv);
        if (ml->p2_latin1_sv)
            SvREFCNT_dec(ml->p2_latin1_sv);
    }
}

SV *
fetch_composite_key(self_hv, full_key_sv)
        HV *self_hv
        SV *full_key_sv
    ALIAS:
        exists_composite_key = 1
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    dFAST_PROPS;
    dMOUNT;
    IV found_it= 0;
    STRLEN full_key_len;
    char *full_key_pv= SvPV(full_key_sv, full_key_len);

    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);

    if (ml->level > 1) croak("not defined on child nodes");

    RETVAL= ix ? NULL : newSV(0);

    found_it= triple_lookup_key_pvn(aTHX_ obj, ml, NULL, full_key_pv, full_key_len, RETVAL, NULL);

    if (!RETVAL)
        RETVAL= found_it ? &PL_sv_yes : &PL_sv_no;
}
    OUTPUT:
        RETVAL

SV *
FETCH(self_hv, key_sv)
        HV *self_hv
        SV *key_sv
    ALIAS:
        EXISTS = 1
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    dFAST_PROPS;
    dMOUNT;
    IV found_it= 0;
    SV *p1_sv= NULL;
    SV *p2_sv= NULL;
    RETVAL= ix ? NULL : newSV(0);

    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);

    if (ml->level == 3) {
        p1_sv= ml->p1_sv;
        p2_sv= ml->p2_sv;
        if (MPH_HASH_FOR_FETCH) {
            STRLEN full_key_len;
            char *pv= triple_build_mortal_key(aTHX_ p1_sv, p2_sv, key_sv, &full_key_len, ml->separator);
            found_it= triple_lookup_key_pvn(aTHX_ obj, ml, NULL, pv, full_key_len, RETVAL, key_sv);
        } else {
            struct mph_header *mph= obj->header;
            IV idx= triple_find_first_prefix(aTHX_
                obj, p1_sv, p2_sv, key_sv,
                ml->leftmost_idx, ml->rightmost_idx);
            if (idx>=0) {
                found_it= 1;
                if (RETVAL)
                    triple_set_val(aTHX_ obj, NULL, idx, RETVAL);
            }
        }
    } else {
        IV key_rightmost_idx;
        IV key_leftmost_idx;
        if ( ml->p1_sv ) {
            p1_sv= ml->p1_sv;
            p2_sv= key_sv;
        }
        else
            p1_sv= key_sv;

        key_leftmost_idx= triple_find_first_last_prefix(aTHX_
            obj, p1_sv, p2_sv, NULL,
            ml->leftmost_idx, ml->rightmost_idx, &key_rightmost_idx);

        if (ix) {
            found_it = key_leftmost_idx >= 0;
        }
        else
        if (key_leftmost_idx >= 0) {
            HV *obj_hv= newHV();
            SV *obj_rv= newRV_noinc((SV*)obj_hv);
            HV *tie_hv= newHV();
            SV *tie_rv= newRV_noinc((SV*)tie_hv);
            SV *key_mount_rv;
            SV *key_fast_props_sv;
            struct mph_multilevel *new_ml;
            struct mph_triple_bucket *first_bucket= (struct mph_triple_bucket *)((char *)obj->header + obj->header->table_ofs);
            struct mph_triple_bucket *bucket= first_bucket + key_leftmost_idx;

            hv_fetch_sv_with_keysv(key_mount_rv,obj_hv,MPH_KEYSV_MOUNT,1);
            sv_setsv(key_mount_rv, mount_rv);

            hv_fetch_sv_with_keysv(key_fast_props_sv,obj_hv,MPH_KEYSV_FAST_PROPS,1);
            sv_grow(key_fast_props_sv,sizeof(struct mph_multilevel));
            SvCUR_set(key_fast_props_sv,sizeof(struct mph_multilevel));
            SvPOK_on(key_fast_props_sv);
            new_ml= (struct mph_multilevel *)SvPVX(key_fast_props_sv);

            new_ml->p1_sv= SvREFCNT_inc(p1_sv);
            new_ml->p1_utf8_sv= NULL;
            new_ml->p1_latin1_sv= NULL;
            new_ml->k1_idx= bucket->k1_idx;

            new_ml->p2_sv= p2_sv;
            new_ml->p2_utf8_sv= NULL;
            new_ml->p2_latin1_sv= NULL;
            if (p2_sv) {
                SvREFCNT_inc(p2_sv);
                new_ml->k2_idx= bucket->k2_idx;
            }

            new_ml->leftmost_idx= key_leftmost_idx;
            new_ml->rightmost_idx= key_rightmost_idx;
            new_ml->level= ml->level+1;
            new_ml->levels= ml->levels;
            new_ml->separator= ml->separator;
            new_ml->converted= 0;

            sv_bless(obj_rv, SvSTASH((SV *)self_hv));
	    sv_magic((SV *)tie_hv, obj_rv, PERL_MAGIC_tied, NULL, 0);

            sv_setsv(RETVAL, tie_rv);
        }
    }
    if (!RETVAL)
        RETVAL= found_it ? &PL_sv_yes : &PL_sv_no;
}
    OUTPUT:
        RETVAL

void
Dump(self_hv,flags)
        HV *self_hv
        U32 flags
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    dFAST_PROPS;
    dMOUNT;
    struct mph_header *mph;
    SV *tmp1= sv_newmortal();
    SV *tmp2= sv_newmortal();
    SV *tmp3= sv_newmortal();
    SV *tmp4= sv_newmortal();
    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);

    mph= obj->header;
    if (mph->variant != 7) croak("must be variant 7!");
    warn("--Header--\n");
    warn("magic_num     : %u\n", mph->magic_num);
    warn("variant       : %u\n", mph->variant);
    warn("num_buckets   : %u\n", mph->num_buckets);
    warn("state_ofs     : 0x%08x\n", mph->state_ofs);
    warn("table_ofs     : 0x%08x\n", mph->table_ofs);
    warn("key_flags_ofs : 0x%08x\n", mph->key_flags_ofs);
    warn("val_flags_ofs : 0x%08x\n", mph->val_flags_ofs);
    warn("str_buf_ofs   : 0x%08x\n", mph->str_buf_ofs);
    warn("utf8_flags    : 0x%02x\n", mph->utf8_flags);
    warn("separator     : 0x%02x (%c)\n", mph->separator, mph->separator);
    warn("reserved_u16  : 0x%04x\n", mph->reserved_u16);
    warn("str_len_ofs   : 0x%08x\n", mph->str_len_ofs);
    warn("codepair_ofs  : 0x%08x\n", mph->codepair_ofs);
    warn("reserved_u32  : 0x%08x\n", mph->reserved_u32);
    warn("state         : 0x%s\n", sv_hex(aTHX_ tmp1, STATE_PTR(mph), 4 * sizeof(U64)));
    warn("---------------------------------------------------------------------\n");
    if (flags & (1<<0)) {
        struct mph_triple_bucket *bucket= TRIPLE_BUCKET_PTR(mph);
        struct mph_triple_bucket *sentinel= bucket + mph->num_buckets;
        U32 i= 0;
        warn("[bucket]  xor_val k1_idx k2_idx k3_idx sortix  v_idx     n1     n2\n");
        for (;bucket < sentinel;bucket++) {
            warn("[%6u] %+8d %6u %6u %6u %6u %6u %+6d %+6d\n",
                i++,
                bucket->xor_val, bucket->k1_idx, bucket->k2_idx, bucket->k3_idx,
                bucket->sort_index, bucket->v_idx, bucket->n1, bucket->n2);
        }
    }
    if (flags & (1<<1)) {
        if (mph->key_flags_ofs != mph->val_flags_ofs) {
            warn("key bits not shown\n");
        }
        if (mph->val_flags_ofs != mph->str_len_ofs) {
            warn("key bits not shown\n");
        }
    }
    if (flags & (1<<2)){
        struct str_len *str_len= STR_LEN_PTR(mph);
        I32 count= str_len->len;
        I32 i;
        warn("---------------------------------------------------------------------\n");
        for (i=0; i<count;i++) {
            if (i) {
                str_len_set_sv_bytes(aTHX_ obj, str_len[i].ofs, str_len[i].len, tmp1);
                pv_pretty(tmp3,SvPVX(tmp1),SvCUR(tmp1),70,NULL,NULL,PERL_PV_PRETTY_QUOTE|PERL_PV_PRETTY_ELLIPSES);
            } else {
                sv_setpvs(tmp3,"undef");
            }
            warn("str_len:%6d ofs:%8u len:%7d %"SVf"\n",i, str_len[i].ofs, str_len[i].len, tmp3);
        }
    }
    if (flags & (1<<3)){
        char *flags[4]= {"  ", "! ", "+ ", "+!"};
        struct codepair_array *cp= &obj->codepair_array;
        U32 i;
        U32 total_len= 0;
        U32 used_len= 0;
        warn("---------------------------------------------------------------------\n");
        warn("num_codepairs: %u\n", cp->next_codepair_id);
        for(i= 257; i < cp->next_codepair_id ; i++) {
            U32 codea, codeb;
            get_codepair_for_idx(cp, i, &codea, &codeb);
            decode_cpid_into_sv(aTHX_ cp, codea, tmp1);
            decode_cpid_into_sv(aTHX_ cp, codeb, tmp2);
            used_len += 6;
            total_len += (SvCUR(tmp1)+SvCUR(tmp2));
            pv_pretty(tmp3,SvPVX(tmp1),SvCUR(tmp1),20,NULL,NULL,PERL_PV_PRETTY_QUOTE|PERL_PV_PRETTY_ELLIPSES);
            pv_pretty(tmp4,SvPVX(tmp2),SvCUR(tmp2),20,NULL,NULL,PERL_PV_PRETTY_QUOTE|PERL_PV_PRETTY_ELLIPSES);
            warn("idx: %7u codea:%8u:%6u%s codeb:%8u:%6u%s len: %4lu Ratio: %6.4f%% | %"SVf" %"SVf"\n",
                i,
                codea,
                codea >> 2,
                flags[codea & 3],
                codeb,
                codeb >> 2,
                flags[codeb & 3],
                SvCUR(tmp1) + SvCUR(tmp2),
                ((double)used_len)/((double)total_len),
                tmp3,
                tmp4
            );
        }
        warn("total string length: %u total used: %u ratio: %6.4f (%6.4f)\n", 
        total_len, 
        used_len,
        ((double)used_len)/((double)total_len),
        ((double)total_len)/((double)used_len)
        );
    }
}


MODULE = Algorithm::MinPerfHashTwoLevel		PACKAGE = Tie::Hash::MinPerfHashTwoLevel::Mount

SV*
mount_file(file_sv,error_sv,flags)
        SV* file_sv
        SV* error_sv
        U32 flags
    PROTOTYPE: $$$
    CODE:
{
    RETVAL= _mount_file(aTHX_ file_sv, error_sv, flags);
    if (!RETVAL)
        XSRETURN_UNDEF;
}
    OUTPUT:
        RETVAL

void
unmount_file(mount_sv)
        SV* mount_sv
    PROTOTYPE: $
    CODE:
{
    struct mph_obj *obj= (struct mph_obj *)SvPV_nomg_nolen(mount_sv);
    _mph_munmap(aTHX_ obj);
    SvOK_off(mount_sv);
}

