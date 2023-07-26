#!/usr/bin/env python3

import tempfile
import pathlib
import subprocess
import debian.deb822
from collections import defaultdict


def main():
    pkglist = defaultdict(lambda: defaultdict(set))
    apttrusted = subprocess.check_output(
        "eval $(apt-config shell v Dir::Etc::Trusted/f); printf $v", shell=True
    ).decode()
    apttrustedparts = subprocess.check_output(
        "eval $(apt-config shell v Dir::Etc::TrustedParts/f); printf $v", shell=True
    ).decode()
    debci_arches = set(
        ["amd64", "arm64", "armel", "armhf", "i386", "ppc64el", "riscv64", "s390x"]
    )
    # debci_arches = set(["amd64", "i386"])
    for arch in list(debci_arches):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = pathlib.Path(tmpdir)
            (tmpdir / "etc" / "apt").mkdir(parents=True)
            (tmpdir / "var" / "cache").mkdir(parents=True)
            (tmpdir / "var" / "lib").mkdir(parents=True)
            (tmpdir / "apt.conf").write_text(
                f"""
                Apt::Architecture "{arch}";
                Apt::Architectures "{arch}";
                Dir "{tmpdir}";
                Dir::Etc::Trusted "{apttrusted}";
                Dir::Etc::TrustedParts "{apttrustedparts}";
            """
            )
            (tmpdir / "etc" / "apt" / "sources.list").write_text(
                "deb http://deb.debian.org/debian/ unstable main"
            )
            subprocess.check_call(
                ["apt-get", "update"], env={"APT_CONFIG": tmpdir / "apt.conf"}
            )
            indextargets = subprocess.check_output(
                [
                    "apt-get",
                    "indextargets",
                    "--format",
                    "$(FILENAME)",
                    "Created-By: Packages",
                    f"Architecture: {arch}",
                ],
                env={"APT_CONFIG": tmpdir / "apt.conf"},
            ).decode()
            if not indextargets.strip():
                print(f"skipping {arch}")
                debci_arches.remove(arch)
                continue
            (tmpdir / "Packages").write_bytes(
                subprocess.check_output(
                    ["/usr/lib/apt/apt-helper", "cat-file", *indextargets.splitlines()]
                )
            )
            pkgset = (
                subprocess.check_output(
                    [
                        "grep-dctrl",
                        "--no-field-names",
                        "--show-field=Package",
                        "--exact-match",
                        "(",
                        "--field=Essential",
                        "yes",
                        "--or",
                        "--field=Priority",
                        "required",
                        "--or",
                        "--field=Priority",
                        "important",
                        "--or",
                        "--field=Priority",
                        "standard",
                        ")",
                        (tmpdir / "Packages"),
                    ]
                )
                .decode()
                .splitlines()
            )
            pkgset.extend(
                [
                    "build-essential",
                    "busybox",
                    "gpg",
                    "eatmydata",
                    "usr-is-merged",
                    "usrmerge",
                ]
            )
            ceve = subprocess.check_output(
                [
                    "dose-ceve",
                    f"--deb-native-arch={arch}",
                    "-c",
                    ",".join(pkgset),
                    "-t",
                    "deb",
                    "-G",
                    "pkg",
                    "-T",
                    "deb",
                    (tmpdir / "Packages"),
                ]
            )
        for pkg in debian.deb822.Packages.iter_paragraphs(ceve):
            src = pkg.get("Source")
            if src is None:
                src = pkg["Package"]
            elif " " in src:
                src = src.split()[0]
            pkglist[src][pkg["Package"]].add(arch)
    result = []
    for src in pkglist:
        srcarches = set()
        for pkg in pkglist[src]:
            srcarches |= pkglist[src][pkg]
        representers = [pkg for pkg in pkglist[src] if pkglist[src][pkg] == srcarches]
        if not representers:
            print(f"nothing represents {src}:", pkglist[src])
            continue
        pkg = sorted(representers)[0]
        if pkglist[src][pkg] == debci_arches:
            result.append(pkg)
        else:
            result.append(f"{pkg} [{' '.join(sorted(pkglist[src][pkg]))}]")
    line = "Depends: "
    for dep in sorted(result):
        newline = line + f"{dep}, "
        if len(newline) > 79:
            print(line.removesuffix(" "))
            line = f" {dep}, "
        else:
            line = newline
    print(line.removesuffix(", "))


if __name__ == "__main__":
    main()
