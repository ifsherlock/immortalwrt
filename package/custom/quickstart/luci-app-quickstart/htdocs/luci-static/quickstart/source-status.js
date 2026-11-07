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
    // Preserve the backend's DNS/offline diagnosis. Only source reachability
    // comes from this probe; never reuse the legacy signature-file result.
    const [response, probe] = await Promise.all([
        getNetworkStatus(),
        readSourceStatus().catch(error => {
            console.error("QuickStart source probe unavailable", error);
            return { networkInfo: "sourceCheckFailed", reason: "probe-unavailable", scope: PROBE_SCOPE };
        }),
    ]);
    if (!response?.data?.result) throw new Error("Network status response missing");
    const connectionStatus = response.data.result.networkInfo;
    const connectionFailed = ["dnsFailed", "netFailed"].includes(connectionStatus);
    const networkInfo = probe.networkInfo === "sourceCheckFailed" ? "sourceCheckFailed" :
        (connectionFailed ? connectionStatus : probe.networkInfo);
    return {
        ...response,
        data: {
            ...response.data,
            result: { ...response.data.result, networkInfo, sourceProbe: probe },
        },
    };
}
