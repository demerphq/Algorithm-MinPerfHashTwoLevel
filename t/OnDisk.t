#########################

use strict;
use warnings;

use Test::More tests => 37;
use File::Temp;
use Data::Dumper; $Data::Dumper::Sortkeys=1; $Data::Dumper::Useqq=1;
my $class;
BEGIN { use_ok($class= 'Tie::Hash::MinPerfHashTwoLevel::OnDisk') };
my $srand=$ENV{SRAND} ? srand(0+$ENV{SRAND}) : srand();
diag "srand=$srand";
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
    { 1..100000 },
    {
        $not_utf8 => $not_utf8,
        $utf8_can_be_downgraded => $utf8_can_be_downgraded,
        $must_be_utf8 => $must_be_utf8,
        #map { chr($_) => chr($_) } 250..260,
    },
);

foreach my $idx (0..$#source_hashes) {
    foreach my $seed ("1234567812345678",undef) {
        my $seed_str= defined $seed ? $seed : "undef";
        my $source_hash= $source_hashes[$idx];
        my $test_file= "$tmpdir/test.$idx.hash";
        my $got_file= $class->make_file(
            file        => $test_file,
            source_hash => $source_hash,
            comment     => "this is a comment",
            debug       => $ENV{TEST_VERBOSE},
            seed        => $seed,
        );

        is( $got_file,$test_file, "make_file returned as expected ($idx - $seed_str)" );
        my ($version,$message)= $class->validate_file(file=>$test_file);
        ok( defined $version, "file validates ok ($idx - $seed_str)")
            or diag $message;
        my %tied_hash;
        tie %tied_hash, $class, $test_file;
        my (@got_keys,@want_keys);
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
            is(0+@bad,0,"no bad values via source_hash (test hash $idx - $seed_str)")
                or diag Dumper(\@bad);
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
            }
            is(0+@bad,0,"no bad values via tied_hash (test_hash $idx - $seed_str)")
                or diag Dumper(\@bad);
        }
        is_deeply(\@got_keys,\@want_keys,"keys in both are the same (test_hash $idx - $seed_str)");
        {
            my @bad;
            foreach my $idx (0..$#got_keys) {
                if (utf8::is_utf8($got_keys[$idx]) != utf8::is_utf8($want_keys[$idx])) {
                    push @bad, [ $got_keys[$idx], $want_keys[$idx] ];
                }
            }
            is(0+@bad,0,"no keys with differing utf8 flags (test_hash $idx - $seed_str)");
        }
    }
}





