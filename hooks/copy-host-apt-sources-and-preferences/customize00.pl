#!/usr/bin/perl
#
# This script makes sure that all packages that are installed both locally as
# well as inside the chroot have the same version.
#
# It is implemented in Perl because there are no associative arrays in POSIX
# shell.

use strict;
use warnings;

sub get_pkgs {
    my $root = shift;
    my %pkgs = ();
    open(my $fh, '-|', 'dpkg-query', "--root=$root", '--showformat',
        '${binary:Package}=${Version}\n', '--show')
      // die "cannot exec dpkg-query";
    while (my $line = <$fh>) {
        my ($pkg, $ver) = split(/=/, $line, 2);
        $pkgs{$pkg} = $ver;
    }
    close $fh;
    if ($? != 0) { die "failed to run dpkg-query" }
    return %pkgs;
}

my %pkgs_local  = get_pkgs('/');
my %pkgs_chroot = get_pkgs($ARGV[0]);

my @diff = ();
foreach my $pkg (keys %pkgs_chroot) {
    next unless exists $pkgs_local{$pkg};
    if ($pkgs_local{$pkg} ne $pkgs_chroot{$pkg}) {
        push @diff, $pkg;
    }
}

if (scalar @diff > 0) {
    print STDERR "E: packages from the host and the chroot differ:\n";
    foreach my $pkg (@diff) {
	print STDERR "E: $pkg $pkgs_local{$pkg} $pkgs_chroot{$pkg}\n";
    }
    exit 1;
}
