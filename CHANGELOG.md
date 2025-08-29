1.5.7 (2025-04-08)
------------------

 - support for elxr Debian derivative
 - support loong64
 - mmdebstrap-autopkgtest-build-qemu: add --sshkey=...

1.5.6 (2025-01-11)
------------------

 - bugfix release

1.5.5 (2025-01-09)
------------------

 - do not run dpkg-preconfigure via DPkg::Pre-Install-Pkgs hook
 - m-a-b-q: support passing args to mmdebstrap

1.5.4 (2024-10-28)
------------------

 - do not generate apt sources.list entry if SUITE is empty

1.5.3 (2024-09-13)
------------------

 - tidy up any zombie processes
 - chrootless hurd-i386
 - add --skip=cleanup/reproducible/machine-id
 - m-a-b-q: replace test_installed by dpkg-checkbuilddeps

1.5.2 (2024-06-26)
------------------

 - mmdebstrap-autopkgtest-build-qemu produces bit-by-bit reproducible output

1.5.1 (2024-06-03)
------------------

 - in root and unshare mode, run 'mount --make-rprivate /' before bind-mounting
 - switch apt variant from using 'apt-get dist-upgrade' to apt patterns

1.5.0 (2024-05-14)
------------------

 - add --format=ext4

1.4.3 (2024-02-01)
------------------

 - take hard links into account when computing disk usage

1.4.2 (2024-01-29)
------------------

 - allow for start-stop-daemon to be in either /sbin or /usr/sbin
 - mmdebstrap-autopkgtest-build-qemu: fix octal mode computation and hostname

1.4.1 (2024-01-09)
------------------

 - set DPkg::Chroot-Directory in APT_CONFIG to simplify calling apt in hooks
 - disallow running chrootless as root without fakeroot unless
   --skip=check/chrootless is used
 - only print short --help output if wrong args are passed
 - read files passed as --aptopt and --dpkgopt outside the unshared namespace

1.4.0 (2023-10-24)
------------------

 - add mmdebstrap-autopkgtest-build-qemu
 - export container=mmdebstrap-unshare env variable in unshare-mode hooks
 - add new skip options: output/dev, output/mknod, tar-in/mknod,
   copy-in/mknod, sync-in/mknod
 - stop copying qemu-$arch-static binary into the chroot
 - tarfilter: add --type-exclude option
 - set MMDEBSTRAP_FORMAT in hooks
 - do not install priority:required in buildd variant following debootstrap

1.3.8 (2023-08-20)
------------------

 - hooks/merged-usr: implement post-merging as debootstrap does
 - exclude ./lost+found from tarball

1.3.7 (2023-06-21)
------------------

 - add hooks/copy-host-apt-sources-and-preferences

1.3.6 (2023-06-16)
------------------

 - bugfix release

1.3.5 (2023-03-20)
------------------

 - bugfix release

1.3.4 (2023-03-16)
------------------

 - more safeguards before automatically choosing unshare mode

1.3.3 (2023-02-19)
------------------

 - testsuite improvements

1.3.2 (2023-02-16)
------------------

 - unshare mode works in privileged docker containers

1.3.1 (2023-01-20)
------------------

 - bugfix release

1.3.0 (2023-01-16)
------------------

 - add hooks/maybe-jessie-or-older and hooks/maybe-merged-usr
 - add --skip=check/signed-by
 - hooks/jessie-or-older: split into two individual hook files
 - skip running apt-get update if we are very sure that it was already run
 - be more verbose when 'apt-get update' failed
 - warn if a hook is named like one but not executable and if a hook is
   executable but not named like one
 - to find signed-by value, run gpg on the individual keys to print better
   error messages in case it fails (gpg doesn't give an indication which file
   it was unable to read) and print progress bar
 - allow empty sources.list entries

1.2.5 (2023-01-04)
------------------

 - bugfix release

1.2.4 (2022-12-23)
------------------

 - bugfix release
 - add jessie-or-older extract hook

1.2.3 (2022-11-16)
------------------

 - use Text::ParseWords::shellwords instead of spawning a new shell
 - mount and unmount once, instead for each run_chroot() call

1.2.2 (2022-10-27)
------------------

 - allow /etc/apt/trusted.gpg.d/ not to exist
 - always create /var/lib/dpkg/arch to make foreign architecture chrootless
   tarballs bit-by-bit identical
 - write an empty /etc/machine-id instead of writing 'uninitialized'
 - only print progress bars on interactive terminals that are wide enough

1.2.1 (2022-09-08)
------------------

 - bugfix release

