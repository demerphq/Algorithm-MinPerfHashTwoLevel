#########################

use strict;
use warnings;

use Test::More tests => 7;
use Data::Dumper; $Data::Dumper::Sortkeys=1; $Data::Dumper::Useqq=1;
BEGIN { use_ok('Algorithm::MinPerfHashTwoLevel') };
use Algorithm::MinPerfHashTwoLevel qw(hash_with_state);

#########################

my $class= "Algorithm::MinPerfHashTwoLevel";

my $o= $class->new("seed"=>"1234567812345678",debug=>$ENV{TEST_VERBOSE},variant=>2);
my $state= $o->get_state;
my $state_as_hex= unpack "h*",$o->get_state;
is($state_as_hex,"cd355d25eec7d5d07bd270f4c86408b5b1f3e9df0fa48f95b964ec012fcddc25","state for seed is as expected");
for my $tuple (
    [ "fnorble",         3242199781855749366 ],
    [ "blah blah blah", 17023070590730889115 ],
    [ "blah blaH blah",  1182042005437744194 ],
) {
    my ($str,$want_hash)= @$tuple;
    my $got_hash= hash_with_state($str,$state);
    is($got_hash,$want_hash,"test hash function '$str'");
}

my %hash= ( "A" .. "Z" );
my $buckets= $o->compute(\%hash);
is_deeply($buckets,
    [
          {
            "h0" => "14220494359272133508",
            "h1_keys" => 1,
            "idx" => 0,
            "key" => "A",
            "key_is_utf8" => 0,
            "key_normalized" => "A",
            "val" => "B",
            "val_is_utf8" => 0,
            "val_normalized" => "B",
            "xor_val" => "4294967295"
          },
          {
            "h0" => "6134220344403434757",
            "h1_keys" => 1,
            "idx" => 1,
            "key" => "E",
            "key_is_utf8" => 0,
            "key_normalized" => "E",
            "val" => "F",
            "val_is_utf8" => 0,
            "val_normalized" => "F",
            "xor_val" => "4294967294"
          },
          {
            "h0" => "7054161505236885200",
            "idx" => 2,
            "key" => "U",
            "key_is_utf8" => 0,
            "key_normalized" => "U",
            "val" => "V",
            "val_is_utf8" => 0,
            "val_normalized" => "V"
          },
          {
            "h0" => "10070244595138406401",
            "h1_keys" => 1,
            "idx" => 3,
            "key" => "C",
            "key_is_utf8" => 0,
            "key_normalized" => "C",
            "val" => "D",
            "val_is_utf8" => 0,
            "val_normalized" => "D",
            "xor_val" => "4294967292"
          },
          {
            "h0" => "6274085422708518726",
            "h1_keys" => 2,
            "idx" => 4,
            "key" => "M",
            "key_is_utf8" => 0,
            "key_normalized" => "M",
            "val" => "N",
            "val_is_utf8" => 0,
            "val_normalized" => "N",
            "xor_val" => 1
          },
          {
            "h0" => "7220512076302328122",
            "idx" => 5,
            "key" => "K",
            "key_is_utf8" => 0,
            "key_normalized" => "K",
            "val" => "L",
            "val_is_utf8" => 0,
            "val_normalized" => "L"
          },
          {
            "h0" => "12281279328183299353",
            "h1_keys" => 1,
            "idx" => 6,
            "key" => "S",
            "key_is_utf8" => 0,
            "key_normalized" => "S",
            "val" => "T",
            "val_is_utf8" => 0,
            "val_normalized" => "T",
            "xor_val" => "4294967287"
          },
          {
            "h0" => "568222511572321279",
            "h1_keys" => 2,
            "idx" => 7,
            "key" => "W",
            "key_is_utf8" => 0,
            "key_normalized" => "W",
            "val" => "X",
            "val_is_utf8" => 0,
            "val_normalized" => "X",
            "xor_val" => 1
          },
          {
            "h0" => "4525548096675545430",
            "h1_keys" => 1,
            "idx" => 8,
            "key" => "Y",
            "key_is_utf8" => 0,
            "key_normalized" => "Y",
            "val" => "Z",
            "val_is_utf8" => 0,
            "val_normalized" => "Z",
            "xor_val" => "4294967286"
          },
          {
            "h0" => "9667849023746033757",
            "idx" => 9,
            "key" => "O",
            "key_is_utf8" => 0,
            "key_normalized" => "O",
            "val" => "P",
            "val_is_utf8" => 0,
            "val_normalized" => "P"
          },
          {
            "h0" => "13317221412674468734",
            "h1_keys" => 3,
            "idx" => 10,
            "key" => "Q",
            "key_is_utf8" => 0,
            "key_normalized" => "Q",
            "val" => "R",
            "val_is_utf8" => 0,
            "val_normalized" => "R",
            "xor_val" => 2
          },
          {
            "h0" => "10066629031135686754",
            "h1_keys" => 1,
            "idx" => 11,
            "key" => "I",
            "key_is_utf8" => 0,
            "key_normalized" => "I",
            "val" => "J",
            "val_is_utf8" => 0,
            "val_normalized" => "J",
            "xor_val" => "4294967285"
          },
          {
            "h0" => "17050369258129167017",
            "idx" => 12,
            "key" => "G",
            "key_is_utf8" => 0,
            "key_normalized" => "G",
            "val" => "H",
            "val_is_utf8" => 0,
            "val_normalized" => "H"
          }
    ],
    "buckets for A..Z as expected"
)
or print STDERR Data::Dumper::Dumper($buckets);

