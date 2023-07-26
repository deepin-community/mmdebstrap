#!/bin/sh

set -eu

# we need to check the version of dpkg
# since at this point packages are just extracted but not installed, we cannot use dpkg-query
# since we want to support chrootless, we cannot run dpkg --version inside the chroot
# to avoid this hook depending on dpkg-dev being installed, we do not parse the extracted changelog with dpkg-parsechangelog
# we also want to avoid parsing the changelog because /usr/share/doc might've been added to dpkg --path-exclude
# instead, we just ask apt about the latest version of dpkg it knows of
# this should only fail in situations where there are multiple versions of dpkg in different suites
ver=$(env --chdir="$1" APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-cache show --no-all-versions dpkg 2>/dev/null | sed -ne 's/^Version: \(.*\)$/\1/p' || printf '')
if [ -z "$ver" ]; then
	echo "no package called dpkg can be installed -- not running jessie-or-older extract00 hook" >&2
	exit 0
fi

if dpkg --compare-versions "$ver" ge 1.17.11; then
	echo "dpkg version $ver is >= 1.17.11 -- not running jessie-or-older extract00 hook" >&2
	exit 0
else
	echo "dpkg version $ver is << 1.17.11 -- running jessie-or-older extract00 hook" >&2
fi

# resolve the script path using several methods in order:
#  1. using dirname -- "$0"
#  2. using ./hooks
#  3. using /usr/share/mmdebstrap/hooks/
for p in "$(dirname -- "$0")/.." ./hooks /usr/share/mmdebstrap/hooks; do
	if [ -x "$p/jessie-or-older/extract00.sh" ] && [ -x "$p/jessie-or-older/extract01.sh" ]; then
		"$p/jessie-or-older/extract00.sh" "$1"
		exit 0
	fi
done

echo "cannot find jessie-or-older hook anywhere" >&2
exit 1
