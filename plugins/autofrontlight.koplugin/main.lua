local Device = require("device")

if not Device:isKindle() or
   (Device.model ~= "KindleVoyage" and Device.model ~= "KindleOasis") then
    return { disabled = true, }
end

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local AutoFrontlight = {
  settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autofrontlight.lua"),
  settings_id = 0,
  enabled = false,
}

function AutoFrontlight:_schedule()
    if not self.enabled then
        logger.dbg("AutoFrontlight:_schedule() is disabled")
        return
    end

    local settings_id = self.settings_id
    logger.dbg("AutoFrontlight:_schedule() @ ", os.time(), ", it should be executed at ", os.time() + 1)
    UIManager:scheduleIn(1, function()
        self:_action(settings_id)
        self:_schedule(self.settings_id)
    end)
end

function AutoFrontlight:_action(settings_id)
    if settings_id ~= self.settings_id then
        logger.dbg("AutoFrontlight:_action(): registered settings_id ",
                   settings_id,
                   " does not equal to current one ",
                   self.settings_id)
        return
    end
    logger.dbg("AutoFrontlight:_action() @ ", os.time())
    if Device:ambientBrightnessLevel() <= 1 then
        logger.dbg("AutoFrontlight: going to turn on frontlight")
        Device:getPowerDevice():turnOnFrontlight()
    else
        logger.dbg("AutoFrontlight: going to turn off frontlight")
        Device:getPowerDevice():turnOffFrontlight()
    end
end

function AutoFrontlight:init()
    self.enabled = not self.settings:nilOrFalse("enable")
    logger.dbg("AutoFrontlight:init() self.enabled: ", self.enabled)
    self:_schedule()
end

AutoFrontlight:init()

local AutoFrontlightWidget = WidgetContainer:new{
    name = "AutoFrontlight",
}

return AutoFrontlightWidget
