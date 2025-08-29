#!/bin/sh

set -eu

: "${DEFAULT_DIST:=unstable}"
: "${cachedir:=./shared/cache}"
: "${MMDEBSTRAP_TESTS_DEBUG:=no}"
tmpdir="$(mktemp -d)"

cleanup() {
  rv=$?
  rm -f "$tmpdir/log"
  [ -e "$tmpdir" ] && rmdir "$tmpdir"
  if [ -e shared/output.txt ]; then
    res="$(cat shared/exitstatus.txt)"
    if [ "$res" != "0" ]; then
      # this might possibly overwrite another non-zero rv
      rv=1
    fi
  fi
  exit $rv
}

trap cleanup INT TERM EXIT

echo 1 >shared/exitstatus.txt
if [ -e shared/output.txt ]; then
  rm shared/output.txt
fi
touch shared/output.txt
setpriv --pdeathsig TERM tail -f shared/output.txt &

set -- timeout --foreground 40m \
  debvm-run --image="$(realpath "$cachedir")/debian-$DEFAULT_DIST.ext4" \
  --
cpuname=$(lscpu | awk '/Model name:/ {print $3}' | tr '\n' '+')
ncpu=$(lscpu | awk '/Core\(s\) per socket:/ {print $4}' | tr '\n' '+')
if [ "$cpuname" = "Cortex-A53+Cortex-A73+" ] && [ "$ncpu" = "2+4+" ]; then
  # crude detection of the big.LITTLE heterogeneous setup of cores on the
  # amlogic a311d bananapi
  #
  # https://lists.nongnu.org/archive/html/qemu-devel/2020-10/msg08494.html
  # https://gitlab.com/qemu-project/qemu/-/issues/239
  # https://segments.zhan.science/posts/kvm_on_pinehone_pro/#trouble-with-heterogeneous-architecture
  set -- taskset --cpu-list 2,3,4,5 "$@" -smp 4
fi

set -- "$@" -nic none -m 4G -snapshot

if [ "$MMDEBSTRAP_TESTS_DEBUG" = "no" ]; then
  # to connect to serial use:
  #   minicom -D 'unix#/tmp/ttyS0'
  # or this (quit with ctrl+q):
  #   socat stdin,raw,echo=0,escape=0x11 unix-connect:/tmp/ttyS0
  set -- "$@" \
    -monitor unix:/tmp/monitor,server,nowait \
    -serial unix:/tmp/ttyS0,server,nowait \
    -serial unix:/tmp/ttyS1,server,nowait
fi

set -- "$@" -virtfs local,id=mmdebstrap,path="$(pwd)/shared",security_model=none,mount_tag=mmdebstrap

ret=0
if [ "$MMDEBSTRAP_TESTS_DEBUG" = "no" ]; then
  "$@" >"$tmpdir/log" 2>&1 || ret=$?
else
  "$@" 2>&1 | tee "$tmpdir/log" || ret=$?
fi
if [ "$ret" -ne 0 ]; then
  cat "$tmpdir/log"
  exit $ret
fi
