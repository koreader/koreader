--[[--
Allows extending KOReader through plugins.

Plugins will be sourced from DEFAULT_PLUGIN_PATH. If set, extra_plugin_paths
is also used. Directories are considered plugins if the name matches
".+%.koplugin".

Running with debug turned on will log stacktraces for event handlers.
Plugins are controlled by the following settings.

- plugins_disabled
- extra_plugin_paths

@module PluginLoader
]]
local dbg = require("dbg")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local DEFAULT_PLUGIN_PATH = "plugins"

local DEPRECATION_MESSAGES = {
    remove = _("This plugin is unmaintained and will be removed soon."),
    feature = _("The following features are unmaintained and will be removed soon:"),
}

local function isProvider(name)
    return name:sub(1, 8) == "provider"
end

local function sortProvidersFirst(v1, v2)
    if isProvider(v1.name) and isProvider(v2.name) then
        return v1.path < v2.path
    elseif isProvider(v1.name) then
        return true
    elseif isProvider(v2.name) then
        return false
    else
        return v1.path < v2.path
    end
end

local function deprecationFmt(field)
    local s
    if type(field) == "table" then
        local f1, f2 = DEPRECATION_MESSAGES[field[1]], field[2]
        if not f2 then
            s = string.format("%s", f1)
        else
            s = string.format("%s: %s", f1, f2)
        end
    end
    if not s then
        return nil, ""
    end
    return true, s
end

-- Deprecated plugins are still available, but show a hint about deprecation.
local function getMenuTable(plugin)
    local t = {}
    t.name = plugin.name
    t.fullname = string.format("%s%s", plugin.fullname or plugin.name,
        plugin.deprecated and " (" .. _("outdated") .. ")" or "")

    local deprecated, message = deprecationFmt(plugin.deprecated)
    t.description = string.format("%s%s", plugin.description,
        deprecated and "\n\n" .. message or "")
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

function PluginLoader:_discover()
    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
    if type(plugins_disabled) ~= "table" then
        plugins_disabled = {}
    end

    local discovered = {}
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
    for _, lookup_path in ipairs(lookup_path_list) do
        logger.info("Looking for plugins in directory:", lookup_path)
        for entry in lfs.dir(lookup_path) do
            local plugin_root = lookup_path.."/"..entry
            local mode = lfs.attributes(plugin_root, "mode")
            -- valid koreader plugin directory
            if mode == "directory" and entry:find(".+%.koplugin$") then
                local mainfile = plugin_root.."/main.lua"
                local metafile = plugin_root.."/_meta.lua"
                local disabled = false
                if plugins_disabled and plugins_disabled[entry:sub(1, -10)] then
                    mainfile = metafile
                    disabled = true
                end
                local __, name = util.splitFilePathName(plugin_root)

                table.insert(discovered, {
                    ["main"] = mainfile,
                    ["meta"] = metafile,
                    ["path"] = plugin_root,
                    ["disabled"] = disabled,
                    ["name"] = name,
                })
            end
        end
    end
    return discovered
end

local LoaderSandbox = { mt = {} }

function LoaderSandbox.new()
    local t = {
        env = getfenv(1),
        log_stacktrace = dbg.is_on,
    }
    return setmetatable(t, LoaderSandbox)
end

function LoaderSandbox:load_path(plugin, path)
    -- use loadfile as it gives us errors while compiling the plugin script
    local chunk, err = loadfile(path)
    if not chunk then
        logger.err("An error occurred while loading a plugin:\n"..err)
        return chunk, err
    end
    local plugin_env = {}
    plugin_env = setmetatable(plugin_env, { __index = self.env })

    local function plugin_require (modulename)
        -- Dynamically inject the plugin path in the package table.
        -- Then we restore it after require is done.
        --
        -- This is necessary because require is a C function and setfenv
        -- does not support C functions.
        local env_path = self.env.package.path
        local env_cpath = self.env.package.cpath
        self.env.package.path  = string.format("%s/?.lua;%s", plugin.path, self.env.package.path)
        self.env.package.cpath = string.format("%s/lib/?.so;%s", plugin.path, self.env.package.cpath)
        local ok, re = pcall(self.env.require, modulename)
        self.env.package.path  = env_path
        self.env.package.cpath = env_cpath
        if ok then
            return re
        else
            error(re, 2)
        end
    end

    -- NOTE override require in plugin environment. This enables
    -- using require both as load time and runtime
    plugin_env.require = plugin_require

    chunk = setfenv(chunk, plugin_env)

    -- execute the chunk and get back a module for the plugin
    local ok, re
    if self.log_stacktrace then
        local traceback = function(plugin_err)
             -- do not print 2 topmost entries in traceback. The first is this local function
             -- and the second is the `load_path` method of LoaderSandbox.
             logger.err("An error occurred while executing a plugin:\n"..plugin_err.."\n"..debug.traceback(plugin.name..":"..path, 2))
        end
        ok, re = xpcall(chunk, traceback)
    else
        ok, re = pcall(chunk)
        if not ok then
            logger.err("An error occurred while executing a plugin:\n"..re)
        end
    end
    return ok, re
end

function PluginLoader:_load(t)
    -- keep reference to old value so they can be restored later

    local loader = LoaderSandbox.new()

    for _, v in ipairs(t) do
        local ok, plugin_module = LoaderSandbox.load_path(loader, v, v.main)
        -- error happened and the loader logged it, bail
        if not ok then goto continue end
        -- plugin's main.lua does has returned no value
        if not plugin_module then
            logger.warn("Plugin "..v.name..": "..v.main.." did not return a non-nil value.")
            goto continue
        end

        -- no error and plugin's main.lua returned a non-nil value
        if type(plugin_module.disabled) ~= "boolean" or not plugin_module.disabled then
            plugin_module.path = v.path
            plugin_module.name = v.name or v.path:match("/(.-)%.koplugin")

            if v.disabled then
                table.insert(self.disabled_plugins, plugin_module)
            else
                local plugin_meta_ok, plugin_meta_module = LoaderSandbox.load_path(loader, v, v.meta)
                if plugin_meta_ok and plugin_meta_module then
                    for k, module in pairs(plugin_meta_module) do
                        plugin_module[k] = module
                    end
                end
                sandboxPluginEventHandlers(plugin_module)
                table.insert(self.enabled_plugins, plugin_module)
                logger.dbg("Plugin loaded", v.name)
            end
        end
        ::continue::
    end
end


function PluginLoader:loadPlugins()
    if self.enabled_plugins then return self.enabled_plugins, self.disabled_plugins end

    self.enabled_plugins = {}
    self.disabled_plugins = {}
    self.loaded_plugins = {}

    local t = self:_discover()
    table.sort(t, sortProvidersFirst)
    self:_load(t)
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
            table.insert(self.all_plugins, element)
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
                    self.show_info = false
                    UIManager:askForRestart()
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
        logger.err("Failed to initialize", plugin.name, "plugin:", re)
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
