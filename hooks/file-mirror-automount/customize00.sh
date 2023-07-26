#!/bin/sh
#
# shellcheck disable=SC2086

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

rootdir="$1"

if [ ! -e "$rootdir/run/mmdebstrap/file-mirror-automount" ]; then
	exit 0
fi

xargsopts="--null --no-run-if-empty -I {} --max-args=1"

case $MMDEBSTRAP_MODE in
	root|unshare)
		echo "unmounting the following mountpoints:" >&2 ;;
	*)
		echo "removing the following directories:" >&2 ;;
esac

< "$rootdir/run/mmdebstrap/file-mirror-automount" \
	xargs $xargsopts echo "    $rootdir/{}"

case $MMDEBSTRAP_MODE in
	root|unshare)
		< "$rootdir/run/mmdebstrap/file-mirror-automount" \
			xargs $xargsopts umount "$rootdir/{}"
		;;
	*)
		< "$rootdir/run/mmdebstrap/file-mirror-automount" \
			xargs $xargsopts rm -r "$rootdir/{}"
		;;
esac

rm "$rootdir/run/mmdebstrap/file-mirror-automount"
rmdir --ignore-fail-on-non-empty "$rootdir/run/mmdebstrap"