1.2.0 (2022-09-05)
------------------

 - remove proot mode
 - error out if stdout is an interactive terminal
 - replace taridshift by tarfilter --idshift
 - tarfilter: add --transform option
 - multiple --skip options can be separated by comma or whitespace
 - also cleanup the contents of /run
 - support apt patterns and paths with commas and whitespace in --include
 - hooks: store the values of the --include option in MMDEBSTRAP_INCLUDE
 - add new --skip options: chroot/start-stop-daemon, chroot/policy-rc.d
   chroot/mount, chroot/mount/dev, chroot/mount/proc, chroot/mount/sys,
   cleanup/run

1.1.0 (2022-07-26)
----------------

 - mount a new /dev/pts instance into the chroot to make posix_openpt work
 - adjust merged-/usr hook to work the same way as debootstrap
 - add no-merged-usr hook

1.0.1 (2022-05-29)
------------------

 - bugfix release

1.0.0 (2022-05-28)
------------------

 - all documented interfaces are now considered stable
 - allow file:// mirrors
 - /var/cache/apt/archives/ is now allowed to contain *.deb packages
 - add file-mirror-automount hook-dir
 - set $MMDEBSTRAP_VERBOSITY in hooks
 - rewrite coverage with multiple individual and skippable shell scripts

0.8.6 (2022-03-25)
------------------

 - allow running root mode inside unshare mode

0.8.5 (2022-03-07)
------------------

 - improve documentation

0.8.4 (2022-02-11)
------------------

 - tarfilter: add --strip-components option
 - don't install essential packages in run_install()
 - remove /var/lib/dbus/machine-id

0.8.3 (2022-01-08)
------------------

 - allow codenames with apt patterns (requires apt >= 2.3.14)
 - don't overwrite existing files in setup code
 - don't copy in qemu-user-static binary if it's not needed

0.8.2 (2021-12-14)
------------------

 - use apt patterns to select priority variants (requires apt >= 2.3.10)

0.8.1 (2021-10-07)
------------------

 - enforce dpkg >= 1.20.0 and apt >= 2.3.7
 - allow working directory be not world readable
 - do not run xz and zstd with --threads=0 since this is a bad default for
   machines with more than 100 cores
 - bit-by-bit identical chrootless mode

0.8.0 (2021-09-21)
------------------

 - allow running inside chroot in root mode
 - allow running without /dev, /sys or /proc
 - new --format=null which gets automatically selected if the output is
   /dev/null and doesn't produce a tarball or other permanent output
 - allow ASCII-armored keyrings (requires gnupg >= 2.2.8)
 - run zstd with --threads=0
 - tarfilter: add --pax-exclude and --pax-include to strip extended attributes
 - add --skip=setup, --skip=update and --skip=cleanup
 - add --skip=cleanup/apt/lists and --skip=cleanup/apt/cache
 - pass extended attributes (excluding system) to tar2sqfs
 - use apt-get update -error-on=any (requires apt >= 2.1.16)
 - support Debian 11 Buster
 - use apt from outside using DPkg::Chroot-Directory (requires apt >= 2.3.7)
    * build chroots without apt (for example from buildinfo files)
    * no need to install additional packages like apt-transport-* or
      ca-certificates inside the chroot
    * no need for additional key material inside the chroot
    * possible use of file:// and copy://
 - use apt pattern to select essential set
 - write 'uninitialized' to /etc/machine-id
 - allow running in root mode without mount working, either because of missing
   CAP_SYS_ADMIN or missing /usr/bin/mount
 - make /etc/ld.so.cache under fakechroot mode bit-by-bit identical to root
   and unshare mode
 - move hooks/setup00-merged-usr.sh to hooks/merged-usr/setup00.sh
 - add gpgvnoexpkeysig script for very old snapshot.d.o timestamps with expired
   signature

0.7.5 (2021-02-06)
------------------

 - skip emulation check for extract variant
 - add new suite name trixie
 - unset TMPDIR in hooks because there is no value that works inside as well as
   outside the chroot
 - expose hook name to hooks via MMDEBSTRAP_HOOK environment variable

0.7.4 (2021-01-16)
------------------

 - Optimize mmtarfilter to handle many path exclusions
 - Set MMDEBSTRAP_APT_CONFIG, MMDEBSTRAP_MODE and MMDEBSTRAP_HOOKSOCK for hook
   scripts
 - Do not run an additional env command inside the chroot
 - Allow unshare mode as root user
 - Additional checks whether root has the necessary privileges to mount
 - Make most features work on Debian 10 Buster

0.7.3 (2020-12-02)
------------------

 - bugfix release

0.7.2 (2020-11-28)
------------------

 - check whether tools like dpkg and apt are installed at startup
 - make it possible to seed /var/cache/apt/archives with deb packages
 - if a suite name was specified, use the matching apt index to figure out the
   package set to install
 - use Debian::DistroInfo or /usr/share/distro-info/debian.csv (if available)
   to figure out the security mirror for bullseye and beyond
 - use argparse in tarfilter and taridshift for proper --help output

