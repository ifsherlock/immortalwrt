-- lua tests/sourcecheck_test.lua PACKAGE_ROOT
-- No real files, network requests, or router services are used.
local root = assert(arg[1], "package root required")
local checker = assert(loadfile(root .. "/luasrc/model/quickstart_sourcecheck.lua"))()
local tests = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    tests = tests + 1
end
local parses = {
    {"apk", "https://mirror.example/base/packages.adb\n", "https://mirror.example/base/packages.adb"},
    {"apk", "  # https://bad.example/base/packages.adb\r\n\r\n https://ok.example/base/packages.adb\r\n", "https://ok.example/base/packages.adb"},
    {"apk", "https://ok.example/luci/packages.adb\nhttps://ok.example/base/packages.adb\n", "https://ok.example/base/packages.adb"},
    {"apk", "https://ok.example/base/packages.adb.asc\n", nil},
    {"apk", "file:///etc/base/packages.adb\n", nil},
    {"apk", "https://ok.example/base/packages.adb\0\n", nil},
    {"apk", nil, nil},
    {"apk", "", nil},
    {"opkg", "src/gz immortalwrt_base https://mirror.example/base/\n", "https://mirror.example/base/Packages.gz"},
    {"opkg", "  # src/gz old_base https://bad.example/base\r\nsrc/gz immortalwrt_base https://ok.example/base\r\n", "https://ok.example/base/Packages.gz"},
    {"opkg", "src/gz immortalwrt_luci https://ok.example/luci\n", nil},
    {"opkg", "src immortalwrt_base https://ok.example/base\n", nil},
}
for index, case in ipairs(parses) do
    equal(checker.parse_feed(case[1], case[2]), case[3], "parse " .. index)
end
local _, reason = checker.parse_feed("apk", string.rep("x", 65537))
equal(reason, "config_too_large", "bounded config")

