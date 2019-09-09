#ifndef MPH2L_BASIC_H
#define MPH2L_BASIC_H

/*
 * Just the basic, C- and Perl-compatible declarations for the header.
 * For Perl, you can just include this file.
 * For C, you will have to include <stdint.h> before including the file.
 */

#if !defined(U8)
#if defined(U8TYPE)
#define U8 U8TYPE
#else
#define U8 uint8_t
#endif
#endif

#if !defined(U16)
#if defined(U16TYPE)
#define U16 U16TYPE
#else
#define U16 uint16_t
#endif
#endif

#if !defined(U32)
#if defined(U32TYPE)
#define U32 U32TYPE
#else
#define U32 uint32_t
#endif
#endif

#if !defined(U64)
#if defined(U64TYPE)
#define U64 U64TYPE
#else
#define U64 uint64_t
#endif
#endif

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
        struct {
            U32 codepair_ofs;
            U32 reserved_u32;
        };
    };
};

#endif