%hash=map {
    my $key= chr($_);
    utf8::upgrade($key) if $_ % 2;
    $key => $key
} 250 .. 260;
$buckets= $o->compute(\%hash);
is_deeply($buckets,
   [
          {
            "h0" => "2093962125127624002",
            "h1_keys" => 2,
            "idx" => 0,
            "key" => "\x{104}",
            "key_is_utf8" => 1,
            "key_normalized" => "\304\204",
            "val" => "\x{104}",
            "val_is_utf8" => 1,
            "val_normalized" => "\304\204",
            "xor_val" => 1
          },
          {
            "h0" => "17633874296866635714",
            "h1_keys" => 2,
            "idx" => 1,
            "key" => "\x{fd}",
            "key_is_utf8" => 2,
            "key_normalized" => "\375",
            "val" => "\x{fd}",
            "val_is_utf8" => 1,
            "val_normalized" => "\303\275",
            "xor_val" => 4
          },
          {
            "h0" => "8976088656043865606",
            "idx" => 2,
            "key" => "\374",
            "key_is_utf8" => 0,
            "key_normalized" => "\374",
            "val" => "\374",
            "val_is_utf8" => 0,
            "val_normalized" => "\374"
          },
          {
            "h0" => "1917046986199830365",
            "h1_keys" => 1,
            "idx" => 3,
            "key" => "\x{102}",
            "key_is_utf8" => 1,
            "key_normalized" => "\304\202",
            "val" => "\x{102}",
            "val_is_utf8" => 1,
            "val_normalized" => "\304\202",
            "xor_val" => "4294967295"
          },
          {
            "h0" => "14197268317010522524",
            "idx" => 4,
            "key" => "\x{101}",
            "key_is_utf8" => 1,
            "key_normalized" => "\304\201",
            "val" => "\x{101}",
            "val_is_utf8" => 1,
            "val_normalized" => "\304\201"
          },
          {
            "h0" => "8734182635755455095",
            "h1_keys" => 1,
            "idx" => 5,
            "key" => "\x{100}",
            "key_is_utf8" => 1,
            "key_normalized" => "\304\200",
            "val" => "\x{100}",
            "val_is_utf8" => 1,
            "val_normalized" => "\304\200",
            "xor_val" => "4294967294"
          },
          {
            "h0" => "15427906322422739763",
            "h1_keys" => 1,
            "idx" => 6,
            "key" => "\376",
            "key_is_utf8" => 0,
            "key_normalized" => "\376",
            "val" => "\376",
            "val_is_utf8" => 0,
            "val_normalized" => "\376",
            "xor_val" => "4294967291"
          },
          {
            "h0" => "17713559403787135240",
            "idx" => 7,
            "key" => "\x{103}",
            "key_is_utf8" => 1,
            "key_normalized" => "\304\203",
            "val" => "\x{103}",
            "val_is_utf8" => 1,
            "val_normalized" => "\304\203"
          },
          {
            "h0" => "4582360795303372070",
            "h1_keys" => 3,
            "idx" => 8,
            "key" => "\x{ff}",
            "key_is_utf8" => 2,
            "key_normalized" => "\377",
            "val" => "\x{ff}",
            "val_is_utf8" => 1,
            "val_normalized" => "\303\277",
            "xor_val" => 1
          },
          {
            "h0" => "655810272549308067",
            "h1_keys" => 1,
            "idx" => 9,
            "key" => "\372",
            "key_is_utf8" => 0,
            "key_normalized" => "\372",
            "val" => "\372",
            "val_is_utf8" => 0,
            "val_normalized" => "\372",
            "xor_val" => "4294967285"
          },
          {
            "h0" => "11104071258332792732",
            "idx" => 10,
            "key" => "\x{fb}",
            "key_is_utf8" => 2,
            "key_normalized" => "\373",
            "val" => "\x{fb}",
            "val_is_utf8" => 1,
            "val_normalized" => "\303\273"
          }
        ], 
    "hash with utf8 works as expected"
)
or print STDERR Data::Dumper::Dumper($buckets);

