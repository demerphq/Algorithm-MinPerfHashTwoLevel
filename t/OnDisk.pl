#########################

use strict;
use warnings;

use Test::More tests => 3 + 238 * (defined($ENV{VARIANT}) ? 1 : 3);
use File::Temp;
use Data::Dumper; $Data::Dumper::Sortkeys=1; $Data::Dumper::Useqq=1;
my $class;
BEGIN { use_ok($class= 'Tie::Hash::MinPerfHashTwoLevel::OnDisk') };
my $srand= $ENV{SRAND} ? srand(0+$ENV{SRAND}) : srand();
ok(defined($srand),"srand as expected: $srand");
my $eval_ok= eval {
    tie my(%fail), $class => $0;
    1;
};
my $error= !$eval_ok && $@;
ok($error,"it failed: $@");

my $tmpdir= File::Temp->newdir();

my $not_utf8= "not utf8: \x{DF}";
my $utf8_can_be_downgraded= "was utf8: \x{DF}";
utf8::upgrade($utf8_can_be_downgraded);
my $must_be_utf8= "is utf8: \x{100}"; # this can ONLY be represented as utf8

my @source_hashes= (
    {
        foo => "bar",
        baz => "bop",
        fiz => "shmang",
        plop => "shwoosh",
    },
    { map { $_ => $_ } 1 .. 50000 },
    {
        $not_utf8 => $not_utf8,
        $utf8_can_be_downgraded => $utf8_can_be_downgraded,
        $must_be_utf8 => $must_be_utf8,
        map { chr($_) => chr($_) } 250..260,
    },
    { map { $_ => $_ } 1 .. 8 },
    { map { $_ => $_ } 1 .. 16 },
    { map { $_ => $_ } 1 .. 32 },
    { map { $_ => $_ } 1 .. 64 },
);

foreach my $variant (defined($ENV{VARIANT}) ? ($ENV{VARIANT}) : (0 .. 2)) {
    foreach my $idx (0..$#source_hashes) {
        foreach my $seed ("1234567812345678",undef) {
            my $seed_str= defined $seed ? $seed : "undef";
            my $source_hash= $source_hashes[$idx];
            my $title= "seed:$seed_str hash:$idx variant:$variant";
            my $test_file= "$tmpdir/test.$seed_str.$idx.$variant.hash";
            my $seed_arg= $seed;
            my $got_file= $class->make_file(
                file        => $test_file,
                source_hash => $source_hash,
                comment     => (my $this_comment="this is a comment: $title"),
                debug       => $ENV{TEST_VERBOSE},
                seed        => \$seed_arg,
                variant     => $variant,
            );
            ok(defined($seed_arg),"seed_arg is defined after make_file()");
            is( $got_file,$test_file, "make_file returned as expected ($title)" );
            my ($got_variant,$got_message)= $class->validate_file(file=>$test_file);
            ok( defined $got_variant, "file validates ok ($title)")
                or diag $got_message;
            is( $got_variant, $variant, "file variant ok ($title)");
            my %tied_hash;
            tie %tied_hash, $class, $test_file;
            my $scalar= scalar(%tied_hash);
            ok($scalar,"scalar works");
            my $obj= tied(%tied_hash);
            is($obj->get_comment, $this_comment, "comment works as expected");
            is($obj->get_hdr_variant, $variant, "variant is as expected");
            is($obj->get_hdr_num_buckets, 0+keys %$source_hash,"num_buckets is as expected");
            my @ofs=(
                $obj->get_hdr_state_ofs,
                $obj->get_hdr_table_ofs,
                $obj->get_hdr_key_flags_ofs,
                $obj->get_hdr_val_flags_ofs,
                $obj->get_hdr_str_buf_ofs,
            );
            my @srt_ofs= sort{ $a <=> $b } @ofs;
            is("@ofs","@srt_ofs","offsets in the right order");

            my (@got_keys,@got_fetch_values,@want_keys);
            {
                my @bad;
                foreach my $key (sort keys %$source_hash) {
                    push @want_keys, $key;
                    my $got= $tied_hash{$key};
                    my $want= $source_hash->{$key};
                    if (defined($got) != defined($want) or (defined($got) and $got ne $want)) {
                        push @bad, [$key,$got,$want];
                    }
                }
                is(0+@bad,0,"no bad values via source_hash ($title)")
                    or diag Dumper($bad[0]);
            }
            {
                my @bad;
                foreach my $key (sort keys %tied_hash) {
                    push @got_keys, $key;
                    my $got= $tied_hash{$key};
                    my $want= $source_hash->{$key};
                    if (defined($got) != defined($want) or (defined($got) and $got ne $want)) {
                        push @bad, [$key,$got,$want];
                    }
                    push @got_fetch_values, $got;
                }
                is(0+@bad,0,"no bad values via tied_hash ($title)")
                    or diag Dumper($bad[0]);
            }
            my @got_values= sort values %tied_hash;
            my @want_values= sort values %$source_hash;

            my @got_each_keys;
            my @got_each_values;
            while (my($k,$v)= each(%tied_hash)) {
                push @got_each_keys, $k;
                push @got_each_values, $v;
            }
            @got_fetch_values= sort @got_fetch_values;
            @got_each_keys= sort @got_each_keys;
            @got_each_values= sort @got_each_values;

            is_deeply(\@got_keys,\@want_keys,"keys in both are the same ($title)");
            is_deeply(\@got_each_keys,\@want_keys,"got_keys and got_each_keys agree ($title)");

            is_deeply(\@got_values,\@want_values,"got_values and got_each_values agree ($title)");
            is_deeply(\@got_fetch_values,\@want_values,"values in both are same ($title)");
            is_deeply(\@got_each_values,\@want_values,"values in both are same ($title)");

            {
                my @bad;
                foreach my $idx (0..$#got_keys) {
                    if (utf8::is_utf8($got_keys[$idx]) != utf8::is_utf8($want_keys[$idx])) {
                        push @bad, [ $got_keys[$idx], $want_keys[$idx] ];
                    }
                }
                is(0+@bad,0,"no keys with differing utf8 flags ($title)")
                    or diag Dumper($bad[0]);
            }


        }
    }
}





