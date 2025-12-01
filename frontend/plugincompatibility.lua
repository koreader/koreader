--[[--
Handles plugin version compatibility checks and load overrides.

This module checks if a plugin is compatible with the current KOReader version
based on the compatibility field in the plugin's _meta.lua file. It also manages
user overrides for loading incompatible plugins.

Settings are stored in a dedicated file via PluginCompatibilitySettings.
Access settings directly through the `settings` field.

To develop this feature, set KODEV_ENABLE_INCOMPATIBLE_PLUGIN env variable
to any value to make hello.koplugin appear as an incompatible plugin.
Check ./plugins/hello.koplugin/_meta.lua to see how this works.

@usage
    local PluginCompatibility = require("plugincompatibility")
    local compatibility = PluginCompatibility:new()

    -- Check compatibility (static method)
    local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)

    -- Manage prompts and overrides via settings
    compatibility.settings:markAsPrompted("myplugin", "1.0")
    compatibility.settings:setLoadOverride("myplugin", "1.0", "always")

    -- Flush settings when done
    compatibility.settings:flush()

    -- Clean up old settings (keep current and 2 previous versions)
    compatibility.settings:purgeOldVersionSettings(3)
]]

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local PluginCompatibilitySettings = require("plugincompatibilitysettings")
local UIManager = require("ui/uimanager")
local Version = require("frontend/version")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local PluginCompatibility = {}
PluginCompatibility.__index = PluginCompatibility

--- Creates a new PluginCompatibility instance.
-- Initializes with a settings object for persistent storage.
-- @treturn PluginCompatibility new instance with settings field
function PluginCompatibility:new()
    local instance = setmetatable({}, self)
    instance.settings = PluginCompatibilitySettings:open()
    return instance
end

--- Check whether plugin compatibility checks are enabled.
-- Reads the global default `ENABLE_PLUGIN_COMPATIBILITY_CHECKS` from `G_defaults`.
-- This is intentionally read at call-time so tests can mock `G_defaults.readSetting`
-- and toggle the behavior dynamically.
-- @treturn boolean|nil true if checks are enabled, false if disabled, or nil if unset
function PluginCompatibility.isCompatibilityCheckEnabled()
    return G_defaults:readSetting("ENABLE_PLUGIN_COMPATIBILITY_CHECKS")
end

--- Check if a plugin is compatible with the current KOReader version.
-- @table plugin_meta The plugin's metadata table (_meta.lua contents)
-- @treturn boolean true if compatible, false otherwise
-- @treturn string|nil reason for incompatibility ("below_minimum", "above_maximum") or nil if compatible
-- @treturn string|nil human-readable message or nil if compatible
function PluginCompatibility.checkCompatibility(plugin_meta)
    if not plugin_meta or not PluginCompatibility.isCompatibilityCheckEnabled() then
        return true, nil, nil
    end
    local compatibility = plugin_meta.compatibility
    if not compatibility then
        -- No compatibility field means it works with all versions (backward compatibility)
        return true, nil, nil
    end
    local current_version, __ = Version:getNormalizedCurrentVersion()
    if not current_version then
        logger.warn("PluginCompatibility: Could not get current KOReader version")
        return true, nil, nil
    end
    local min_version = compatibility.min_version
    local max_version = compatibility.max_version
    -- Check minimum version requirement
    if min_version then
        local min_ver = Version:getNormalizedVersion(min_version)
        if min_ver and current_version < min_ver then
            local message = T(_("Requires KOReader %1 or later (current: %2)"), min_version, Version:getShortVersion())
            return false, "below_minimum", message
        end
    end
    -- Check maximum version requirement
    if max_version then
        local max_ver = Version:getNormalizedVersion(max_version)
        if max_ver and current_version > max_ver then
            local message = T(
                _("Not compatible with KOReader %1 and newer. Requires KOReader %2 or older"),
                Version:getShortVersion(),
                max_version
            )
            return false, "above_maximum", message
        end
    end
    return true, nil, nil
end

