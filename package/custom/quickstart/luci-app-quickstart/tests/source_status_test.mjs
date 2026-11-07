import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../htdocs/luci-static/quickstart/source-status.js", import.meta.url), "utf8");
const { quickstartNetworkStatus } = await import("data:text/javascript;base64," + Buffer.from(source).toString("base64"));
globalThis.window = { quickstart_configs: { source_probe_url: "/cgi-bin/luci/admin/quickstart_source_status" } };
const originalError = console.error;
const errors = [];
console.error = (...args) => errors.push(args);
const network = { data: { result: { networkInfo: "softSourceFailed", ipv4addr: "192.0.2.2", uptimeStamp: 123 } } };
const body = status => ({ success: 0, result: { networkInfo: status, scope: "base-index-reachability", checked_at: 100 } });
for (const status of ["netSuccess", "softSourceFailed"]) {
    globalThis.fetch = async (url, options) => {
        assert.equal(url, window.quickstart_configs.source_probe_url);
        assert.equal(options.credentials, "same-origin");
        assert.equal(options.cache, "no-store");
        return { ok: true, json: async () => body(status) };
    };
    const result = await quickstartNetworkStatus(async () => network);
    assert.equal(result.data.result.networkInfo, status);
    assert.equal(result.data.result.ipv4addr, "192.0.2.2");
    assert.equal(network.data.result.networkInfo, "softSourceFailed", "do not mutate backend data");
}
const success = { data: { result: { networkInfo: "netSuccess", ipv4addr: "192.0.2.2" } } };
for (const connectionStatus of ["dnsFailed", "netFailed"]) {
    for (const sourceStatus of ["netSuccess", "softSourceFailed"]) {
        globalThis.fetch = async () => ({ ok: true, json: async () => body(sourceStatus) });
        const result = await quickstartNetworkStatus(async () => ({ data: { result: { networkInfo: connectionStatus } } }));
        assert.equal(result.data.result.networkInfo, connectionStatus, "preserve existing DNS and offline diagnosis");
        assert.equal(result.data.result.sourceProbe.networkInfo, sourceStatus, "source status has one independent authority");
    }
}
for (const fetcher of [
    async () => { throw new Error("transport failure"); },
    async () => ({ ok: false, status: 403 }),
    async () => ({ ok: true, json: async () => { throw new Error("invalid JSON"); } }),
    async () => ({ ok: true, json: async () => ({ success: 1 }) }),
    async () => ({ ok: true, json: async () => ({ success: 0, result: { networkInfo: "netSuccess" } }) }),
    async () => ({ ok: true, json: async () => body("unexpected") }),
]) {
    globalThis.fetch = fetcher;
    const result = await quickstartNetworkStatus(async () => success);
    assert.equal(result.data.result.networkInfo, "sourceCheckFailed", "failed probe must clear old success");
    assert.equal(result.data.result.ipv4addr, "192.0.2.2", "preserve network configuration data");
}
const originalTimeout = globalThis.setTimeout;
globalThis.setTimeout = fn => originalTimeout(fn, 0);
globalThis.fetch = (_, { signal }) => new Promise((resolve, reject) => signal.addEventListener("abort", () => reject(new Error("aborted"))));
assert.equal((await quickstartNetworkStatus(async () => success)).data.result.networkInfo, "sourceCheckFailed");
globalThis.setTimeout = originalTimeout;
globalThis.fetch = async () => ({ ok: true, json: async () => body("netSuccess") });
await assert.rejects(quickstartNetworkStatus(async () => { throw new Error("backend unavailable"); }), /backend unavailable/);
await assert.rejects(quickstartNetworkStatus(async () => ({ data: {} })), /response missing/);
assert.equal(errors.length, 7, "diagnostic failures must remain visible in console");
console.error = originalError;

const bundle = readFileSync(new URL("../htdocs/luci-static/quickstart/index.js", import.meta.url), "utf8");
assert.equal((bundle.match(/quickstartNetworkStatus\(\(\)=>W/g) || []).length, 1);
assert.ok(bundle.includes('a.updateNetworkStatus({networkInfo:"sourceCheckFailed"})'), "poll errors clear stale success");
assert.ok(bundle.includes('["softSourceFailed","sourceCheckFailed"].includes(e(m).networkInfo)'), "explicit failure must render");
console.log("PASS: actual source probe, preserved DNS/offline diagnosis, seven failure paths, timeout and stale-success removal");
