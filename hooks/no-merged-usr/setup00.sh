#!/bin/sh
#
# mmdebstrap does have a --no-merged-usr option but only as a no-op for
# debootstrap compatibility
#
# Using this hook script, you can emulate what debootstrap does to set up
# a system without merged-/usr even after the essential init-system-helpers
# package added a dependency on "usrmerge | usr-is-merged". By installing
# a dummy usr-is-merged package, it avoids pulling in the dependencies of
# the usrmerge package.

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
        set -x
fi

TARGET="$1"

echo "Warning: starting with Debian 12 (Bookworm), systems without merged-/usr are not supported anymore" >&2
echo "Warning: starting with Debian 13 (Trixie), merged-/usr symlinks are shipped by packages in the essential-set making this hook ineffective" >&2

echo "this system will not be supported in the future" > "$TARGET/etc/unsupported-skip-usrmerge-conversion"

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
Description: dummy package created by mmdebstrap no-merged-usr setup hook
 This package was generated and installed by the mmdebstrap no-merged-usr
 setup hook at /usr/share/mmdebstrap/hooks/no-merged-usr.
 .
 If this package is installed in the final chroot, then this is a bug
 in mmdebstrap. Please report: https://gitlab.mister-muffin.de/josch/mmdebstrap
END
dpkg-deb --build "$tmpdir/usr-is-merged" "$tmpdir/usr-is-merged.deb"
dpkg --root="$TARGET" --log="$TARGET/var/log/dpkg.log" --install "$tmpdir/usr-is-merged.deb"
rm "$tmpdir/usr-is-merged.deb" "$tmpdir/usr-is-merged/DEBIAN/control"
rmdir "$tmpdir/usr-is-merged/DEBIAN" "$tmpdir/usr-is-merged" "$tmpdir"
