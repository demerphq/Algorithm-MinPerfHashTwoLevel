package Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk;
use strict;
use warnings;
use Tie::Hash::MinPerfHashTwoLevel::Mount;
use Tie::Hash::MinPerfHashTwoLevel::OnDisk ':flags', ':xs_subs';
our $VERSION = '0.16';
our $DEFAULT_VARIANT = 7;
our @ISA= ("Tie::Hash::MinPerfHashTwoLevel::OnDisk");

# this also installs the XS routines we use into our namespace.
use Exporter qw(import);
use Carp;
use constant {
    DEBUG               => 0,
    MOUNT_IDX           => 0,
    SEPARATOR_IDX       => 1,
};

our %EXPORT_TAGS = (
    'all' => [],
    'flags' => [],
    'magic' => [],
);

my $scalar_has_slash= scalar(%EXPORT_TAGS)=~m!/!;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw();

sub mph2l_multi_tied_hashref {
    my ($file, %opts)= @_;
    tie my %tied, __PACKAGE__, $file, %opts;
    return \%tied;
}

sub new {
    my $self;
    my ($class,%opts)= @_;
    my $sep= $opts{separator} //= "/";
    if (length($sep) != 1 or ord($sep) > 127) {
        die "Separator MUST be a single ASCII character (eg 0-127)";
    }
    my $mount= $opts{mount}= Tie::Hash::MinPerfHashTwoLevel::Mount->new(\%opts);
    $self= bless \%opts, $class;
    if ($self->get_hdr_variant != 7) {
        die "Cannot use ".__PACKAGE__." with a variant " . $self->get_hdr_variant . " file";
    }
    $self->{leftmost_idx}= 0;
    $self->{rightmost_idx}= $self->get_hdr_num_buckets - 1;
    $self->{levels}= 3;
    $self->{level}= 1;
    return $self;
}


*TIEHASH= *new;


# mixed XS/pure-perl version of FETCH - the real FETCH is in MinPerfHashTwoLevel.xs
sub SCALAR {
    my ($self)= @_;
    return $self->{scalar_buckets} //= do {
        my $bucket_count= $self->{rightmost_idx} - $self->{leftmost_idx} + 1;
        if ($bucket_count && $scalar_has_slash) {
            $bucket_count .= "/" . $bucket_count;
        }
        $bucket_count;
    };
}

sub UNTIE {
    my ($self)= @_;
}

sub STORE {
    my ($self, $key, $value)= @_;
    confess __PACKAGE__ . " is readonly, STORE operations are not supported";
}

sub DELETE {
    my ($self, $key)= @_;
    confess __PACKAGE__ . " is readonly, DELETE operations are not supported";
}

sub CLEAR {
    my ($self)= @_;
    confess __PACKAGE__ . " is readonly, CLEAR operations are not supported";
}

1;
__END__

=head1 NAME

Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk - construct or tie a "two level" minimal perfect hash based on disk

=head1 SYNOPSIS

  use Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk;

  Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk->make_file(
    file => $some_file,
    source_hash => $some_hash,
    comment => "this is a comment",
    compress_keys => 0,
    compress_vals => 1,
    separator => "/",                   # MANDATORY!
    debug => 0,
  );

  my %hash;
  tie %hash, "Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk", file => $some_file;

=head1 DESCRIPTION

This module allows one to either construct, or use a precomputed minimal
perfect hash on disk via tied interface. The disk image of the hash is
loaded by using mmap, which means that multiple processes may use the
same disk image at the same time without memory duplication. The hash
is readonly, and may only contain string values.

This module is similar to Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk
in that it allows one to represent a multi level hash using composite keys
with a separator. Unlike MultiLevelOnDisk however the nesting depth is fixed
to three levels, and the disk structure and code are optimised for three
level hashes. Additionally ThreeLevelOnDisk supports inline key and value
compression if desired.

=head2 METHODS

=over 4

=item make_file

Construct a new file from a given 'source_hash' argument. Takes the following arguments:

=over 4

=item file

The file name to produce, mandatory.

=item comment

An arbitrary piece of text of your choosing. Can be extracted from
the file later if needed. Only practical restriction on the value is
that it cannot contain a null.

=item seed

A 16 byte string (or a reference to one) to use as the seed for
the hashing and generation process. If this is omitted a standard default
is chosen.

If it should prove impossible to construct a solution using the seed chosen
then a new one will be constructed deterministically from the old until a
solution is found (see L<max_tries>) (prior to version v0.10 this used rand()).
Should you wish to access the seed actually used for the final solution
then you can pass in a reference to a scalar containing your chosen seed.
The reference scalar will be updated after successful construction.

Thus both of the following are valid:

    Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk->make_file(seed => "1234567812345678", ...);
    Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk->make_file(seed => \my $seed= "1234567812345678", ...);

=item no_dedupe

Speed up construction at the cost of a larger string buffer by disabling
deduplication of values and keys.  Same as setting the MPH_F_NO_DEDUPE bit
in compute_flags.

=item filter_undef

Ignore keys with undef values during construction. This means that exists() checks
may differ between source and the constructed hash table, but avoids the need to
store such keys in the resulting file, saving space. Same as setting the
MPH_F_FILTER_UNDEF bit in compute_flags.

=item max_tries

The maximum number of attempts to make to find a solution for this keyset.
Defaults to 3.

=item debug

Enable debug during generation.

=item compress_keys

Keys will be compressed internally. This will slow things down.

=item compress_vals

Values will be compressed internally. This will slow things down a bit.

=item variant

Variant must be 7 for a ThreeLevelOnDisk hash.

