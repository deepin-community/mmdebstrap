#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
        set -x
fi

TARGET="$1"

if [ "${MMDEBSTRAP_MODE:-}" = "chrootless" ]; then
	APT_CONFIG=$MMDEBSTRAP_APT_CONFIG apt-get --yes install \
		-oDPkg::Chroot-Directory= \
		-oDPkg::Options::=--force-not-root \
		-oDPkg::Options::=--force-script-chrootless \
		-oDPkg::Options::=--root="$TARGET" \
		-oDPkg::Options::=--log="$TARGET/var/log/dpkg.log" \
		usr-is-merged
	export DPKG_ROOT="$TARGET"
	dpkg-query --showformat '${db:Status-Status}\n' --show usr-is-merged | grep -q '^installed$'
	dpkg-query --showformat '${Source}\n' --show usr-is-merged | grep -q '^usrmerge$'
	dpkg --compare-versions "1" "lt" "$(dpkg-query --showformat '${Version}\n' --show usr-is-merged)"
else
	APT_CONFIG=$MMDEBSTRAP_APT_CONFIG apt-get --yes install usr-is-merged
	chroot "$TARGET" dpkg-query --showformat '${db:Status-Status}\n' --show usr-is-merged | grep -q '^installed$'
	chroot "$TARGET" dpkg-query --showformat '${Source}\n' --show usr-is-merged | grep -q '^usrmerge$'
	dpkg --compare-versions "1" "lt" "$(chroot "$TARGET" dpkg-query --showformat '${Version}\n' --show usr-is-merged)"
fi
