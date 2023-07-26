#!/bin/sh

set -eu

# The jessie-or-older extract01 hook has to be run up to the point where the
# Essential:yes field was removed from the init package (with
# init-system-helpers 1.34). Since the essential packages have only been
# extracted but not installed, we cannot use dpkg-query to find out its
# version. Since /usr/share/doc might be missing due to dpkg --path-exclude, we
# also cannot check whether /usr/share/doc/init/copyright exists. There also
# was a time (before init-system-helpers 1.20) where there was no init package
# at all where we also want to apply this hook. So we just ask apt about the
# candidate version for init-system-helpers. This should only fail in
# situations where there are multiple versions of init-system-helpers in
# different suites.
ver=$(env --chdir="$1" APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-cache show --no-all-versions init-system-helpers 2>/dev/null | sed -ne 's/^Version: \(.*\)$/\1/p' || printf '')
if [ -z "$ver" ]; then
	# there is no package called init-system-helpers, so either:
	#  - this is so old that init-system-helpers didn't exist yet
	#  - we are in a future where init-system-helpers doesn't exist anymore
	#  - something strange is going on
	# we should only call the hook in the first case
	ver=$(env --chdir="$1" APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-cache show --no-all-versions base-files 2>/dev/null | sed -ne 's/^Version: \(.*\)$/\1/p' || printf '')
	if [ -z "$ver" ]; then
		echo "neither init-system-helpers nor base-files can be installed -- not running jessie-or-older extract01 hook" >&2
		exit 0
	fi

	# Jessie is Debian 8
	if dpkg --compare-versions "$ver" ge 8; then
		echo "there is no init-system-helpers but base-files version $ver is >= 8 -- not running jessie-or-older extract01 hook" >&2
		exit 0
	else
		echo "there is no init-system-helpers but base-files version $ver is << 8 -- running jessie-or-older extract01 hook" >&2
	fi
else
	if dpkg --compare-versions "$ver" ge 1.34; then
		echo "init-system-helpers version $ver is >= 1.34 -- not running jessie-or-older extract01 hook" >&2
		exit 0
	else
		echo "init-system-helpers version $ver is << 1.34 -- running jessie-or-older extract01 hook" >&2
	fi
fi

# resolve the script path using several methods in order:
#  1. using dirname -- "$0"
#  2. using ./hooks
#  3. using /usr/share/mmdebstrap/hooks/
for p in "$(dirname -- "$0")/.." ./hooks /usr/share/mmdebstrap/hooks; do
	if [ -x "$p/jessie-or-older/extract00.sh" ] && [ -x "$p/jessie-or-older/extract01.sh" ]; then
		"$p/jessie-or-older/extract01.sh" "$1"
		exit 0
	fi
done

echo "cannot find jessie-or-older hook anywhere" >&2
exit 1
