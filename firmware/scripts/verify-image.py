#!/usr/bin/env python3
"""Audit real x86 firmware artifacts, installed packages, and the compiled kernel."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

REQUIRED_PACKAGES = (
    "apk-openssl", "nikki", "luci-app-nikki", "mihomo-meta", "netdata",
    "honk", "luci-app-honk", "udpxy", "luci-app-udpxy", "luci-theme-argon", "kmod-igc",
    "luci-theme-neobird", "luci-theme-vantage", "luci-app-vantage",
)
FORBIDDEN_PACKAGES = ("opkg", "mihomo-alpha")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def decompress_image(source, destination):
    """Validate the gzip CRC while allowing documented fwtool trailers after gzip."""
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
    trailing = b""
    with source.open("rb") as incoming, destination.open("wb") as outgoing:
        while chunk := incoming.read(1024 * 1024):
            if decoder.eof:
                trailing += chunk
                if len(trailing) > 1024 * 1024:
                    raise ValueError(f"{source.name}: excessive gzip trailing data")
                continue
            pending = chunk
            while pending:
                outgoing.write(decoder.decompress(pending, 1024 * 1024))
                pending = decoder.unconsumed_tail
                if decoder.eof:
                    trailing = decoder.unused_data
                    break
        if not decoder.eof:
            raise ValueError(f"{source.name}: incomplete gzip stream")
    # fwtool appends one or more payload + 16-byte big-endian trailer records.
    extra_bytes = len(trailing)
    while trailing:
        if len(trailing) < 16:
            raise ValueError(f"{source.name}: unrecognized gzip trailing data")
        magic, _crc, kind, size = struct.unpack(">IIB3xI", trailing[-16:])
        if magic != 0x46577830 or kind not in (0, 1) or not 16 <= size <= len(trailing):
            raise ValueError(f"{source.name}: invalid fwtool trailer")
        trailing = trailing[:-size]
    return {"uncompressed_bytes": destination.stat().st_size, "fwtool_trailing_bytes": extra_bytes}


def inspect_disk(path, filesystem, efi):
    with path.open("rb") as stream:
        mbr = stream.read(512)
        if len(mbr) != 512 or mbr[510:] != b"\x55\xaa":
            raise ValueError(f"{path.name}: invalid boot sector")
        if efi:
            header = stream.read(512)
            if header[:8] != b"EFI PART":
                raise ValueError(f"{path.name}: missing GPT header")
            table_lba = struct.unpack_from("<Q", header, 72)[0]
            count, entry_size = struct.unpack_from("<II", header, 80)
            if not 2 <= count <= 4096 or not 128 <= entry_size <= 4096:
                raise ValueError(f"{path.name}: invalid GPT partition table")
            stream.seek(table_lba * 512 + entry_size)
            root_entry = stream.read(entry_size)
            root_lba = struct.unpack_from("<Q", root_entry, 32)[0]
        else:
            if mbr[450] == 0xEE:
                raise ValueError(f"{path.name}: expected BIOS MBR, found protective GPT MBR")
            root_lba = struct.unpack_from("<I", mbr, 446 + 16 + 8)[0]
        if root_lba == 0 or root_lba * 512 >= path.stat().st_size:
            raise ValueError(f"{path.name}: invalid root partition offset")
        stream.seek(root_lba * 512 + (1080 if filesystem == "ext4" else 0))
        expected = b"\x53\xef" if filesystem == "ext4" else b"hsqs"
        if stream.read(len(expected)) != expected:
            raise ValueError(f"{path.name}: root partition is not {filesystem}")
    return {"partition_table": "gpt" if efi else "mbr", "root_filesystem": filesystem}


def unique(paths, description):
    matches = sorted(path for path in paths if path.is_file())
    if len(matches) != 1:
        raise ValueError(f"expected one {description}, found {len(matches)}: {matches}")
    return matches[0]


def audit(args, report):
    target = args.target_dir.resolve()
    manifests = sorted(target.glob("*.manifest"))
    if not manifests:
        raise ValueError("no firmware package manifest found")
    report["manifests"] = []
    for manifest in manifests:
        packages = {}
        for line in manifest.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            name, separator, version = line.partition(" - ")
            if not separator or not name or not version:
                raise ValueError(f"invalid package manifest line in {manifest.name}: {line!r}")
            packages[name] = version
        missing = sorted(set(REQUIRED_PACKAGES) - packages.keys())
        forbidden = sorted(set(FORBIDDEN_PACKAGES) & packages.keys())
        record = {"file": manifest.name, "package_count": len(packages), "required_versions": {
            name: packages.get(name) for name in REQUIRED_PACKAGES
        }, "missing": missing, "forbidden": forbidden}
        report["manifests"].append(record)
        if missing or forbidden:
            raise ValueError(f"{manifest.name}: missing={missing}, forbidden={forbidden}")
    kernel_dir = args.kernel_dir
    if kernel_dir is None:
        config = unique(Path("build_dir").glob("target-*/linux-x86_64/linux-*/.config"), "built x86 Linux configuration")
        kernel_dir = config.parent
    else:
        config = kernel_dir / ".config"
    validator = Path(__file__).with_name("verify-honk-kernel.py")
    result = subprocess.run([sys.executable, str(validator), str(config), str(kernel_dir / "vmlinux")],
                            text=True, capture_output=True)
    report["kernel"] = {"validator_exit": result.returncode, "output": result.stdout, "stderr": result.stderr}
    if result.returncode:
        raise ValueError("compiled kernel verification failed: " + result.stdout + result.stderr)
    report["images"] = []
    report["qcow2"] = []
    with tempfile.TemporaryDirectory(prefix="firmware-image-audit-") as temp:
        for filesystem in ("squashfs", "ext4"):
            for efi in (False, True):
                suffix = "-efi" if efi else ""
                compressed = unique(target.glob(f"*-{filesystem}-combined{suffix}.img.gz"), f"{filesystem} {'EFI' if efi else 'BIOS'} gzip image")
                raw = Path(temp) / "image.raw"
                record = {"file": compressed.name, "compressed_bytes": compressed.stat().st_size}
                record.update(decompress_image(compressed, raw))
                record.update(inspect_disk(raw, filesystem, efi))
                report["images"].append(record)
                raw.unlink()
        for compressed in sorted(set(target.glob("*.qcow2")) | set(target.glob("*.qcow2.gz"))):
            image = compressed
            record = {"file": compressed.name}
            if compressed.suffix == ".gz":
                image = Path(temp) / "image.qcow2"
                record.update(decompress_image(compressed, image))
            result = subprocess.run(["qemu-img", "check", "-f", "qcow2", str(image)], text=True, capture_output=True)
            record.update({"check_exit": result.returncode, "output": result.stdout, "stderr": result.stderr})
            report["qcow2"].append(record)
            if result.returncode:
                raise ValueError(f"{compressed.name}: qemu-img integrity check failed: {result.stderr}")
            if image != compressed:
                image.unlink()
    report["files"] = []
    for artifact in sorted(target.iterdir()):
        if artifact.is_file() and artifact.name != "sha256sums":
            report["files"].append({"file": artifact.name, "bytes": artifact.stat().st_size, "sha256": sha256(artifact)})
    checksums = "".join(f"{item['sha256']}  {item['file']}\n" for item in report["files"])
    (args.output_dir / "SHA256SUMS").write_text(checksums, encoding="utf-8")
    report["status"] = "passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-dir", type=Path, default=Path("bin/targets/x86/64"))
    parser.add_argument("--kernel-dir", type=Path, help="Built Linux directory with .config and vmlinux; otherwise require one unique x86 build")
    parser.add_argument("--output-dir", type=Path, default=Path("build-audit"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {"status": "failed", "scope": "compiled image artifacts; no production network validation"}
    try:
        audit(args, report)
    except (OSError, ValueError, zlib.error, struct.error) as error:
        report["error"] = str(error)
        print(f"Firmware artifact audit FAILED: {error}", file=sys.stderr)
        return 1
    finally:
        (args.output_dir / "image-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Firmware artifact audit passed: {len(report['images'])} boot images, {len(report['manifests'])} manifests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
