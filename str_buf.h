struct str_buf {
    char *start;
    char *ofs_start;
    char *end;
    char *pos;
    HV   *hv;
};

PERL_STATIC_INLINE void
str_buf_init(pTHX_ struct str_buf *str_buf, char *start, char *pos, char *end) {
    str_buf->start= start;
    str_buf->end= end;
    str_buf->ofs_start= pos;
    str_buf->pos= pos + 2;
    pos[0]=0;
    pos[1]=0;
    str_buf->hv= (HV*)sv_2mortal((SV*)newHV());
}


PERL_STATIC_INLINE U32
str_buf_add_from_sv(pTHX_ struct str_buf *str_buf, SV *sv, U16 *plen, const U32 flags) {
    HE *ofs_he;
    SV *ofs_sv;
    char *pv;
    STRLEN len;
    U32 ofs= 0;

    if (!SvOK(sv)) {
        if (plen)
            *plen= 0;
        return 0;
    }
    pv= SvPV(sv,len);
    if (plen)
        *plen= len;
    if (!len)
        return 1;
    if (len > UINT16_MAX)
        croak("string too long!");
    if (!(flags & MPH_F_NO_DEDUPE)) {
        ofs_he= hv_fetch_ent(str_buf->hv,sv,1,0); /* lvalue fetch */
        if (!ofs_he)
            croak("panic: out of memory getting str ofs HE");
        ofs_sv= HeVAL(ofs_he);
        if (!ofs_sv)
            croak("panic: out of memory getting str ofs SV");
        if (SvOK(ofs_sv))
            ofs= SvUV(ofs_sv);
    }
    if (!ofs) {
        if (str_buf->pos + len <= str_buf->end) {
            ofs= str_buf->pos - str_buf->ofs_start;
            Copy(pv, str_buf->pos, len, char);
            str_buf->pos += len;
            if (ofs_sv)
                sv_setuv(ofs_sv, ofs);
        } else {
            croak("ran out of concat space!");
        }
    }
    return ofs;
}

PERL_STATIC_INLINE U32
str_buf_add_from_he(pTHX_ struct str_buf *str_buf, HE *he, U16 *plen, const U32 flags) {
    SV *sv= HeVAL(he);
    if (!sv)
        croak("no HE in str_buf_add_from_he!");
    return str_buf_add_from_sv(aTHX_ str_buf,sv,plen,flags);
}

PERL_STATIC_INLINE void
str_buf_cat_char(pTHX_ struct str_buf *str_buf, char ch) {
    if (str_buf->pos + 1 <= str_buf->end) {
        str_buf->pos[0]= ch;
        str_buf->pos++;
    } else {
        croak("ran out of concat space!");
    }
}

PERL_STATIC_INLINE STRLEN
str_buf_finalize(pTHX_ struct str_buf *str_buf, U32 alignment, char *state) {
    U32 r;
    str_buf_cat_char(aTHX_ str_buf, 0);
    str_buf_cat_char(aTHX_ str_buf, 128);

    r= (str_buf->pos - str_buf->start) % alignment;
    for (;r && r<alignment;r++)
        str_buf_cat_char(aTHX_ str_buf, 0);

    if (str_buf->pos + sizeof(U64) <= str_buf->end) {
        *((U64 *)str_buf->pos)= mph_hash_with_state(state, str_buf->start, str_buf->pos - str_buf->start);
        str_buf->pos += sizeof(U64);
    } else {
        croak("not enough space in str_buf to finalize: %ld remaining", str_buf->end - str_buf->pos);
    }

    return str_buf->pos - str_buf->start;
}


