-- overview of available modules: http://koreader.rocks/doc/index.html

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("ffi/util")
local _ = require("gettext")
local T = require("ffi/util").template

local EyeSaver = WidgetContainer:new {
    name = "eyesaver",
    -- in minutes:
    --display_interval = 3600 / 3,
    display_interval = 3600 / 30,
    display_time_clock = '', -- The expected display_timestamp of display if enabled, or ''
    enabled = false,
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/eyesaver_options.lua"),
    display_timestamp = 0,
    timed_display_callback = nil,
}

function EyeSaver:init()
    -- here the text for the main menu gets constructed:
    self.ui.menu:registerToMainMenu(self)
    self.display_time_clock = self.settings:readSetting("eyesaver_display_time_clock") or ""
    self.display_timestamp = self.settings:readSetting("eyesaver_timestamp") or 0
    self.enabled = self.settings:readSetting("eyesaver_enabled") or false

    self.timed_display_callback = function()
        if not self.enabled or not self:eyeSaverMessageScheduled() then
            return
        end -- How could this happen?
        self:onShowEyeSaverMessage()
        self:scheduleTimeCompute()
        -- schedule the next display of a eyesaver message:
        self:schedule()
    end

    if self.enabled and not self:eyeSaverMessageScheduled() then
        self:scheduleTimeCompute()
        -- schedule the next display of a eyesaver message:
        self:schedule()
    end
end

-- when display_timestamp for displaying the message was in a period in which the ereader "slept", adapt the new display display_timestamp to be in the future again:
function EyeSaver:scheduleAdapt()
    if not self.enabled then
        return
    end
    local timestamp = self.display_timestamp
    if self:eyeSaverMessageScheduled() and timestamp < os.time() then
        self:unschedule();
        self:scheduleTimeCompute()
        self:schedule();
    end
end

function EyeSaver:scheduleTimeCompute()
    if not self.enabled then
        return
    end
    local time = self.display_interval
    local now = util:getTimestamp()
    self.display_timestamp = now + time
    self.display_time_clock = os.date(_("%H:%M"), self.display_timestamp)
    self:saveSettings()
end

function EyeSaver:schedule()
    if not self.enabled then
        return
    end
    if not self:eyeSaverMessageScheduled() then
        self:scheduleTimeCompute()
    end
    UIManager:schedule(self.display_timestamp, self.timed_display_callback)
end

function EyeSaver:unschedule()
    if self:eyeSaverMessageScheduled() then
        UIManager:unschedule(self.timed_display_callback)
    end
    self:resetTimer()
end

function EyeSaver:onResume()
    self:scheduleAdapt()
end

function EyeSaver:onSuspend()
    self:unschedule()
end

function EyeSaver:onShowEyeSaverMessage()
    UIManager:show(InfoMessage:new {
        text = _("Look 20 seconds into the distance.\n\nAfter this period current message will disappear…"),
        timeout = 20
    })
end

function EyeSaver:onToggleEyeSaverMessage()
    self.enabled = not self.enabled
    local status
    if self.enabled then
        self.settings:saveSetting("eyesaver_enabled", true)
        if not self:eyeSaverMessageScheduled() then
            self:schedule()
        end
        status = _("enabled")
    else
        self:unschedule()
        self.settings:saveSetting("eyesaver_enabled", false)
        status = _("disabled")
    end
    UIManager:show(InfoMessage:new {
        text = T(_("EyeSaver messages: %1"), status),
        timeout = 3
    })
end

function EyeSaver:eyeSaverMessageScheduled()
    return self.display_timestamp > 0
end

function EyeSaver:resetTimer()
    self.display_timestamp = 0
    self.display_time_clock = ''
    self:saveSettings()
end

function EyeSaver:saveSettings()
    self.settings:saveSetting("eyesaver_timestamp", self.display_timestamp)
    self.settings:saveSetting("eyesaver_display_time_clock", self.display_time_clock)
end

function EyeSaver:onCloseWidget()
    self:resetTimer()
end

function EyeSaver:addToMainMenu(menu_items)
    menu_items.eyesaver = {
        checked_func = function()
            return self.enabled
        end,
        text = _("EyeSaver messages"),
        keep_menu_open = false,
        callback = function()
            self:onToggleEyeSaverMessage(true)
        end,
    }
end

return EyeSaver
