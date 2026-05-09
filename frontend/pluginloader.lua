--[[--
Allows extending KOReader through plugins.

Plugins will be sourced from DEFAULT_PLUGIN_PATH. If set, extra_plugin_paths
is also used. Directories are considered plugins if the name matches
".+%.koplugin".

Running with debug turned on will log stacktraces for event handlers.
Plugins are controlled by the following settings.

- plugins_disabled
- extra_plugin_paths
]]
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local DEFAULT_PLUGIN_PATH = "plugins"

local BUILTIN_PLUGINS = {
    ["archiveviewer"] = true,
    ["autodim"] = true,
    ["autostandby"] = true,
    ["autosuspend"] = true,
    ["autoturn"] = true,
    ["autowarmth"] = true,
    ["batterystat"] = true,
    ["bookshortcuts"] = true,
    ["calibre"] = true,
    ["cloudstorage"] = true,
    ["coverbrowser"] = true,
    ["coverimage"] = true,
    ["docsettingtweak"] = true,
    ["exporter"] = true,
    ["externalkeyboard"] = true,
    ["gestures"] = true,
    ["hello"] = true,
    ["hotkeys"] = true,
    ["httpinspector"] = true,
    ["japanese"] = true,
    ["keepalive"] = true,
    ["kosync"] = true,
    ["movetoarchive"] = true,
    ["newsdownloader"] = true,
    ["opds"] = true,
    ["perceptionexpander"] = true,
    ["profiles"] = true,
    ["qrclipboard"] = true,
    ["readtimer"] = true,
    ["SSH"] = true,
    ["statistics"] = true,
    ["systemstat"] = true,
    ["terminal"] = true,
    ["texteditor"] = true,
    ["timesync"] = true,
    ["vocabbuilder"] = true,
    ["wallabag"] = true,
}

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
    t.path = plugin.path
    t.fullname = string.format("%s%s", plugin.fullname or plugin.name,
        plugin.deprecated and " (" .. _("outdated") .. ")" or "")

    local deprecated, message = deprecationFmt(plugin.deprecated)
    t.description = string.format("%s%s", plugin.description,
        deprecated and "\n\n" .. message or "")
    return t
end

-- Event handlers defined by plugins are wrapped in a HandlerSandbox.
-- The purpose of the sandbox is to get meaningful stack-traces out of errors happening in plugins.
local HandlerSandbox = { mt = {} }

function HandlerSandbox.new(context, fname, f, module)
    local t = {
        context = context,
        fname = fname,
        f = f,
        log_stacktrace = dbg.is_on,
    }
    return setmetatable(t, HandlerSandbox.mt)
end

function HandlerSandbox:call(module, ...)
    -- NOTE the signature is (self, module, ...)
    -- self refers to the HandlerSandbox instance but module refers to the
    -- self parameter of the handlers
    local ok, re
    if self.log_stacktrace then
        local traceback = function(err)
             -- do not print 2 topmost entries in traceback. The first is this local function
             -- and the second is the `call` method of HandlerSandbox.
             logger.err("An error occurred while executing a handler:\n"..err.."\n"..debug.traceback(self.context.name..":"..self.fname, 2))
        end
        ok, re = xpcall(self.f, traceback, module, ...)
    else
        ok, re = pcall(self.f, module, ...)
        if not ok then logger.err("An error occurred while executing handler "..self.context.name..":"..self.fname..":\n", re) end
    end
    -- NOTE backward compatibility with previous implementation
    -- of handler wrapping that returned false on error
    if ok then
        return re
    else
        return false
    end
end

HandlerSandbox.mt.__call = HandlerSandbox.call

local function sandboxPluginEventHandlers(plugin)
    for key, value in pairs(plugin) do
        if key:sub(1, 2) == "on" and type(value) == "function" then
            plugin[key] = HandlerSandbox.new(plugin, key, value)
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
    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled", {})
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
            -- A valid KOReader plugin directory ends with .koplugin
            if mode == "directory" and entry:sub(-9) == ".koplugin" then
                local mainfile = plugin_root.."/main.lua"
                local metafile = plugin_root.."/_meta.lua"
                local plugin_name = entry:sub(1, -10)
                local disabled = false
                if plugins_disabled and plugins_disabled[plugin_name] then
                    mainfile = metafile
                    disabled = true
                end

                table.insert(discovered, {
                    ["main"] = mainfile,
                    ["meta"] = metafile,
                    ["path"] = plugin_root,
                    ["disabled"] = disabled,
                    ["name"] = plugin_name,
                })
            end
        end
    end
    return discovered
