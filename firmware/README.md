# x86/64 ImmortalWrt firmware

Build branch: `pve-x86-25.12`. Upstream base and feed revisions are recorded in
`sources.lock.json`. Run **Build PVE x86 firmware** in GitHub Actions.

This build uses the 25.12 maintenance branch, APK, the matching kernel/modules,
source-built honk v0.1.0-beta.5 as the primary proxy, Nikki v1.26.2 as a standby,
Netdata 2.11.0, and native kernel BTF. Argon v3.1.3, Kucat, Bootstrap,
NeoBird and Vantage provide switchable themes. Official feeds provide firewall4, PPPoE,
IPv6, udpxy, msd_lite, UPnP, storage, device accounting and management tools.
Selected compatibility packages retain iStore, QuickStart, Lucky, EasyTier and additional
administration pages. Binary-only package components are identified by their
recipes and fixed download hashes; firmware compilation does not imply that
every embedded executable was built from source.

The image contains no router backups, passwords, keys, subscriptions, local
addresses, or personal interface assignments. Proxy/tunnel daemons remain
disabled until the operator restores and verifies configuration. Use only one
transparent proxy owner at a time. Keep the stock firewall WAN policy.

Outputs include BIOS and EFI images in ext4/squashfs formats, QCOW2 images,
matching APK packages, manifests, source locks, license/source material and
SHA256 sums. The workflow checks requested configuration, real kernel BTF,
installed packages and an isolated QEMU boot. It cannot validate a household's
PPPoE account, physical port assignments, IPTV multicast or IPv6 ingress.

Do not restore an entire foreign firmware `/etc` over this image. Restore
network/firewall/DHCP and application settings selectively after reviewing
interface roles, firewall includes and changed configuration formats. Old IPK
packages and old kernel modules are incompatible. Keep the matching custom
kernel APKs with each image; never force-install modules from another build.

Known UI substitutions: LibreSpeed and iperf3 provide speed measurement;
nlbwmon and Netdata provide accounting; stock system/network pages and
Argon settings replace obsolete package installers and vendor-specific
optimization pages. These are functional alternatives, not a
claim of identical menus or proprietary features.

QuickStart uses the official 0.13.1 static runtime and the upstream LuCI
0.12.10 interface, with RAID as an optional build feature (disabled in this
profile). The UI advertises RAID only when mdadm is installed. Automatic
network-event handling by startdhns is disabled by the firmware defaults;
the dashboard and explicit network wizard remain available.

Run **Build QuickStart APK packages** to package QuickStart, its LuCI interface,
iStore and the Vantage dashboard with the pinned SDK. It does not rebuild the firmware or kernel. SDK versions
do not authorize mixing kernel modules between builds. Full firmware builds
include these packages; older artifacts need the separate addon installation.

iStore uses its top-level admin/store route, matching QuickStart shortcuts.
The Vantage theme shows its dashboard and hides the duplicate QuickStart home
menu. Other themes retain the QuickStart home menu without the Vantage dashboard.
QuickStart's direct home route and network wizard remain available. On APK systems,
QuickStart opens LuCI's native package manager for software source settings.
Build-only feeds without published indexes remain disabled as online sources;
their compiled packages are retained with the firmware artifacts.

QuickStart's displayed source health comes from an authenticated LuCI probe of
the configured base repository index (`packages.adb` or `Packages.gz`). The
official backend still supplies network parameters and DNS/offline diagnoses;
its legacy signature-sidecar result is not used for source health. Missing feeds, HTTP/transport errors
and TLS failures remain errors. An unavailable diagnostic clears old success.
Checks are cached for 90 seconds after success and 5 seconds after failure;
changing the source configuration invalidates the cache. This checks base-index
reachability, not every repository or package signature. The package manager's
signature verification remains unchanged.
