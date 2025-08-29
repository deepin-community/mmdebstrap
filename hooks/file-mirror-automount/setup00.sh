#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

rootdir="$1"

# process all configured apt repositories
env APT_CONFIG="$MMDEBSTRAP_APT_CONFIG" apt-get indextargets --no-release-info --format '$(REPO_URI)' \
	| sed -ne 's/^file:\/\+//p' \
	| sort -u \
	| while read -r path; do
		mkdir -p "$rootdir/run/mmdebstrap"
		if [ ! -d "/$path" ]; then
			echo "W: /$path is not an existing directory" >&2
			continue
		fi
		case $MMDEBSTRAP_MODE in
			root|unshare)
				echo "bind-mounting /$path into the chroot" >&2
				mkdir -p "$rootdir/$path"
				mount -o ro,bind "/$path" "$rootdir/$path"
				;;
			*)
				echo "copying /$path into the chroot" >&2
				mkdir -p "$rootdir/$path"
				"$MMDEBSTRAP_ARGV0" --hook-helper "$rootdir" "$MMDEBSTRAP_MODE" "$MMDEBSTRAP_HOOK" env "$MMDEBSTRAP_VERBOSITY" sync-in "/$path" "/$path" <&"$MMDEBSTRAP_HOOKSOCK" >&"$MMDEBSTRAP_HOOKSOCK"
				;;
		esac
		printf '/%s\0' "$path" >> "$rootdir/run/mmdebstrap/file-mirror-automount"
	done

# process all files given via --include
set -f # turn off pathname expansion
IFS=',' # split by comma
for pkg in $MMDEBSTRAP_INCLUDE; do
	set +f; unset IFS
	case $pkg in
		./*|../*|/*) : ;; # we are interested in this case
		*) continue ;; # not a file
	esac
	# undo escaping
	pkg="$(printf '%s' "$pkg" | sed 's/%2C/,/g; s/%25/%/g')"
	# check for existance
	if [ ! -f "$pkg" ]; then
		echo "$pkg does not exist" >&2
		continue
	fi
	# make path absolute
	pkg="$(realpath "$pkg")"
	case "$pkg" in
		/*) : ;;
		*) echo "path for $pkg is not absolute" >&2; continue;;
	esac
	mkdir -p "$rootdir/run/mmdebstrap"
	mkdir -p "$rootdir/$(dirname "$pkg")"
	case $MMDEBSTRAP_MODE in
		root|unshare)
			echo "bind-mounting $pkg into the chroot" >&2
			touch "$rootdir/$pkg"
			mount -o bind "$pkg" "$rootdir/$pkg"
			;;
		*)
			echo "copying $pkg into the chroot" >&2
			"$MMDEBSTRAP_ARGV0" --hook-helper "$rootdir" "$MMDEBSTRAP_MODE" "$MMDEBSTRAP_HOOK" env "$MMDEBSTRAP_VERBOSITY" upload "$pkg" "$pkg" <&"$MMDEBSTRAP_HOOKSOCK" >&"$MMDEBSTRAP_HOOKSOCK"
			;;
	esac
	printf '/%s\0' "$pkg" >> "$rootdir/run/mmdebstrap/file-mirror-automount"
done
set +f; unset IFS
