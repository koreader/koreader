--[[--
Handles persistent storage for plugin compatibility settings.

This module extends LuaSettings to provide a dedicated settings file for
plugin compatibility data (prompts shown, load overrides). Settings are stored
in the settings directory as `plugincompatibility.lua`.

Settings are organized by KOReader version, making it easy to clean up old
settings when they become irrelevant.

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

    -- Purge old settings (keep only current and N previous versions)
    settings:purgeOldVersionSettings(2)

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
    -- Initialize version_settings structure if it doesn't exist
    if not new.data.version_settings then
        new.data.version_settings = {}
    end
    return new
end

--- Get the settings table for a specific KOReader version, creating it if needed.
-- @string koreader_version The KOReader version (defaults to current)
-- @bool create_if_missing If true, create the structure if it doesn't exist
-- @treturn table|nil The settings table for this version, or nil if not found and not creating
function PluginCompatibilitySettings:_getVersionSettings(koreader_version, create_if_missing)
    koreader_version = koreader_version or Version:getShortVersion()
    if not self.data.version_settings then
        if create_if_missing then
            self.data.version_settings = {}
        else
            return nil
        end
    end
    if not self.data.version_settings[koreader_version] then
        if create_if_missing then
            self.data.version_settings[koreader_version] = {
                plugin_load_overrides = {},
                plugin_compatibility_prompts_shown = {},
            }
        else
            return nil
        end
    end
    return self.data.version_settings[koreader_version]
end

--- Get a unique key for this plugin + version combination.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @treturn string unique key combining plugin name and plugin version
function PluginCompatibilitySettings:getOverrideKey(plugin_name, plugin_version)
    return string.format("%s-%s", plugin_name, plugin_version)
end

--- Check if the user has been prompted about this specific plugin version.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @treturn boolean true if user has been prompted before
function PluginCompatibilitySettings:hasBeenPrompted(plugin_name, plugin_version)
    local version_settings = self:_getVersionSettings(nil, false)
    if not version_settings then
        return false
    end
    local prompts_shown = version_settings.plugin_compatibility_prompts_shown or {}
    local key = self:getOverrideKey(plugin_name, plugin_version)
    return prompts_shown[key] == true
end

--- Mark that the user has been prompted about this specific plugin version.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
function PluginCompatibilitySettings:markAsPrompted(plugin_name, plugin_version)
    local version_settings = self:_getVersionSettings(nil, true)
    local key = self:getOverrideKey(plugin_name, plugin_version)
    version_settings.plugin_compatibility_prompts_shown[key] = true
end

--- Remove the prompted mark for this specific plugin version.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
function PluginCompatibilitySettings:removePromptedMark(plugin_name, plugin_version)
    local version_settings = self:_getVersionSettings(nil, false)
    if not version_settings then
        return
    end
    local key = self:getOverrideKey(plugin_name, plugin_version)
    version_settings.plugin_compatibility_prompts_shown[key] = nil
end

--- Get the load override action for a plugin.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @string koreader_version Optional, defaults to current KOReader version
-- @treturn string|nil "always", "never", "load-once", or nil if no override
function PluginCompatibilitySettings:getLoadOverride(plugin_name, plugin_version, koreader_version)
    local version_settings = self:_getVersionSettings(koreader_version, false)
    if not version_settings then
        return nil
    end
    local overrides = version_settings.plugin_load_overrides or {}
    local override = overrides[plugin_name]
    if not override then
        return nil
    end
    -- Check if the override is for the current plugin version
    if override.version ~= plugin_version then
        -- Override exists but for different plugin version, treat as no override
        return nil
    end
    return override.action
end

--- Set the load override for a plugin.
-- @string plugin_name The name of the plugin
-- @string plugin_version The version of the plugin
-- @tparam string|nil action "always", "never", "load-once", or nil/ask to remove override
function PluginCompatibilitySettings:setLoadOverride(plugin_name, plugin_version, action)
    local version_settings = self:_getVersionSettings(nil, true)
    if action == nil or action == "ask" then
        -- Remove override
        version_settings.plugin_load_overrides[plugin_name] = nil
    else
        version_settings.plugin_load_overrides[plugin_name] = {
            action = action,
            version = plugin_version,
        }
    end
end

--- Clear the load-once override after it has been used.
-- Only clears if the current override action is "load-once".
-- @string plugin_name The name of the plugin
function PluginCompatibilitySettings:clearLoadOnceOverride(plugin_name)
    local version_settings = self:_getVersionSettings(nil, false)
    if not version_settings then
        return
    end
    local overrides = version_settings.plugin_load_overrides or {}
    local override = overrides[plugin_name]
    if override and override.action == "load-once" then
        version_settings.plugin_load_overrides[plugin_name] = nil
    end
end

--- Normalize a version string for comparison.
-- Uses Version:getNormalizedVersion with a "v" prefix if needed.
-- @string version_str Version string like "2024.01" or "2024.01.1-123"
-- @treturn number|nil Normalized version number, or nil if invalid
function PluginCompatibilitySettings:_normalizeVersion(version_str)
    if not version_str then
        return nil
    end
    -- getNormalizedVersion expects "v" prefix
    local prefixed = version_str
    if not version_str:match("^v") then
        prefixed = "v" .. version_str
    end
    local normalized, _ = Version:getNormalizedVersion(prefixed)
    return normalized
end

--- Purge settings for KOReader versions older than the specified threshold.
-- @int keep_versions Number of versions to keep (relative to current version).
--                    For example, if keep_versions is 2 and current version is 2025.03,
--                    settings for 2025.01 and earlier will be deleted.
-- @treturn int Number of versions purged
function PluginCompatibilitySettings:purgeOldVersionSettings(keep_versions)
    if not self.data.version_settings then
        return 0
    end
    -- Collect all versions with their normalized values
    local versions = {}
    for version_str, _ in pairs(self.data.version_settings) do
        local normalized = self:_normalizeVersion(version_str)
        if normalized then
            table.insert(versions, {
                str = version_str,
                normalized = normalized,
            })
        end
    end
    -- Sort by normalized version (descending - newest first)
    table.sort(versions, function(a, b)
        return a.normalized > b.normalized
    end)
    -- Keep the newest `keep_versions` versions, delete the rest
    local purged_count = 0
    for i, version in ipairs(versions) do
        if i > keep_versions then
            self.data.version_settings[version.str] = nil
            purged_count = purged_count + 1
        end
    end
    return purged_count
end

--- Get a list of all KOReader versions that have settings stored.
-- @treturn table Array of version strings, sorted newest first
function PluginCompatibilitySettings:getStoredVersions()
    if not self.data.version_settings then
        return {}
    end
    local versions = {}
    for version_str, _ in pairs(self.data.version_settings) do
        local normalized = self:_normalizeVersion(version_str)
        if normalized then
            table.insert(versions, {
                str = version_str,
                normalized = normalized,
            })
        end
    end
    -- Sort by normalized version (descending - newest first)
    table.sort(versions, function(a, b)
        return a.normalized > b.normalized
    end)
    local result = {}
    for _, v in ipairs(versions) do
        table.insert(result, v.str)
    end
    return result
end

return PluginCompatibilitySettings
