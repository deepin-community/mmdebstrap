#!/bin/sh

set -eu

ver=$(dpkg-query --root="$1" -f '${db:Status-Status} ${Source} ${Version}' --show usr-is-merged 2>/dev/null || printf '')
case "$ver" in
	'')
		echo "no package called usr-is-merged is installed -- not running merged-usr essential hook" >&2
		exit 0
		;;
	'installed mmdebstrap-dummy-usr-is-merged 1')
		echo "dummy usr-is-merged package installed -- running merged-usr essential hook" >&2
		;;
	'installed usrmerge '*)
		echo "usr-is-merged package from src:usrmerge installed -- not running merged-usr essential hook" >&2
		exit 0
		;;
	'not-installed  ')
		echo "usr-is-merged was not installed in a previous hook -- not running merged-usr essential hook" >&2
		exit 0
		;;
	*)
		echo "unexpected situation for package usr-is-merged: $ver" >&2
		exit 1
		;;
esac

# resolve the script path using several methods in order:
#  1. using dirname -- "$0"
#  2. using ./hooks
#  3. using /usr/share/mmdebstrap/hooks/
for p in "$(dirname -- "$0")/.." ./hooks /usr/share/mmdebstrap/hooks; do
	if [ -x "$p/merged-usr/setup00.sh" ] && [ -x "$p/merged-usr/extract00.sh" ] && [ -x "$p/merged-usr/essential00.sh" ]; then
		"$p/merged-usr/essential00.sh" "$1"
		exit 0
	fi
done

echo "cannot find merged-usr hook anywhere" >&2
exit 1
