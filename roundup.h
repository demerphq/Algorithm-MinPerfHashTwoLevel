PERL_STATIC_INLINE U32
_roundup(const U32 n, const U32 s) {
    const U32 r= n % s;
    if (r) {
        return n + s - r;
    } else {
        return n;
    }
}