=back

=item validate_file

Validate the file specified by the 'file' argument. Returns a list of
two values, 'variant' and 'message'. If the file fails validation the 'variant'
will be undef and the 'message' will contain an error message. If the file
passes validation the 'variant' will specify the variant of the file
(currently only 0 is valid), and 'message' will contain some basic information
about the file, such as how many keys it contains, the comment it was
created with, etc.

=back

=head2 TIED INTERFACE

  my %hash;
  tie %hash, "Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk", file => $some_file, separator => "/";

will setup %hash to read from the mmapped image on disk as created by make_file().
The underlying image is never altered, and copies of the keys and values are made
when necessary. The flags field is an integer which contains bit-flags to control
the reading process, currently only one flag is supported MPH_F_VALIDATE which enables
a full file checksum before returning (forcing the data to be loaded and then read).
By default this validation is disabled, however basic checks of that the header is
sane will be performed on loading (or "mounting") the image. The tie operation may
die if the file is not found or any of these checks fail.

=head2 FILE FORMAT

Variant 7 uses the following structure:

Structure:

    Header
    Hash-state
    Bucket-table
    Key flags (optional)
    Val flags (optional)
    String/Length Data
    Strings (optional)
    Compressed Data (optional)
    Checksum

Header:

    U32 magic_num       -> 1278363728 -> "PH2L"
    U32 variant         -> 7
    U32 num_buckets     -> number of buckets/keys in hash
    U32 state_ofs       -> offset in file where hash preseeded state is found
    U32 table_ofs       -> offset in file where bucket table starts
    U32 key_flags_ofs   -> offset in file where key flags are located
    U32 val_flags ofs   -> offset in file where val flags are located
    U32 str_buf_ofs     -> offset in file where strings are located
    U8  utf8_flags      -> flag bits for all keys if any
    U8  separator       -> which codepoint is the separator for our keys
    U16 reserved_u16    -> reserved/padding (0)
    U32 str_len_ofs     -> offset in file where str_len data is located.
    U32 codepair_ofs    -> offset in file where codepair data is located.
    U32 reserved_u32    -> reserved field/padding (0)


All "_ofs" values in the header are a multiple of 8, and the relevant sections
maybe be null padded to ensure this is so.

The last 8 bytes of the file contains a hash checksum of the rest of the entire
file. This value is itself 8 byte aligned.

Keys and values can be independently encoded as either raw strings, or as compressed
data. Raw strings are automatically packed to avoid duplication where possible. String
values are represented by a U32 which represents an offset into the "str_len" table.
This table consists of a set of pairs of I32,U32 "offset and length", where negative
values represent the dictionary ids of compressed strings, and positive values
represent offsets into the string buffer. Compressed data is stored in a set of buckets
which are either 48 or 64 bits wide.

Buckets:

   I32 xor_val      -> the xor_val for this bucket's h1 lookups (0 means none)
                       for variant 1 and later this may also be treated as a signed
                       integer, with negative values representing the index of
                       the bucket which contains the correct key (-index-1).
   U32 k1           -> str_len index for the first element of the compound key.
   U32 k2           -> str_len index for the second element of the compound key.
   U32 k3           -> str_len index for the third element of the compound key.
   U32 sort_index   -> sort index for this bucket, used in hash lookup in combination with xor_val
   U32 v_idx        -> str_len index for the value of this key.
   I32 n1           -> offset to the first or last item with the same k1 as this record.
   I32 n2           -> offset to the first or last item with the same k2 as this record.

Str Len:

    I32 offset      -> When >=0 offset into str_buf, when negative represents a compressed item
    U32 length      -> Length of either the string or the compressed item.

Compressed Data: # this may be revised before release!
    U32 compressed_magic    - 19720428
    U32 next_codepair_id    - max codepair id. these names are terrible
    U32 short_info_next     - max short codepair id.
    U32 long_info_next      - max long codepair id.
    U32 short_bytes         - number of short codepair ids
    U32 long_bytes          - number of long codepair ids

Short Codepairs:
    U24 codea       -> code value a
    U24 codeb       -> code value b

Long Codepairs:
    U32 codea
    U32 codeb

Compression, data can be optionally compressed using a custom version of LZ compression.
All data is represented as one or mode "codes", which are essentially indexes into a dictionary.
The first 257 codes are "virtual", with the ones from 0..255 representing their respective byte,
and code 256 representing the empty string. With this in mind, the data stream is broken down
into pairs of codes, with each new pair being given the next available code which can be reused
when compressing something later. The pair that represents the most data is chosen each time.
The empty string is used to resolve cases where the data cannot efficiently be divided into an
even number of subsequences. This code are complemented by two bits which are used to represent
a "continue bit", and a "stop bit". The "stop bit" is used to represent the end of a string,
and the "continue bit" is used to be able to insert previous emited sequences of pairs, instead
of just a pair.

The end result is that every unique string contained in the compressed blob can be represented
by a single code and bits. Decoding is recursive, but eventually always hits a code that is in
the 0..256 range where it stops. For codes that can be represented with 22 bits a 48 bit
representation is used for the pairs, and for codes that require up to 30 bits a 64 bit
representation is used for the pair. Compression for large numbers of small strings is in
the 3:1 to 4:1 range, but for long strings it tends to be in the 8:1 or 9:1.

=head2 EXPORT

None by default.

=head1 SEE ALSO

Algorithm::MinPerfHashTwoLevel

=head1 AUTHOR

Yves Orton

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Yves Orton

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.4 or,
at your option, any later version of Perl 5 you may have available.

=cut
