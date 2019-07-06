#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"
#include "mph2l.h"

#define MY_CXT_KEY "Algorithm::MinPerfHashTwoLevel::_stash" XS_VERSION
START_MY_CXT

I32
_compare(pTHX_ SV *a, SV *b) {
    dMY_CXT;
    struct sv_with_hash *keyname_sv= MY_CXT.keyname_sv;
    HE *a_he= hv_fetch_ent_with_keysv((HV*)SvRV(a),MPH_KEYSV_KEY,0);
    HE *b_he= hv_fetch_ent_with_keysv((HV*)SvRV(b),MPH_KEYSV_KEY,0);

    return sv_cmp(HeVAL(a_he),HeVAL(b_he));
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
    SV *mount_sv;
    char *start;
    HE *got= hv_fetch_ent_with_keysv(self_hv,MPH_KEYSV_MOUNT,0);
    if (!got)
        croak("must be mounted to use this function");
    mount_sv= HeVAL(got);
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

