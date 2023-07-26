#!/bin/sh
#
# needed until init 1.33 which pre-depends on systemd-sysv
# starting with init 1.34, init is not Essential:yes anymore
#
# jessie has init 1.22

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

TARGET="$1"

if [ -z "${MMDEBSTRAP_ESSENTIAL+x}" ]; then
	MMDEBSTRAP_ESSENTIAL=
	for f in "$TARGET/var/cache/apt/archives/"*.deb; do
		[ -f "$f" ] || continue
		f="${f#"$TARGET"}"
		MMDEBSTRAP_ESSENTIAL="$MMDEBSTRAP_ESSENTIAL $f"
	done
fi

fname_base_passwd=
fname_base_files=
fname_dpkg=
for pkg in $MMDEBSTRAP_ESSENTIAL; do
	pkgname=$(dpkg-deb --show --showformat='${Package}' "$TARGET/$pkg")
	# shellcheck disable=SC2034
	case $pkgname in
		base-passwd) fname_base_passwd=$pkg;;
		base-files)  fname_base_files=$pkg;;
		dpkg)        fname_dpkg=$pkg;;
	esac
done

for var in base_passwd base_files dpkg; do
	eval 'val=$fname_'"$var"
	[ -z "$val" ] && continue
	chroot "$TARGET" dpkg --install --force-depends "$val"
done

# shellcheck disable=SC2086
chroot "$TARGET" dpkg --unpack --force-depends $MMDEBSTRAP_ESSENTIAL

chroot "$TARGET" dpkg --configure --pending
