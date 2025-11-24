--[[--
Handles plugin version compatibility checks and load overrides.

This module checks if a plugin is compatible with the current KOReader version
based on the compatibility field in the plugin's _meta.lua file. It also manages
user overrides for loading incompatible plugins.

Settings structure in G_reader_settings:
- plugin_load_overrides: {
    ["plugin-name"] = {
        action = "always" | "never" | "load-once",
        version = "plugin_version",
        koreader_version = "koreader_version",
    }
  }
- plugin_compatibility_prompts_shown: {
    ["plugin-name-version-koreader_version"] = true,
  }
]]

-- TODO: there must be a way to clean up lingering settings.
-- e.g. when a plugin is uninstalled, or when a new KOReader version is released
-- that makes old overrides irrelevant.

local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Version = require("frontend/version")
local _ = require("gettext")
local logger = require("logger")

local PluginCompatibility = {}

--- Check whether plugin compatibility checks are enabled.
-- Reads the global default `ENABLE_PLUGIN_COMPATIBILITY_CHECKS` from `G_defaults`.
-- This is intentionally read at call-time so tests can mock `G_defaults.readSetting`
-- and toggle the behavior dynamically.
-- @treturn boolean|nil true if checks are enabled, false if disabled, or nil if unset
function PluginCompatibility.isCompatibilityCheckEnabled()
    return G_defaults:readSetting("ENABLE_PLUGIN_COMPATIBILITY_CHECKS")
end

--- Check if a plugin is compatible with the current KOReader version.
-- @tparam table plugin_meta The plugin's metadata table (_meta.lua contents)
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

    local current_version, _ = Version:getNormalizedCurrentVersion()
    if not current_version then
        logger.warn("PluginCompatibility: Could not get current KOReader version")
        return true, nil, nil
    end

    local min_version = compatibility.min_version
    local max_version = compatibility.max_version

    -- Check minimum version requirement
    if min_version then
        local min_ver, _ = Version:getNormalizedVersion(min_version)
        if min_ver and current_version < min_ver then
            local message =
                string.format("Requires KOReader %s or later (current: %s)", min_version, Version:getShortVersion())
            return false, "below_minimum", message
        end
    end

    -- Check maximum version requirement
    if max_version then
        local max_ver, _ = Version:getNormalizedVersion(max_version)
        if max_ver and current_version > max_ver then
            local message = string.format(
                "Not compatible with KOReader %s and newer. Requires KOReader %s or older",
                Version:getShortVersion(),
                max_version
            )
            return false, "above_maximum", message
        end
    end

    return true, nil, nil
end

--- Get a unique key for this plugin + version + koreader version combination.
-- @tparam string plugin_name
-- @tparam string plugin_version
-- @treturn string unique key
function PluginCompatibility.getOverrideKey(plugin_name, plugin_version)
    local koreader_version = Version:getShortVersion()
    return string.format("%s-%s-%s", plugin_name, plugin_version or "unknown", koreader_version)
end

--- Check if the user has been prompted about this specific plugin version.
-- @tparam table G_reader_settings
-- @tparam string plugin_name
-- @tparam string plugin_version
-- @treturn boolean true if user has been prompted before
function PluginCompatibility.hasBeenPrompted(G_reader_settings, plugin_name, plugin_version)
    local prompts_shown = G_reader_settings:readSetting("plugin_compatibility_prompts_shown") or {}
    local key = PluginCompatibility.getOverrideKey(plugin_name, plugin_version)
    return prompts_shown[key] == true
end

--- Mark that the user has been prompted about this specific plugin version.
-- @tparam table G_reader_settings
-- @tparam string plugin_name
-- @tparam string plugin_version
function PluginCompatibility.markAsPrompted(G_reader_settings, plugin_name, plugin_version)
    local prompts_shown = G_reader_settings:readSetting("plugin_compatibility_prompts_shown") or {}
    local key = PluginCompatibility.getOverrideKey(plugin_name, plugin_version)
    prompts_shown[key] = true
    G_reader_settings:saveSetting("plugin_compatibility_prompts_shown", prompts_shown)
end

