local root = assert(arg[1], "source root required")
local entries, theme, running = {}, nil, true
package.preload["luci.http"] = function() return {} end
package.preload["luci.model.uci"] = function()
    return {cursor = function()
        return {get = function(_, config, section, option)
            if config == "luci" and section == "main" and option == "mediaurlbase" then
                return theme
            end
        end}
    end}
end
package.preload["luci.model.quickstart_capabilities"] = function()
    return {raid = function() return false end}
end
_G.luci = {sys = {call = function() return running and 0 or 1 end}}
_G.nixio = {fs = {access = function() return false end}}
_G._ = function(value) return value end
_G.entry = function(path, action, title, order)
    local node = {action = action, title = title, order = order}
    entries[table.concat(path, "/")] = node
    return node
end
_G.template = function(path) return {type = "template", path = path} end
_G.call = function(name) return {type = "call", name = name} end
_G.post = _G.call
assert(loadfile(root .. "/luasrc/controller/quickstart.lua"))()
local controller = package.loaded["luci.controller.quickstart"]
for _, name in ipairs({"vantage", "argon", "neobird", "kucat", "bootstrap"}) do
    theme, entries = "/luci-static/" .. name, {}
    controller.index()
    local home = assert(entries["admin/quickstart"])
    assert(home.title == (name ~= "vantage" and "QuickStart" or nil), name .. " home menu visibility")
    assert(home.action.type == "template" and home.action.path == "quickstart/home", "direct home route retained")
    assert(entries["admin/network_guide"].title == "NetworkGuide", "network wizard retained")
    assert(entries["admin/quickstart_source_status"], "source diagnostic route retained")
end
running, entries = false, {}
controller.index()
assert(entries["admin/quickstart"].title == nil, "stopped service has no home menu")
assert(entries["admin/quickstart"].action.name == "redirect_fallback")
local file = assert(io.open(root .. "/root/usr/share/luci/menu.d/luci-app-quickstart.json"))
local menu = file:read("*a")
file:close()
assert(not menu:find('"title"'), "static route must not override theme-dependent title")
assert(menu:find('"quickstart/home"'), "static route remains available")
print("PASS: five theme menu variants, direct home, wizard and diagnostic routes, stopped service")
