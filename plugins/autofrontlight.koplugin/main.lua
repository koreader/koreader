local Device = require("device")

if not Device:isKindle() or
   (Device.model ~= "KindleVoyage" and Device.model ~= "KindleOasis") then
    return { disabled = true, }
end

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local AutoFrontlight = {}

function AutoFrontlight:_schedule()
    logger.dbg("AutoFrontlight:_schedule() @ ", os.time(), ", it should be executed at ", os.time() + 1)
    UIManager:scheduleIn(1, function()
        self:_action()
        self:_schedule()
    end)
end

function AutoFrontlight:_action()
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
    self:_schedule()
end

AutoFrontlight:init()

local AutoFrontlightWidget = WidgetContainer:new{
    name = "AutoFrontlight",
}

return AutoFrontlightWidget