--- Remove the prompted mark for this specific plugin version.
-- @tparam table G_reader_settings
-- @tparam string plugin_name
-- @tparam string plugin_version
function PluginCompatibility.removePromptedMark(G_reader_settings, plugin_name, plugin_version)
    local prompts_shown = G_reader_settings:readSetting("plugin_compatibility_prompts_shown") or {}
    local key = PluginCompatibility.getOverrideKey(plugin_name, plugin_version)
    prompts_shown[key] = nil
    G_reader_settings:saveSetting("plugin_compatibility_prompts_shown", prompts_shown)
end

--- Get the load override action for a plugin.
-- @tparam table G_reader_settings
-- @tparam string plugin_name
-- @tparam string plugin_version
-- @tparam string koreader_version Optional, defaults to current version
-- @treturn string|nil "always", "never", "load-once", or nil if no override
function PluginCompatibility.getLoadOverride(G_reader_settings, plugin_name, plugin_version, koreader_version)
    local overrides = G_reader_settings:readSetting("plugin_load_overrides") or {}
    local override = overrides[plugin_name]

    if not override then
        return nil
    end

    -- Check if the override is for the current versions
    local current_koreader_version = koreader_version or Version:getShortVersion()
    if override.version ~= plugin_version or override.koreader_version ~= current_koreader_version then
        -- Override exists but for different versions, treat as no override
        return nil
    end

    return override.action
end

--- Set the load override for a plugin.
-- @tparam table G_reader_settings
-- @tparam string plugin_name
-- @tparam string plugin_version
-- @tparam string action "always", "never", or "load-once"
function PluginCompatibility.setLoadOverride(G_reader_settings, plugin_name, plugin_version, action)
    local overrides = G_reader_settings:readSetting("plugin_load_overrides") or {}
    local koreader_version = Version:getShortVersion()

    if action == nil or action == "ask" then
        -- Remove override
        overrides[plugin_name] = nil
    else
        overrides[plugin_name] = {
            action = action,
            version = plugin_version,
            koreader_version = koreader_version,
        }
    end

    G_reader_settings:saveSetting("plugin_load_overrides", overrides)
end

--- Clear the load-once override after it has been used.
-- @tparam table G_reader_settings
-- @tparam string plugin_name
function PluginCompatibility.clearLoadOnceOverride(G_reader_settings, plugin_name)
    local overrides = G_reader_settings:readSetting("plugin_load_overrides") or {}
    local override = overrides[plugin_name]

    if override and override.action == "load-once" then
        overrides[plugin_name] = nil
        G_reader_settings:saveSetting("plugin_load_overrides", overrides)
    end
end

--- Determine if a plugin should be loaded based on compatibility and overrides.
-- @tparam table G_reader_settings
-- @tparam table plugin_meta The plugin's metadata
-- @tparam string plugin_name
-- @treturn boolean true if should load, false otherwise
-- @treturn string|nil reason for not loading or nil
-- @treturn string|nil incompatibility message or nil
-- @treturn boolean true if user should be prompted
function PluginCompatibility.shouldLoadPlugin(G_reader_settings, plugin_meta, plugin_name)
    local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)

    if is_compatible then
        -- Plugin is compatible, load it
        return true, nil, nil, false
    end

    -- Plugin is incompatible, check for overrides
    local plugin_version = plugin_meta and plugin_meta.version or "unknown"
    local override = PluginCompatibility.getLoadOverride(G_reader_settings, plugin_name, plugin_version)

    if override == "always" then
        -- User wants to always load this plugin despite incompatibility
        return true, nil, nil, false
    elseif override == "never" then
        -- User explicitly doesn't want this plugin loaded
        return false, reason, message, false
    elseif override == "load-once" then
        -- User wants to load it once for testing
        -- Clear the override so next time it won't auto-load
        PluginCompatibility.clearLoadOnceOverride(G_reader_settings, plugin_name)
        PluginCompatibility.removePromptedMark(G_reader_settings, plugin_name, plugin_version)
        return true, nil, nil, false
    end

    -- No override exists, check if we've already prompted the user
    local has_been_prompted = PluginCompatibility.hasBeenPrompted(G_reader_settings, plugin_name, plugin_version)
    logger.dbg("PluginCompatibility: has_been_prompted for", plugin_name, "is", has_been_prompted)

    if has_been_prompted then
        -- We've asked before and user didn't set an override, so don't load
        return false, reason, message, false
    else
        -- First time seeing this incompatibility, prompt the user
        return false, reason, message, true
    end
