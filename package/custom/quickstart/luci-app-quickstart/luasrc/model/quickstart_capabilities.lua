local fs = require "nixio.fs"
local capabilities = {}

-- Use the installed capability, so adding or removing mdadm updates every entry.
function capabilities.raid()
    return fs.access("/sbin/mdadm", "x") == true
end

return capabilities
