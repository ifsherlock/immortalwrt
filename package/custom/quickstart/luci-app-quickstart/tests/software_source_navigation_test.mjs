import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../htdocs/luci-static/quickstart/index.js", import.meta.url), "utf8");
const start = source.indexOf("const Qa=()=>{");
const end = source.indexOf(",j3=", start);
assert.ok(start >= 0 && end > start, "software-source entry must be unique and identifiable");
const entry = source.slice(start, end) + ";globalThis.configureSource=Qa;";
for (const configs of [undefined, {}, { software_source_url: "/cgi-bin/luci/admin/system/package-manager" }]) {
    let created = 0;
    let mounted = 0;
    let unmounted = 0;
    const status = { networkInfo: "softSourceFailed" };
    const context = vm.createContext({
        window: { quickstart_configs: configs, location: { href: "" } },
        document: {
            createElement: () => { created++; return { remove: () => {} }; },
            body: { appendChild: () => {} },
        },
        xt: () => ({ mount: () => { mounted++; }, unmount: () => { unmounted++; } }),
        G3: {},
        status,
    });
    vm.runInContext(entry, context);
    const result = context.configureSource();
    if (configs?.software_source_url) {
        assert.equal(context.window.location.href, configs.software_source_url);
        assert.equal(created, 0, "APK must not instantiate the legacy source editor");
        assert.equal(mounted, 0);
        assert.equal(result, undefined);
    } else {
        assert.equal(context.window.location.href, "");
        assert.equal(created, 1);
        assert.equal(mounted, 1);
        result.Close();
        assert.equal(unmounted, 1);
    }
    assert.equal(status.networkInfo, "softSourceFailed", "navigation must not fabricate source health");
}
assert.equal((source.match(/networkInfo=="softSourceFailed"/g) || []).length, 1);
console.log("PASS: native APK source navigation, legacy dialog lifecycle, unchanged error state");
