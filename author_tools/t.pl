use strict;
use warnings;
use blib;
use Tie::Hash::MinPerfHashTwoLevel::OnDisk qw(mph2l_make_file);
use Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk;
use Sereal qw(read_sereal_file);
use Data::Dumper;
use Time::HiRes qw(time);

my $hash_x= {
    "a/1/A" => 0,
    "a/1/B" => 1,

    "a/2/C" => 2,
    "a/2/D" => 3,
    
    "b/3/E" => 4,
    "b/3/F" => 5,
    
    "b/4/G" => 6,
    "b/4/H" => 7,
    
    "c/5/I" => 8,
    "c/5/J" => 9,
    
    "c/6/K" => 10,
    "c/6/L" => 11,
};
if (!-e "test.file") {
    my $read_time= 0 - time();
    read_sereal_file("../uni_prop_parser/1.tr.0a0cad65cc42f6ceafc0a7266c1f113e",{},my $hash);
    my  @keys= sort keys %$hash;
    #$hash->{$keys[$_]}= $keys[$_] for 0..$#keys;
    warn "num keys: ", 0+@keys,"\n";
    $read_time += time();
    printf "read took %.0fms\n", $read_time;
    my $make_time= 0 - time();
    mph2l_make_file("test.file", variant => 6, source_hash => $hash);
    $make_time += time();
    printf "make file took %.0fms\n", $make_time * 1000;
}
my $tie_time= 0 - time();
tie my %hash, "Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk", file => "test.file";
$tie_time += time();
printf "tie took %.0fms\n", $tie_time * 1000;
my $loop_time= 0 - time();
use constant SHOWIT => 0;
foreach my $k1 (keys %hash) {
    my $hash2= $hash{$k1};
    SHOWIT and warn $k1,"\n";
    foreach my $k2 (keys %$hash2) {
        my $hash3= $hash2->{$k2};
        SHOWIT and warn join("\t",$k1,$k2),"\n";
        foreach my $k3 (keys %$hash3) {
            SHOWIT and warn join("\t",$k1,$k2,$k3),"\n";
            my $got= $hash3->{$k3};
        }
    }
}
$loop_time += time();
printf "loop took %.0fms\n", $loop_time * 1000;
$Data::Dumper::Useqq=1;
print Dumper(\%hash);

