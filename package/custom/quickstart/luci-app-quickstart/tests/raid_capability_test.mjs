import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../htdocs/luci-static/quickstart/index.js", import.meta.url), "utf8");
const helper = source.match(/^function quickstartHasRaid\(\).*$/m)?.[0];
assert.ok(helper.startsWith("function quickstartHasRaid()"));
const pickerStart = source.indexOf("const f=yield Promise.all([");
assert.notEqual(pickerStart, -1);
const picker = source.slice(pickerStart + "const f=yield ".length, source.indexOf(";try{", pickerStart));
const generators = [...source.matchAll(/function\*\(\)\{if\(!quickstartHasRaid\(\)\)return;try\{const ([kw])=yield G\.Raid\.List\.GET\(\);[\s\S]*?catch\(\1\)\{console\.log\(\1\)\}\}/g)].map(match => match[0]);
assert.equal(generators.length, 2, "dashboard and RAID-page requests must both be guarded");
const menu = source.match(/"settings-menu":V\(\(\)=>\[(quickstartHasRaid\(\)\?[\s\S]*?:D\("",!0\)),og/);
assert.ok(menu, "dashboard RAID link guard missing");
const route = source.match(/\.\.\.\(quickstartHasRaid\(\)\?\[\{name:"RaidPage"[\s\S]*?component:by\}\]:\[\]\)/);
assert.ok(route, "RAID route guard missing");

for (const features of [undefined, [], ["raid"]]) {
    const enabled = Array.isArray(features) && features.includes("raid");
    let diskCalls = 0;
    let raidCalls = 0;
    const response = { data: { result: { disks: ["raid-device"] } } };
    const context = vm.createContext({
        window: { quickstart_features: features },
        G: {
            Nas: { Disk: { Status: { GET: () => { diskCalls++; return Promise.resolve("disk-status"); } } } },
            Raid: { List: { GET: () => { raidCalls++; return Promise.resolve(response); } } },
        },
        l: { raidList: null, disksList: [] },
        console: { log: error => { throw error; } },
        ag: { href: "/cgi-bin/luci/admin/nas/raid" },
        t: (tag, attrs, children) => ({ tag, attrs, children }),
        e: value => value,
        n: value => value,
        i: value => value,
        D: () => null,
        by: "raid-component",
    });
    vm.runInContext(helper, context);
    const results = await vm.runInContext(picker, context);
    assert.equal(diskCalls, 1);
    assert.equal(raidCalls, Number(enabled));
    assert.equal(results.length, enabled ? 2 : 1, "disabled RAID must not produce a fabricated response");
    for (const body of generators) {
        const before = raidCalls;
        const iterator = vm.runInContext(`(${body})()`, context);
        const step = iterator.next();
        assert.equal(step.done, !enabled);
        assert.equal(raidCalls - before, Number(enabled));
        if (enabled) assert.equal(iterator.next(await step.value).done, true);
    }
    assert.equal(vm.runInContext(menu[1], context) !== null, enabled);
    assert.equal(vm.runInContext(`[${route[0]}]`, context).length, Number(enabled));
}

const failure = new Error("disk request failed");
const context = vm.createContext({
    window: { quickstart_features: [] },
    G: { Nas: { Disk: { Status: { GET: () => Promise.reject(failure) } } } },
});
vm.runInContext(helper, context);
await assert.rejects(vm.runInContext(picker, context), error => error === failure);
console.log("PASS: RAID capability absent/disabled/enabled; all three request sites, link, route and error propagation");
