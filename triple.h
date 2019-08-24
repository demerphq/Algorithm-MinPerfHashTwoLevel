#ifndef _MPH_TRIPLE_H
#define _MPH_TRIPLE_H
IV triple_find_first_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r);
IV triple_find_last_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r);
IV triple_find_first_last_prefix(pTHX_ struct mph_obj *obj, SV *p1_sv, SV *p2_sv, SV *p3_sv, IV l, IV r, IV *last);

void triple_set_val(struct mph_obj *obj, struct mph_triple_bucket *bucket, U32 bucket_idx, SV *val_sv);
void triple_set_key(struct mph_obj *obj, U32 str_len_idx, struct mph_triple_bucket *bucket, U32 bucket_idx, SV *key_sv);


int triple_lookup_key_pvn(pTHX_ struct mph_obj *obj, struct mph_multilevel *ml, SV *full_key_sv, U8 *full_key_pv, STRLEN full_key_len, SV *val_sv, SV *leaf_sv);
char *triple_build_mortal_key(pTHX_ SV *p1_sv, SV *p2_sv, SV *key_sv, STRLEN *full_key_lenp, const char separator);

MPH_STATIC_INLINE struct mph_triple_bucket *
last_bucket_by_k1(struct mph_triple_bucket *bucket) {
    I32 n= bucket->n1;
    return n > 0 ? bucket + n : bucket;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
first_bucket_by_k1(struct mph_triple_bucket *bucket) {
    I32 n;
    struct mph_triple_bucket *last_bucket= last_bucket_by_k1(bucket);
    n= last_bucket->n1;
    return last_bucket + n + 1;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
last_bucket_by_k2(struct mph_triple_bucket *bucket) {
    I32 n= bucket->n2;
    return n > 0 ? bucket + n : bucket;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
first_bucket_by_k2(struct mph_triple_bucket *bucket) {
    I32 n;
    struct mph_triple_bucket *last_bucket= last_bucket_by_k2(bucket);
    n= last_bucket->n2;
    return last_bucket + n + 1;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
prev_bucket_by_k1(struct mph_triple_bucket *bucket) {
    return first_bucket_by_k1(bucket) - 1;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
next_bucket_by_k1(struct mph_triple_bucket *bucket) {
    return last_bucket_by_k1(bucket) + 1;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
prev_bucket_by_k2(struct mph_triple_bucket *bucket) {
    return first_bucket_by_k2(bucket) - 1;
}

MPH_STATIC_INLINE struct mph_triple_bucket *
next_bucket_by_k2(struct mph_triple_bucket *bucket) {
    return last_bucket_by_k2(bucket) + 1;
}
#endif /* _MPH_TRIPLE_H */
