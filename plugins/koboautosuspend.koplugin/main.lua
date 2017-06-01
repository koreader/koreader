local Device = require("device")

if not Device:isKobo() and not Device:isSDL() then return { disabled = true, } end

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local KoboAutoSuspend = {
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/koboautosuspend.lua"),
    settings_id = 0,
    last_action_sec = os.time(),
}

function KoboAutoSuspend:_readTimeoutSecFrom(settings)
    local sec = settings:readSetting("auto_suspend_timeout_seconds")
    if type(sec) == "number" then
        return sec
    end
    return -1
end

function KoboAutoSuspend:_readTimeoutSec()
    local candidates = { self.settings, G_reader_settings }
    for _, candidate in ipairs(candidates) do
        local sec = self:_readTimeoutSecFrom(candidate)
        if sec ~= -1 then
            return sec
        end
    end

    -- default setting is 60 minutes
    return 60 * 60
end

function KoboAutoSuspend:_action(settings_id)
    if self.settings_id ~= settings_id then
        logger.dbg("KoboAutoSuspend: registered settings_id ",
                   settings_id,
                   " does not equal to current one ",
                   self.settings_id)
        return
    end

    local now = os.time()
    if self.last_action_sec + self.auto_suspend_sec <= now then
        logger.dbg("KoboAutoSuspend: will suspend the device")
        UIManager:suspend()
    else
        self:_schedule()
    end
end

function KoboAutoSuspend:_enabled()
    return self.auto_suspend_sec > 0
end

function KoboAutoSuspend:_schedule()
    assert(self:_enabled())
    local delay = self.last_action_sec + self.auto_suspend_sec - os.time();
    logger.dbg("KoboAutoSuspend: scheduleIn ", delay, " seconds")
    UIManager:scheduleIn(delay, function() self:_action(self.settings_id) end)
end

function KoboAutoSuspend:_deprecateLastTask()
    self.settings_id = self.settings_id + 1
    logger.dbg("KoboAutoSuspend: deprecateLastTask ", self.settings_id)
end

function KoboAutoSuspend:_start()
    if self:_enabled() then
        self:_schedule()
    end
end

function KoboAutoSuspend:init()
    self.auto_suspend_sec = self:_readTimeoutSec()
    self:_deprecateLastTask()
    self:_start()
end

function KoboAutoSuspend:onInputEvent()
    logger.dbg("KoboAutoSuspend: onInputEvent")
    self.last_action_sec = os.time()
end

-- We do not want auto suspend procedure to waste battery during suspend. So let's unschedule it
-- when suspending and restart it after resume.
function KoboAutoSuspend:onSuspend()
    logger.dbg("KoboAutoSuspend: onSuspend")
    self:_deprecateLastTask()
end

function KoboAutoSuspend:onResume()
    logger.dbg("KoboAutoSuspend: onResume")
    self:_start()
end

KoboAutoSuspend:init()

local KoboAutoSuspendWidget = WidgetContainer:new{
    name = "KoboAutoSuspend",
}

function KoboAutoSuspendWidget:onInputEvent()
    KoboAutoSuspend:onInputEvent()
end

function KoboAutoSuspendWidget:onSuspend()
    KoboAutoSuspend:onSuspend()
end

function KoboAutoSuspendWidget:onResume()
    KoboAutoSuspend:onResume()
end

return KoboAutoSuspendWidget
