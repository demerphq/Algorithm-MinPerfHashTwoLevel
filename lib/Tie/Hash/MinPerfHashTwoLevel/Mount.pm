package Tie::Hash::MinPerfHashTwoLevel::Mount;
use strict;
use warnings;
use constant {
       MPH_F_VALIDATE          =>  (1<<3),
};
use Exporter qw(import);
our @EXPORT_OK=('MPH_F_VALIDATE');

sub new {
    my ($class, $opts)= @_;

    $opts->{flags} ||= 0;
    $opts->{flags} |= MPH_F_VALIDATE if $opts->{validate};
    my $error;
    my $mount= mount_file($opts->{file},$error,$opts->{flags});
    my $error_rsv= delete $opts->{error_rsv};
    if ($error_rsv) {
        $$error_rsv= $error;
    }
    if (!defined($mount)) {
        if ($error_rsv) {
            return;
        } else {
            die "Failed to mount file '$opts->{file}': $error";
        }
    }
    return bless [ $mount,$opts->{separator} ], $class;
}

sub DESTROY {
    my ($self)= @_;
    unmount_file($self->[0]) if defined $self->[0];
    undef $self->[0];
}

1;

