#!/usr/bin/env python3
"""Prepare one pinned source graph. Never reads host/router configuration."""
import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)
def checkout(url, commit, path):
    if path.exists():
        raise SystemExit(f'Refusing to replace an existing checkout: {path}')
    path.mkdir(parents=True)
    run('git', '-C', str(path), 'init', '-q')
    run('git', '-C', str(path), 'remote', 'add', 'origin', url)
    run('git', '-C', str(path), 'fetch', '--depth=1', 'origin', commit)
    run('git', '-C', str(path), 'checkout', '--detach', 'FETCH_HEAD')
    actual = subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    if actual != commit:
        raise SystemExit(f'Source pin mismatch: {path}')

sources = json.loads((ROOT/'firmware/sources.lock.json').read_text())['sources']
shutil.copyfile(ROOT/'firmware/feeds.conf', ROOT/'feeds.conf')
run('./scripts/feeds', 'update', '-a')
# A package name has one owner: remove the stock definitions before metadata generation.
for relative in ['feeds/luci/themes/luci-theme-argon', 'feeds/luci/applications/luci-app-argon-config', 'feeds/packages/admin/netdata']:
    target = ROOT/relative
    if not target.is_dir():
        raise SystemExit(f'Expected stock package is missing: {relative}')
    shutil.rmtree(target)
run('./scripts/feeds','update','-i','luci','packages')
checkout(sources['argon']['url'],sources['argon']['commit'],ROOT/'package/custom/luci-theme-argon')
checkout(sources['honk']['url'],sources['honk']['commit'],ROOT/'feeds/daeuniverse/honk/src')
# A separate dashboard window also works when LuCI itself is served over HTTPS.
dashboard = ROOT/'feeds/luci/applications/luci-app-netdata/htdocs/luci-static/resources/view/netdata.js'
dashboard_text = dashboard.read_text()
old = """E('iframe', {
				'src': 'http://' + window.location.hostname + ':19999',
				'style': 'width: 100%; min-height: 1200px; border: none; border-radius: 3px; resize: vertical;'
			}, null)"""
new = """E('a', {
				'href': 'http://' + window.location.hostname + ':19999',
				'target': '_blank',
				'rel': 'noopener noreferrer',
				'class': 'cbi-button cbi-button-action'
			}, _('Open Netdata Dashboard'))"""
if dashboard_text.count(old) != 1:
    raise SystemExit('The pinned Netdata dashboard view changed; review the patch.')
dashboard.write_text(dashboard_text.replace(old,new))
run('./scripts/feeds','install','-a')
text = (ROOT/'firmware/pve-x86.config').read_text() + '\n' + (ROOT/'firmware/fragments/honk.config').read_text()
(ROOT/'.config').write_text(text)
run('make','defconfig')
run('python3','firmware/scripts/verify-config.py')
print('Pinned feeds and firmware configuration prepared.')
