use strict;
use warnings;
use Test::More;
use Tie::Hash::MinPerfHashTwoLevel::OnDisk qw(mph2l_make_file);
use Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk;
use Tie::Hash::MinPerfHashTwoLevel::CompoundSorted;
use File::Temp;
use Data::Dumper;

our $SEP= "\t";
my $VAL= 1;
my %IDS;

sub new_id {
    my $id;
    do {
        $id = join "",map { chr(65+int(rand(26))) } 1 .. int(3+rand(6));
    } while $IDS{$id}++;
    return $id;
}

sub new_val {
    return $VAL++;
}

sub generate_fixed {
    my ($rules,$flat_hash,$nested_hash,$level,@path)= @_;
    $nested_hash||={};
    $flat_hash||={};
    $level||=0;
    if ($rules ? $level >= @$rules : ($level && ($level >= 5 || rand(1) < 0.50))  ) {
        my $path_key= join $SEP, @path;
        $_[2]= new_val();
        $flat_hash->{$path_key}= $_[2];
    } else {
        my ($min,$max)= @{$rules ? $rules->[$level] : [ 1, 4 ]};
        my $num= $min + int(rand($max-$min));
        for my $i (1 .. $num) {
            my $new= new_id();
            generate_fixed($rules,$flat_hash,$nested_hash->{$new}||={},$level+1,@path,$new);
        }
    }
    return($flat_hash,$nested_hash);
}

sub flatten_hash {
    my ($nested_hash, $separator, $flat_hash, @path)= @_;
    $flat_hash //= {};
    $separator //= $SEP;
    foreach my $key (keys %$nested_hash) {
        my $val= $nested_hash->{$key};
        if (ref $val) {
            flatten_hash($val, $separator, $flat_hash, @path, $key);
        } else {
            $flat_hash->{join $separator, @path, $key}= $val;
        }
    }
    return $flat_hash;
}

sub expand_hash {
    my ($flat_hash, $separator)= @_;
    $separator //= $SEP;
    my %nested_hash;
    foreach my $key (keys %$flat_hash) {
        my @inner= split /\Q$separator\E/, $key;
        my $leaf= pop @inner;
        my $hash= \%nested_hash;
        $hash= $hash->{$_}||={} for @inner;
        $hash->{$leaf}= $flat_hash->{$key};
    }
    return \%nested_hash;
}

sub merge_flat {
    my @flat= @_;
    my %flat;
    foreach my $h (@flat) {
        foreach my $k (keys %$h) {
            $flat{$k} //= $h->{$k};
        }
    }
    return \%flat;
}

sub merge_nested {
    return expand_hash(merge_flat(map { flatten_hash($_) } @_));
}

$Data::Dumper::Useqq=1;
$Data::Dumper::Sortkeys=1;

my $tmpdir= File::Temp->newdir();
my $this_comment= "this is a test";
for my $test_nr (1..1000) {
    my ($want_flat1, $want_nested1)= generate_fixed([[3,3],[1,5],[1,5]]);
    my ($want_flat2, $want_nested2)= generate_fixed([[3,3],[1,5],[1,5]]);
    my $want_flat= merge_flat($want_flat1,$want_flat2);
    my $want_nested= expand_hash($want_flat);
    my $test_file= "$tmpdir/ml.mph.$test_nr";

    mph2l_make_file(
        "$test_file.a",
        source_hash => $want_flat,
        comment     => $this_comment . ": a",
        debug       => ($ENV{TEST_VERBOSE}||0)>1,
        variant     => 7,
        canonical   => 1,
        separator   => $SEP,
    );
    mph2l_make_file(
        "$test_file.b",
        source_hash => $want_flat2,
        comment     => $this_comment . " : b",
        debug       => ($ENV{TEST_VERBOSE}||0)>1,
        variant     => 7,
        canonical   => 1,
        separator   => $SEP,
    );

    tie my %tied_hash_a, 'Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk', file=>"$test_file.a", separator => $SEP;
    tie my %tied_hash_b, 'Tie::Hash::MinPerfHashTwoLevel::ThreeLevelOnDisk', file=>"$test_file.b", separator => $SEP;
    tie my %tied_hash,   'Tie::Hash::MinPerfHashTwoLevel::CompoundSorted',   tied_hashes=>[ \%tied_hash_a, \%tied_hash_b ];

    #print Dumper(\%tied_hash);
    my $got_nested= \%tied_hash;
    is_deeply($got_nested, $want_nested, "nested test $test_nr");
    my $got_flat= flatten_hash($got_nested);
    is_deeply($got_flat,   $want_flat, "flattened test $test_nr");
    my $not_present= new_id();
    ok(!exists $tied_hash{$not_present},"not exists as expected");
    my ($top_key)= grep { ref $tied_hash{$_} } keys(%tied_hash);
    if (defined $top_key) {
        ok(!exists $tied_hash{$top_key}{$not_present}, "second level not exists as expected");
    }
    if (0) {
        my $tied= tied(%tied_hash);
        foreach my $key (keys %$want_flat) {
            my $exists= $tied->exists_composite($key);
            my $value= $tied->fetch_composite($key);
            is($exists, 1, "exists_composite key '$key'");
            is($value, $want_flat->{$key},"fetch_composite key '$key'");
        }
    }
}
done_testing();
