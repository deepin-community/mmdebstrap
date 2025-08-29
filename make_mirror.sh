#!/bin/sh

set -eu

# This script fills either cache.A or cache.B with new content and then
# atomically switches the cache symlink from one to the other at the end.
# This way, at no point will the cache be in an non-working state, even
# when this script got canceled at any point.
# Working with two directories also automatically prunes old packages in
# the local repository.

deletecache() {
  dir="$1"
  echo "running deletecache $dir" >&2
  if [ ! -e "$dir" ]; then
    return
  fi
  if [ ! -e "$dir/mmdebstrapcache" ]; then
    echo "$dir cannot be the mmdebstrap cache" >&2
    return 1
  fi
  # be very careful with removing the old directory
  # experimental is pulled in with USE_HOST_APT_CONFIG=yes on debci
  # when testing a package from experimental
  for dist in oldstable stable testing unstable experimental; do
    # deleting artifacts from test "debootstrap"
    for variant in minbase buildd -; do
      if [ -e "$dir/debian-$dist-$variant.tar" ]; then
        rm "$dir/debian-$dist-$variant.tar"
      else
        echo "does not exist: $dir/debian-$dist-$variant.tar" >&2
      fi
    done
    # deleting artifacts from test "mmdebstrap"
    for variant in essential apt minbase buildd - standard; do
      for format in tar ext2 ext4 squashfs; do
        if [ -e "$dir/mmdebstrap-$dist-$variant.$format" ]; then
          # attempt to delete for all dists because DEFAULT_DIST might've been different the last time
          rm "$dir/mmdebstrap-$dist-$variant.$format"
        elif [ "$dist" = "$DEFAULT_DIST" ]; then
          # only warn about non-existance when it's expected to exist
          echo "does not exist: $dir/mmdebstrap-$dist-$variant.$format" >&2
        fi
      done
    done
    if [ -e "$dir/debian/dists/$dist" ]; then
      rm --one-file-system --recursive "$dir/debian/dists/$dist"
    else
      echo "does not exist: $dir/debian/dists/$dist" >&2
    fi
    case "$dist" in oldstable | stable)
      if [ -e "$dir/debian/dists/$dist-updates" ]; then
        rm --one-file-system --recursive "$dir/debian/dists/$dist-updates"
      else
        echo "does not exist: $dir/debian/dists/$dist-updates" >&2
      fi
      ;;
    esac
    case "$dist" in oldstable | stable)
      if [ -e "$dir/debian-security/dists/$dist-security" ]; then
        rm --one-file-system --recursive "$dir/debian-security/dists/$dist-security"
      else
        echo "does not exist: $dir/debian-security/dists/$dist-security" >&2
      fi
      ;;
    esac
  done
  for f in "$dir/debian-"*.ext4; do
    if [ -e "$f" ]; then
      rm --one-file-system "$f"
    fi
  done
  # on i386 and amd64, the intel-microcode and amd64-microcode packages
  # from non-free-firwame get pulled in because they are
  # priority:standard with USE_HOST_APT_CONFIG=yes
  for c in main non-free-firmware; do
    if [ -e "$dir/debian/pool/$c" ]; then
      rm --one-file-system --recursive "$dir/debian/pool/$c"
    else
      echo "does not exist: $dir/debian/pool/$c" >&2
    fi
  done
  if [ -e "$dir/debian-security/pool/updates/main" ]; then
    rm --one-file-system --recursive "$dir/debian-security/pool/updates/main"
  else
    echo "does not exist: $dir/debian-security/pool/updates/main" >&2
  fi
  for i in $(seq 1 6); do
    if [ ! -e "$dir/debian$i" ]; then
      continue
    fi
    rm "$dir/debian$i"
  done
  rm "$dir/mmdebstrapcache"
  # remove all symlinks
  find "$dir" -type l -delete

  # now the rest should only be empty directories
  if [ -e "$dir" ]; then
    find "$dir" -depth -print0 | xargs -0 --no-run-if-empty rmdir
  else
    echo "does not exist: $dir" >&2
  fi
}

