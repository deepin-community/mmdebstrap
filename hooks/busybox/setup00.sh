#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

rootdir="$1"

mkdir -p "$rootdir/bin"
echo root:x:0:0:root:/root:/bin/sh > "$rootdir/etc/passwd"
cat << END > "$rootdir/etc/group"
root:x:0:
mail:x:8:
utmp:x:43:
END
