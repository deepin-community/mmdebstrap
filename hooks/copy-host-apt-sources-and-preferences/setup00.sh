#!/bin/sh
#
# This script makes sure that the apt sources.list and preferences from outside
# the chroot also exist inside the chroot by *appending* them to any existing
# files. If you do not want to keep the original content, add another setup
# hook before this one which cleans up the files you don't want to keep.
#
# If instead of copying sources.list verbatim you want to mangle its contents,
# consider using python-apt for that. An example can be found in the Debian
# packaging of mmdebstrap in ./debian/tests/sourcesfilter

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

if [ -n "${MMDEBSTRAP_SUITE:-}" ]; then
	if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 1 ]; then
		echo "W: using a non-empty suite name $MMDEBSTRAP_SUITE does not make sense with this hook and might select the wrong Essential:yes package set" >&2
	fi
fi

rootdir="$1"

SOURCELIST="/etc/apt/sources.list"
eval "$(apt-config shell SOURCELIST Dir::Etc::SourceList/f)"
SOURCEPARTS="/etc/apt/sources.d/"
eval "$(apt-config shell SOURCEPARTS Dir::Etc::SourceParts/d)"
PREFERENCES="/etc/apt/preferences"
eval "$(apt-config shell PREFERENCES Dir::Etc::Preferences/f)"
PREFERENCESPARTS="/etc/apt/preferences.d/"
eval "$(apt-config shell PREFERENCESPARTS Dir::Etc::PreferencesParts/d)"

for f in "$SOURCELIST" \
	"$SOURCEPARTS"/*.list \
	"$SOURCEPARTS"/*.sources \
	"$PREFERENCES" \
	"$PREFERENCESPARTS"/*; do
	[ -e "$f" ] || continue
	mkdir --parents "$(dirname "$rootdir/$f")"
	if [ -e "$rootdir/$f" ]; then
		if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 2 ]; then
			echo "I: $f already exists in chroot, appending..." >&2
		fi
		# Add extra newline between old content and new content.
		# This is required in case of deb822 files.
		echo >> "$rootdir/$f"
	fi
	cat "$f" >> "$rootdir/$f"
	if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
		echo "D: contents of $f inside the chroot:" >&2
		cat "$rootdir/$f" >&2
	fi
done