end

--- Get a human-readable description of the load override action.
-- @tparam string action "always", "never", "load-once", or nil
-- @treturn string human-readable description
function PluginCompatibility.getOverrideDescription(action)
    if action == "always" then
        return "Always load (even if incompatible)"
    elseif action == "never" then
        return "Never load"
    elseif action == "load-once" then
        return "Load once (for testing)"
    else
        return "Ask on incompatibility"
    end
end

--- Create menu item for a single override option.
-- Returns a menu item that, when selected, applies the override action,
-- marks the plugin as prompted, and pops back to the parent menu.
-- @tparam table plugin Plugin reference table
-- @tparam table option Override option with action and text
-- @tparam table G_reader_settings Settings object
-- @treturn table Menu item for this override option
local function createOverrideOptionMenuItem(plugin, option, G_reader_settings)
    return {
        text = option.text,
        callback = function(menu)
            logger.dbg("PluginCompatibility: submenu action called", plugin.name, option.action)
            PluginCompatibility.setLoadOverride(G_reader_settings, plugin.name, plugin.version, option.action)
            if option.action then
                PluginCompatibility.markAsPrompted(G_reader_settings, plugin.name, plugin.version)
            end
            if menu and menu.onClose then
                menu:onClose()
            end
        end,
    }
end

--- Generate menu items for plugin override options.
-- Creates a submenu listing all available override actions for a plugin.
-- @tparam table plugin Plugin table with name and version
-- @tparam table G_reader_settings Settings object for storing overrides
-- @treturn table Array of menu items for override options
local function genOverrideMenuItems(plugin, G_reader_settings)
    local override_options = {
        { action = nil, text = _("Ask on incompatibility (default)") },
        { action = "load-once", text = _("Load once (for testing)") },
        { action = "always", text = _("Always load (ignore incompatibility)") },
        { action = "never", text = _("Never load") },
    }

    local menu_items = {}
    for _, option in ipairs(override_options) do
        table.insert(menu_items, createOverrideOptionMenuItem(plugin, option, G_reader_settings))
    end
    return menu_items
end

--- Create menu item for a single incompatible plugin.
-- Generates a menu item with the plugin name, current override status (mandatory),
-- and a submenu of override options.
-- @tparam table plugin Plugin table with name, version, and incompatibility_message
-- @tparam table G_reader_settings Settings object for reading current overrides
-- @treturn table Menu item for this incompatible plugin
local function createPluginMenuItem(plugin, G_reader_settings)
    local current_override = PluginCompatibility.getLoadOverride(G_reader_settings, plugin.name, plugin.version)
    local status_text = PluginCompatibility.getOverrideDescription(current_override)

    return {
        text = plugin.fullname or plugin.name,
        mandatory = status_text,
        help_text = plugin.incompatibility_message,
        sub_item_table = genOverrideMenuItems(plugin, G_reader_settings),
    }
end

--- Generate all menu items for the main incompatible plugins menu.
-- Creates a list of menu items, one per incompatible plugin, each with its
-- current override status and submenu of options.
-- @tparam table incompatible_plugins List of incompatible plugins
-- @tparam table G_reader_settings Settings object for reading current overrides
-- @treturn table Array of menu items for all incompatible plugins
local function genMainMenuItems(incompatible_plugins, G_reader_settings)
    local menu_items = {}
    for _, plugin in ipairs(incompatible_plugins) do
        table.insert(menu_items, createPluginMenuItem(plugin, G_reader_settings))
    end
    return menu_items
end

--- Handle leaf menu item selection (override option chosen).
-- Executes the item callback, pops back to parent menu if in a submenu,
-- and refreshes the main menu display if returning to root level.
-- @tparam table menu Menu instance
-- @tparam table item Selected menu item
-- @treturn boolean True to indicate event was handled
local function handleLeafMenuSelect(menu, item, genMainMenuItems_func)
    if item.select_enabled == false then
        return true
    end
    if item.select_enabled_func and not item.select_enabled_func() then
        return true
    end

    if item.callback then
        item.callback(menu)
    end

    if #menu.item_table_stack == 0 then
        menu:switchItemTable(nil, genMainMenuItems_func())
    end
    return true