cleanup_newcachedir() {
  echo "running cleanup_newcachedir"
  deletecache "$newcachedir"
}

cleanupapt() {
  echo "running cleanupapt" >&2
  if [ ! -e "$rootdir" ]; then
    return
  fi
  for f in \
    "$rootdir/var/cache/apt/archives/"*.deb \
    "$rootdir/var/cache/apt/archives/partial/"*.deb \
    "$rootdir/var/cache/apt/"*.bin \
    "$rootdir/var/lib/apt/lists/"* \
    "$rootdir/var/lib/dpkg/status" \
    "$rootdir/var/lib/dpkg/lock-frontend" \
    "$rootdir/var/lib/dpkg/lock" \
    "$rootdir/var/lib/apt/lists/lock" \
    "$rootdir/etc/apt/apt.conf" \
    "$rootdir/etc/apt/sources.list.d/"* \
    "$rootdir/etc/apt/preferences.d/"* \
    "$rootdir/etc/apt/sources.list" \
    "$rootdir/var/cache/apt/archives/lock"; do
    if [ ! -e "$f" ]; then
      echo "does not exist: $f" >&2
      continue
    fi
    if [ -d "$f" ]; then
      rmdir "$f"
    else
      rm "$f"
    fi
  done
  find "$rootdir" -depth -print0 | xargs -0 --no-run-if-empty rmdir
}

