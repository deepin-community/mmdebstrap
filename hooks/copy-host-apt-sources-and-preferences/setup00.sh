#!/bin/sh

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
	if [ -e "$rootdir/$f" ]; then
		if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 2 ]; then
			echo "I: $f already exists in chroot, appending..." >&2
		fi
		echo >> "$rootdir/$f"
	fi
	cat "$f" >> "$rootdir/$f"
	if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
		echo "D: contents of $f inside the chroot:" >&2
		cat "$rootdir/$f" >&2
	fi
done
