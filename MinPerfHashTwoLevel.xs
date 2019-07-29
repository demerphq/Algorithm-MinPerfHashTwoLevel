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
    struct mph_obj *obj;
    SV *mount_rv;
    SV **mount_svp;
    SV *mount_sv;
    AV *mount_av;
    char *start;
    HE *got= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_MOUNT,0);
    if (!got)
        croak("must be mounted to use this function");
    /* yes, yes, this is overly pedantic */
    mount_rv= HeVAL(got);
    mount_av= (AV *)SvRV(mount_rv);
    mount_svp= av_fetch(mount_av,MOUNT_ARRAY_MOUNT_IDX,0);
    mount_sv= *mount_svp;

    if (!mount_sv || !SvPOK(mount_sv))
        croak("$self->'mount' is expected to be a string!");
    obj= (struct mph_obj *)SvPV_nolen(mount_sv);
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
    SV *mount_rv;
    SV **svp;
    SV *mount_sv;
    char separator;
    char *separator_pos;
    AV *mount_av;

    struct mph_obj *obj;
    SV *iter_idx_sv;
    SV *rightmost_idx_sv;
    SV *prefix_sv;
    IV status;
    SV *nextkey_sv= newSV(0);
    int n_is_utf8;
    IV iv;

    STRLEN nextkey_len;
    char *nextkey_pv;
    STRLEN prefix_len;
    char *prefix_pv;

    HE *got_he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_MOUNT,0);
    if (!got_he)
        croak("must be mounted to use this function");
    /* yes, yes, this is overly pedantic */
    mount_rv= HeVAL(got_he);
    mount_av= (AV *)SvRV(mount_rv);
    svp= av_fetch(mount_av,MOUNT_ARRAY_MOUNT_IDX,0);
    mount_sv= *svp;
    obj= (struct mph_obj *)SvPV_nolen(mount_sv);

    hv_fetch_sv_with_keysv(iter_idx_sv,self_hv,MPH_KEYSV_ITER_IDX,1);
    if (ix) { /* FIRSTKEY */
        SV *leftmost_idx_sv;
        hv_fetch_sv_with_keysv(leftmost_idx_sv,self_hv,MPH_KEYSV_LEFTMOST_IDX,1);
        sv_setiv(iter_idx_sv,SvIV(leftmost_idx_sv));
        /* warn("init iter_idx_sv=leftmost_idx=%ld",SvIV(leftmost_idx_sv)); */
    }

    status= lookup_bucket(aTHX_ obj->header,SvIV(iter_idx_sv),nextkey_sv,NULL);
    if (!status) XSRETURN_UNDEF;

    n_is_utf8= SvUTF8(nextkey_sv) ? 1 : 0;

    if (n_is_utf8) {
        SV *prefix_utf8_sv;
        hv_fetch_sv_with_keysv(prefix_utf8_sv,self_hv,MPH_KEYSV_PREFIX_UTF8,1);
        if (!SvOK(prefix_utf8_sv)) {
            hv_fetch_sv_with_keysv(prefix_sv,self_hv,MPH_KEYSV_PREFIX,1);
            sv_setsv(prefix_utf8_sv,prefix_sv);
            sv_utf8_upgrade(prefix_utf8_sv);
        }
        prefix_sv= prefix_utf8_sv;
    } else {
        SV *prefix_latin1_sv;
        hv_fetch_sv_with_keysv(prefix_latin1_sv,self_hv,MPH_KEYSV_PREFIX_LATIN1,1);
        if (!SvOK(prefix_latin1_sv)) {
            hv_fetch_sv_with_keysv(prefix_sv,self_hv,MPH_KEYSV_PREFIX,1);
            sv_setsv(prefix_latin1_sv,prefix_sv);
            sv_utf8_downgrade(prefix_latin1_sv,1);
            if (SvUTF8(prefix_latin1_sv)) {
                sv_utf8_upgrade(nextkey_sv);
                n_is_utf8 = 2;
            } else {
                prefix_sv= prefix_latin1_sv;
            }
        } else {
            prefix_sv= prefix_latin1_sv;
        }
    }
    /* at this point prefix_sv and nextkey_sv have the same utf8ness */

    if (sv_prefix_cmp3(nextkey_sv,prefix_sv,prefix_sv))
        XSRETURN_UNDEF;

    svp= av_fetch(mount_av,MOUNT_ARRAY_SEPARATOR_IDX,0);
    separator= (SvPV_nolen(*svp))[0];

    nextkey_pv= SvPV_nomg(nextkey_sv, nextkey_len);
    prefix_pv= SvPV_nomg(prefix_sv, prefix_len);

    separator_pos= (prefix_len <= nextkey_len)
                   ? memchr(nextkey_pv + prefix_len, separator, nextkey_len - prefix_len)
                   : NULL;

    if (!separator_pos) {
        sv_inc(iter_idx_sv);
    } else {
        SvCUR_set(nextkey_sv,separator_pos - nextkey_pv + 1);
        hv_fetch_sv_with_keysv(rightmost_idx_sv,self_hv,MPH_KEYSV_RIGHTMOST_IDX,1);
        iv= find_last_prefix(aTHX_ obj->header,nextkey_sv,SvIV(iter_idx_sv),SvIV(rightmost_idx_sv)+1);
        sv_setiv(iter_idx_sv, iv+1);
        SvCUR_set(nextkey_sv,separator_pos - nextkey_pv);
    }
    sv_chop(nextkey_sv,nextkey_pv + prefix_len);
    if (n_is_utf8 > 1) {
        sv_utf8_downgrade(nextkey_sv,1);
    }

    RETVAL= nextkey_sv;
}
    OUTPUT:
        RETVAL

