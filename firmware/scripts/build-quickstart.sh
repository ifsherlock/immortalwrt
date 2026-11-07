#!/usr/bin/env bash
# Package the official static backend and LuCI application; never build firmware.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work_dir="$repo_dir/work/quickstart-sdk"
sdk_dir="$work_dir/sdk"
audit_dir="$repo_dir/quickstart-audit"
dist_dir="$repo_dir/quickstart-dist"
sdk_spec=$(python3 - "$repo_dir/firmware/sources.lock.json" <<'PY'
import json
import re
import sys
source = json.load(open(sys.argv[1]))['sources']['quickstart']
if not re.fullmatch(r'https://downloads\.immortalwrt\.org/releases/[^\s]+\.tar\.zst', source['sdk_url']):
    raise SystemExit('Unexpected SDK source')
if not re.fullmatch(r'[0-9a-f]{64}', source['sdk_sha256']):
    raise SystemExit('Invalid SDK SHA256')
print(source['sdk_url'])
print(source['sdk_sha256'])
PY
)
mapfile -t sdk_values <<< "$sdk_spec"
[[ ${#sdk_values[@]} -eq 2 ]] || { echo 'Missing SDK lock values.' >&2; exit 1; }
sdk_url=${sdk_values[0]}
sdk_sha256=${sdk_values[1]}
signing_key="$work_dir/private-key.pem"

[[ $(uname -s) == Linux ]] || { echo 'This SDK requires a Linux build host.' >&2; exit 1; }
[[ ! -e "$sdk_dir" && ! -e "$dist_dir" ]] || { echo 'Refusing to reuse an SDK or output directory.' >&2; exit 1; }
mkdir -p "$work_dir" "$audit_dir" "$sdk_dir"
trap 'rm -f "$signing_key"' EXIT
cp "$repo_dir/firmware/sources.lock.json" "$audit_dir/"
cp "$repo_dir/package/custom/quickstart/SOURCE.json" "$audit_dir/quickstart-source.json"
printf '%s\n' "SDK URL: $sdk_url" "SDK SHA256: $sdk_sha256" > "$audit_dir/sdk.txt"
git -C "$repo_dir" rev-parse HEAD > "$audit_dir/source-commit.txt"

curl --fail --location --retry 3 "$sdk_url" -o "$work_dir/sdk.tar.zst"
printf '%s  %s\n' "$sdk_sha256" "$work_dir/sdk.tar.zst" | sha256sum -c -
tar --zstd -xf "$work_dir/sdk.tar.zst" --strip-components=1 -C "$sdk_dir"

# Keep SDK dependency generation aligned with the firmware's upstream fix.
# A changed SDK must fail the patch check rather than silently omit the fix.
metadata_patch="$repo_dir/firmware/patches/001-package-metadata-provider-gates.patch"
patch --batch --forward --dry-run -d "$sdk_dir" -p1 < "$metadata_patch"
patch --batch --forward -d "$sdk_dir" -p1 < "$metadata_patch"
cp "$metadata_patch" "$audit_dir/"

# The SDK's own base feed owns its host tools. Do not substitute the firmware
# commit: these packages contain a static executable and LuCI assets, no kmods.
python3 - "$repo_dir" "$sdk_dir" <<'PY'
import json
from pathlib import Path
import re
import sys

repo, sdk = map(Path, sys.argv[1:])
sources = json.loads((repo / 'firmware/sources.lock.json').read_text())['sources']
base = [line.strip() for line in (sdk / 'feeds.conf.default').read_text().splitlines()
        if re.match(r'^src-git\s+--root=package\s+base\s+', line)]
if len(base) != 1 or not re.fullmatch(
        r'src-git\s+--root=package\s+base\s+https://github\.com/immortalwrt/immortalwrt(?:\.git)?\^[0-9a-f]{40}', base[0]):
    raise SystemExit('Expected one commit-pinned official SDK base feed')
feeds = base[:]
for name in ('packages', 'luci'):
    source = sources[name]
    if source['url'] != f'https://github.com/immortalwrt/{name}.git' or not re.fullmatch(r'[0-9a-f]{40}', source['commit']):
        raise SystemExit(f'Invalid official {name} source pin')
    feeds.append(f"src-git {name} {source['url']}^{source['commit']}")
(sdk / 'feeds.conf').write_text('\n'.join(feeds) + '\n')
PY
cp "$sdk_dir/feeds.conf" "$audit_dir/feeds.conf"
mkdir -p "$sdk_dir/package/custom/quickstart" "$sdk_dir/package/custom/compat-extras"
cp -a "$repo_dir/package/custom/quickstart/quickstart" "$repo_dir/package/custom/quickstart/luci-app-quickstart" "$sdk_dir/package/custom/quickstart/"
# Metadata only: the APKs retain these runtime dependencies for installation.
for package in luci-app-store taskd luci-lib-taskd luci-lib-xterm; do
    cp -a "$repo_dir/package/custom/compat-extras/$package" "$sdk_dir/package/custom/compat-extras/"
done

cd "$sdk_dir"
./scripts/feeds update -a
./scripts/feeds install -a
cat > .config <<'CONFIG'
CONFIG_ALL=n
CONFIG_ALL_NONSHARED=n
CONFIG_ALL_KMODS=n
CONFIG_BUILD_LOG=y
CONFIG_SIGNED_PACKAGES=y
CONFIG_PACKAGE_quickstart=m
CONFIG_PACKAGE_luci-app-quickstart=m
CONFIG_PACKAGE_luci-i18n-quickstart-zh-cn=m
# The SDK enables tar XZ support; xz has a non-selecting xz-utils prerequisite.
CONFIG_PACKAGE_xz-utils=m
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_QUICKSTART_INCLUDE_RAID=n
CONFIG_LUCI_SRCDIET=n
CONFIG_LUCI_JSMIN=n
CONFIG_LUCI_CSSTIDY=n
CONFIG
make defconfig
cp .config "$audit_dir/sdk.config"
cp tmp/.packageinfo "$audit_dir/packageinfo.txt"
python3 - <<'PY'
from pathlib import Path

values = dict(line.split('=', 1) for line in Path('.config').read_text().splitlines()
              if line.startswith('CONFIG_') and '=' in line)
for key in ('CONFIG_USE_APK', 'CONFIG_LUCI_LANG_zh_Hans'):
    if values.get(key) != 'y':
        raise SystemExit(f'Required selection missing: {key}=y')
for name in ('quickstart', 'luci-app-quickstart', 'luci-i18n-quickstart-zh-cn'):
    if values.get(f'CONFIG_PACKAGE_{name}') != 'm':
        raise SystemExit(f'Required package selection missing: {name}=m')
for key in ('ALL', 'ALL_NONSHARED', 'ALL_KMODS', 'QUICKSTART_INCLUDE_RAID', 'LUCI_SRCDIET', 'LUCI_JSMIN', 'LUCI_CSSTIDY'):
    if values.get(f'CONFIG_{key}', 'n') != 'n':
        raise SystemExit(f'Unexpected build option enabled: {key}')
PY

# include/subdir.mk exposes host/compile and full recipe-directory targets.
# NO_DEPS skips recursive builds, not Package/DEPENDS written into APK metadata.
make_options=(-j2 V=s NO_DEPS=1 LUCI_MINIFY_LUA=0 LUCI_MINIFY_JS=0 LUCI_MINIFY_CSS=0)
make "${make_options[@]}" package/feeds/base/lua/host/compile
make "${make_options[@]}" package/feeds/luci/luci-base/host/compile
make "${make_options[@]}" package/custom/quickstart/quickstart/compile
make "${make_options[@]}" package/custom/quickstart/luci-app-quickstart/compile

mkdir -p "$dist_dir/packages" "$dist_dir/keys" "$dist_dir/metadata"
for package in quickstart luci-app-quickstart luci-i18n-quickstart-zh-cn; do
    mapfile -d '' -t matches < <(find bin/packages -type f -name "${package}-[0-9]*.apk" -print0)
    [[ ${#matches[@]} -eq 1 ]] || { echo "Expected exactly one APK for $package, found ${#matches[@]}" >&2; exit 1; }
    cp "${matches[0]}" "$dist_dir/packages/"
done

openssl ecparam -name prime256v1 -genkey -noout -out "$signing_key"
chmod 600 "$signing_key"
openssl ec -in "$signing_key" -pubout -out "$dist_dir/keys/quickstart-build.pem"
apk="$sdk_dir/staging_dir/host/bin/apk"
"$apk" adbsign --sign "$signing_key" "$dist_dir"/packages/*.apk
"$apk" verify --keys-dir "$dist_dir/keys" "$dist_dir"/packages/*.apk
for package in "$dist_dir"/packages/*.apk; do
    "$apk" adbdump --format json "$package" > "$dist_dir/metadata/$(basename "$package").json"
done
python3 - "$dist_dir" <<'PY'
import json
from pathlib import Path
import re
import sys

dist = Path(sys.argv[1])
expected = {'quickstart', 'luci-app-quickstart', 'luci-i18n-quickstart-zh-cn'}
packages = {}
for path in sorted((dist / 'metadata').glob('*.json')):
    info = json.loads(path.read_text())['info']
    name = info['name']
    if name not in expected or name in packages:
        raise SystemExit(f'Unexpected or duplicate output package: {name}')
    if info['arch'] != ('x86_64' if name == 'quickstart' else 'noarch'):
        raise SystemExit(f'Unexpected architecture for {name}: {info["arch"]}')
    dependencies = json.dumps(info.get('depends', []))
    if re.search(r'mdadm|kmod-', dependencies):
        raise SystemExit(f'Unexpected RAID/kernel dependency in {name}: {dependencies}')
    required = ('shadow-useradd', 'ubus', 'uci') if name == 'quickstart' else ('luci-app-quickstart',)
    if name == 'luci-app-quickstart':
        required = ('quickstart', 'luci-app-store', 'luci-compat')
    if any(item not in dependencies for item in required):
        raise SystemExit(f'Runtime dependencies were lost from {name}: {dependencies}')
    packages[name] = info
if set(packages) != expected:
    raise SystemExit('Missing expected QuickStart APK output')
(dist / 'package-versions.json').write_text(json.dumps(packages, indent=2) + '\n')
PY
cp "$audit_dir/sources.lock.json" "$audit_dir/quickstart-source.json" "$audit_dir/sdk.txt" \
    "$audit_dir/source-commit.txt" "$audit_dir/feeds.conf" "$audit_dir/sdk.config" "$dist_dir/"
printf '%s\n' \
    'Standalone QuickStart APKs: official static backend plus LuCI and Simplified Chinese.' \
    'RAID is disabled. Runtime dependencies remain in the APK metadata and are not rebuilt here.' \
    'The SDK base source is independent of the firmware commit; no kernel or firmware image is built.' \
    'Only the public signing key is distributed. Package signatures and metadata were checked; device runtime still requires verification.' \
    > "$dist_dir/BUILD-SCOPE.txt"
echo 'QuickStart APK build, signatures and metadata checks passed.'
