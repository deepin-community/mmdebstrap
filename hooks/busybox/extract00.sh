#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

rootdir="$1"

# Run busybox using an absolute path so that this script also works in case
# /proc is not mounted. Busybox uses /proc/self/exe to figure out the path
# to its executable.
chroot "$rootdir" /bin/busybox --install -s
