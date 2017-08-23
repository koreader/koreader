local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local NetworkPoller = {
  settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/networkpoller.lua"),
  settings_id = 0,
  enabled = false,
}

function NetworkPoller:_schedule(settings_id)
    local enabled = function()
        if not self.enabled then
            logger.dbg("NetworkPoller:_schedule() is disabled")
            return false
        end
        if settings_id ~= self.settings_id then
            logger.dbg("NetworkPoller:_schedule(): registered settings_id ",
                       settings_id,
                       " does not equal to current one ",
                       self.settings_id)
            return false
        end

        return true
    end

    table.insert(PluginShare.backgroundJobs, {
        insert_sec = 0,  -- Actively set the insert_sec to start it immediately.
        when = 30,       -- Checks network connectivity once per 30 seconds.
        repeated = enabled,
        executable = "ping -W 1 -c 1 www.example.com",
        callback = function(job)
            self:_writeResult(job)
        end,
    })
end

function NetworkPoller:_writeResult(job)
    if job == nil then
        -- When polling job is disabled, ensure the connection has been generated.
        PluginShare.network_connectivity = true
    else
        PluginShare.network_connectivity = (job.result == 0)
    end
end

function NetworkPoller:init()
    self.enabled = self.settings:nilOrTrue("enable")
    self.settings_id = self.settings_id + 1
    logger.dbg("NetworkPoller:init() self.enabled: ", self.enabled, " with id ", self.settings_id)
    self:_schedule(self.settings_id)
end

function NetworkPoller:flipSetting()
    self.settings:flipNilOrTrue("enable")
    self:init()
end

function NetworkPoller:onFlushSettings()
    self.settings:flush()
end

NetworkPoller:init()

local NetworkPollerWidget = WidgetContainer:new{
    name = "NetworkPoller",
}

function NetworkPollerWidget:init()
    -- self.ui and self.ui.menu are nil in unittests.
    if self.ui ~= nil and self.ui.menu ~= nil then
        self.ui.menu:registerToMainMenu(self)
    end
end

function NetworkPollerWidget:flipSetting()
    NetworkPoller:flipSetting()
end

-- For test only.
function NetworkPollerWidget:deprecateLastTask()
    logger.dbg("NetworkPollerWidget:deprecateLastTask() @ ", NetworkPoller.settings_id)
    NetworkPoller.settings_id = NetworkPoller.settings_id + 1
end

function NetworkPollerWidget:addToMainMenu(menu_items)
    menu_items.network_poller = {
        text = _("Poll network connectivity"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = T(_("KOReader can actively poll network connectivity to \nDo you want to %1 it?"),
                         NetworkPoller.enabled and _("disable") or _("enable")),
                ok_text = NetworkPoller.enabled and _("Disable") or _("Enable"),
                ok_callback = function()
                    self:flipSetting()
                end
            })
        end,
        checked_func = function() return NetworkPoller.enabled end,
    }
end

function NetworkPollerWidget:onFlushSettings()
    NetworkPoller:onFlushSettings()
end

return NetworkPollerWidget
