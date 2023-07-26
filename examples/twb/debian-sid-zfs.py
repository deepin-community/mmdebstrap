#!/usr/bin/python3
import argparse
import pathlib
import subprocess
import tempfile
import pathlib

__author__ = "Trent W. Buck"
__copyright__ = "Copyright © 2020 Trent W. Buck"
__license__ = "expat"

__doc__ = """ build a Debian Live image that can install Debian 11 on ZFS 2

This uses mmdebstrap to do the heavy lifting;
it can run entirely without root privileges.
It emits a USB key disk image that contains a bootable EFI ESP,
which in turn includes a bootloader (refind), kernel, ramdisk, and filesystem.squashfs.

"""

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "output_file", nargs="?", default=pathlib.Path("filesystem.img"), type=pathlib.Path
)
parser.add_argument(
    "--timezone",
    default="Australia/Melbourne",
    type=lambda s: s.split("/"),
    help='NOTE: MUST be "Area/Zone" not e.g. "UTC", for now',
)
parser.add_argument(
    "--locale", default="en_AU.UTF-8", help='NOTE: MUST end in ".UTF-8", for now'
)
args = parser.parse_args()


filesystem_img_size = "512M"  # big enough to include filesystem.squashfs + about 64M of bootloader, kernel, and ramdisk.
esp_offset = 1024 * 1024  # 1MiB
esp_label = "UEFI-ESP"  # max 8 bytes for FAT32
live_media_path = "debian-live"

