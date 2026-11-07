#!/usr/bin/env python3
"""Fail CI if the kernel actually built lacks honk's documented runtime prerequisites."""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("kernel_config", type=Path, help="The built Linux kernel .config, not the firmware seed .config")
parser.add_argument("vmlinux", type=Path, help="The matching unstripped Linux vmlinux ELF")
args = parser.parse_args()
values = dict(
    line.split("=", 1)
    for line in args.kernel_config.read_text().splitlines()
    if line.startswith("CONFIG_") and "=" in line
)
required_builtin = (
    "BPF", "BPF_SYSCALL", "BPF_JIT", "CGROUPS", "CGROUP_BPF",
    "NET_SCHED", "NET_CLS_ACT", "NET_XGRESS", "NAMESPACES", "NET_NS",
    "DEBUG_INFO_BTF", "FTRACE", "FUNCTION_TRACER", "DYNAMIC_FTRACE",
)
required_enabled = (
    "NF_TABLES", "NF_TABLES_INET", "NFT_CT", "NFT_QUEUE", "NETFILTER_NETLINK_QUEUE",
)
missing = [f"CONFIG_{key}=y" for key in required_builtin if values.get(f"CONFIG_{key}") != "y"]
missing += [f"CONFIG_{key}=y/m" for key in required_enabled if values.get(f"CONFIG_{key}") not in {"y", "m"}]
if missing:
    raise SystemExit("honk kernel requirements missing: " + ", ".join(missing))
sections = subprocess.check_output(["readelf", "-SW", str(args.vmlinux)], text=True)
btf = re.search(r"\]\s+\.BTF\s+PROGBITS\s+\S+\s+\S+\s+([0-9a-fA-F]+)\b", sections)
if btf is None or int(btf.group(1), 16) == 0:
    raise SystemExit("honk kernel verification failed: vmlinux has no nonempty .BTF section")
print(f"honk kernel prerequisites verified in {args.kernel_config}")
print(f"honk native kernel BTF verified: {args.vmlinux}, {int(btf.group(1), 16)} bytes")