end

function PluginLoader:_load(t)
    -- keep reference to old value so they can be restored later
    local package_path = package.path
    local package_cpath = package.cpath

    local mainfile, metafile, plugin_root, disabled
    for _, v in ipairs(t) do
        mainfile = v.main
        metafile = v.meta
        plugin_root = v.path
        disabled = v.disabled
        package.path = string.format("%s/?.lua;%s", plugin_root, package_path)
        package.cpath = string.format("%s/lib/?.so;%s", plugin_root, package_cpath)
        local ok, plugin_module = pcall(dofile, mainfile)
        if not ok or not plugin_module then
            logger.warn("Error when loading", mainfile, plugin_module)
        elseif type(plugin_module.disabled) ~= "boolean" or not plugin_module.disabled then
            plugin_module.path = plugin_root
            plugin_module.name = v.name
            if disabled then
                table.insert(self.disabled_plugins, plugin_module)
            else
                local ok_meta, plugin_metamodule = pcall(dofile, metafile)
                if ok_meta and plugin_metamodule then
                    for k, module in pairs(plugin_metamodule) do
                        if k ~= "name" then
                            plugin_module[k] = module
                        else
                            logger.warn("PluginLoader:", plugin_module.name, "name in _meta.lua, is deprecated and will be ignored.")
                        end
                    end
                end
                sandboxPluginEventHandlers(plugin_module)
                table.insert(self.enabled_plugins, plugin_module)
                logger.dbg("Plugin loaded", plugin_module.name)
            end
        end
    end
    package.path = package_path
    package.cpath = package_cpath
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

    local builtin_plugin_items = {}
    local user_plugin_items = {}
    for _, plugin in ipairs(self.all_plugins) do
        local item = {
            text = plugin.fullname,
            checked_func = function()
                return plugin.enable
            end,
            callback = function()
                local plugins_disabled = G_reader_settings:readSetting("plugins_disabled") or {}
                plugin.enable = not plugin.enable
                if plugin.enable then
                    plugins_disabled[plugin.name] = nil
                else
                    plugins_disabled[plugin.name] = true
                    self:stopPluginInstanceByName(plugin.name)
                end
                G_reader_settings:saveSetting("plugins_disabled", plugins_disabled)
                if self.show_info then
                    self.show_info = false
                    UIManager:askForRestart()
                end
            end,
            hold_callback = function(touchmenu_instance)
                self:showPluginDialog(plugin, touchmenu_instance)
            end,
        }
        if BUILTIN_PLUGINS[plugin.name] then
            table.insert(builtin_plugin_items, item)
        else
            table.insert(user_plugin_items, item)
        end
    end
    return {
        {
            text = _("Built-in plugins"),
            enabled_func = function()
                return #builtin_plugin_items > 0
            end,
            sub_item_table = builtin_plugin_items,
        },
        {
            text = _("User plugins"),
            enabled_func = function()
                return #user_plugin_items > 0
            end,
            sub_item_table = user_plugin_items,
        },
    }
end