end

--- Handle stacked submenu navigation.
-- Pushes current item table onto stack and displays the submenu.
-- @tparam table menu Menu instance
-- @tparam table item Selected menu item with sub_item_table
local function handleSubmenuSelect(menu, item)
    menu.item_table.title = menu.title
    table.insert(menu.item_table_stack, menu.item_table)
    menu:switchItemTable(item.text, item.sub_item_table)
end

--- Create custom onMenuSelect handler for incompatible plugins menu.
-- Returns a function that handles both leaf selection (override choice)
-- and submenu selection (plugin choice) with proper stacking behavior.
-- @tparam function genMainMenuItems_func Function to regenerate main menu items
-- @treturn function onMenuSelect handler
local function createMenuSelectHandler(genMainMenuItems_func)
    return function(self, item)
        if item.sub_item_table == nil then
            handleLeafMenuSelect(self, item, genMainMenuItems_func)
        else
            handleSubmenuSelect(self, item)
        end
        return true
    end
end

--- Create callback for main menu close event.
-- Handles cleanup when the main menu is fully closed (no stacked submenus).
-- @tparam table main_menu Menu instance
-- @tparam function on_close_callback User-provided callback (e.g., restart prompt)
-- @treturn function close_callback handler
local function createCloseCallback(main_menu, on_close_callback)
    return function()
        logger.dbg("PluginCompatibility: main menu close_callback called")
        UIManager:close(main_menu)
        if on_close_callback then
            on_close_callback()
        end
    end
end

--- Show the main incompatible plugins menu.
-- Creates a full-screen stacked menu listing all incompatible plugins.
-- When a plugin is selected, a submenu with override options is displayed.
-- When an override option is selected, it is applied and the menu returns to the plugin list.
-- When the main menu is closed, the on_close_callback is invoked.
-- @tparam table incompatible_plugins List of incompatible plugin tables with name, version, incompatibility_message
-- @tparam table G_reader_settings Settings object for storing overrides
-- @tparam function on_close_callback Callback to execute when the main menu is fully closed (e.g., restart prompt)
function PluginCompatibility.showIncompatiblePluginsMenu(incompatible_plugins, G_reader_settings, on_close_callback)
    local function genMainMenuItemsWrapper()
        return genMainMenuItems(incompatible_plugins, G_reader_settings)
    end

    local main_menu
    main_menu = Menu:new({
        title = _("Incompatible Plugins"),
        item_table = genMainMenuItemsWrapper(),
        is_popout = false,
        is_borderless = true,
        covers_fullscreen = true,
        onMenuSelect = createMenuSelectHandler(genMainMenuItemsWrapper),
        close_callback = createCloseCallback(main_menu, on_close_callback),
    })

    UIManager:show(main_menu)
end

--- Generate a simple sub_menu table for a single plugin (for plugin manager use)
-- This mirrors the submenu content used by the stacked UI, but returns a plain
-- table suitable for `Menu.item_table` or `Menu.itemTableFromTouchMenu()` usage.
function PluginCompatibility.genPluginOverrideSubMenu(plugin, G_reader_settings)
    local plugin_name = plugin.name
    local plugin_version = plugin.version or "unknown"

    local sub_menu = {
        {
            text = _("Incompatibility Details"),
            enabled = false,
            separator = true,
        },
    }

    local override_options = {
        { action = nil, text = _("Ask on incompatibility (default)") },
        { action = "load-once", text = _("Load once (for testing)") },
        { action = "always", text = _("Always load (ignore incompatibility)") },
        { action = "never", text = _("Never load") },
    }

    for i, option in ipairs(override_options) do
        table.insert(sub_menu, {
            text = option.text,
            checked_func = function()
                return PluginCompatibility.getLoadOverride(G_reader_settings, plugin_name, plugin_version)
                    == option.action
            end,
            callback = function()
                PluginCompatibility.setLoadOverride(G_reader_settings, plugin_name, plugin_version, option.action)
                PluginCompatibility.markAsPrompted(G_reader_settings, plugin_name, plugin_version)

                UIManager:askForRestart()
            end,
        })
    end

    return sub_menu
end

return PluginCompatibility
