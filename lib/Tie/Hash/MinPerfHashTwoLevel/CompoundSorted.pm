package Tie::Hash::MinPerfHashTwoLevel::CompoundSorted;

use strict;
use warnings;

sub TIEHASH {
    my ($class, %opts)= @_;
    
    if (!defined $opts{levels}) {
        $opts{levels}= 3;
        $opts{level}= 1;
    }
    $opts{ties} ||= [ map tied(%$_), @{$opts{tied_hashes}} ];
    my $self= bless \%opts, $class;
}

sub FETCH {
    my ($self, $key)= @_;

    if ((my $level= $self->{level}) < (my $levels= $self->{levels})) {
        my $cached= $self->{cache}{$key} //= do{ 
            my $ret;
            my @got= map { $_->{$key} // () } @{$self->{tied_hashes}};
            if (@got) {
                my %sub_hash;
                tie %sub_hash, ref($self), 
                    tied_hashes=> \@got, 
                    levels => $levels, 
                    level => $level + 1;
                $ret= \%sub_hash;
            }
            \$ret;
        };
        return $$cached;
    }
    for my $tied (@{$self->{tied_hashes}}) {
        my $got= $tied->{$key};
        return $got if defined $got or exists($tied->{$key});
    }
    return undef;
}

sub EXISTS {
    my ($self, $key)= @_;

    $_->EXISTS($key) and return 1 
        for @{$self->{ties}};
    return 0;
}

sub FIRSTKEY {
    my ($self)= @_;
    my @iter= map { $_->FIRSTKEY() } @{$self->{ties}};
    $self->{iter}= \@iter;
    return $self->NEXTKEY();
}


sub NEXTKEY {
    my ($self, $last_key)= @_;

    my $iter= $self->{iter}
        or Carp::confess( "FIRSTKEY not called yet?");
    my $min;
    for my $key (@$iter) {
        $min= $key if defined $key and (!defined $min or $min gt $key);
    }
    if (defined $min) {
        my $ties= $self->{ties};
        for my $idx ( 0 .. $#$iter ) {
            my $key= $iter->[$idx];
            next unless defined $key and $key eq $min;
            $iter->[$idx]= $ties->[$idx]->NEXTKEY($min);
        }
    }
    return $min;
}


sub DELETE {
    my $class= ref $_[0];
    die "Cannot delete from a $class object";
}

sub STORE {
    my $class= ref $_[0];
    die "Cannot delete from a $class object";
}


1;