# note: this function uses brackets instead of curly braces, so that it's run
# in its own process and we can handle traps independent from the outside
update_cache() (
  dist="$1"
  nativearch="$2"

  # use a subdirectory of $newcachedir so that we can use
  # hardlinks
  rootdir="$newcachedir/apt"
  mkdir -p "$rootdir"

  # we only set this trap here and overwrite the previous trap, because
  # the update_cache function is run as part of a pipe and thus in its
  # own process which will EXIT after it finished
  trap 'kill "$PROXYPID" || :;cleanupapt' EXIT INT TERM

  for p in /etc/apt/apt.conf.d /etc/apt/sources.list.d /etc/apt/preferences.d /var/cache/apt/archives /var/lib/apt/lists/partial /var/lib/dpkg; do
    mkdir -p "$rootdir/$p"
  done

  # read sources.list content from stdin
  cat >"$rootdir/etc/apt/sources.list"

  cat <<END >"$rootdir/etc/apt/apt.conf"
Apt::Architecture "$nativearch";
Apt::Architectures "$nativearch";
Dir::Etc "$rootdir/etc/apt";
Dir::State "$rootdir/var/lib/apt";
Dir::Cache "$rootdir/var/cache/apt";
Apt::Install-Recommends false;
Apt::Get::Download-Only true;
Acquire::Languages "none";
Dir::Etc::Trusted "/etc/apt/trusted.gpg";
Dir::Etc::TrustedParts "/etc/apt/trusted.gpg.d";
Acquire::http::Proxy "http://127.0.0.1:8080/";
END

  : >"$rootdir/var/lib/dpkg/status"

  if [ "$dist" = "$DEFAULT_DIST" ] && [ "$nativearch" = "$HOSTARCH" ] && [ "$USE_HOST_APT_CONFIG" = "yes" ]; then
    # we append sources and settings instead of overwriting after
    # an empty line
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
      [ -e "$f" ] || continue
      [ -e "$rootdir/$f" ] && echo >>"$rootdir/$f"
      # Filter out file:// repositories as they are added
      # to each mmdebstrap call verbatim by
      # debian/tests/copy_host_apt_config
      # Also filter out all mirrors that are not of suite
      # $DEFAULT_DIST, except experimental if the suite
      # is unstable. This prevents packages from
      # unstable entering a testing mirror.
      if [ "$dist" = unstable ]; then
        grep -v ' file://' "$f" \
          | grep -E " (unstable|experimental) " \
            >>"$rootdir/$f" || :
      else
        grep -v ' file://' "$f" \
          | grep " $DEFAULT_DIST " \
            >>"$rootdir/$f" || :
      fi
    done
    for f in /etc/apt/preferences.d/*; do
      [ -e "$f" ] || continue
      [ -e "$rootdir/$f" ] && echo >>"$rootdir/$f"
      cat "$f" >>"$rootdir/$f"
    done
  fi

  echo "creating mirror for $dist" >&2
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/* /etc/apt/preferences.d/*; do
    [ -e "$rootdir/$f" ] || continue
    echo "contents of $f:" >&2
    cat "$rootdir/$f" >&2
  done

  APT_CONFIG="$rootdir/etc/apt/apt.conf" apt-get update --error-on=any

  pkgs=$(APT_CONFIG="$rootdir/etc/apt/apt.conf" apt-get indextargets \
    --format '$(FILENAME)' 'Created-By: Packages' "Architecture: $nativearch" \
    | xargs --delimiter='\n' /usr/lib/apt/apt-helper cat-file \
    | grep-dctrl --no-field-names --show-field=Package --exact-match \
      \( --field=Essential yes --or --field=Priority required \
      --or --field=Priority important --or --field=Priority standard \
      \))

  pkgs="$pkgs build-essential busybox eatmydata fakechroot fakeroot"

  # we need usr-is-merged to simulate debootstrap behaviour for all dists
  # starting from Debian 12 (Bullseye)
  case "$dist" in
    oldstable) pkgs="$pkgs gpg" ;;
    stable) pkgs="$pkgs gpg usr-is-merged usrmerge" ;;
    testing | unstable) pkgs="$pkgs gpg-from-sq" ;;
  esac

  # shellcheck disable=SC2086
  APT_CONFIG="$rootdir/etc/apt/apt.conf" apt-get --yes install $pkgs \
    || APT_CONFIG="$rootdir/etc/apt/apt.conf" apt-get --yes install \
      -oDebug::pkgProblemResolver=true -oDebug::pkgDepCache::Marker=1 \
      -oDebug::pkgDepCache::AutoInstall=1 \
      $pkgs

  rm "$rootdir/var/cache/apt/archives/lock"
  rmdir "$rootdir/var/cache/apt/archives/partial"
  APT_CONFIG="$rootdir/etc/apt/apt.conf" apt-get --option Dir::Etc::SourceList=/dev/null update
  APT_CONFIG="$rootdir/etc/apt/apt.conf" apt-get clean

  cleanupapt

  # this function is run in its own process, so we unset all traps before
  # returning
  trap "-" EXIT INT TERM
)

check_proxy_running() {
  if timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080 && printf "GET http://deb.debian.org/debian/dists/'"$DEFAULT_DIST"'/InRelease HTTP/1.1\nHost: deb.debian.org\n\n" >&3 && grep "Suite: '"$DEFAULT_DIST"'" <&3 >/dev/null' 2>/dev/null; then
    return 0
  elif timeout 1 env http_proxy="http://127.0.0.1:8080/" wget --quiet -O - "http://deb.debian.org/debian/dists/$DEFAULT_DIST/InRelease" | grep "Suite: $DEFAULT_DIST" >/dev/null; then
    return 0
  elif timeout 1 curl --proxy "http://127.0.0.1:8080/" --silent "http://deb.debian.org/debian/dists/$DEFAULT_DIST/InRelease" | grep "Suite: $DEFAULT_DIST" >/dev/null; then
    return 0
  fi
  return 1
}

if [ -e "./shared/cache.A" ] && [ -e "./shared/cache.B" ]; then
  echo "both ./shared/cache.A and ./shared/cache.B exist" >&2
  echo "was a former run of the script aborted?" >&2
  if [ -e ./shared/cache ]; then
    echo "cache symlink points to $(readlink ./shared/cache)" >&2
    case "$(readlink ./shared/cache)" in
      cache.A)
        echo "removing ./shared/cache.B" >&2
        rm -r ./shared/cache.B
        ;;
      cache.B)
        echo "removing ./shared/cache.A" >&2
        rm -r ./shared/cache.A
        ;;
      *)
        echo "unexpected" >&2
        exit 1
        ;;
    esac
  else
    echo "./shared/cache doesn't exist" >&2
    exit 1
  fi
fi

if [ -e "./shared/cache.A" ]; then
  oldcache=cache.A
  newcache=cache.B
else
  oldcache=cache.B
  newcache=cache.A
fi

oldcachedir="./shared/$oldcache"
newcachedir="./shared/$newcache"

oldmirrordir="$oldcachedir/debian"
newmirrordir="$newcachedir/debian"

mirror="http://deb.debian.org/debian"
security_mirror="http://security.debian.org/debian-security"
components=main

: "${DEFAULT_DIST:=unstable}"
: "${ONLY_DEFAULT_DIST:=no}"
: "${ONLY_HOSTARCH:=no}"
: "${HAVE_QEMU:=yes}"
: "${RUN_MA_SAME_TESTS:=yes}"
# by default, use the mmdebstrap executable in the current directory
: "${CMD:=./mmdebstrap}"
: "${USE_HOST_APT_CONFIG:=no}"
: "${FORCE_UPDATE:=no}"

if [ "$FORCE_UPDATE" != "yes" ] && [ -e "$oldmirrordir/dists/$DEFAULT_DIST/InRelease" ]; then
  http_code=$(curl --output /dev/null --silent --location --head --time-cond "$oldmirrordir/dists/$DEFAULT_DIST/InRelease" --write-out '%{http_code}' "$mirror/dists/$DEFAULT_DIST/InRelease")
  case "$http_code" in
    200) ;; # need update
    304)
      echo up-to-date
      exit 0
      ;;
    *)
      echo "unexpected status: $http_code"
      exit 1
      ;;
  esac
fi

./caching_proxy.py "$oldcachedir" "$newcachedir" &
PROXYPID=$!
trap 'kill "$PROXYPID" || :' EXIT INT TERM

for i in $(seq 10); do
  check_proxy_running && break
  sleep 1
done
if [ ! -s "$newmirrordir/dists/$DEFAULT_DIST/InRelease" ]; then
  echo "failed to start proxy" >&2
  kill $PROXYPID
  exit 1
fi

trap 'kill "$PROXYPID" || :;cleanup_newcachedir' EXIT INT TERM

mkdir -p "$newcachedir"
touch "$newcachedir/mmdebstrapcache"

HOSTARCH=$(dpkg --print-architecture)
arches="$HOSTARCH"
if [ "$HOSTARCH" = amd64 ]; then
  arches="$arches arm64 i386"
elif [ "$HOSTARCH" = arm64 ]; then
  arches="$arches amd64 armhf"
fi

# we need the split_inline_sig() function
# shellcheck disable=SC1091
. /usr/share/debootstrap/functions

for dist in oldstable stable testing unstable; do
  for nativearch in $arches; do
    # non-host architectures are only downloaded for $DEFAULT_DIST
    if [ "$nativearch" != "$HOSTARCH" ] && [ "$DEFAULT_DIST" != "$dist" ]; then
      continue
    fi
    # if ONLY_DEFAULT_DIST is set, only download DEFAULT_DIST
    if [ "$ONLY_DEFAULT_DIST" = "yes" ] && [ "$DEFAULT_DIST" != "$dist" ]; then
      continue
    fi
    if [ "$ONLY_HOSTARCH" = "yes" ] && [ "$nativearch" != "$HOSTARCH" ]; then
      continue
    fi
    # we need a first pass without updates and security patches
    # because otherwise, old package versions needed by
    # debootstrap will not get included
    echo "deb [arch=$nativearch] $mirror $dist $components" | update_cache "$dist" "$nativearch"
    # we need to include the base mirror again or otherwise
    # packages like build-essential will be missing
    case "$dist" in oldstable | stable)
      cat <<END | update_cache "$dist" "$nativearch"
deb [arch=$nativearch] $mirror $dist $components
deb [arch=$nativearch] $mirror $dist-updates main
deb [arch=$nativearch] $security_mirror $dist-security main
END
      ;;
    esac
  done
  codename=$(awk '/^Codename: / { print $2; }' <"$newmirrordir/dists/$dist/InRelease")
  ln -s "$dist" "$newmirrordir/dists/$codename"

  # split the InRelease file into Release and Release.gpg not because apt
  # or debootstrap need it that way but because grep-dctrl does
  split_inline_sig \
    "$newmirrordir/dists/$dist/InRelease" \
    "$newmirrordir/dists/$dist/Release" \
    "$newmirrordir/dists/$dist/Release.gpg"
  touch --reference="$newmirrordir/dists/$dist/InRelease" "$newmirrordir/dists/$dist/Release" "$newmirrordir/dists/$dist/Release.gpg"
done

kill $PROXYPID

# Create some symlinks so that we can trick apt into accepting multiple apt
# lines that point to the same repository but look different. This is to
# avoid the warning:
# W: Target Packages (main/binary-all/Packages) is configured multiple times...
for i in $(seq 1 6); do
  ln -s debian "$newcachedir/debian$i"
done

tmpdir=""

cleanuptmpdir() {
  if [ -z "$tmpdir" ]; then
    return
  fi
  if [ ! -e "$tmpdir" ]; then
    return
  fi
  for f in "$tmpdir/worker.sh" "$tmpdir/mmdebstrap.service"; do
    if [ ! -e "$f" ]; then
      echo "does not exist: $f" >&2
      continue
    fi
    rm "$f"
  done
  rmdir "$tmpdir"
}

SOURCE_DATE_EPOCH="$(date --date="$(grep-dctrl -s Date -n '' "$newmirrordir/dists/$DEFAULT_DIST/Release")" +%s)"
export SOURCE_DATE_EPOCH

if [ "$HAVE_QEMU" = "yes" ]; then
  # we use the caching proxy again when building the qemu image
  #  - we can re-use the packages that were already downloaded earlier
  #  - we make sure that the qemu image uses the same Release file even
  #    if a mirror push happened between now and earlier
  #  - we avoid polluting the mirror with the additional packages by
  #    using --readonly
  ./caching_proxy.py --readonly "$oldcachedir" "$newcachedir" &
  PROXYPID=$!

  for i in $(seq 10); do
    check_proxy_running && break
    sleep 1
  done
  if [ ! -s "$newmirrordir/dists/$DEFAULT_DIST/InRelease" ]; then
    echo "failed to start proxy" >&2
    kill $PROXYPID
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  trap 'kill "$PROXYPID" || :;cleanuptmpdir; cleanup_newcachedir' EXIT INT TERM

  pkgs=perl-doc,systemd-sysv,perl,arch-test,fakechroot,fakeroot,mount,uidmap,qemu-user-binfmt,dpkg-dev,mini-httpd,libdevel-cover-perl,libtemplate-perl,debootstrap,procps,apt-cudf,aspcud,python3,libcap2-bin,gpg-from-sq,debootstrap,distro-info-data,iproute2,ubuntu-keyring,apt-utils,squashfs-tools-ng,genext2fs,linux-image-generic,passwd,e2fsprogs,uuid-runtime
  if [ ! -e ./mmdebstrap ]; then
    pkgs="$pkgs,mmdebstrap"
  fi
  arches=$HOSTARCH
  if [ "$RUN_MA_SAME_TESTS" = "yes" ]; then
    case "$HOSTARCH" in
      amd64)
        arches=amd64,arm64
        pkgs="$pkgs,libfakechroot:arm64,libfakeroot:arm64"
        ;;
      arm64)
        arches=arm64,amd64
        pkgs="$pkgs,libfakechroot:amd64,libfakeroot:amd64"
        ;;
    esac
  fi

  cat <<END >"$tmpdir/mmdebstrap.service"
[Unit]
Description=mmdebstrap worker script

[Service]
Type=oneshot
ExecStart=/worker.sh

[Install]
WantedBy=multi-user.target
END
  # here is something crazy:
  # as we run mmdebstrap, the process ends up being run by different users with
  # different privileges (real or fake). But for being able to collect
  # Devel::Cover data, they must all share a single directory. The only way that
  # I found to make this work is to mount the database directory with a
  # filesystem that doesn't support ownership information at all and a umask that
  # gives read/write access to everybody.
  # https://github.com/pjcj/Devel--Cover/issues/223
  cat <<'END' >"$tmpdir/worker.sh"
#!/bin/sh
echo 'root:root' | chpasswd
mount -t 9p -o trans=virtio,access=any,msize=128k mmdebstrap /mnt
# need to restart mini-httpd because we mounted different content into www-root
systemctl restart mini-httpd

ip link set enp0s1 down || :

handler () {
	while IFS= read -r line || [ -n "$line" ]; do
		printf "%s %s: %s\n" "$(date -u -d "0 $(date +%s.%3N) seconds - $2 seconds" +"%T.%3N")" "$1" "$line"
	done
}

(
	cd /mnt;
	if [ -e cover_db.img ]; then
		mkdir -p cover_db
		mount -o loop,umask=000 cover_db.img cover_db
	fi

	now=$(date +%s.%3N)
	ret=0
	{ { { { {
	          sh -x ./test.sh 2>&1 1>&4 3>&- 4>&-; echo $? >&2;
	        } | handler E "$now" >&3;
	      } 4>&1 | handler O "$now" >&3;
	    } 2>&1;
	  } | { read xs; exit $xs; };
	} 3>&1 || ret=$?
	echo $ret > /mnt/exitstatus.txt
	if [ -e cover_db.img ]; then
		df -h cover_db
		umount cover_db
	fi
) > /mnt/output.txt 2>&1
umount /mnt
systemctl poweroff
END
  chmod +x "$tmpdir/worker.sh"
  if [ -z ${DISK_SIZE+x} ]; then
    DISK_SIZE=10G
  fi
  # set PATH to pick up the correct mmdebstrap variant
  env PATH="$(dirname "$(realpath --canonicalize-existing "$CMD")"):$PATH" \
    debvm-create --skip=usrmerge,systemdnetwork \
    --size="$DISK_SIZE" --release="$DEFAULT_DIST" \
    --output="$newcachedir/debian-$DEFAULT_DIST.ext4" -- \
    --architectures="$arches" --include="$pkgs" \
    --setup-hook='echo "Acquire::http::Proxy \"http://127.0.0.1:8080/\";" > "$1/etc/apt/apt.conf.d/00proxy"' \
    --hook-dir=/usr/share/mmdebstrap/hooks/maybe-merged-usr \
    --customize-hook='rm "$1/etc/apt/apt.conf.d/00proxy"' \
    --customize-hook='mkdir -p "$1/etc/systemd/system/multi-user.target.wants"' \
    --customize-hook='ln -s ../mmdebstrap.service "$1/etc/systemd/system/multi-user.target.wants/mmdebstrap.service"' \
    --customize-hook='touch "$1/mmdebstrap-testenv"' \
    --customize-hook='copy-in "'"$tmpdir"'/mmdebstrap.service" /etc/systemd/system/' \
    --customize-hook='copy-in "'"$tmpdir"'/worker.sh" /' \
    --customize-hook='echo 127.0.0.1 localhost > "$1/etc/hosts"' \
    --customize-hook='printf "START=1\nDAEMON_OPTS=\"-h 127.0.0.1 -p 80 -u nobody -dd /mnt/cache -i /var/run/mini-httpd.pid -T UTF-8\"\n" > "$1/etc/default/mini-httpd"' \
    --customize-hook='touch "$1/etc/systemd/system/tmp.mount"' \
    "$mirror"

  kill $PROXYPID
  cleanuptmpdir
  trap "cleanup_newcachedir" EXIT INT TERM
fi

# delete possibly leftover symlink
if [ -e ./shared/cache.tmp ]; then
  rm ./shared/cache.tmp
fi
# now atomically switch the symlink to point to the other directory
ln -s $newcache ./shared/cache.tmp
mv --no-target-directory ./shared/cache.tmp ./shared/cache

deletecache "$oldcachedir"

trap - EXIT INT TERM

echo "$0 finished successfully" >&2