with tempfile.TemporaryDirectory(prefix="debian-sid-zfs.") as td:
    td = pathlib.Path(td)
    subprocess.check_call(
        [
            "mmdebstrap",
            "--mode=unshare",
            "--variant=apt",
            '--aptopt=Acquire::http::Proxy "http://apt-cacher-ng.cyber.com.au:3142"',
            '--aptopt=Acquire::https::Proxy "DIRECT"',
            "--dpkgopt=force-unsafe-io",
            "--components=main contrib non-free",  # needed for CPU security patches
            "--include=init initramfs-tools xz-utils live-boot netbase",
            "--include=dbus",  # https://bugs.debian.org/814758
            "--include=linux-image-amd64 firmware-linux",
            # Have ZFS 2.0 support.
            "--include=zfs-dkms zfsutils-linux zfs-zed build-essential linux-headers-amd64",  # ZFS 2 support
            # Make the initrd a little smaller (41MB -> 20MB), at the expensive of significantly slower image build time.
            "--include=zstd",
            "--essential-hook=mkdir -p $1/etc/initramfs-tools/conf.d",
            "--essential-hook=>$1/etc/initramfs-tools/conf.d/zstd echo COMPRESS=zstd",
            # Be the equivalent of Debian Live GNOME
            # '--include=live-task-gnome',
            #'--include=live-task-xfce',
            # FIXME: enable this?  It makes live-task-xfce go from 1G to 16G... so no.
            #'--aptopt=Apt::Install-Recommends "true"',
            # ...cherry-pick instead
            # UPDATE: debian-installer-launcher DOES NOT WORK because we don't load crap SPECIFICALLY into /live/installer, in the ESP.
            # UPDATE: network-manager-gnome DOES NOT WORK, nor is systemd-networkd auto-started... WTF?
            #         end result is no networking.
            #'--include=live-config user-setup sudo firmware-linux haveged',
            #'--include=calamares-settings-debian udisks2',  # 300MB weirdo Qt GUI debian installer
            #'--include=xfce4-terminal',
            # x86_64 CPUs are undocumented proprietary RISC chips that EMULATE a documented x86_64 CISC ISA.
            # The emulator is called "microcode", and is full of security vulnerabilities.
            # Make sure security patches for microcode for *ALL* CPUs are included.
            # By default, it tries to auto-detect the running CPU, so only patches the CPU of the build server.
            "--include=intel-microcode amd64-microcode iucode-tool",
            "--essential-hook=>$1/etc/default/intel-microcode echo IUCODE_TOOL_INITRAMFS=yes IUCODE_TOOL_SCANCPUS=no",
            "--essential-hook=>$1/etc/default/amd64-microcode echo AMD64UCODE_INITRAMFS=yes",
            "--dpkgopt=force-confold",  # Work around https://bugs.debian.org/981004
            # DHCP/DNS/SNTP clients...
            # FIXME: use live-config ?
            "--include=libnss-resolve libnss-myhostname systemd-timesyncd",
            "--customize-hook=chroot $1 cp -alf /lib/systemd/resolv.conf /etc/resolv.conf",  # This probably needs to happen LAST
            # FIXME: fix resolv.conf to point to resolved, not "copy from the build-time OS"
            # FIXME: fix hostname & hosts to not exist, not "copy from the build-time OS"
            "--customize-hook=systemctl --root=$1 enable systemd-networkd systemd-timesyncd",  # is this needed?
            # Run a DHCP client on *ALL* ifaces.
            # Consider network "up" (start sshd and local login prompt) when *ANY* (not ALL) ifaces are up.
            "--customize-hook=>$1/etc/systemd/network/up.network printf '%s\n'  '[Match]' Name='en*' '[Network]' DHCP=yes",  # try DHCP on all ethernet ifaces
            "--customize-hook=mkdir $1/etc/systemd/system/systemd-networkd-wait-online.service.d",
            "--customize-hook=>$1/etc/systemd/system/systemd-networkd-wait-online.service.d/any-not-all.conf printf '%s\n' '[Service]' 'ExecStart=' 'ExecStart=/lib/systemd/systemd-networkd-wait-online --any'",
            # Hope there's a central smarthost SMTP server called "mail" in the local search domain.
            # FIXME: can live-config do this?
            "--include=msmtp-mta",
            "--customize-hook=>$1/etc/msmtprc printf '%s\n' 'account default' 'syslog LOG_MAIL' 'host mail' 'auto_from on'",
            # Hope there's a central RELP logserver called "logserv" in the local domain.
            # FIXME: can live-config do this?
            "--include=rsyslog-relp",
            """--customize-hook=>$1/etc/rsyslog.conf printf '%s\n' 'module(load="imuxsock")' 'module(load="imklog")' 'module(load="omrelp")' 'action(type="omrelp" target="logserv" port="2514" template="RSYSLOG_SyslogProtocol23Format")'""",
            # Run self-tests on all discoverable hard disks, and (try to) email if something goes wrong.
            "--include=smartmontools bsd-mailx",
            "--customize-hook=>$1/etc/smartd.conf echo 'DEVICESCAN -n standby,15 -a -o on -S on -s (S/../../7/00|L/../01/./01) -t -H -m root -M once'",
            # For rarely-updated, rarely-rebooted SOEs, apply what security updates we can into transient tmpfs COW.
            # This CANNOT apply kernel security updates (though it will download them).
            # This CANNOT make the upgrades persistent across reboots (they re-download each boot).
            # FIXME: Would it be cleaner to set Environment=NEEDRESTART_MODE=a in
            #        apt-daily-upgrade.service and/or
            #        unattended-upgrades.service, so
            #        needrestart is noninteractive only when apt is noninteractive?
            "--include=unattended-upgrades needrestart",
            "--customize-hook=echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | chroot $1 debconf-set-selections",
            """--customize-hook=>$1/etc/needrestart/conf.d/unattended-needrestart.conf  echo '$nrconf{restart} = "a";'""",  # https://bugs.debian.org/894444
            # Do an apt update & apt upgrade at boot time (as well as @daily).
            # The lack of /etc/machine-id causes these to be implicitly enabled.
            # FIXME: use dropin in /etc.
            "--customize-hook=>>$1/lib/systemd/system/apt-daily.service		printf '%s\n' '[Install]' 'WantedBy=multi-user.target'",
            "--customize-hook=>>$1/lib/systemd/system/apt-daily-upgrade.service	printf '%s\n' '[Install]' 'WantedBy=multi-user.target'",
            # FIXME: add support for this stuff (for the non-live final install this happens via ansible):
            #
            #            unattended-upgrades
            #            smartd
            #            networkd (boot off ANY NIC, not EVERY NIC -- https://github.com/systemd/systemd/issues/9714)
            #            refind (bootloader config)
            #            misc safety nets
            #            double-check that mmdebstrap's machine-id support works properly
            # Bare minimum to let me SSH in.
            # FIXME: make this configurable.
            # FIXME: trust a CA certificate instead -- see Zero Trust SSH, Jeremy Stott, LCA 2020 <https://youtu.be/lYzklWPTbsQ>
            # WARNING: tinysshd does not support RSA, nor MaxStartups, nor sftp (unless you also install openssh-client, which is huge).
            # FIXME: double-check no host keys are baked into the image (openssh-server and dropbear do this).
            "--include=tinysshd rsync",
            "--essential-hook=install -dm700 $1/root/.ssh",
            '--essential-hook=echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIapAZ0E0353DaY6xBnasvu/DOvdWdKQ6RQURwq4l6Wu twb@cyber.com.au (Trent W. Buck)" >$1/root/.ssh/authorized_keys',
            # Bare minimum to let me log in locally.
            # DO NOT use this on production builds!
            "--essential-hook=chroot $1 passwd --delete root",
            # Configure language (not needed to boot).
            # Racism saves a **LOT** of space -- something like 2GB for Debian Live images.
            # FIXME: use live-config instead?
            "--include=locales localepurge",
            f"--essential-hook=echo locales locales/default_environment_locale   select {args.locale}       | chroot $1 debconf-set-selections",
            f"--essential-hook=echo locales locales/locales_to_be_generated multiselect {args.locale} UTF-8 | chroot $1 debconf-set-selections",
            # FIXME: https://bugs.debian.org/603700
            "--customize-hook=chroot $1 sed -i /etc/locale.nopurge -e 's/^USE_DPKG/#ARGH#&/'",
            "--customize-hook=chroot $1 localepurge",
            "--customize-hook=chroot $1 sed -i /etc/locale.nopurge -e 's/^#ARGH#//'",
            # Removing documentation also saves a LOT of space.
            "--dpkgopt=path-exclude=/usr/share/doc/*",
            "--dpkgopt=path-exclude=/usr/share/info/*",
            "--dpkgopt=path-exclude=/usr/share/man/*",
            "--dpkgopt=path-exclude=/usr/share/omf/*",
            "--dpkgopt=path-exclude=/usr/share/help/*",
            "--dpkgopt=path-exclude=/usr/share/gnome/help/*",
            # Configure timezone (not needed to boot)`
            # FIXME: use live-config instead?
            "--include=tzdata",
            f"--essential-hook=echo tzdata tzdata/Areas                    select {args.timezone[0]} | chroot $1 debconf-set-selections",
            f"--essential-hook=echo tzdata tzdata/Zones/{args.timezone[0]} select {args.timezone[1]} | chroot $1 debconf-set-selections",
            # Do the **BARE MINIMUM** to make a USB key that can boot on X86_64 UEFI.
            # We use mtools so we do not ever need root privileges.
            # We can't use mkfs.vfat, as that needs kpartx or losetup (i.e. root).
            # We can't use mkfs.udf, as that needs mount (i.e. root).
            # We can't use "refind-install --usedefault" as that runs mount(8) (i.e. root).
            # We don't use genisoimage because
            # 1) ISO9660 must die;
            # 2) incomplete UDF 1.5+ support;
            # 3) resulting filesystem can't be tweaked after flashing (e.g. debian-live/site.dir/etc/systemd/network/up.network).
            #
            # We use refind because 1) I hate grub; and 2) I like refind.
            # If you want aarch64 or ia32 you need to install their BOOTxxx.EFI files.
            # If you want kernel+initrd on something other than FAT, you need refind/drivers_xxx/xxx_xxx.EFI.
            #
            # FIXME: with qemu in UEFI mode (OVMF), I get dumped into startup.nsh (UEFI REPL).
            #        From there, I can manually type in "FS0:\EFI\BOOT\BOOTX64.EFI" to start refind, tho.
            #        So WTF is its problem?  Does it not support fallback bootloader?
            "--include=refind parted mtools",
            "--essential-hook=echo refind refind/install_to_esp boolean false | chroot $1 debconf-set-selections",
            "--customize-hook=echo refind refind/install_to_esp boolean true  | chroot $1 debconf-set-selections",
            "--customize-hook=chroot $1 mkdir -p /boot/USB /boot/EFI/BOOT",
            "--customize-hook=chroot $1 cp /usr/share/refind/refind/refind_x64.efi /boot/EFI/BOOT/BOOTX64.EFI",
            "--customize-hook=chroot $1 cp /usr/share/refind/refind/refind.conf-sample /boot/EFI/BOOT/refind.conf",
            f"--customize-hook=chroot $1 truncate --size={filesystem_img_size} /boot/USB/filesystem.img",
            f"--customize-hook=chroot $1 parted --script --align=optimal /boot/USB/filesystem.img  mklabel gpt  mkpart {esp_label} {esp_offset}b 100%  set 1 esp on",
            f"--customize-hook=chroot $1 mformat -i /boot/USB/filesystem.img@@{esp_offset} -F -v {esp_label}",
            f"--customize-hook=chroot $1 mmd     -i /boot/USB/filesystem.img@@{esp_offset} ::{live_media_path}",
            f"""--customize-hook=echo '"Boot with default options" "boot=live live-media-path={live_media_path}"' >$1/boot/refind_linux.conf""",
            f"""--customize-hook=chroot $1 find /boot/ -xdev -mindepth 1 -maxdepth 1 -not -name filesystem.img -not -name USB -exec mcopy -vsbpm -i /boot/USB/filesystem.img@@{esp_offset} {{}} :: ';'""",
            # FIXME: copy-out doesn't handle sparseness, so is REALLY slow (about 50 seconds).
            # Therefore instead leave it in the squashfs, and extract it later.
            #  f'--customize-hook=copy-out /boot/USB/filesystem.img /tmp/',
            #  f'--customize-hook=chroot $1 rm /boot/USB/filesystem.img',
            "sid",
            td / "filesystem.squashfs",
        ]
    )

    with args.output_file.open("wb") as f:
        subprocess.check_call(
            ["rdsquashfs", "--cat=boot/USB/filesystem.img", td / "filesystem.squashfs"],
            stdout=f,
        )
    subprocess.check_call(
        [
            "mcopy",
            "-i",
            f"{args.output_file}@@{esp_offset}",
            td / "filesystem.squashfs",
            f"::{live_media_path}/filesystem.squashfs",
        ]
    )
