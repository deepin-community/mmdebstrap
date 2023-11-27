#!/bin/sh
#
# mmdebstrap does have a --merged-usr option but only as a no-op for
# debootstrap compatibility
#
# Using this hook script, you can emulate what debootstrap does to set up
# merged /usr via directory symlinks, even using the exact same shell function
# that debootstrap uses by running mmdebstrap with:
#
#     --setup-hook=/usr/share/mmdebstrap/hooks/merged-usr/setup00.sh
#
# Alternatively, you can setup merged-/usr by installing the usrmerge package:
#
#     --include=usrmerge
#
# mmdebstrap will not include this functionality via a --merged-usr option
# because there are many reasons against implementing merged-/usr that way:
#
# https://wiki.debian.org/Teams/Dpkg/MergedUsr
# https://wiki.debian.org/Teams/Dpkg/FAQ#Q:_Does_dpkg_support_merged-.2Fusr-via-aliased-dirs.3F
# https://lists.debian.org/20190219044924.GB21901@gaara.hadrons.org
# https://lists.debian.org/YAkLOMIocggdprSQ@thunder.hadrons.org
# https://lists.debian.org/20181223030614.GA8788@gaara.hadrons.org
#
# In addition, the merged-/usr-via-aliased-dirs approach violates an important
# principle of component based software engineering one of the core design
# ideas/goals of mmdebstrap: All the information to create a chroot of a Debian
# based distribution should be included in its packages and their metadata.
# Using directory symlinks as used by debootstrap contradicts this principle.
# The information whether a distribution uses this approach to merged-/usr or
# not is not anymore contained in its packages but in a tool from the outside.
#
# Example real world problem: I'm using debbisect to bisect Debian unstable
# between 2015 and today. For which snapshot.d.o timestamp should a merged-/usr
# chroot be created and for which ones not?
#
# The problem is not the idea of merged-/usr but the problem is the way how it
# got implemented in debootstrap via directory symlinks. That way of rolling
# out merged-/usr is bad from the dpkg point-of-view and completely opposite of
# the vision with which in mind I wrote mmdebstrap.

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

TARGET="$1"

# now install an empty "usr-is-merged" package to avoid installing the
# usrmerge package on this system even after init-system-helpers starts
# depending on "usrmerge | usr-is-merged".
#
# This package will not end up in the final chroot because the essential
# hook replaces it with the actual usr-is-merged package from src:usrmerge.

tmpdir=$(mktemp --directory --tmpdir="$TARGET/tmp")
mkdir -p "$tmpdir/usr-is-merged/DEBIAN"

cat << END > "$tmpdir/usr-is-merged/DEBIAN/control"
Package: usr-is-merged
Priority: optional
Section: oldlibs
Maintainer: Johannes Schauer Marin Rodrigues <josch@debian.org>
Architecture: all
Multi-Arch: foreign
Source: mmdebstrap-dummy-usr-is-merged
Version: 1
Description: dummy package created by mmdebstrap merged-usr setup hook
 This package was generated and installed by the mmdebstrap merged-usr
 setup hook at /usr/share/mmdebstrap/hooks/merged-usr.
 .
 If this package is installed in the final chroot, then this is a bug
 in mmdebstrap. Please report: https://gitlab.mister-muffin.de/josch/mmdebstrap
END
dpkg-deb --build "$tmpdir/usr-is-merged" "$tmpdir/usr-is-merged.deb"
dpkg --root="$TARGET" --log="$TARGET/var/log/dpkg.log" --install "$tmpdir/usr-is-merged.deb"
rm "$tmpdir/usr-is-merged.deb" "$tmpdir/usr-is-merged/DEBIAN/control"
rmdir "$tmpdir/usr-is-merged/DEBIAN" "$tmpdir/usr-is-merged" "$tmpdir"
