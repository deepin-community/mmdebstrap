#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

TARGET="$1"

# not needed since dpkg 1.17.11
for f in available diversions cmethopt; do
	if [ ! -e "$TARGET/var/lib/dpkg/$f" ]; then
		touch "$TARGET/var/lib/dpkg/$f"
	fi
done
