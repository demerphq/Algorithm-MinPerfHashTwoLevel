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

I32
_compare(pTHX_ SV *a, SV *b) {
    dMY_CXT;
    struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    HE *a_he= hv_fetch_ent_with_keysv((HV*)SvRV(a),MPH_KEYSV_KEY,0);
    HE *b_he= hv_fetch_ent_with_keysv((HV*)SvRV(b),MPH_KEYSV_KEY,0);
    SV *a_sv= HeVAL(a_he);
    SV *b_sv= HeVAL(b_he);
    return sv_cmp(a_sv,b_sv);
}

I32 setup_fast_props(pTHX_ HV *self_hv, AV *mount_av, struct sv_with_hash *keyname_sv, SV *fast_props_sv) {
    SV *sv;
    SV **svp;
    struct mph_multilevel ml;
    
    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_PREFIX,1);
    ml.prefix_sv= SvREFCNT_inc(sv);
    ml.prefix_utf8_sv= NULL;
    ml.prefix_latin1_sv= NULL;

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_LEFTMOST_IDX,1);
    ml.leftmost_idx= SvIV(sv);

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_RIGHTMOST_IDX,1);
    ml.rightmost_idx= SvIV(sv);

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_LEVEL,1);
    ml.level= SvIV(sv);

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_LEVELS,1);
    ml.levels= SvIV(sv);

    hv_fetch_sv_with_keysv(sv, self_hv, MPH_KEYSV_FETCH_KEY_FIRST,1);
    ml.fetch_key_first= SvIV(sv);

    svp= av_fetch(mount_av,MOUNT_ARRAY_SEPARATOR_IDX,0);
    ml.separator= SvPV_nolen(*svp)[0];

    sv_setpvn(fast_props_sv,(char *)&ml,sizeof(struct mph_multilevel));
    ml.converted= 1;
}

#define dFAST_PROPS \
    struct mph_multilevel *ml; \
    SV *fast_props_sv

#define GET_FAST_PROPS(self_hv) STMT_START {                                    \
    hv_fetch_sv_with_keysv(fast_props_sv, self_hv, MPH_KEYSV_FAST_PROPS,1);     \
    if (!SvOK(fast_props_sv))                                                   \
        setup_fast_props(aTHX_ self_hv, mount_av, keyname_sv, fast_props_sv);   \
    ml= (struct mph_multilevel *)SvPV_nolen(fast_props_sv);                     \
} STMT_END

#define dMOUNT        \
    struct mph_obj *obj= NULL;  \
    SV *mount_rv;               \
    AV *mount_av;               \
    SV *mount_sv

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
    mount_av= (AV *)SvRV(mount_rv);                                 \
    mount_svp= av_fetch(mount_av,MOUNT_ARRAY_MOUNT_IDX,0);          \
    mount_sv= *mount_svp;                                           \
    obj= (struct mph_obj *)SvPV_nolen(mount_sv);                    \
} STMT_END

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

SV *
packed_xs(variant,buf_length_sv,state_sv,comment_sv,flags,buckets_av)
        U32 variant
        SV* buf_length_sv
        SV* state_sv
        SV* comment_sv
        AV *buckets_av
        U32 flags
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    PROTOTYPE: $$$$$\@
    CODE:
{
    RETVAL= _packed_xs(variant, buf_length_sv, state_sv, comment_sv, flags, buckets_av, keyname_sv);
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
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
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
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
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

IV
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


SV *
get_comment(self_hv)
        HV* self_hv
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
            get_state = 11
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    PROTOTYPE: $
    CODE:
{
    dMOUNT;
    char *start;

    GET_MOUNT_AND_OBJ(self_hv);

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
    if (sv_prefix_cmp3(nextkey_sv,this_prefix_sv,this_prefix_sv))
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
        ml= (struct mph_multilevel *)SvPV_nolen(fast_props_sv);
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
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    dFAST_PROPS;
    dMOUNT;
    SV *fetch_key_sv;
    RETVAL= newSV(0);

    GET_MOUNT_AND_OBJ(self_hv);
    GET_FAST_PROPS(self_hv);

    fetch_key_sv= sv_2mortal(newSVsv(ml->prefix_sv));
    sv_catsv(fetch_key_sv,key_sv);

    if ( !(ml->fetch_key_first && ( lookup_key(aTHX_ obj->header, fetch_key_sv, RETVAL) || ml->fetch_key_first > 1 ) ) ) {
        IV key_rightmost_idx;
        IV key_leftmost_idx;

        sv_catpvn(fetch_key_sv,&ml->separator,1);

        key_leftmost_idx= find_first_last_prefix(aTHX_ obj->header, fetch_key_sv, ml->leftmost_idx,
            ml->rightmost_idx+1, &key_rightmost_idx);

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
}
    OUTPUT:
        RETVAL

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
    struct mph_obj *obj= (struct mph_obj *)SvPV_nolen(mount_sv);
    _mph_munmap(obj);
    SvOK_off(mount_sv);
}


