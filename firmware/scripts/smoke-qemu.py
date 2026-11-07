#!/usr/bin/env python3
"""Boot a disposable x86 firmware disk under TCG without any network interface."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zlib


def image_helpers():
    spec = importlib.util.spec_from_file_location("firmware_image_audit", Path(__file__).with_name("verify-image.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def await_shell(child, timeout, pexpect):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = child.expect([
            r"(?m)^root@[^\r\n]*[#] ?$", r"Please press Enter to activate this console",
            r"(?m)(?:^|\r?\n)[^\r\n]* login: ?$", r"[Pp]assword:",
            r"Kernel panic|not syncing:|No bootable device", pexpect.EOF, pexpect.TIMEOUT,
        ], timeout=min(10, max(1, deadline - time.monotonic())))
        if found == 0:
            return
        if found == 1:
            child.sendline("")
        elif found == 2:
            child.sendline("root")
        elif found == 3:
            raise RuntimeError("fresh image unexpectedly requests a root password")
        elif found in (4, 5):
            raise RuntimeError("QEMU boot failed or exited before reaching the root shell")
    raise RuntimeError("QEMU boot timed out before reaching the root shell")


def run_check(child, name, command, report, timeout=60):
    identifier = uuid.uuid4().hex
    marker = re.compile(r"__FW_CHECK_" + identifier + r"_EXIT:([0-9]+)__")
    # The complete marker is absent from the echoed command, so echo cannot pass a test.
    child.sendline(f"( {command} ); result=$?; printf '\\n__FW_CHECK_%s_EXIT:%s__\\n' '{identifier}' \"$result\"")
    child.expect(marker, timeout=timeout)
    code = int(child.match.group(1))
    output = child.before.replace("\r\n", "\n").strip()
    report["checks"].append({"name": name, "exit_code": code, "output": output})
    if code:
        raise RuntimeError(f"guest check failed: {name} (exit {code})")
    print(f"PASS: {name}", flush=True)


def smoke(args, report):
    try:
        import pexpect
    except ImportError as error:
        raise RuntimeError("install python3-pexpect on the Linux CI runner") from error
    qemu = shutil.which("qemu-system-x86_64")
    if qemu is None:
        raise RuntimeError("qemu-system-x86_64 is required")
    helpers = image_helpers()
    source = args.image
    if source is None:
        source = helpers.unique(args.target_dir.glob("*-squashfs-combined.img.gz"), "BIOS squashfs image")
    source = source.resolve()
    report["image"] = {"file": source.name, "sha256": helpers.sha256(source)}
    with tempfile.TemporaryDirectory(prefix="firmware-qemu-") as temp:
        disk = source
        if source.suffix == ".gz":
            disk = Path(temp) / source.stem
            report["image"].update(helpers.decompress_image(source, disk))
        disk_format = "qcow2" if disk.suffix == ".qcow2" else "raw"
        if "," in str(disk):
            raise ValueError("QEMU disk path must not contain a comma")
        command = [qemu, "-accel", "tcg", "-cpu", "max", "-m", str(args.memory), "-smp", "2",
                   "-nographic", "-monitor", "none", "-nic", "none", "-snapshot", "-no-reboot",
                   "-drive", f"file={disk},format={disk_format},if=virtio"]
        if args.uefi:
            if args.ovmf_code is None or args.ovmf_vars is None:
                raise ValueError("UEFI boot needs both --ovmf-code and --ovmf-vars")
            variables = Path(temp) / "OVMF_VARS.fd"
            shutil.copyfile(args.ovmf_vars, variables)
            command.extend(["-drive", f"if=pflash,format=raw,readonly=on,file={args.ovmf_code.resolve()}",
                            "-drive", f"if=pflash,format=raw,file={variables}"])
        elif "-efi" in source.name:
            raise ValueError("EFI images must be tested with --uefi and OVMF files")
        report["qemu"] = {"acceleration": "tcg", "network": "none", "snapshot": True,
                          "firmware": "uefi" if args.uefi else "bios", "memory_mib": args.memory}
        child = None
        with (args.output_dir / "qemu-console.log").open("w", encoding="utf-8") as console:
            try:
                child = pexpect.spawn(command[0], command[1:], encoding="utf-8", codec_errors="replace", timeout=60)
                child.logfile_read = console
                await_shell(child, args.timeout, pexpect)
                run_check(child, "root shell", "stty -echo; test \"$(id -u)\" = 0", report)
                run_check(child, "running kernel", "uname -r", report)
                run_check(child, "apk package manager", "apk --version && ! command -v opkg", report)
                for package in helpers.REQUIRED_PACKAGES:
                    run_check(child, f"package {package}", f"apk info --exists {shlex.quote(package)}", report)
                run_check(child, "no conflicting packages", "! apk info --exists opkg && ! apk info --exists mihomo-alpha", report)
                run_check(child, "native kernel BTF", "test -r /sys/kernel/btf/vmlinux && test \"$(wc -c < /sys/kernel/btf/vmlinux)\" -gt 0", report)
                run_check(child, "cgroup v2", "test -r /sys/fs/cgroup/cgroup.controllers", report)
                run_check(child, "honk executable", "honk-core --version", report)
                run_check(child, "Mihomo executable", "/usr/bin/mihomo -v", report)
                run_check(child, "Netdata executable", "/usr/sbin/netdata -v", report)
                run_check(child, "Netdata local API", "curl --fail --silent --show-error --max-time 30 --retry 5 --retry-delay 1 --retry-connrefused http://127.0.0.1:19999/api/v1/info -o /tmp/netdata-info.json && jsonfilter -i /tmp/netdata-info.json -e '@.version'", report)
                run_check(child, "LuCI files", "test -s /usr/share/rpcd/acl.d/luci-app-nikki.json && test -s /usr/share/luci/menu.d/luci-app-honk.json && test -s /usr/share/luci/menu.d/luci-app-udpxy.json && test -d /www/luci-static/argon", report)
                run_check(child, "honk disabled", "! /etc/init.d/honk enabled && ! pidof honk-core && test ! -e /sys/class/net/dae0", report)
                run_check(child, "standby proxies disabled", "! /etc/init.d/nikki enabled && ! /etc/init.d/momo enabled && ! pidof mihomo && ! pidof sing-box", report)
                for theme in ("argon", "neobird", "vantage", "kucat"):
                    command = (f"uci set luci.main.mediaurlbase='/luci-static/{theme}' && uci commit luci && "
                               "curl --fail --silent --show-error --location --max-time 30 --retry 3 --retry-connrefused "
                               "http://127.0.0.1/cgi-bin/luci/ -o /tmp/theme-page.html && "
                               f"grep -q 'luci-static/{theme}' /tmp/theme-page.html && "
                               "! grep -qi 'runtime error\\|stack traceback' /tmp/theme-page.html")
                    run_check(child, f"LuCI renders {theme}", command, report)
                run_check(child, "restore default theme", "uci set luci.main.mediaurlbase='/luci-static/argon' && uci commit luci", report)
                run_check(child, "no QEMU network adapters", "test \"$(ls /sys/class/net | grep -E '^(eth|en)' | wc -l)\" -eq 0", report)
                report["status"] = "passed"
            except (pexpect.TIMEOUT, pexpect.EOF) as error:
                raise RuntimeError(f"QEMU console {type(error).__name__}; see qemu-console.log") from error
            finally:
                if child is not None:
                    child.close(force=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, help="raw .img, .qcow2, or their gzip form; default: unique BIOS squashfs image")
    parser.add_argument("--target-dir", type=Path, default=Path("bin/targets/x86/64"))
    parser.add_argument("--output-dir", type=Path, default=Path("build-audit/smoke"))
    parser.add_argument("--timeout", type=int, default=420, help="boot timeout in seconds")
    parser.add_argument("--memory", type=int, default=1024, help="guest RAM in MiB")
    parser.add_argument("--uefi", action="store_true")
    parser.add_argument("--ovmf-code", type=Path)
    parser.add_argument("--ovmf-vars", type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {"status": "failed", "checks": [], "scope": "isolated boot and executable checks; no production traffic or proxy data-plane test"}
    try:
        smoke(args, report)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, zlib.error, struct.error) as error:
        report["error"] = str(error)
        print(f"QEMU smoke FAILED: {error}", file=sys.stderr)
        return 1
    finally:
        (args.output_dir / "qemu-smoke.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("QEMU isolated smoke passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
