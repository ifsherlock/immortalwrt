local fs = require "nixio.fs"
local capabilities = {}

-- Use the installed capability, so adding or removing mdadm updates every entry.
function capabilities.raid()
    return fs.access("/sbin/mdadm", "x") == true
end

function capabilities.apk_package_manager()
    return fs.access("/usr/bin/apk", "x") == true and
        fs.access("/usr/share/luci/menu.d/luci-app-package-manager.json") == true
end

return capabilities
