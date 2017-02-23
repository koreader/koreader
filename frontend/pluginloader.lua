local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local PluginLoader = {
    plugin_path = "plugins"
}

function PluginLoader:loadPlugins()
    if self.plugins then return self.plugins end

    self.plugins = {}
    for f in lfs.dir(self.plugin_path) do
        local path = self.plugin_path.."/"..f
        local mode = lfs.attributes(path, "mode")
        -- valid koreader plugin directory
        if mode == "directory" and f:find(".+%.koplugin$") then
            local mainfile = path.."/".."main.lua"
            local package_path = package.path
            local package_cpath = package.cpath
            package.path = path.."/?.lua;"..package.path
            package.cpath = path.."/lib/?.so;"..package.cpath
            local ok, plugin_module = pcall(dofile, mainfile)
            if not ok or not plugin_module then
                logger.warn("Error when loading", mainfile, plugin_module)
            end
            if ok and plugin_module and not plugin_module.disabled then
                package.path = package_path
                package.cpath = package_cpath
                plugin_module.path = path
                plugin_module.name = plugin_module.name or path:match("/(.-)%.koplugin")
                table.insert(self.plugins, plugin_module)
            end
        end
    end

    for _,plugin in ipairs(self.plugins) do
        package.path = package.path..";"..plugin.path.."/?.lua"
        package.cpath = package.cpath..";"..plugin.path.."/lib/?.so"
    end

    table.sort(self.plugins, function(v1,v2) return v1.path < v2.path end)

    return self.plugins
end

return PluginLoader
