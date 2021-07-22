local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local DEFAULT_PLUGIN_PATH = "plugins"

-- plugin names that were removed and are no longer available.
local OBSOLETE_PLUGINS = {
    calibrecompanion = true,
    storagestat = true,
    kobolight = true,
    zsync = true,
}
-- Deprecated plugins are still available, but show a hint about deprecation.
local function getMenuTable(plugin)
    local t = {}
    t.name = plugin.name
    t.fullname = string.format("%s%s", plugin.fullname or plugin.name,
        plugin.deprecated and " (" .. _("outdated") .. ")" or "")
    t.description = string.format("%s%s", plugin.description,
        type(plugin.deprecated) == "string"  and "\n\n" .. plugin.deprecated or "")
    return t
end

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


local PluginLoader = {
    show_info = true,
    enabled_plugins = nil,
    disabled_plugins = nil,
    loaded_plugins = nil,
    all_plugins = nil,
}

function PluginLoader:loadPlugins()
    if self.enabled_plugins then return self.enabled_plugins, self.disabled_plugins end

    self.enabled_plugins = {}
    self.disabled_plugins = {}
    self.loaded_plugins = {}
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
    else
        local data_dir = require("datastorage"):getDataDir()
        if data_dir ~= "." then
            local extra_path = data_dir .. "/plugins/"
            G_reader_settings:saveSetting("extra_plugin_paths", { extra_path })
            table.insert(lookup_path_list, extra_path)
        end
    end

    -- keep reference to old value so they can be restored later
    local package_path = package.path
    local package_cpath = package.cpath

    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
    if type(plugins_disabled) ~= "table" then
        plugins_disabled = {}
    end
    --disable obsolete plugins
    for element in pairs(OBSOLETE_PLUGINS) do
        plugins_disabled[element] = true
    end
    for _, lookup_path in ipairs(lookup_path_list) do
        logger.info("Loading plugins from directory:", lookup_path)
        for entry in lfs.dir(lookup_path) do
            local plugin_root = lookup_path.."/"..entry
            local mode = lfs.attributes(plugin_root, "mode")
            -- valid koreader plugin directory
            if mode == "directory" and entry:find(".+%.koplugin$") then
                local mainfile = plugin_root.."/main.lua"
                local metafile = plugin_root.."/_meta.lua"
                if plugins_disabled and plugins_disabled[entry:sub(1, -10)] then
                    mainfile = metafile
                end
                package.path = string.format("%s/?.lua;%s", plugin_root, package_path)
                package.cpath = string.format("%s/lib/?.so;%s", plugin_root, package_cpath)
                local ok, plugin_module = pcall(dofile, mainfile)
                if not ok or not plugin_module then
                    logger.warn("Error when loading", mainfile, plugin_module)
                elseif type(plugin_module.disabled) ~= "boolean" or not plugin_module.disabled then
                    plugin_module.path = plugin_root
                    plugin_module.name = plugin_module.name or plugin_root:match("/(.-)%.koplugin")
                    if (plugins_disabled and plugins_disabled[entry:sub(1, -10)]) then
                        table.insert(self.disabled_plugins, plugin_module)
                    else
                        local ok_meta, plugin_metamodule = pcall(dofile, metafile)
                        if ok_meta and plugin_metamodule then
                            for k,v in pairs(plugin_metamodule) do plugin_module[k] = v end
                        end
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
    for _, plugin in ipairs(self.enabled_plugins) do
        package.path = string.format("%s;%s/?.lua", package.path, plugin.path)
        package.cpath = string.format("%s;%s/lib/?.so", package.cpath, plugin.path)
    end

    table.sort(self.enabled_plugins, function(v1,v2) return v1.path < v2.path end)

    return self.enabled_plugins, self.disabled_plugins
end

function PluginLoader:genPluginManagerSubItem()
    if not self.all_plugins then
        local enabled_plugins, disabled_plugins = self:loadPlugins()
        self.all_plugins = {}

        for _, plugin in ipairs(enabled_plugins) do
            local element = getMenuTable(plugin)
            element.enable = true
            table.insert(self.all_plugins, element)
        end

        for _, plugin in ipairs(disabled_plugins) do
            local element = getMenuTable(plugin)
            element.enable = false
            if not OBSOLETE_PLUGINS[element.name] then
                table.insert(self.all_plugins, element)
            end
        end

        table.sort(self.all_plugins, function(v1, v2) return v1.fullname < v2.fullname end)
    end

    local plugin_table = {}
    for __, plugin in ipairs(self.all_plugins) do
        table.insert(plugin_table, {
            text = plugin.fullname,
            checked_func = function()
                return plugin.enable
            end,
            callback = function()
                local InfoMessage = require("ui/widget/infomessage")
                local UIManager = require("ui/uimanager")
                local _ = require("gettext")
                local plugins_disabled = G_reader_settings:readSetting("plugins_disabled") or {}
                plugin.enable = not plugin.enable
                if plugin.enable then
                    plugins_disabled[plugin.name] = nil
                else
                    plugins_disabled[plugin.name] = true
                end
                G_reader_settings:saveSetting("plugins_disabled", plugins_disabled)
                if self.show_info then
                    UIManager:show(InfoMessage:new{
                        text = _("This will take effect on next restart."),
                    })
                    self.show_info = false
                end
            end,
            help_text = plugin.description,
        })
    end
    return plugin_table
end

function PluginLoader:createPluginInstance(plugin, attr)
    local ok, re = pcall(plugin.new, plugin, attr)
    if ok then  -- re is a plugin instance
        self.loaded_plugins[plugin.name] = re
        return ok, re
    else  -- re is the error message
        logger.err("Failed to initialize", plugin.name, "plugin: ", re)
        return nil, re
    end
end

--- Checks if a specific plugin is instantiated
function PluginLoader:isPluginLoaded(name)
   return self.loaded_plugins[name] ~= nil
end

--- Returns the current instance of a specific Plugin (if any)
--- (NOTE: You can also usually access it via self.ui[plugin_name])
function PluginLoader:getPluginInstance(name)
   return self.loaded_plugins[name]
end

-- *MUST* be called on destruction of whatever called createPluginInstance!
function PluginLoader:finalize()
    -- Unpin stale references
    self.loaded_plugins = {}
end

return PluginLoader