--- Determine if a plugin should be loaded based on compatibility and overrides.
-- @table plugin_meta The plugin's metadata
-- @treturn boolean true if should load, false otherwise
-- @treturn string|nil reason for not loading or nil
-- @treturn string|nil incompatibility message or nil
-- @treturn boolean true if user should be prompted
function PluginCompatibility:shouldLoadPlugin(plugin_meta)
    local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
    if is_compatible then
        -- Plugin is compatible, load it
        return true, nil, nil, false
    end
    -- Plugin is incompatible, check for overrides
    local override = self.settings:getLoadOverride(plugin_meta.name, plugin_meta.version)
    if override == "always" then
        -- User wants to always load this plugin despite incompatibility
        return true, nil, nil, false
    elseif override == "never" then
        -- User explicitly doesn't want this plugin loaded
        return false, reason, message, false
    elseif override == "load-once" then
        -- User wants to load it once for testing
        -- Clear the override so next time it won't auto-load
        self.settings:clearLoadOnceOverride(plugin_meta.name)
        self.settings:removePromptedMark(plugin_meta.name, plugin_meta.version)
        return true, nil, nil, false
    end
    -- No override exists, check if we've already prompted the user
    local has_been_prompted = self.settings:hasBeenPrompted(plugin_meta.name, plugin_meta.version)
    logger.dbg("PluginCompatibility: has_been_prompted for", plugin_meta.name, "is", has_been_prompted)
    if has_been_prompted then
        -- We've asked before and user didn't set an override, so don't load
        return false, reason, message, false
    else
        -- First time seeing this incompatibility, prompt the user
        return false, reason, message, true
    end
end

--- Get a human-readable description of the load override action.
-- @string action "always", "never", "load-once", or nil
-- @treturn string human-readable description
function PluginCompatibility.getOverrideDescription(action)
    if action == "always" then
        return _("Always load (even if incompatible)")
    elseif action == "never" then
        return _("Never load")
    elseif action == "load-once" then
        return _("Load once (for testing)")
    else
        return _("Ask on incompatibility")
    end
end

--- Returns a list of available override actions for incompatible plugins.
-- @treturn table
local function overrideItems()
    return {
        { action = nil, text = _("Ask on incompatibility (default)") },
        { action = "load-once", text = _("Load once (for testing)") },
        { action = "always", text = _("Always load (ignore incompatibility)") },
        { action = "never", text = _("Never load") },
    }
end

--- Show ButtonDialog for plugin override options.
-- Displays a dialog with buttons for each override action. When an action is selected,
-- it is applied and the dialog is closed. The tap_close_callback refreshes the menu.
-- @table self PluginCompatibility instance
-- @table plugin Plugin table with name and version
-- @func on_close Function to call when dialog closes (to refresh menu)
local function showOverrideButtonDialog(self, plugin, on_close)
    local buttons = {}
    local button_row = {}
    local dialog

    for i, option in ipairs(overrideItems()) do
        local current_override = self.settings:getLoadOverride(plugin.name, plugin.version)
        table.insert(button_row, {
            text = option.text .. (current_override == option.action and "  ✓" or ""),
            callback = function()
                logger.dbg("PluginCompatibility: button dialog action called", plugin.name, option.action)
                self.settings:removePromptedMark(plugin.name, plugin.version)
                self.settings:setLoadOverride(plugin.name, plugin.version, option.action)
                if option.action then
                    self.settings:markAsPrompted(plugin.name, plugin.version)
                end
                self.settings:flush()
                dialog:onClose()
            end,
        })
        table.insert(buttons, button_row)
        button_row = {}
    end
    dialog = ButtonDialog:new({
        title = T(_("%1"), plugin.fullname or plugin.name),
        title_align = "center",
        buttons = buttons,
        tap_close_callback = on_close,
    })
    UIManager:show(dialog)
end

--- Create menu item for a single incompatible plugin.
-- Generates a menu item with the plugin name, current override status (mandatory),
-- that opens a ButtonDialog with override options when selected.
-- @table self PluginCompatibility instance
-- @table plugin Plugin table with name, version, and incompatibility_message
-- @func on_close Function to call when dialog closes (to refresh menu)
-- @treturn table Menu item for this incompatible plugin
local function createPluginMenuItem(self, plugin, on_close)
    local current_override = self.settings:getLoadOverride(plugin.name, plugin.version)
    local status_text = PluginCompatibility.getOverrideDescription(current_override)
    return {
        text = plugin.fullname or plugin.name,
        mandatory = status_text,
        help_text = plugin.incompatibility_message,
        callback = function()
            showOverrideButtonDialog(self, plugin, on_close)
        end,
    }
