const PROBE_TIMEOUT_MS = 8000;
const PROBE_SCOPE = "base-index-reachability";

async function readSourceStatus() {
    const url = window.quickstart_configs.source_probe_url;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);
    try {
        const response = await fetch(url, {
            credentials: "same-origin",
            cache: "no-store",
            signal: controller.signal,
            headers: { Accept: "application/json" },
        });
        if (!response.ok) throw new Error(`Source probe HTTP ${response.status}`);
        const body = await response.json();
        const result = body.result;
        if (body.success !== 0 || !result || result.scope !== PROBE_SCOPE ||
            !["netSuccess", "softSourceFailed"].includes(result.networkInfo) ||
            !Number.isFinite(result.checked_at)) {
            throw new Error("Invalid source probe response");
        }
        return result;
    } finally {
        clearTimeout(timeout);
    }
}

export async function quickstartNetworkStatus(getNetworkStatus) {
    // Network parameters stay with the existing backend; only this probe owns
    // the displayed health result. Never reuse its legacy signature-file check.
    const [response, probe] = await Promise.all([
        getNetworkStatus(),
        readSourceStatus().catch(error => {
            console.error("QuickStart source probe unavailable", error);
            return { networkInfo: "sourceCheckFailed", reason: "probe-unavailable", scope: PROBE_SCOPE };
        }),
    ]);
    if (!response?.data?.result) throw new Error("Network status response missing");
    return {
        ...response,
        data: {
            ...response.data,
            result: { ...response.data.result, networkInfo: probe.networkInfo, sourceProbe: probe },
        },
    };
}
