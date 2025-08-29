#!/bin/sh

set -eu

# by default, use the mmdebstrap executable in the current directory together
# with perl Devel::Cover but allow to overwrite this
: "${CMD:=perl -MDevel::Cover=-silent,-nogcov ./mmdebstrap}"

case "$CMD" in
  "mmdebstrap "* | mmdebstrap | *" mmdebstrap" | *" mmdebstrap "*)
    MMSCRIPT="$(command -v mmdebstrap 2>/dev/null)"
    ;;
  *) MMSCRIPT=./mmdebstrap ;;
esac

if [ -e "$MMSCRIPT" ]; then
  TMPFILE=$(mktemp)
  perltidy <"$MMSCRIPT" >"$TMPFILE"
  ret=0
  diff -u "$MMSCRIPT" "$TMPFILE" || ret=$?
  if [ "$ret" -ne 0 ]; then
    echo "perltidy failed" >&2
    rm "$TMPFILE"
    exit 1
  fi
  rm "$TMPFILE"

  if [ "$(sed -e '/^__END__$/,$d' "$MMSCRIPT" | wc --max-line-length)" -gt 79 ]; then
    echo "$MMSCRIPT exceeded maximum line length of 79 characters" >&2
    exit 1
  fi

  perlcritic --severity 4 --verbose 8 "$MMSCRIPT"

  pod2man "$MMSCRIPT" >/dev/null
fi

for f in tarfilter coverage.py caching_proxy.py; do
  [ -e "./$f" ] || continue
  black --check "./$f"
done

shellcheck --exclude=SC2016 coverage.sh make_mirror.sh run_null.sh run_qemu.sh gpgvnoexpkeysig mmdebstrap-autopkgtest-build-qemu hooks/*/*.sh

shfmt --binary-next-line --case-indent --indent 2 --simplify -d coverage.sh make_mirror.sh run_null.sh run_qemu.sh mmdebstrap-autopkgtest-build-qemu gpgvnoexpkeysig

mirrordir="./shared/cache/debian"

if [ ! -e "$mirrordir" ]; then
  echo "run ./make_mirror.sh before running $0" >&2
  exit 1
fi

# we use -f because the file might not exist
rm -f shared/cover_db.img

: "${DEFAULT_DIST:=unstable}"
: "${HAVE_QEMU:=yes}"
: "${RUN_MA_SAME_TESTS:=yes}"

if [ "$HAVE_QEMU" = "yes" ]; then
  # prepare image for cover_db
  fallocate -l 64M shared/cover_db.img
  /usr/sbin/mkfs.vfat shared/cover_db.img

  if [ ! -e "./shared/cache/debian-$DEFAULT_DIST.ext4" ]; then
    echo "./shared/cache/debian-$DEFAULT_DIST.ext4 does not exist" >&2
    exit 1
  fi
fi

# choose the timestamp of the unstable Release file, so that we get
# reproducible results for the same mirror timestamp
SOURCE_DATE_EPOCH=$(date --date="$(grep-dctrl -s Date -n '' "$mirrordir/dists/$DEFAULT_DIST/Release")" +%s)

# for traditional sort order that uses native byte values
export LC_ALL=C.UTF-8

: "${HAVE_BINFMT:=yes}"

mirror="http://127.0.0.1/debian"

export HAVE_QEMU HAVE_BINFMT RUN_MA_SAME_TESTS DEFAULT_DIST SOURCE_DATE_EPOCH CMD mirror

./coverage.py "$@"

if [ -e shared/cover_db.img ]; then
  # produce report inside the VM to make sure that the versions match or
  # otherwise we might get:
  # Can't read shared/cover_db/runs/1598213854.252.64287/cover.14 with Sereal: Sereal: Error: Bad Sereal header: Not a valid Sereal document. at offset 1 of input at srl_decoder.c line 600 at /usr/lib/x86_64-linux-gnu/perl5/5.30/Devel/Cover/DB/IO/Sereal.pm line 34, <$fh> chunk 1.
  cat <<END >shared/test.sh
cover -nogcov -report html_basic cover_db >&2
mkdir -p report
for f in common.js coverage.html cover.css css.js mmdebstrap--branch.html mmdebstrap--condition.html mmdebstrap.html mmdebstrap--subroutine.html standardista-table-sorting.js; do
	cp -a cover_db/\$f report
done
cover -delete cover_db >&2
END
  if [ "$HAVE_QEMU" = "yes" ]; then
    ./run_qemu.sh
  else
    ./run_null.sh
  fi

  echo
  echo "open file://$(pwd)/shared/report/coverage.html in a browser"
  echo
fi

# check if the wiki has to be updated with pod2markdown output
if [ "${DEBEMAIL-}" = "josch@debian.org" ]; then
  bash -exc "diff -u <(curl --silent https://gitlab.mister-muffin.de/josch/mmdebstrap/wiki/raw/Home | dos2unix; echo) <(pod2markdown < mmdebstrap)" || :
fi

rm -f shared/test.sh shared/tar1.txt shared/tar2.txt shared/pkglist.txt shared/doc-debian.tar.list shared/mmdebstrap shared/tarfilter shared/proxysolver

echo "$0 finished successfully" >&2
