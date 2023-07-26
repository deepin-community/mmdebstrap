#!/usr/bin/python3
import argparse
import pathlib
import subprocess
import tempfile
import pathlib

__author__ = "Trent W. Buck"
__copyright__ = "Copyright © 2020 Trent W. Buck"
__license__ = "expat"

__doc__ = """ build the simplest Debian Live image that can boot

This uses mmdebstrap to do the heavy lifting;
it can run entirely without root privileges.
It emits a USB key disk image that contains a bootable EFI ESP,
which in turn includes a bootloader (refind), kernel, ramdisk, and filesystem.squashfs.

NOTE: this is the simplest config possible.
      It lacks CRITICAL SECURITY AND DATA LOSS packages, such as amd64-microcode and smartd.
"""

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "output_file", nargs="?", default=pathlib.Path("filesystem.img"), type=pathlib.Path
)
args = parser.parse_args()


filesystem_img_size = "256M"  # big enough to include filesystem.squashfs + about 64M of bootloader, kernel, and ramdisk.
esp_offset = 1024 * 1024  # 1MiB
esp_label = "UEFI-ESP"  # max 8 bytes for FAT32
live_media_path = "debian-live"

with tempfile.TemporaryDirectory(prefix="debian-live-bullseye-amd64-minimal.") as td:
    td = pathlib.Path(td)
    subprocess.check_call(
        [
            "mmdebstrap",
            "--mode=unshare",
            "--variant=apt",
            '--aptopt=Acquire::http::Proxy "http://apt-cacher-ng.cyber.com.au:3142"',
            '--aptopt=Acquire::https::Proxy "DIRECT"',
            "--dpkgopt=force-unsafe-io",
            "--include=linux-image-amd64 init initramfs-tools live-boot netbase",
            "--include=dbus",  # https://bugs.debian.org/814758
            "--include=live-config iproute2 keyboard-configuration locales sudo user-setup",
            "--include=ifupdown isc-dhcp-client",  # live-config doesn't support systemd-networkd yet.
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
            f"--customize-hook=chroot $1 truncate --size={filesystem_img_size} /boot/USB/filesystem.img",
            f"--customize-hook=chroot $1 parted --script --align=optimal /boot/USB/filesystem.img  mklabel gpt  mkpart {esp_label} {esp_offset}b 100%  set 1 esp on",
            f"--customize-hook=chroot $1 mformat -i /boot/USB/filesystem.img@@{esp_offset} -F -v {esp_label}",
            f"--customize-hook=chroot $1 mmd     -i /boot/USB/filesystem.img@@{esp_offset} ::{live_media_path}",
            f"""--customize-hook=echo '"Boot with default options" "boot=live live-media-path={live_media_path}"' >$1/boot/refind_linux.conf""",
            # NOTE: find sidesteps the "glob expands before chroot applies" problem.
            f"""--customize-hook=chroot $1 find -O3 /boot/ -xdev -mindepth 1 -maxdepth 1 -regextype posix-egrep -iregex '.*/(EFI|refind_linux.conf|vmlinuz.*|initrd.img.*)' -exec mcopy -vsbpm -i /boot/USB/filesystem.img@@{esp_offset} {{}} :: ';'""",
            # FIXME: copy-out doesn't handle sparseness, so is REALLY slow (about 50 seconds).
            # Therefore instead leave it in the squashfs, and extract it later.
            #  f'--customize-hook=copy-out /boot/USB/filesystem.img /tmp/',
            #  f'--customize-hook=chroot $1 rm /boot/USB/filesystem.img',
            "bullseye",
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
