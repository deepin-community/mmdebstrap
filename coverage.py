#!/usr/bin/env python3

from debian.deb822 import Deb822, Release
import email.utils
import os
import sys
import shutil
import subprocess
import argparse
import time
from datetime import timedelta
from collections import defaultdict
from itertools import product

have_qemu = os.getenv("HAVE_QEMU", "yes") == "yes"
have_binfmt = os.getenv("HAVE_BINFMT", "yes") == "yes"
run_ma_same_tests = os.getenv("RUN_MA_SAME_TESTS", "yes") == "yes"
use_host_apt_config = os.getenv("USE_HOST_APT_CONFIG", "no") == "yes"
cmd = os.getenv("CMD", "./mmdebstrap")

default_dist = os.getenv("DEFAULT_DIST", "unstable")
all_dists = ["oldstable", "stable", "testing", "unstable"]
default_mode = "auto"
all_modes = ["auto", "root", "unshare", "fakechroot", "chrootless"]
default_variant = "apt"
all_variants = [
    "extract",
    "custom",
    "essential",
    "apt",
    "minbase",
    "buildd",
    "-",
    "standard",
]
default_format = "auto"
all_formats = ["auto", "directory", "tar", "squashfs", "ext2", "ext4", "null"]

mirror = os.getenv("mirror", "http://127.0.0.1/debian")
hostarch = subprocess.check_output(["dpkg", "--print-architecture"]).decode().strip()

release_path = f"./shared/cache/debian/dists/{default_dist}/InRelease"
if not os.path.exists(release_path):
    print("path doesn't exist:", release_path, file=sys.stderr)
    print("run ./make_mirror.sh first", file=sys.stderr)
    exit(1)
if os.getenv("SOURCE_DATE_EPOCH") is not None:
    s_d_e = os.getenv("SOURCE_DATE_EPOCH")
else:
    with open(release_path) as f:
        rel = Release(f)
    s_d_e = str(email.utils.mktime_tz(email.utils.parsedate_tz(rel["Date"])))

separator = (
    "------------------------------------------------------------------------------"
)


def skip(condition, dist, mode, variant, fmt):
    if not condition:
        return ""
    for line in condition.splitlines():
        if not line:
            continue
        if eval(line):
            return line.strip()
    return ""


def parse_config(confname):
    config_dict = defaultdict(dict)
    config_order = list()
    all_vals = {
        "Dists": all_dists,
        "Modes": all_modes,
        "Variants": all_variants,
        "Formats": all_formats,
    }
    with open(confname) as f:
        for test in Deb822.iter_paragraphs(f):
            if "Test" not in test.keys():
                print("Test without name", file=sys.stderr)
                exit(1)
            name = test["Test"]
            config_order.append(name)
            for k in test.keys():
                v = test[k]
                if k not in [
                    "Test",
                    "Dists",
                    "Modes",
                    "Variants",
                    "Formats",
                    "Skip-If",
                    "Needs-QEMU",
                    "Needs-Root",
                    "Needs-APT-Config",
                ]:
                    print(f"Unknown field name {k} in test {name}")
                    exit(1)
                if k in all_vals.keys():
                    if v == "default":
                        print(
                            f"Setting {k} to default in Test {name} is redundant",
                            file=sys.stderr,
                        )
                        exit(1)
                    if v == "any":
                        v = all_vals[k]
                    else:
                        # else, split the value by whitespace
                        v = v.split()
                        for i in v:
                            if i not in all_vals[k]:
                                print(
                                    f"{i} is not a valid value for {k}", file=sys.stderr
                                )
                                exit(1)
                config_dict[name][k] = v
    return config_order, config_dict


