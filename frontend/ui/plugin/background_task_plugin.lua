--[[--
BackgroundTaskPlugin creates a plugin with a switch to enable or disable it and executes a
background task.
See spec/unit/background_task_plugin_spec.lua for the usage.
]]

local PluginShare = require("pluginshare")
local SwitchPlugin = require("ui/plugin/switch_plugin")

local BackgroundTaskPlugin = SwitchPlugin:extend()

function BackgroundTaskPlugin:_schedule(settings_id)
    local enabled = function()
        if not self.enabled then
            return false
        end
        if settings_id ~= self.settings_id then
            return false
        end

        return true
    end

    table.insert(PluginShare.backgroundJobs, {
        when = self.when,
        repeated = enabled,
        executable = self.executable,
    })
    local Event = require("ui/event")
    local UIManager = require("ui/uimanager")
    UIManager:broadcastEvent(Event:new("BackgroundJobsUpdated"))
end

function BackgroundTaskPlugin:_start()
    self:_schedule(self.settings_id)
end

return BackgroundTaskPlugin
