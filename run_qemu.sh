#!/bin/sh

set -eu

: "${DEFAULT_DIST:=unstable}"
: "${cachedir:=./shared/cache}"
tmpdir="$(mktemp -d)"

cleanup() {
	rv=$?
	rm -f "$tmpdir/log"
	[ -e "$tmpdir" ] && rmdir "$tmpdir"
	if [ -n "${TAIL_PID:-}" ]; then
		kill "$TAIL_PID"
	fi
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

echo 1 > shared/exitstatus.txt
if [ -e shared/output.txt ]; then
	rm shared/output.txt
fi
touch shared/output.txt
tail -f shared/output.txt &
TAIL_PID=$!

# to connect to serial use:
#   minicom -D 'unix#/tmp/ttyS0'
#
# or this (quit with ctrl+q):
#   socat stdin,raw,echo=0,escape=0x11 unix-connect:/tmp/ttyS0
ret=0
timeout --foreground 40m debvm-run --image="$(realpath "$cachedir")/debian-$DEFAULT_DIST.ext4" -- \
	-m 4G -snapshot \
	-monitor unix:/tmp/monitor,server,nowait \
	-serial unix:/tmp/ttyS0,server,nowait \
	-serial unix:/tmp/ttyS1,server,nowait \
	-virtfs local,id=mmdebstrap,path="$(pwd)/shared",security_model=none,mount_tag=mmdebstrap \
	>"$tmpdir/log" 2>&1 || ret=$?
if [ "$ret" -ne 0 ]; then
	cat "$tmpdir/log"
	exit $ret
fi