end

--- Generate all menu items for the main incompatible plugins menu.
-- Creates a list of menu items, one per incompatible plugin, each with its
-- current override status and a callback to show button dialog options.
-- @table self PluginCompatibility instance
-- @table incompatible_plugins List of incompatible plugins
-- @func on_close Function to call when dialog closes (to refresh menu)
-- @treturn table Array of menu items for all incompatible plugins
local function genMainMenuItems(self, incompatible_plugins, on_close)
    local menu_items = {}
    for _, plugin in ipairs(incompatible_plugins) do
        table.insert(menu_items, createPluginMenuItem(self, plugin, on_close))
    end
    return menu_items
end

--- Create onMenuSelect handler to prevent close_callback on menu item selection.
-- Returns a handler that invokes the item callback (which shows a ButtonDialog).
-- The menu refresh is handled by the ButtonDialog callback, not here.
-- @treturn function onMenuSelect handler
local function createMenuSelectHandler()
    return function(menu, item)
        if item.callback then
            item.callback()
        end
        return true
    end
end

--- Create callback for main menu close event.
-- Handles cleanup when the main menu is fully closed.
-- @func on_close_callback User-provided callback (e.g., restart prompt)
-- @treturn function close_callback handler
local function createCloseCallback(self, on_close_callback)
    return function()
        logger.dbg("PluginCompatibility: main menu close_callback called")
        if on_close_callback then
            on_close_callback()
        end
        self.settings:flush()
    end
end

--- Show the main incompatible plugins menu.
-- Creates a full-screen menu listing all incompatible plugins.
-- When a plugin is selected, a ButtonDialog with override options is displayed.
-- When an override option is selected, it is applied and the menu is refreshed.
-- When the main menu is closed, the on_close_callback is invoked.
-- @table incompatible_plugins List of incompatible plugin tables with name, version, incompatibility_message
-- @func on_close_callback Callback to execute when the main menu is fully closed (e.g., restart prompt)
function PluginCompatibility:showIncompatiblePluginsMenu(incompatible_plugins, on_close_callback)
    local self_ref = self
    local main_menu
    local function refreshMenu()
        if main_menu then
            local new_items = genMainMenuItems(self_ref, incompatible_plugins, refreshMenu)
            main_menu:switchItemTable(nil, new_items)
        end
    end
    main_menu = Menu:new({
        title = _("Incompatible Plugins"),
        item_table = genMainMenuItems(self_ref, incompatible_plugins, refreshMenu),
        is_popout = false,
        is_borderless = true,
        covers_fullscreen = true,
        onMenuSelect = createMenuSelectHandler(),
        close_callback = createCloseCallback(self_ref, on_close_callback),
    })
    UIManager:show(main_menu)
    UIManager:show(InfoMessage:new({
        text = _([[These plugins are incompatible with the current version of KOReader.

Go through the list and decide what you would like to do for each plugin.
]]),
    }))
end

--- Generate a simple sub_menu table for a single plugin (for plugin manager use)
-- This mirrors the submenu content used by the stacked UI, but returns a plain
-- table suitable for `Menu.item_table` or `Menu.itemTableFromTouchMenu()` usage.
-- @table plugin
-- @treturn table sub_menu suitable for Menu.item_table
function PluginCompatibility:genPluginOverrideSubMenu(plugin)
    local settings = self.settings
    local plugin_name = plugin.name
    local plugin_version = plugin.version
    local sub_menu = {
        {
            text = _("Incompatibility details"),
            enabled = false,
            separator = true,
        },
    }
    for _, option in ipairs(overrideItems()) do
        table.insert(sub_menu, {
            text = option.text,
            radio = true,
            checked_func = function()
                return settings:getLoadOverride(plugin_name, plugin_version) == option.action
            end,
            callback = function()
                settings:setLoadOverride(plugin_name, plugin_version, option.action)
                settings:markAsPrompted(plugin_name, plugin_version)
                settings:flush()
                UIManager:askForRestart()
            end,
        })
    end
    return sub_menu
end

return PluginCompatibility
