local sourcecheck = {}
local SCOPE = "base-index-reachability"
local CONFIG_LIMIT = 65536
local CACHE_DIR = "/tmp/quickstart-sourcecheck"
local CACHE_FILE = CACHE_DIR .. "/result.json"

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function http_url(value)
    return value:match("^https?://[^/%s]+/") and not value:find("[%z\1-\32\127]")
end

-- Keep the original base-feed scope; this is not package signature validation.
function sourcecheck.parse_feed(manager, content)
    if type(content) ~= "string" then return nil, "config_unreadable" end
    if #content > CONFIG_LIMIT then return nil, "config_too_large" end
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        line = trim(line)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            if manager == "apk" and http_url(line) and
                    line:match("/base/packages%.adb$") then
                return line
            end
            if manager == "opkg" then
                local name, url = line:match("^src/gz%s+(%S+)%s+(%S+)%s*$")
                if name and name:match("_base$") and http_url(url) then
                    return url:gsub("/+$", "") .. "/Packages.gz"
                end
            end
        end
    end
    return nil, "base_index_not_configured"
end

local function shellquote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function probe_command(url)
    -- Ignore curlrc so local preferences cannot disable TLS verification.
    return "curl --disable --silent --show-error --fail --location --max-redirs 5 " ..
        "--max-time 6 --connect-timeout 3 --proto '=http,https' " ..
        "--proto-redir '=http,https' --output /dev/null --write-out '%{http_code}\\n' -- " ..
        shellquote(url) .. " 2>/dev/null; printf '\\n%d\\n' \"$?\""
end

local function probe_result(output, checked_at)
    local status, code
    if type(output) == "string" then
        status, code = output:match("^(%d%d%d)%s+(%d+)%s*$")
    end
    status, code = tonumber(status), tonumber(code)
    local result = {
        networkInfo = "softSourceFailed", scope = SCOPE,
        checked_at = checked_at, reason = "probe_error", http_status = status or 0,
    }
    if code == 0 and (status == 200 or status == 206) then
        result.networkInfo, result.reason = "netSuccess", "index_reachable"
    elseif code == 28 then
        result.reason = "timeout"
    elseif code == 35 or code == 51 or code == 58 or code == 60 or code == 77 or code == 83 or code == 90 or code == 91 then
        result.reason = "tls_error"
    elseif code == 5 or code == 6 then
        result.reason = "source_dns_error"
    elseif code == 7 then
        result.reason = "source_connect_error"
    elseif code == 22 or code == 0 then
        result.reason = "http_error"
    elseif code == 47 then
        result.reason = "redirect_error"
    end
    return result
end

local function valid_cache(record, key, now)
    if type(record) ~= "table" or record.key ~= key then return false end
    local result = record.result
    if type(result) ~= "table" or result.scope ~= SCOPE or
            type(result.checked_at) ~= "number" or type(result.reason) ~= "string" or
            type(result.http_status) ~= "number" then return false end
    local success = result.networkInfo == "netSuccess"
    if not success and result.networkInfo ~= "softSourceFailed" then return false end
    if success and (result.reason ~= "index_reachable" or
            (result.http_status ~= 200 and result.http_status ~= 206)) then return false end
    local age = now - result.checked_at
    return age >= 0 and age < (success and 90 or 5)
end

local function default_dependencies()
    local fs = require "nixio.fs"
    local nixio = require "nixio"
    local json = require "luci.jsonc"
    local util = require "luci.util"
    local function private_path(path, kind, permissions)
        local info = fs.lstat(path)
        return info and info.type == kind and info.uid == 0 and info.modestr == permissions
    end
    return {
        now = os.time,
        read_config = function()
            local apk = fs.access("/usr/bin/apk", "x") or fs.access("/sbin/apk", "x")
            local manager = apk and "apk" or "opkg"
            local path = apk and "/etc/apk/repositories.d/distfeeds.list" or "/etc/opkg/distfeeds.conf"
            return manager, fs.readfile(path, CONFIG_LIMIT + 1)
        end,
        run = util.exec,
        log = function(message) nixio.syslog("warning", "QuickStart source check: " .. message) end,
        cache_read = function()
            if not fs.lstat(CACHE_DIR) then return nil end
            if not private_path(CACHE_DIR, "dir", "rwx------") then return nil, "unsafe_cache_directory" end
            if not fs.lstat(CACHE_FILE) then return nil end
            if not private_path(CACHE_FILE, "reg", "rw-------") then return nil, "unsafe_cache_file" end
            local data = fs.readfile(CACHE_FILE, CONFIG_LIMIT * 2 + 4096)
            if not data then return nil, "cache_read_failed" end
            local result = json.parse(data)
            if type(result) ~= "table" then return nil, "invalid_cache_json" end
            return result
        end,
        cache_write = function(record)
            if nixio.getuid() ~= 0 then return nil, "cache_requires_root" end
            if not fs.lstat(CACHE_DIR) then fs.mkdir(CACHE_DIR, "700") end
            if not private_path(CACHE_DIR, "dir", "rwx------") then return nil, "unsafe_cache_directory" end
            local temporary = CACHE_DIR .. "/result." .. nixio.getpid()
            local file = nixio.open(temporary, nixio.open_flags("wronly", "creat", "excl"), "600")
            if not file then return nil, "cache_create_failed" end
            local data = json.stringify(record)
            local written = file:writeall(data)
            local closed = file:close()
            if written ~= #data or not closed then
                fs.unlink(temporary)
                return nil, "cache_write_failed"
            end
            if not fs.rename(temporary, CACHE_FILE) then
                fs.unlink(temporary)
                return nil, "cache_rename_failed"
            end
            return true
        end,
    }
end

-- Dependencies are injectable for tests; the HTTP controller supplies no input.
function sourcecheck.check(dependencies)
    local io = dependencies or default_dependencies()
    local manager, content = io.read_config()
    local url, reason = sourcecheck.parse_feed(manager, content)
    local key = manager .. "\0" .. (content or "")
    local record, cache_error = io.cache_read()
    if cache_error then io.log(cache_error) end
    local now = io.now()
    if valid_cache(record, key, now) then return record.result end
    local result
    if url then
        result = probe_result(io.run(probe_command(url)), io.now())
    else
        result = {networkInfo = "softSourceFailed", scope = SCOPE,
            checked_at = now, reason = reason, http_status = 0}
    end
    local saved, error_reason = io.cache_write({key = key, result = result})
    if not saved then io.log(error_reason or "cache_write_failed") end
    return result
end

return sourcecheck