def format_test(num, total, name, dist, mode, variant, fmt, config_dict):
    ret = f"({num}/{total}) {name}"
    if len(config_dict[name].get("Dists", [])) > 1:
        ret += f" --dist={dist}"
    if len(config_dict[name].get("Modes", [])) > 1:
        ret += f" --mode={mode}"
    if len(config_dict[name].get("Variants", [])) > 1:
        ret += f" --variant={variant}"
    if len(config_dict[name].get("Formats", [])) > 1:
        ret += f" --format={fmt}"
    return ret


def print_time_per_test(time_per_test, name="test"):
    print(
        f"average time per {name}:",
        sum(time_per_test.values(), start=timedelta()) / len(time_per_test),
        file=sys.stderr,
    )
    print(
        f"median time per {name}:",
        sorted(time_per_test.values())[len(time_per_test) // 2],
        file=sys.stderr,
    )
    head_tail_num = 10
    print(f"{head_tail_num} fastests {name}s:", file=sys.stderr)
    for k, v in sorted(time_per_test.items(), key=lambda i: i[1])[
        : min(head_tail_num, len(time_per_test))
    ]:
        print(f"    {k}: {v}", file=sys.stderr)
    print(f"{head_tail_num} slowest {name}s:", file=sys.stderr)
    for k, v in sorted(time_per_test.items(), key=lambda i: i[1], reverse=True)[
        : min(head_tail_num, len(time_per_test))
    ]:
        print(f"    {k}: {v}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("test", nargs="*", help="only run these tests")
    parser.add_argument(
        "-x",
        "--exitfirst",
        action="store_const",
        dest="maxfail",
        const=1,
        help="exit instantly on first error or failed test.",
    )
    parser.add_argument(
        "--maxfail",
        metavar="num",
        action="store",
        type=int,
        dest="maxfail",
        default=0,
        help="exit after first num failures or errors.",
    )
    parser.add_argument(
        "--mode",
        metavar="mode",
        help=f"only run tests with this mode (Default = {default_mode})",
    )
    parser.add_argument(
        "--dist",
        metavar="dist",
        help=f"only run tests with this dist (Default = {default_dist})",
    )
    parser.add_argument(
        "--variant",
        metavar="variant",
        help=f"only run tests with this variant (Default = {default_variant})",
    )
    parser.add_argument(
        "--format",
        metavar="format",
        help=f"only run tests with this format (Default = {default_format})",
    )
    parser.add_argument(
        "--skip", metavar="test", action="append", help="skip this test"
    )
    args = parser.parse_args()

    # copy over files from git or as distributed
    for git, dist, target in [
        ("./mmdebstrap", "/usr/bin/mmdebstrap", "mmdebstrap"),
        ("./tarfilter", "/usr/bin/mmtarfilter", "tarfilter"),
        (
            "./proxysolver",
            "/usr/lib/apt/solvers/mmdebstrap-dump-solution",
            "proxysolver",
        ),
        (
            "./ldconfig.fakechroot",
            "/usr/libexec/mmdebstrap/ldconfig.fakechroot",
            "ldconfig.fakechroot",
        ),
    ]:
        if os.path.exists(git):
            shutil.copy(git, f"shared/{target}")
        else:
            shutil.copy(dist, f"shared/{target}")
    # copy over hooks from git or as distributed
    if os.path.exists("hooks"):
        shutil.copytree("hooks", "shared/hooks", dirs_exist_ok=True)
    else:
        shutil.copytree(
            "/usr/share/mmdebstrap/hooks", "shared/hooks", dirs_exist_ok=True
        )

    # parse coverage.txt
    config_order, config_dict = parse_config("coverage.txt")

    indirbutnotcovered = set(
        [d for d in os.listdir("tests") if not d.startswith(".")]
    ) - set(config_order)
    if indirbutnotcovered:
        print(
            "test(s) missing from coverage.txt: %s"
            % (", ".join(sorted(indirbutnotcovered))),
            file=sys.stderr,
        )
        exit(1)
    coveredbutnotindir = set(config_order) - set(
        [d for d in os.listdir("tests") if not d.startswith(".")]
    )
    if coveredbutnotindir:
        print(
            "test(s) missing from ./tests: %s"
            % (", ".join(sorted(coveredbutnotindir))),
            file=sys.stderr,
        )

        exit(1)

    # produce the list of tests using the cartesian product of all allowed
    # dists, modes, variants and formats of a given test
    tests = []
    for name in config_order:
        test = config_dict[name]
        for dist, mode, variant, fmt in product(
            test.get("Dists", [default_dist]),
            test.get("Modes", [default_mode]),
            test.get("Variants", [default_variant]),
            test.get("Formats", [default_format]),
        ):
            skipreason = skip(test.get("Skip-If"), dist, mode, variant, fmt)
            if skipreason:
                tt = ("skip", skipreason)
            elif (
                test.get("Needs-APT-Config", "false") == "true" and use_host_apt_config
            ):
                tt = ("skip", "test cannot use host apt config")
            elif have_qemu:
                tt = "qemu"
            elif test.get("Needs-QEMU", "false") == "true":
                tt = ("skip", "test needs QEMU")
            elif test.get("Needs-Root", "false") == "true":
                tt = "sudo"
            elif mode == "root":
                tt = "sudo"
            else:
                tt = "null"
            tests.append((tt, name, dist, mode, variant, fmt))

    torun = []
    num_tests = len(tests)
    if args.test:
        # check if all given tests are either a valid name or a valid number
        for test in args.test:
            if test in [name for (_, name, _, _, _, _) in tests]:
                continue
            if not test.isdigit():
                print(f"cannot find test named {test}", file=sys.stderr)
                exit(1)
            if int(test) >= len(tests) or int(test) <= 0 or str(int(test)) != test:
                print(f"test number {test} doesn't exist", file=sys.stderr)
                exit(1)

        for i, (_, name, _, _, _, _) in enumerate(tests):
            # if either the number or test name matches, then we use this test,
            # otherwise we skip it
            if name in args.test:
                torun.append(i)
            if str(i + 1) in args.test:
                torun.append(i)
        num_tests = len(torun)

    starttime = time.time()
    skipped = defaultdict(list)
    failed = []
    num_success = 0
    num_finished = 0
    time_per_test = {}
    acc_time_per_test = defaultdict(list)
    for i, (test, name, dist, mode, variant, fmt) in enumerate(tests):
        if torun and i not in torun:
            continue
        print(separator, file=sys.stderr)
        print("(%d/%d) %s" % (i + 1, len(tests), name), file=sys.stderr)
        print("dist: %s" % dist, file=sys.stderr)
        print("mode: %s" % mode, file=sys.stderr)
        print("variant: %s" % variant, file=sys.stderr)
        print("format: %s" % fmt, file=sys.stderr)
        if num_finished > 0:
            currenttime = time.time()
            timeleft = timedelta(
                seconds=int(
                    (num_tests - num_finished)
                    * (currenttime - starttime)
                    / num_finished
                )
            )
            print("time left: %s" % timeleft, file=sys.stderr)
        if failed:
            print("failed: %d" % len(failed), file=sys.stderr)
        num_finished += 1
        with open("tests/" + name) as fin, open("shared/test.sh", "w") as fout:
            for line in fin:
                line = line.replace("{{ CMD }}", cmd)
                line = line.replace("{{ SOURCE_DATE_EPOCH }}", s_d_e)
                line = line.replace("{{ DIST }}", dist)
                line = line.replace("{{ MIRROR }}", mirror)
                line = line.replace("{{ MODE }}", mode)
                line = line.replace("{{ VARIANT }}", variant)
                line = line.replace("{{ FORMAT }}", fmt)
                line = line.replace("{{ HOSTARCH }}", hostarch)
                fout.write(line)
        # ignore:
        # SC2016 Expressions don't expand in single quotes, use double quotes for that.
        # SC2050 This expression is constant. Did you forget the $ on a variable?
        # SC2194 This word is constant. Did you forget the $ on a variable?
        shellcheck = subprocess.run(
            [
                "shellcheck",
                "--exclude=SC2050,SC2194,SC2016",
                "-f",
                "gcc",
                "shared/test.sh",
            ],
            check=False,
            stdout=subprocess.PIPE,
        ).stdout.decode()
        shfmt = subprocess.run(
            [
                "shfmt",
                "--posix",
                "--binary-next-line",
                "--case-indent",
                "--indent",
                "2",
                "--simplify",
                "-d",
                "shared/test.sh",
            ],
            check=False,
            stdout=subprocess.PIPE,
        ).stdout.decode()
        argv = None
        match test:
            case "qemu":
                argv = ["./run_qemu.sh"]
            case "sudo":
                argv = ["./run_null.sh", "SUDO"]
            case "null":
                argv = ["./run_null.sh"]
            case ("skip", reason):
                skipped[reason].append(
                    format_test(
                        i + 1, len(tests), name, dist, mode, variant, fmt, config_dict
                    )
                )
                print(f"skipped because of {reason}", file=sys.stderr)
                continue
        print(separator, file=sys.stderr)
        if args.skip and name in args.skip:
            print(f"skipping because of --skip={name}", file=sys.stderr)
            continue
        if args.dist and args.dist != dist:
            print(f"skipping because of --dist={args.dist}", file=sys.stderr)
            continue
        if args.mode and args.mode != mode:
            print(f"skipping because of --mode={args.mode}", file=sys.stderr)
            continue
        if args.variant and args.variant != variant:
            print(f"skipping because of --variant={args.variant}", file=sys.stderr)
            continue
        if args.format and args.format != fmt:
            print(f"skipping because of --format={args.format}", file=sys.stderr)
            continue
        before = time.time()
        proc = subprocess.Popen(argv)
        try:
            proc.wait()
        except KeyboardInterrupt:
            proc.terminate()
            proc.wait()
            break
        after = time.time()
        walltime = timedelta(seconds=int(after - before))
        formated_test_name = format_test(
            i + 1, len(tests), name, dist, mode, variant, fmt, config_dict
        )
        time_per_test[formated_test_name] = walltime
        acc_time_per_test[name].append(walltime)
        print(separator, file=sys.stderr)
        print(f"duration: {walltime}", file=sys.stderr)
        if proc.returncode != 0 or shellcheck != "" or shfmt != "":
            if shellcheck != "":
                print(shellcheck)
            if shfmt != "":
                print(shfmt)
            failed.append(formated_test_name)
            print("result: FAILURE", file=sys.stderr)
        else:
            print("result: SUCCESS", file=sys.stderr)
            num_success += 1
        if args.maxfail and len(failed) >= args.maxfail:
            break
    print(separator, file=sys.stderr)
    print(
        "successfully ran %d tests" % num_success,
        file=sys.stderr,
    )
    if skipped:
        print("skipped %d:" % sum([len(v) for v in skipped.values()]), file=sys.stderr)
        for reason, l in skipped.items():
            print(f"skipped because of {reason}:", file=sys.stderr)
            for t in l:
                print(f"    {t}", file=sys.stderr)
    if len(time_per_test) > 1:
        print_time_per_test(time_per_test)
    if len(acc_time_per_test) > 1:
        print_time_per_test(
            {
                f"{len(v)}x {k}": sum(v, start=timedelta())
                for k, v in acc_time_per_test.items()
            },
            "accumulated test",
        )
    if failed:
        print("failed %d:" % len(failed), file=sys.stderr)
        for f in failed:
            print(f, file=sys.stderr)
    currenttime = time.time()
    walltime = timedelta(seconds=int(currenttime - starttime))
    print(f"total runtime: {walltime}", file=sys.stderr)
    if failed:
        exit(1)


if __name__ == "__main__":
    main()