local function fixture()
    local state = {manager="apk", content="https://ok.example/base/packages.adb\n", time=1000,
        output="200\n\n0\n", calls=0, logs={}, cache=nil, save=true}
    local dependencies = {
        now=function() return state.time end,
        read_config=function() return state.manager, state.content end,
        run=function(command) state.calls=state.calls+1; state.command=command; return state.output end,
        cache_read=function() return state.cache, state.read_error end,
        cache_write=function(record)
            if not state.save then return nil, "cache_test_failure" end
            state.cache=record; return true
        end,
        log=function(message) state.logs[#state.logs+1]=message end,
    }
    return state, dependencies
end

local results = {
    {"200\n\n0\n", "netSuccess", "index_reachable", 200},
    {"206\n0\n", "netSuccess", "index_reachable", 206},
    {"404\n22\n", "softSourceFailed", "http_error", 404},
    {"500\n22\n", "softSourceFailed", "http_error", 500},
    {"204\n0\n", "softSourceFailed", "http_error", 204},
    {"000\n60\n", "softSourceFailed", "tls_error", 0},
    {"200\n28\n", "softSourceFailed", "timeout", 200},
    {"000\n6\n", "softSourceFailed", "source_dns_error", 0},
    {"000\n7\n", "softSourceFailed", "source_connect_error", 0},
    {"000\n47\n", "softSourceFailed", "redirect_error", 0},
    {"broken", "softSourceFailed", "probe_error", 0},
    {false, "softSourceFailed", "probe_error", 0},
}
for index, case in ipairs(results) do
    local state, dependencies = fixture()
    state.output = case[1]
    local result = checker.check(dependencies)
    equal(result.networkInfo, case[2], "probe state " .. index)
    equal(result.reason, case[3], "probe reason " .. index)
    equal(result.http_status, case[4], "probe HTTP " .. index)
    equal(result.scope, "base-index-reachability", "honest probe scope")
end

local state, dependencies = fixture()
checker.check(dependencies)
state.time=1089
checker.check(dependencies)
equal(state.calls, 1, "success cached for 90 seconds")
state.time=1090; state.output="404\n22\n"
equal(checker.check(dependencies).networkInfo, "softSourceFailed", "expired success replaced by failure")
state.time=1094; checker.check(dependencies)
equal(state.calls, 2, "failure cached for five seconds")
state.time=1095; state.output="206\n0\n"
equal(checker.check(dependencies).networkInfo, "netSuccess", "failure expires")
state.content="https://other.example/base/packages.adb\n"; state.output="500\n22\n"
equal(checker.check(dependencies).networkInfo, "softSourceFailed", "config change invalidates success")
equal(state.calls, 4, "config change checks immediately")
state.manager="opkg"; state.content="src/gz distro_base https://other.example/base\n"; state.output="200\n0\n"
equal(checker.check(dependencies).networkInfo, "netSuccess", "manager change invalidates cache")
equal(state.calls, 5, "manager change checks immediately")
state.time=900; state.output="broken"
equal(checker.check(dependencies).networkInfo, "softSourceFailed", "clock rollback cannot reuse success")
equal(state.calls, 6, "clock rollback checks immediately")

state, dependencies = fixture()
checker.check(dependencies)
state.cache.result.http_status=404
state.output="500\n22\n"
equal(checker.check(dependencies).networkInfo, "softSourceFailed", "inconsistent cached success rejected")
equal(state.calls, 2, "invalid cache triggers real probe")
state.time=1100
dependencies.run=function() error("fixture runner exception") end
local ran = pcall(checker.check, dependencies)
equal(ran, false, "unexpected runner error propagates instead of serving stale cache")

state, dependencies = fixture()
checker.check(dependencies)
state.content=nil
local absent = checker.check(dependencies)
equal(absent.reason, "config_unreadable", "unreadable config invalidates success")
equal(absent.networkInfo, "softSourceFailed", "no fallback on config error")
equal(state.calls, 1, "no curl without configured source")
state.content="# disabled source\n"
equal(checker.check(dependencies).reason, "base_index_not_configured", "disabled source explicit")

state, dependencies = fixture()
state.save=false; state.read_error="invalid_cache_json"
equal(checker.check(dependencies).networkInfo, "netSuccess", "cache failure does not fake probe failure")
equal(state.logs[1], "invalid_cache_json", "cache read error logged")
equal(state.logs[2], "cache_test_failure", "cache write error logged")
state.output="000\n28\n"
equal(checker.check(dependencies).networkInfo, "softSourceFailed", "uncached timeout stays failure")

state, dependencies = fixture()
state.content="https://host.example/a'$(touch${IFS}no)/base/packages.adb\n"
checker.check(dependencies)
assert(state.command:find("'\\''", 1, true), "URL quote not escaped")
assert(state.command:find("--disable", 1, true), "curlrc not disabled")
assert(state.command:find("--max-time 6", 1, true), "total timeout missing")
assert(state.command:find("--connect-timeout 3", 1, true), "connect timeout missing")
assert(state.command:find("--proto '=http,https'", 1, true), "protocol restriction missing")
assert(state.command:find("--proto-redir '=http,https'", 1, true), "redirect restriction missing")
assert(not state.command:find("--insecure", 1, true), "TLS validation disabled")
assert(not state.command:find(".asc", 1, true), "signature sidecar still probed")
equal(checker.check(dependencies).url, nil, "response contains no source URL")

-- Exercise the production cache adapter with filesystem and process doubles.
local paths, saved_records, adapter_logs = {}, {}, {}
local config = "https://ok.example/base/packages.adb\n"
local adapter_runs, adapter_uid, adapter_reads = 0, 0, 0
local fail_rename = false
local cache_directory = "/tmp/quickstart-sourcecheck"
local cache_file = cache_directory .. "/result.json"
local function nixio_mode(mode)
    -- Nixio interprets permission digits as octal, not POSIX decimal bitmasks.
    local digits = tostring(mode)
    assert(digits:match("^[0-7][0-7][0-7]$"), "invalid Nixio permission digits")
    return tonumber(digits, 8)
end
assert(not pcall(nixio_mode, 448), "fixture must reject decimal directory bitmask")
assert(not pcall(nixio_mode, 384), "fixture must reject decimal file bitmask")
package.preload["nixio.fs"] = function() return {
    access=function(path) return path == "/usr/bin/apk" end,
    lstat=function(path) return paths[path] end,
    readfile=function(path)
        if path == "/etc/apk/repositories.d/distfeeds.list" then return config end
        adapter_reads = adapter_reads + 1
        return paths[path] and paths[path].data
    end,
    mkdir=function(path, mode)
        equal(mode, "700", "explicit Nixio octal directory mode")
        assert(nixio_mode(mode) == 448, "cache directory mode is not 0700")
        paths[path]={type="dir", uid=0, modestr="rwx------"}; return true
    end,
    rename=function(from, to)
        if fail_rename then return nil end
        paths[to], paths[from] = paths[from], nil; return true
    end,
    unlink=function(path) paths[path]=nil; return true end,
} end
package.preload["nixio"] = function() return {
    getuid=function() return adapter_uid end,
    getpid=function() return 42 end,
    open_flags=function(...) return table.concat({...}, ",") end,
    syslog=function(_, message) adapter_logs[#adapter_logs+1]=message end,
    open=function(path, flags, mode)
        equal(flags, "wronly,creat,excl", "cache create is exclusive")
        equal(mode, "600", "explicit Nixio octal file mode")
        assert(nixio_mode(mode) == 384, "cache file mode is not 0600")
        if paths[path] then return nil end
        paths[path]={type="reg", uid=0, modestr="rw-------"}
        return {
            writeall=function(_, data) paths[path].data=data; return #data end,
            close=function() return true end,
        }
    end,
} end
package.preload["luci.jsonc"] = function() return {
    stringify=function(record)
        saved_records[#saved_records+1]=record; return tostring(#saved_records)
    end,
    parse=function(data) return saved_records[tonumber(data)] end,
} end
package.preload["luci.util"] = function() return {
    exec=function() adapter_runs=adapter_runs+1; return "200\n0\n" end,
} end
equal(checker.check().networkInfo, "netSuccess", "default adapter success")
assert(paths[cache_file] and not paths[cache_directory .. "/result.42"], "atomic rename did not finish")
checker.check()
equal(adapter_runs, 1, "default adapter reads persisted cache")
paths[cache_file].type="lnk"
local reads_before=adapter_reads
checker.check()
equal(adapter_reads, reads_before, "cache symlink never read")
assert(adapter_logs[#adapter_logs]:find("unsafe_cache_file", 1, true), "unsafe cache not logged")
paths[cache_directory].modestr="rwxrwxrwx"
checker.check()
assert(adapter_logs[#adapter_logs]:find("unsafe_cache_directory", 1, true), "unsafe directory not logged")
paths[cache_directory].modestr="rwx------"
config="https://changed.example/base/packages.adb\n"; fail_rename=true
checker.check()
assert(adapter_logs[#adapter_logs]:find("cache_rename_failed", 1, true), "rename failure not logged")
equal(paths[cache_directory .. "/result.42"], nil, "failed atomic write cleaned up")
adapter_uid=1000
checker.check()
assert(adapter_logs[#adapter_logs]:find("cache_requires_root", 1, true), "non-root cache write accepted")
print("PASS: " .. tests .. " source detection assertions, command bounds and quoting")
