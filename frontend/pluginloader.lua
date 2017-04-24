local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local DEFAULT_PLUGIN_PATH = "plugins"



local function sandboxPluginEventHandlers(plugin)
    for key, value in pairs(plugin) do
        if key:sub(1, 2) == "on" and type(value) == "function" then
            plugin[key] = function(self, ...)
                local ok, re = pcall(value, self, ...)
                if ok then
                    return re
                else
                    logger.err("failed to call event handler", key, re)
                    return false
                end
            end
        end
    end
end


local PluginLoader = {}

function PluginLoader:loadPlugins()
    if self.plugins then return self.plugins end

    self.plugins = {}
    local lookup_path_list = { DEFAULT_PLUGIN_PATH }
    local extra_paths = G_reader_settings:readSetting("extra_plugin_paths")
    if extra_paths then
        if type(extra_paths) == "string" then
            extra_paths = { extra_paths }
        end
        if type(extra_paths) == "table" then
            for _,extra_path in ipairs(extra_paths) do
                local extra_path_mode = lfs.attributes(extra_path, "mode")
                if extra_path_mode == "directory" and extra_path ~= DEFAULT_PLUGIN_PATH then
                    table.insert(lookup_path_list, extra_path)
                end
            end
        else
            logger.err("extra_plugin_paths config only accepts string or table value")
        end
    end

    -- keep reference to old value so they can be restored later
    local package_path = package.path
    local package_cpath = package.cpath

    for _,lookup_path in ipairs(lookup_path_list) do
        logger.info('Loading plugins from directory:', lookup_path)
        for entry in lfs.dir(lookup_path) do
            local plugin_root = lookup_path.."/"..entry
            local mode = lfs.attributes(plugin_root, "mode")
            -- valid koreader plugin directory
            if mode == "directory" and entry:find(".+%.koplugin$") then
                local mainfile = plugin_root.."/main.lua"
                package.path = string.format("%s/?.lua;%s", plugin_root, package_path)
                package.cpath = string.format("%s/lib/?.so;%s", plugin_root, package_cpath)
                local ok, plugin_module = pcall(dofile, mainfile)
                if not ok or not plugin_module then
                    logger.warn("Error when loading", mainfile, plugin_module)
                elseif type(plugin_module.disabled) ~= "boolean" or not plugin_module.disabled then
                    plugin_module.path = plugin_root
                    plugin_module.name = plugin_module.name or plugin_root:match("/(.-)%.koplugin")
                    sandboxPluginEventHandlers(plugin_module)
                    table.insert(self.plugins, plugin_module)
                else
                    logger.info("Plugin ", mainfile, " has been disabled.")
                end
                package.path = package_path
                package.cpath = package_cpath
            end
        end
    end

    -- set package path for all loaded plugins
    for _,plugin in ipairs(self.plugins) do
        package.path = string.format("%s;%s/?.lua", package.path, plugin.path)
        package.cpath = string.format("%s;%s/lib/?.so", package.cpath, plugin.path)
    end

    table.sort(self.plugins, function(v1,v2) return v1.path < v2.path end)

    return self.plugins
end

function PluginLoader:createPluginInstance(plugin, attr)
    local ok, re = pcall(plugin.new, plugin, attr)
    if ok then  -- re is a plugin instance
        return ok, re
    else  -- re is the error message
        logger.err('Failed to initialize', plugin.name, 'plugin: ', re)
        return nil, re
    end
end

return PluginLoader