SV *
FETCH(self_hv, key_sv)
        HV *self_hv
        SV *key_sv
    PREINIT:
        dMY_CXT;
        struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    CODE:
{
    SV **svp;
    SV *mount_rv;
    AV *mount_av;
    SV *mount_sv;

    struct mph_obj *obj;

    SV *prefix_sv;
    SV *fetch_key_sv;
    SV *fetch_key_first_sv;

    IV key_rightmost_idx;
    IV key_leftmost_idx;
    HE *got_he;
    RETVAL= newSV(0);

    got_he= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_MOUNT,0);
    if (!got_he)
        croak("must be mounted to use this function");

    /* yes, yes, this is overly pedantic */
    mount_rv= HeVAL(got_he);
    mount_av= (AV *)SvRV(mount_rv);
    svp= av_fetch(mount_av,MOUNT_ARRAY_MOUNT_IDX,0);
    mount_sv= *svp;
    obj= (struct mph_obj *)SvPV_nolen(mount_sv);

    hv_fetch_sv_with_keysv(prefix_sv,self_hv,MPH_KEYSV_PREFIX,1);
    fetch_key_sv= sv_2mortal(newSVsv(prefix_sv));
    sv_catsv(fetch_key_sv,key_sv);

    hv_fetch_sv_with_keysv(fetch_key_first_sv,self_hv,MPH_KEYSV_FETCH_KEY_FIRST,1);

    if ( !(SvIV(fetch_key_first_sv) && (lookup_key(aTHX_ obj->header, fetch_key_sv, RETVAL) || SvIV(fetch_key_first_sv)>1))) {
        SV *rightmost_idx_sv;
        SV *leftmost_idx_sv;
        SV **separator_svp= av_fetch(mount_av,MOUNT_ARRAY_SEPARATOR_IDX,0);

        sv_catsv(fetch_key_sv,*separator_svp);
        hv_fetch_sv_with_keysv(leftmost_idx_sv,self_hv,MPH_KEYSV_LEFTMOST_IDX,1);
        hv_fetch_sv_with_keysv(rightmost_idx_sv,self_hv,MPH_KEYSV_RIGHTMOST_IDX,1);

        key_leftmost_idx= find_first_last_prefix(aTHX_ obj->header, fetch_key_sv, SvIV(leftmost_idx_sv), SvIV(rightmost_idx_sv)+1,
            &key_rightmost_idx);
        if (key_leftmost_idx >= 0) {
            HV *obj_hv= newHV();
            SV *obj_rv= newRV_noinc((SV*)obj_hv);
            HV *tie_hv= newHV();
            SV *tie_rv= newRV_noinc((SV*)tie_hv);
            SV *key_leftmost_idx_sv;
            SV *key_rightmost_idx_sv;
            SV *key_fetch_key_first_sv;
            SV *key_mount_rv;
            SV *key_level_sv;
            SV *key_levels_sv;
            SV *level_sv;
            SV *levels_sv;

            hv_store_ent_with_keysv(obj_hv, MPH_KEYSV_PREFIX, fetch_key_sv);
            SvREFCNT_inc(fetch_key_sv);

            hv_fetch_sv_with_keysv(key_leftmost_idx_sv,obj_hv,MPH_KEYSV_LEFTMOST_IDX,1);
            sv_setiv(key_leftmost_idx_sv, key_leftmost_idx);

            hv_fetch_sv_with_keysv(key_rightmost_idx_sv,obj_hv,MPH_KEYSV_RIGHTMOST_IDX,1);
            sv_setiv(key_rightmost_idx_sv, key_rightmost_idx);

            hv_fetch_sv_with_keysv(key_mount_rv,obj_hv,MPH_KEYSV_MOUNT,1);
            sv_setsv(key_mount_rv, mount_rv);

            hv_fetch_sv_with_keysv(key_level_sv,obj_hv,MPH_KEYSV_LEVEL,1);
            hv_fetch_sv_with_keysv(key_levels_sv,obj_hv,MPH_KEYSV_LEVELS,1);

            hv_fetch_sv_with_keysv(level_sv,self_hv,MPH_KEYSV_LEVEL,1);
            hv_fetch_sv_with_keysv(levels_sv,self_hv,MPH_KEYSV_LEVELS,1);
            sv_setiv(key_level_sv,SvIV(level_sv)+1);
            sv_setsv(key_levels_sv,levels_sv);

            hv_fetch_sv_with_keysv(key_fetch_key_first_sv,obj_hv,MPH_KEYSV_FETCH_KEY_FIRST,1);
            sv_setiv(key_fetch_key_first_sv,
                (SvIV(key_level_sv) == SvIV(key_levels_sv)
                 ? 2
                : (SvIV(key_level_sv)==1 || SvIV(key_level_sv)>SvIV(key_levels_sv))
                   ? 1 : 0));


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