0.7.1 (2020-09-18)
------------------

 - bugfix release

0.7.0 (2020-08-27)
-----------------

 - the hook system (setup, extract, essential, customize and hook-dir) is made
   public and is now a documented interface
 - tarball is also created if the output is a named pipe or character special
 - add --format option to control the output format independent of the output
   filename or in cases where output is directed to stdout
 - generate ext2 filesystems if output file ends with .ext2 or --format=ext2
 - add --skip option to prevent some automatic actions from being carried out
 - implement dpkg-realpath in perl so that we don't need to run tar inside the
   chroot anymore for modes other than fakechroot and proot
 - add ready-to-use hook scripts for eatmydata, merged-usr and busybox
 - add tarfilter tool
 - use distro-info-data and debootstrap to help with suite name and keyring
   discovery
 - no longer needs to install twice when --depkgopt=path-exclude is given
 - variant=custom and hooks can be used as a debootstrap wrapper
 - use File::Find instead of "du" to avoid different results on different
   filesystems
 - many, many bugfixes and documentation enhancements

0.6.1 (2020-03-08)
------------------

 - replace /etc/machine-id with an empty file
 - fix deterministic tar with pax and xattr support
 - support deb822-style format apt sources
 - mount /sys and /proc as read-only in root mode
 - unset TMPDIR environment variable for everything running inside the chroot

0.6.0 (2020-01-16)
------------------

 - allow multiple --architecture options
 - allow multiple --include options
 - enable parallel compression with xz by default
 - add --man option
 - add --keyring option overwriting apt's default keyring
 - preserve extended attributes in tarball
 - allow running tests on non-amd64 systems
 - generate squashfs images if output file ends in .sqfs or .squashfs
 - add --dry-run/--simulate options
 - add taridshift tool

0.5.1 (2019-10-19)
------------------

 - minor bugfixes and documentation clarification
 - the --components option now takes component names as a comma or whitespace
   separated list or as multiple --components options
 - make_mirror.sh now has to be invoked manually before calling coverage.sh

0.5.0 (2019-10-05)
------------------

 - do not unconditionally read sources.list stdin anymore
     * if mmdebstrap is used via ssh without a pseudo-terminal, it will stall
       forever
     * as this is unexpected, one now has to explicitly request reading
       sources.list from stdin in situations where it's ambiguous whether
       that is requested
     * thus, the following modes of operation don't work anymore:
         $ mmdebstrap unstable /output/dir < sources.list
         $ mmdebstrap unstable /output/dir http://mirror < sources.list
     * instead, one now has to write:
         $ mmdebstrap unstable /output/dir - < sources.list
         $ mmdebstrap unstable /output/dir http://mirror - < sources.list
 - fix binfmt_misc support on docker
 - do not use qemu for architectures unequal the native architecture that can
   be used without it
 - do not copy /etc/resolv.conf or /etc/hostname if the host system doesn't
   have them
 - add --force-check-gpg dummy option
 - allow hooks to remove start-stop-daemon
 - add /var/lib/dpkg/arch in chrootless mode when chroot architecture differs
 - create /var/lib/dpkg/cmethopt for dselect
 - do not skip package installation in 'custom' variant
 - fix EDSP output for external solvers so that apt doesn't mark itself as
   Essential:yes
 - also re-exec under fakechroot if fakechroot is picked in 'auto' mode
 - chdir() before 'apt-get update' to accomodate for apt << 1.5
 - add Dir::State::Status to apt config for apt << 1.3
 - chmod 0755 on qemu-user-static binary
 - select the right mirror for ubuntu, kali and tanglu

0.4.1 (2019-03-01)
------------------

 - re-enable fakechroot mode testing
 - disable apt sandboxing if necessary
 - keep apt and dpkg lock files

0.4.0 (2019-02-23)
------------------

 - disable merged-usr
 - add --verbose option that prints apt and dpkg output instead of progress
   bars
 - add --quiet/--silent options which print nothing on stderr
 - add --debug option for even more output than with --verbose
 - add some no-op options to make mmdebstrap a drop-in replacement for certain
   debootstrap wrappers like sbuild-createchroot
 - add --logfile option which outputs to a file what would otherwise be written
   to stderr
 - add --version option

0.3.0 (2018-11-21)
------------------

 - add chrootless mode
 - add extract and custom variants
 - make testsuite unprivileged through qemu and guestfish
 - allow empty lost+found directory in target
 - add 54 testcases and fix lots of bugs as a result

0.2.0 (2018-10-03)
------------------

 - if no MIRROR was specified but there was data on standard input, then use
   that data as the sources.list instead of falling back to the default mirror
 - lots of bug fixes

0.1.0 (2018-09-24)
------------------

 - initial release
