mmdebstrap
==========

An alternative to debootstrap which uses apt internally and is thus able to use
more than one mirror and resolve more complex dependencies.

Usage
-----

Use like debootstrap:

    sudo mmdebstrap unstable ./unstable-chroot

Without superuser privileges:

    mmdebstrap unstable unstable-chroot.tar

With complex apt options:

    cat /etc/apt/sources.list | mmdebstrap > unstable-chroot.tar

For the full documentation use:

    pod2man ./mmdebstrap | man -l -

Or read a HTML version of the man page in either of these locations:

 - https://gitlab.mister-muffin.de/josch/mmdebstrap/wiki
 - https://manpages.debian.org/unstable/mmdebstrap/mmdebstrap.1.en.html

The sales pitch in comparison to debootstrap
--------------------------------------------

Summary:

 - more than one mirror possible
 - security and updates mirror included for Debian stable chroots
 - twice as fast
 - chroot with apt in 11 seconds
 - gzipped tarball with apt is 27M small
 - bit-by-bit reproducible output
 - unprivileged operation using Linux user namespaces or fakechroot
 - can operate on filesystems mounted with nodev
 - foreign architecture chroots with qemu-user
 - variant installing only Essential:yes packages and dependencies
 - temporary chroots by redirecting to /dev/null
 - chroots without apt inside (for chroot from buildinfo file with debootsnap)

The author believes that a chroot of a Debian stable release should include the
latest packages including security fixes by default. This has been a wontfix
with debootstrap since 2009 (See #543819 and #762222). Since mmdebstrap uses
apt internally, support for multiple mirrors comes for free and stable or
oldstable **chroots will include security and updates mirrors**.

A side-effect of using apt is being twice as fast as debootstrap. The
timings were carried out on a laptop with an Intel Core i5-5200U, using a
mirror on localhost and a tmpfs.

| variant   | mmdebstrap | debootstrap  |
| --------- | ---------- | ------------ |
| essential | 9.52 s     | n.a          |
| apt       | 10.98 s    | n.a          |
| minbase   | 13.54 s    | 26.37 s      |
| buildd    | 21.31 s    | 34.85 s      |
| -         | 23.01 s    | 48.83 s      |

Apt considers itself an `Essential: yes` package. This feature allows one to
create a chroot containing just the `Essential: yes` packages and apt (and
their hard dependencies) in **just 11 seconds**.

If desired, a most minimal chroot with just the `Essential: yes` packages and
their hard dependencies can be created with a gzipped tarball size of just 34M.
By using dpkg's `--path-exclude` option to exclude documentation, even smaller
gzipped tarballs of 21M in size are possible. If apt is included, the result is
a **gzipped tarball of only 27M**.

These small sizes are also achieved because apt caches and other cruft is
stripped from the chroot. This also makes the result **bit-by-bit
reproducible** if the `$SOURCE_DATE_EPOCH` environment variable is set.

The author believes, that it should not be necessary to have superuser
privileges to create a file (the chroot tarball) in one's home directory.
Thus, mmdebstrap provides multiple options to create a chroot tarball with the
right permissions **without superuser privileges**. This avoids a whole class
of bugs like #921815. Depending on what is available, it uses either Linux user
namespaces or fakechroot. Debootstrap supports fakechroot but will not
create a tarball with the right permissions by itself. Support for Linux user
namespaces is missing (see #829134).

When creating a chroot tarball with debootstrap, the temporary chroot directory
cannot be on a filesystem that has been mounted with nodev. In unprivileged
mode, **mknod is never used**, which means that /tmp can be used as a temporary
directory location even if if it's mounted with nodev as a security measure.

If the chroot architecture cannot be executed by the current machine, qemu-user
is used to allow one to create a **foreign architecture chroot**.

Limitations in comparison to debootstrap
----------------------------------------

Debootstrap supports creating a Debian chroot on non-Debian systems but
mmdebstrap requires apt and is thus limited to Debian and derivatives. This
means that mmdebstrap can never fully replace debootstrap and debootstrap will
continue to be relevant in situations where you want to create a Debian chroot
from a platform without apt and dpkg.

There is no `SCRIPT` argument.

The following options, don't exist: `--second-stage`, `--exclude`,
`--resolve-deps`, `--force-check-gpg`, `--merged-usr` and `--no-merged-usr`.

The quirks from debootstrap are needed to create chroots of Debian unstable
from snapshot.d.o before timestamp 20141107T220431Z or Debian 8 (Jessie) or
later.

Tests
=====

The script `coverage.sh` runs mmdebstrap in all kind of scenarios to execute
all code paths of the script. It verifies its output in each scenario and
displays the results gathered with Devel::Cover. It also compares the output of
mmdebstrap with debootstrap in several scenarios. To run the testsuite, run:

    ./make_mirror.sh
    CMD=./mmdebstrap ./coverage.sh

To also generate perl Devel::Cover data, omit the `CMD` environment variable.
But that will also take a lot longer.

The `make_mirror.sh` script will be a no-op if nothing changed in Debian
unstable. You don't need to run `make_mirror.sh` before every invocation of
`coverage.sh`. When you make changes to `make_mirror.sh` and want to regenerate
the cache, run:

    touch -d yesterday shared/cache/debian/dists/unstable/Release

The script `coverage.sh` does not need an active internet connection by
default. An online connection is only needed by the `make_mirror.sh` script
which fills a local cache with a few minimal Debian mirror copies.

By default, `coverage.sh` will skip running a single test which tries creating
a Ubuntu Focal chroot. To not skip that test, run `coverage.sh` with the
environment variable `ONLINE=yes`.

If a test fails you can run individual tests by executing `coverage.py` with
the test name and optionally limit it to a specific distribution like so:

    CMD=./mmdebstrap ./coverage.py --dist unstable check-against-debootstrap-dist

Bugs
====

mmdebstrap has bugs. Report them here:
https://gitlab.mister-muffin.de/josch/mmdebstrap/issues

Contributors
============

 - Johannes Schauer Marin Rodrigues (main author)
 - Jochen Sprickerhof
 - Helmut Grohne
 - Gioele Barabucci
 - Benjamin Drung
 - Josh Triplett
 - Konstantin Demin
 - Charles Short
 - Chris Hofstaedtler
 - Colin Watson
 - David Kalnischkies
 - Emilio Pozuelo Monfort
 - Francesco Poli
 - Jakub Wilk
 - Joe Groocock
 - Max-Julian Pogner
 - Nicolas Vigier
 - Raul Tambre
 - Steve Dodd
 - Trent W. Buck
 - Vagrant Cascadian
