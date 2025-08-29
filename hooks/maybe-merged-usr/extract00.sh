#!/bin/sh

set -eu

env --chdir="$1" APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-get update --error-on=any

if env --chdir="$1" APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-cache show --no-all-versions usr-is-merged > /dev/null 2>&1; then
	# if apt-cache exited successfully, then usr-is-merged exists either as
	# a real or virtual package
	if env --chdir="$1" APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-cache show --no-all-versions usr-is-merged 2>/dev/null | grep -q "Package: usr-is-merged"; then
		echo "usr-is-merged found -- running merged-usr extract hook" >&2
	else
		# The usr-is-merged must be virtual, so assume that nothing
		# has to be done. This is the case with Debian Trixie or later
		# or with Ubuntu Lunar or later
		echo "usr-is-merged found but not real -- not running merged-usr extract hook" >&2
		exit 0
	fi
else
	# if the usr-is-merged package cannot be installed with apt, do nothing
	echo "no package providing usr-is-merged found -- not running merged-usr extract hook" >&2
	exit 0
fi

# resolve the script path using several methods in order:
#  1. using dirname -- "$0"
#  2. using ./hooks
#  3. using /usr/share/mmdebstrap/hooks/
for p in "$(dirname -- "$0")/.." ./hooks /usr/share/mmdebstrap/hooks; do
	if [ -x "$p/merged-usr/setup00.sh" ] && [ -x "$p/merged-usr/extract00.sh" ] && [ -x "$p/merged-usr/essential00.sh" ]; then
		"$p/merged-usr/extract00.sh" "$1"
		exit 0
	fi
done

echo "cannot find merged-usr hook anywhere" >&2
exit 1
