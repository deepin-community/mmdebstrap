#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

rootdir="$1"

if [ -e "$rootdir/var/lib/dpkg/arch" ]; then
	chrootarch=$(head -1 "$rootdir/var/lib/dpkg/arch")
else
	chrootarch=$(dpkg --print-architecture)
fi
libdir="/usr/lib/$(dpkg-architecture -a "$chrootarch" -q DEB_HOST_MULTIARCH)"

# if eatmydata was actually installed properly, then we are not removing
# anything here
if ! chroot "$rootdir" dpkg-query --show eatmydata; then
	rm "$rootdir/usr/bin/eatmydata"
fi
if ! chroot "$rootdir" dpkg-query --show libeatmydata1; then
	rm "$rootdir$libdir"/libeatmydata.so*
fi

rm "$rootdir/usr/bin/dpkg"
chroot "$rootdir" dpkg-divert --local --rename --remove /usr/bin/dpkg

sync
