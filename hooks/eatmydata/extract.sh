#!/bin/sh

set -eu

if [ "${MMDEBSTRAP_VERBOSITY:-1}" -ge 3 ]; then
	set -x
fi

rootdir="$1"

if [ -e "$rootdir/var/lib/dpkg/arch" ]; then
	chrootarch=$(head -1 "$rootdir/var/lib/dpkg/arch")
else
	chrootarch=$(dpkg --print-architecture)
fi

trusted=
eval "$(apt-config shell trusted Dir::Etc::trusted/f)"
trustedparts=
eval "$(apt-config shell trustedparts Dir::Etc::trustedparts/d)"
tmpfile=$(mktemp --tmpdir="$rootdir/tmp")
cat << END > "$tmpfile"
Apt::Architecture "$chrootarch";
Apt::Architectures "$chrootarch";
Dir "$rootdir";
Dir::Etc::Trusted "$trusted";
Dir::Etc::TrustedParts "$trustedparts";
END
# we run "apt-get download --print-uris" in a temporary directory, to make sure
# that the packages do not already exist in the current directory, or otherwise
# nothing will be printed for them
tmpdir=$(mktemp --directory --tmpdir="$rootdir/tmp")
env --chdir="$tmpdir" APT_CONFIG="$tmpfile" apt-get download --print-uris eatmydata libeatmydata1 \
	| sed -ne "s/^'\([^']\+\)'\s\+\(\S\+\)\s\+\([0-9]\+\)\s\+\(SHA256:[a-f0-9]\+\)$/\1 \2 \3 \4/p" \
	| while read -r uri fname size hash; do
		echo "processing $fname" >&2
		if [ -e "$tmpdir/$fname" ]; then
			echo "$tmpdir/$fname already exists" >&2
			exit 1
		fi
		[ -z "$hash" ] && hash="Checksum-FileSize:$size"
		env --chdir="$tmpdir" APT_CONFIG="$tmpfile" /usr/lib/apt/apt-helper download-file "$uri" "$fname" "$hash"
		case "$fname" in
			eatmydata_*_all.deb)
				mkdir -p "$rootdir/usr/bin"
				dpkg-deb --fsys-tarfile "$tmpdir/$fname" \
					| tar --directory="$rootdir/usr/bin" --strip-components=3 --extract --verbose ./usr/bin/eatmydata
				;;
			libeatmydata1_*_$chrootarch.deb)
				libdir="/usr/lib/$(dpkg-architecture -a "$chrootarch" -q DEB_HOST_MULTIARCH)"
				mkdir -p "$rootdir$libdir"
				dpkg-deb --fsys-tarfile "$tmpdir/$fname" \
					| tar --directory="$rootdir$libdir" --strip-components=4 --extract --verbose --wildcards ".$libdir/libeatmydata.so*"
				;;
			*)
				echo "unexpected filename: $fname" >&2
				exit 1
				;;
		esac
		rm "$tmpdir/$fname"
done
rm "$tmpfile"
rmdir "$tmpdir"

mv "$rootdir/usr/bin/dpkg" "$rootdir/usr/bin/dpkg.distrib"
cat << END > "$rootdir/usr/bin/dpkg"
#!/bin/sh
exec /usr/bin/eatmydata /usr/bin/dpkg.distrib "\$@"
END
chmod +x "$rootdir/usr/bin/dpkg"
cat << END  >> "$rootdir/var/lib/dpkg/diversions"
/usr/bin/dpkg
/usr/bin/dpkg.distrib
:
END
