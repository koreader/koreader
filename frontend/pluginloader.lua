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
    if self.enabled_plugins then return self.enabled_plugins, self.disabled_plugins end

    self.enabled_plugins = {}
    self.disabled_plugins = {}
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

    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
    if type(plugins_disabled) ~= "table" then
        plugins_disabled = {}
    end
    --permanent remove storage stats plugin (#2926)
    plugins_disabled["storagestat"] = true
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
                    if (plugins_disabled and plugins_disabled[entry:sub(1, -10)]) then
                        sandboxPluginEventHandlers(plugin_module)
                        table.insert(self.disabled_plugins, plugin_module)
                    else
                        sandboxPluginEventHandlers(plugin_module)
                        table.insert(self.enabled_plugins, plugin_module)
                    end
                else
                    logger.info("Plugin ", mainfile, " has been disabled.")
                end
                package.path = package_path
                package.cpath = package_cpath
            end
        end
    end

    -- set package path for all loaded plugins
    for _,plugin in ipairs(self.enabled_plugins) do
        package.path = string.format("%s;%s/?.lua", package.path, plugin.path)
        package.cpath = string.format("%s;%s/lib/?.so", package.cpath, plugin.path)
    end

    table.sort(self.enabled_plugins, function(v1,v2) return v1.path < v2.path end)

    return self.enabled_plugins, self.disabled_plugins
end

function PluginLoader:genPluginManagerSubItem()
    local all_plugins = {}
    local enabled_plugins, disabled_plugins = self:loadPlugins()


    for _, plugin in ipairs(enabled_plugins) do
        local element = {}
        element.name = plugin.fullname or plugin.name
        element.enable = true
        table.insert(all_plugins, element)
    end

    for _, plugin in ipairs(disabled_plugins) do
        local element = {}
        element.name = plugin.fullname or plugin.name
        element.enable = false
        if element.name ~= "storagestat" then
            table.insert(all_plugins, element)
        end
    end
    table.sort(all_plugins, function(v1, v2) return v1.name < v2.name end)

    local plugin_table = {}
    for _, plugin in ipairs(all_plugins) do
        table.insert(plugin_table, {
            text = plugin.name,
            checked_func = function()
                return plugin.enable
            end,
            callback = function()
                local plugins_disabled = G_reader_settings:readSetting("plugins_disabled") or {}
                plugins_disabled[plugin.name] = plugin.enable
                plugin.enable = not plugin.enable
                G_reader_settings:saveSetting("plugins_disabled", plugins_disabled)
            end
        })
    end
    return plugin_table
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
