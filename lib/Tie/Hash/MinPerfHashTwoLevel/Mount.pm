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

    my $self= bless [ $mount,$opts->{separator} ], $class;
    if (Tie::Hash::MinPerfHashTwoLevel::OnDisk::get_hdr_variant($self) == 7) {
        my $hdr_sep= Tie::Hash::MinPerfHashTwoLevel::OnDisk::get_hdr_separator($self);
        if (defined $self->[1]) {
            if ($hdr_sep ne $self->[1]) {
                $error= sprintf "ThreeLevel (variant 7) file has a separator of %d %s but you passed in %d %s to the constructor",
                    ord($hdr_sep), Data::Dumper::qquote($hdr_sep), ord($self->[1]), Data::Dumper::qquote($self->[1]);
                if ($error_rsv) {
                    $$error_rsv = $error;
                }
                if ($error_rsv) {
                    return;
                } else {
                    die $error;
                }
            }
        } else {
            $self->[1]= $hdr_sep;
        }
    }
    return $self;
}

sub DESTROY {
    my ($self)= @_;
    unmount_file($self->[0]) if defined $self->[0];
    undef $self->[0];
}

1;