function PluginLoader:showPluginDialog(plugin, touchmenu_instance)
    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
    local function set_and_restart(enable, disabled)
        plugin.enable = enable
        plugins_disabled[plugin.name] = disabled
        touchmenu_instance:updateItems()
        if self.show_info then
            self.show_info = false
            UIManager:askForRestart()
        end
    end
    local plugin_instance = self:getPluginInstance(plugin.name)
    local can_delete_settings = (plugin_instance and (plugin_instance.deletePluginSettings
        or plugin_instance.settings_file or plugin_instance.settings_key)) and true or false
    local plugin_dialog, buttons
    if plugin.enable then
        buttons = {
            {{
                text = _("Disable plugin"),
                callback = function()
                    UIManager:close(plugin_dialog)
                    if plugin_instance then
                        self:stopPluginInstance(plugin_instance)
                    end
                    set_and_restart(false, true)
                end,
            }},
        }
        if can_delete_settings then
            table.insert(buttons, {{
                text = _("Disable plugin and delete settings"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete plugin settings?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            UIManager:close(plugin_dialog)
                            self:deletePluginSettings(plugin_instance)
                            self:stopPluginInstance(plugin_instance)
                            set_and_restart(false, true)
                        end,
                    })
                end,
            }})
        end
    else -- disabled
        buttons = {
            {{
                text = _("Enable plugin"),
                callback = function()
                    UIManager:close(plugin_dialog)
                    set_and_restart(true, false)
                end,
            }},
        }
    end
    if not BUILTIN_PLUGINS[plugin.name] then
        table.insert(buttons, {}) -- separator
        table.insert(buttons, {{
            text = _("Delete plugin"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Delete plugin?"),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        local ok, err = ffiUtil.purgeDir(plugin.path)
                        if ok then
                            UIManager:close(plugin_dialog)
                            if plugin_instance then
                                self:stopPluginInstance(plugin_instance)
                            end
                            set_and_restart(false, nil)
                        else
                            UIManager:show(InfoMessage:new{ text = _("Failed to delete plugin:") .. "\n" .. err })
                        end
                    end,
                })
            end,
        }})
        if can_delete_settings then
            table.insert(buttons, {{
                text = _("Delete plugin and settings"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete plugin and settings?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            local ok, err = ffiUtil.purgeDir(plugin.path)
                            if ok then
                                UIManager:close(plugin_dialog)
                                self:deletePluginSettings(plugin_instance)
                                self:stopPluginInstance(plugin_instance)
                                set_and_restart(false, nil)
                            else
                                UIManager:show(InfoMessage:new{ text = _("Failed to delete plugin:") .. "\n" .. err })
                            end
                        end,
                    })
                end,
            }})
        end
    end
    plugin_dialog = ButtonDialog:new{
        title = plugin.fullname .. "\n\n" .. plugin.description .. "\n",
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(plugin_dialog)
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

--- Calls the stopPlugin() method on a plugin instance of a given name if it's currently loaded.
--- This is only intended for plugins that manage external resources or processes.
--- @param name string The name of the plugin to stop.
--- @return boolean Success, string|nil
function PluginLoader:stopPluginInstanceByName(name)
    local instance = self:getPluginInstance(name)
    local stopPluginFn = instance and instance.stopPlugin
    if type(stopPluginFn) ~= "function" then
        return true, nil
    end
    local ok, err = self:stopPluginInstance(instance)
    if ok then
        return true, nil
    end
    logger.err("PluginLoader: Failed to stop plugin instance", name, err)
    ok, err = self:stopPluginInstance(instance, true)
    if not ok then
        logger.err("PluginLoader: Failed to force-stop plugin instance", name, err)
    end
    return false, err
end

--- Calls the deletePluginSettings() method on a plugin instance of a given name if it's currently loaded.
--- This is only intended for plugins that manage settings in G_reader_settings or koreader/settings.
--- @param name string The name of the plugin whose settings should be deleted.
--- @return boolean Success, string|nil
function PluginLoader:deletePluginSettingsByName(name)
    local instance = self:getPluginInstance(name)
    local deletePluginSettingsFn = instance and instance.deletePluginSettings
    if type(deletePluginSettingsFn) ~= "function" then
        return true, nil
    end
    local ok, err = self:deletePluginSettings(instance)
    if not ok then
        logger.err("PluginLoader: Failed to delete plugin settings", name, err)
    end
    return ok, err
end

--- Calls the deletePluginSettings() method on a plugin instance if it's currently loaded.
--- This is only intended for plugins that manage settings in G_reader_settings or koreader/settings.
--- @param instance table The plugin instance whose settings should be deleted.
--- @return boolean Success, string|nil
function PluginLoader:deletePluginSettings(instance)
    local ok
    local fn = instance.deletePluginSettings
    if type(fn) == "function" then
        ok = pcall(fn, instance)
    end
    if instance.settings_file then
        os.remove(instance.settings_file)
        os.remove(instance.settings_file .. ".old")
        ok = true
    end
    if instance.settings_key then
        G_reader_settings:delSetting(instance.settings_key)
        ok = true
    end
    return ok
end

--- Calls the stopPlugin() method on a plugin instance if it's currently loaded.
--- This is only intended for plugins that manage external resources or processes.
--- @param instance table The plugin instance to stop.
--- @param force boolean|nil If true, forces the plugin to stop even if it encounters errors.
--- @return boolean Success, string|nil
function PluginLoader:stopPluginInstance(instance, force)
    local ok, err = false, "no stopPlugin method"
    local fn = instance.stopPlugin
    if type(fn) == "function" then
        ok, err = pcall(fn, instance, force)
    end
    if ok then return true, nil end
    return false, err
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
