#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

TARGET="$1"

# can_usrmerge_symlink() and can_usrmerge_symlink() are
# Copyright 2023 Helmut Grohne <helmut@subdivi.de>
# and part of the debootstrap source in /usr/share/debootstrap/functions
# https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/96
# https://bugs.debian.org/104989
can_usrmerge_symlink() {
	# Absolute symlinks can be relocated without problems.
	test "${2#/}" = "$2" || return 0
	while :; do
		if test "${2#/}" != "$2"; then
			# Handle double-slashes.
			set -- "$1" "${2#/}"
		elif test "${2#./}" != "$2"; then
			# Handle ./ inside a link target.
			set -- "$1" "${2#./}"
		elif test "$2" = ..; then
			# A parent directory symlink is ok if it does not
			# cross the top level directory.
			test "${1%/*/*}" != "$1" -a -n "${1%/*/*}"
			return $?
		elif test "${2#../}" != "$2"; then
			# Symbolic link crossing / cannot be moved safely.
			# This is prohibited by Debian Policy 10.5.
			test "${1%/*/*}" = "$1" -o -z "${1%/*/*}" && return 1
			set -- "${1%/*}" "${2#../}"
		else
			# Consider the symlink ok if its target does not
			# contain a parent directory. When we fail here,
			# the link target is non-minimal and doesn't happen
			# in the archive.
			test "${2#*/../}" = "$2"
			return $?
		fi
	done
}

merge_usr_entry() {
	# shellcheck disable=SC3043
	local entry canon
	canon="$TARGET/usr/${1#"$TARGET/"}"
	test -h "$canon" &&
		error 1 USRMERGEFAIL "cannot move %s as its destination exists as a symlink" "${1#"$TARGET"}"
	if ! test -e "$canon"; then
		mv "$1" "$canon"
		return 0
	fi
	test -d "$1" ||
		error 1 USRMERGEFAIL "cannot move non-directory %s as its destination exists" "${1#"$TARGET"}"
	test -d "$canon" ||
		error 1 USRMERGEFAIL "cannot move directory %s as its destination is not a directory" "${1#"$TARGET"}"
	for entry in "$1/"* "$1/."*; do
		# Some shells return . and .. on dot globs.
		test "${entry%/.}" != "${entry%/..}" && continue
		if test -h "$entry" && ! can_usrmerge_symlink "${entry#"$TARGET"}" "$(readlink "$entry")"; then
			error 1 USRMERGEFAIL "cannot move relative symlink crossing top-level directory" "${entry#"$TARGET"}"
		fi
		# Ignore glob match failures
		if test "${entry%'/*'}" != "${entry%'/.*'}" && ! test -e "$entry"; then
			continue
		fi
		merge_usr_entry "$entry"
	done
	rmdir "$1"
}

# This is list includes all possible multilib directories. It must be
# updated when new multilib directories are being added. Hopefully,
# all new architectures use multiarch instead, so we never get to
# update this.
for dir in bin lib lib32 lib64 libo32 libx32 sbin; do
	test -h "$TARGET/$dir" && continue
	test -e "$TARGET/$dir" || continue
	merge_usr_entry "$TARGET/$dir"
	ln -s "usr/$dir" "$TARGET/$dir"
done
