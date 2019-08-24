#define U64 U64TYPE
#include "trie2.h"

struct sv_with_hash {
    SV *sv;
    U32 hash;
};

struct mph_header {
    U32 magic_num;
    U32 variant;
    U32 num_buckets;
    U32 state_ofs;

    U32 table_ofs;
    U32 key_flags_ofs;
    U32 val_flags_ofs;
    U32 str_buf_ofs;

    union {
        U64 table_checksum;
        U64 general_flags;
        union {
            struct {
                U8 utf8_flags;
                U8 separator;
                U16 reserved_u16;
                U32 str_len_ofs;
            };
        };
    };
    union {
        U64 str_buf_checksum;
        union {
            U32 codepair_ofs;
            U32 reserved_u32_1;
        };
    };
};


#define BUCKET_FIELDS           \
    union {                     \
        U32 xor_val;            \
        I32 index;              \
    };                          \
    union {                     \
        U32 key_ofs;            \
        U32 k1_idx;             \
    };                          \
    union {                     \
        U32 val_ofs;            \
        U32 k2_idx;             \
    };                          \
    union {                     \
        struct {                \
            U16 key_len;        \
            U16 val_len;        \
        };                      \
        U32 k3_idx;             \
    }


struct mph_bucket {
    BUCKET_FIELDS;
};

struct mph_sorted_bucket {
    BUCKET_FIELDS;
    U32 sort_index;
};

struct mph_triple_bucket {
    BUCKET_FIELDS;
    U32 sort_index;
    U32 v_idx;
    I32 n1;
    I32 n2;
};

struct str_len {
    U32 ofs;
    I32 len;
};

struct str_len_obj {
    HV *compressed_hv;
    HV *uncompressed_hv;
    U32 count;
    U32 next;
    U32 compressed_count;
    U32 uncompressed_count;
    U32 longest_compressed;
    U32 longest_uncompressed;
    U32 longest;
    struct compressor *compressor;
    struct str_len *str_len;
};

struct mph_obj {
    size_t bytes;
    struct mph_header *header;
    struct codepair_array codepair_array;
};

struct mph_multilevel {
    IV iter_idx;
    IV leftmost_idx;
    IV rightmost_idx;
    IV bucket_count;
    union {
        SV *prefix_sv;
        SV *p1_sv;
    };
    union {
        SV *prefix_utf8_sv;
        SV *p1_utf8_sv;
    };
    union {
        SV *prefix_latin1_sv;
        SV *p1_latin1_sv;
    };
    IV level;
    IV levels;
    IV fetch_key_first;
    char separator;
    char converted;
    SV *p2_sv;
    SV *p2_utf8_sv;
    SV *p2_latin1_sv;
    I32 k1_idx;
    I32 k2_idx;
};
