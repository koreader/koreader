--[[--
Handles persistent storage for plugin compatibility settings.

This module extends LuaSettings to provide a dedicated settings file for
plugin compatibility data (prompts shown, load overrides). Settings are stored
in the settings directory as `plugincompatibility.lua`.

@usage
    local PluginCompatibilitySettings = require("plugincompatibilitysettings")
    local settings = PluginCompatibilitySettings:open()

    -- Check if user has been prompted
    if not settings:hasBeenPrompted("myplugin", "1.0") then
        settings:markAsPrompted("myplugin", "1.0")
    end

    -- Manage load overrides
    settings:setLoadOverride("myplugin", "1.0", "always")
    local override = settings:getLoadOverride("myplugin", "1.0")

    -- Save changes
    settings:flush()
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Version = require("frontend/version")

local PluginCompatibilitySettings = LuaSettings:extend({})

local SETTINGS_FILE = "plugincompatibility.lua"

--- Opens the plugin compatibility settings file.
-- Creates a new instance each time. Creates the file if it doesn't exist.
-- @treturn PluginCompatibilitySettings settings instance
function PluginCompatibilitySettings:open()
    local file_path = DataStorage:getSettingsDir() .. "/" .. SETTINGS_FILE
    local new = LuaSettings.open(self, file_path)
    setmetatable(new, { __index = PluginCompatibilitySettings })

    -- Initialize data structures if they don't exist
    if not new.data.plugin_load_overrides then
        new.data.plugin_load_overrides = {}
    end
    if not new.data.plugin_compatibility_prompts_shown then
        new.data.plugin_compatibility_prompts_shown = {}
    end

    return new
end

--- Get a unique key for this plugin + version + koreader version combination.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @treturn string unique key combining plugin name, plugin version, and KOReader version
function PluginCompatibilitySettings:getOverrideKey(plugin_name, plugin_version)
    local koreader_version = Version:getShortVersion()
    return string.format("%s-%s-%s", plugin_name, plugin_version, koreader_version)
end

--- Check if the user has been prompted about this specific plugin version.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @treturn boolean true if user has been prompted before
function PluginCompatibilitySettings:hasBeenPrompted(plugin_name, plugin_version)
    local prompts_shown = self.data.plugin_compatibility_prompts_shown or {}
    local key = self:getOverrideKey(plugin_name, plugin_version)
    return prompts_shown[key] == true
end

--- Mark that the user has been prompted about this specific plugin version.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
function PluginCompatibilitySettings:markAsPrompted(plugin_name, plugin_version)
    if not self.data.plugin_compatibility_prompts_shown then
        self.data.plugin_compatibility_prompts_shown = {}
    end
    local key = self:getOverrideKey(plugin_name, plugin_version)
    self.data.plugin_compatibility_prompts_shown[key] = true
end

--- Remove the prompted mark for this specific plugin version.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
function PluginCompatibilitySettings:removePromptedMark(plugin_name, plugin_version)
    if not self.data.plugin_compatibility_prompts_shown then
        return
    end
    local key = self:getOverrideKey(plugin_name, plugin_version)
    self.data.plugin_compatibility_prompts_shown[key] = nil
end

--- Get the load override action for a plugin.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @string koreader_version Optional, defaults to current KOReader version
-- @treturn string|nil "always", "never", "load-once", or nil if no override
function PluginCompatibilitySettings:getLoadOverride(plugin_name, plugin_version, koreader_version)
    local overrides = self.data.plugin_load_overrides or {}
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
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @tparam string|nil action "always", "never", "load-once", or nil/ask to remove override
function PluginCompatibilitySettings:setLoadOverride(plugin_name, plugin_version, action)
    if not self.data.plugin_load_overrides then
        self.data.plugin_load_overrides = {}
    end

    local koreader_version = Version:getShortVersion()

    if action == nil or action == "ask" then
        -- Remove override
        self.data.plugin_load_overrides[plugin_name] = nil
    else
        self.data.plugin_load_overrides[plugin_name] = {
            action = action,
            version = plugin_version,
            koreader_version = koreader_version,
        }
    end
end

--- Clear the load-once override after it has been used.
-- Only clears if the current override action is "load-once".
-- @string plugin_name The name of the plugin
function PluginCompatibilitySettings:clearLoadOnceOverride(plugin_name)
    local overrides = self.data.plugin_load_overrides or {}
    local override = overrides[plugin_name]

    if override and override.action == "load-once" then
        self.data.plugin_load_overrides[plugin_name] = nil
    end
end

return PluginCompatibilitySettings
