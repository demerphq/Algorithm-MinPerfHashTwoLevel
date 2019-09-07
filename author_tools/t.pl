use strict;
use warnings;
use blib;
use Tie::Hash::MinPerfHashTwoLevel::OnDisk qw(mph2l_make_file);
use Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk;
use Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk;
use Sereal;
use Data::Dumper;
use Time::HiRes qw(time);
use constant SHOWIT => 0;
use Benchmark qw(cmpthese);
use Array::RefElem qw(av_push);

$|++;select((select(STDERR),$|++)[0]);

sub walk_hash {
    my ($hash1, $cmp_hash) =@_;
    foreach my $k1 (keys %$hash1) {
        my $hash2= $hash1->{$k1};
        SHOWIT and warn $k1,"\n";
        foreach my $k2 (keys %$hash2) {
            my $hash3= $hash2->{$k2};
            SHOWIT and warn join("\t",$k1,$k2),"\n";
            foreach my $k3 (keys %$hash3) {
                SHOWIT and warn join("\t",$k1,$k2,$k3),"\n";
                my $got1= $hash3->{$k3};
                if ($cmp_hash) {
                    my $got2= $cmp_hash->{$k1}{$k2}{$k3};
                    if ( defined($got1)!=defined($got2) || (defined $got1 and $got1 ne $got2)) {
                        die "$k1/$k2/$k3 are different!\n",Dumper($got1,$got2);
                    }
                }
            }
        }
    }
}

$|++;
my %split_hash;
my %sep_hash;
my $read_time= 0 - time();
my $f= "../uni_prop_parser/1.tr.0a0cad65cc42f6ceafc0a7266c1f113e";
#$f= "../uni_prop_parser/1.tr.386e2d76e63a8b749c715b59ce43b8e5";
#$f= "../uni_prop_parser/1.tr.711eed460fa9a8a67daafa2deb9ed6fe";
my $hash;
$hash= {
        "a/aa/aaa"=>"aaaa",
        "aa/aaa/aaaa"=>"aaaaa",
        "aaa/aaaaa/aaaaaaa"=>"aaaaaaaaaaaaaaaaaaaa",
        "b/bb/bbb"=>"bbbb",
        "bb/bbbb/bbbbb"=>"bbbbbb",
        "bbb/bbbbbb/bbbbb"=>"bbbb",
} if 0;
Sereal::read_sereal_file($f,{},$hash) unless $hash;

my $sep= "/";


foreach my $key (sort keys %$hash) {
    my $val= $hash->{$key};
    #next if !defined $val or !length $val;

    my @parts= split "/", $key;
    my ($k1,$k2,$k3)= @parts;
    $k1//="";
    $k2//="";
    $k3//="";

    $sep_hash{join $sep, $k1,$k2,$k3}= $val;
    $split_hash{$k1}{$k2}{$k3}= $hash->{$key};
}

my ($class, $variant);
if (!@ARGV or !$ARGV[0]) {
    $class= "Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk";
    $variant= 7;
} else {
    $class= "Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk";
    $variant= 6;
}
my $fn=  "test.file.$variant.mph";

$read_time += time();
warn sprintf "read took %.0fms\n", $read_time;
foreach my $i (1..($ENV{LEAK_TEST_COUNT}||1)) {
    warn "-start------------------------------------------------------\n";
    m!perl author_tools/t.pl! and warn $_ for `ps auwx`;
    my $make_time= 0 - time();
    mph2l_make_file(
        $fn,
        variant         => $variant,
        source_hash     => \%sep_hash,
        separator       => $sep,
        compress_keys   => $ENV{COMPRESS_KEYS},
        compress_vals   => $ENV{COMPRESS_VALS},
        debug           => $ENV{DEBUG});
    $make_time += time();
    warn sprintf "make file took %.0fms\n", $make_time * 1000;
    m!perl author_tools/t.pl! and warn $_ for `ps auwx`;
    print "-end------------------------------------------------------\n";
}
exit if $ENV{LEAK_TEST_COUNT};
my $tie_time= 0 - time();
tie my %tied_hash, $class,
    file => $fn,
    #separator => "\0", #$sep,
    validate => 0;
$tie_time += time();
warn sprintf "tie took %.0fms\n", $tie_time * 1000;

tied(%tied_hash)->Dump();


warn "walking tied hash\n";
my $loop_time= 0 - time();
my $hash1= \%tied_hash;
walk_hash(\%tied_hash);
$loop_time += time();
warn sprintf "loop took %.0fms\n", $loop_time * 1000;
warn "walking split hash checking against tied hash\n";

walk_hash(\%split_hash,\%tied_hash);
warn "walking tied hash checking against split hash\n";
walk_hash(\%tied_hash,\%split_hash);
warn "Dumping tied hash\n";

$Data::Dumper::Useqq=1;
my $dump_took= 0 - time;
my $got1= Dumper(\%tied_hash);
$dump_took+=time;
warn "Dumper took $dump_took for tied data\n";

warn "Dumping split hash\n";
$Data::Dumper::Sortkeys= 1;
$dump_took= 0 - time;
my $got2= Dumper(\%split_hash);
$dump_took += time;
warn "Dumper took $dump_took for copied data\n";

if ($got1 ne $got2) {
    print "Dumper is different!\n";
} else {
    print "Dumper is ok! \\o/\n";
}

if (1 or $got1 ne $got2) {
    open my $fh1, ">", "tied.$variant.txt";
    print $fh1 $got1;
    close $fh1;
    open my $fh2, ">", "split.$variant.txt";
    print $fh2 $got2;
    close $fh2;
}

warn "$class\n";
warn sprintf "file size: %d bytes\n", -s $fn;
