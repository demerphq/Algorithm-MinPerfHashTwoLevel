use strict;
use warnings;
use Test::More;
use Tie::Hash::MinPerfHashTwoLevel::OnDisk qw(mph2l_make_file);
use Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk;
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

$Data::Dumper::Useqq=1;
$Data::Dumper::Sortkeys=1;

my $tmpdir= File::Temp->newdir();
my $test_file= "$tmpdir/ml.mph.0";
my $this_comment= "this is a test";
for my $test_nr (1..1000) {
    my ($want_flat, $want_nested)= generate_fixed($test_nr % 2 ? [[3,3],[1,5],[1,5]] : ());

    mph2l_make_file(
        $test_file,
        source_hash => $want_flat,
        comment     => $this_comment,
        debug       => ($ENV{TEST_VERBOSE}||0)>1,
        variant     => 6,
        canonical   => 1,
    );

    tie my %tied_hash, 'Tie::Hash::MinPerfHashTwoLevel::MultiLevelOnDisk', file=>$test_file, separator => $SEP;
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
}
done_testing();
