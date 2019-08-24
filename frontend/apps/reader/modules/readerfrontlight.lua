local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderFrontLight = InputContainer:new{
    steps_fl = { 0.1, 0.1, 0.2, 0.4, 0.7, 1.1, 1.6, 2.2, 2.9, 3.7, 4.6, 5.6, 6.7, 7.9, 9.2, 10.6, },
    gestureScale = Screen:getWidth() * FRONTLIGHT_SENSITIVITY_DECREASE,
}

-- direction +1 - increase frontlight
-- direction -1 - decrease frontlight
function ReaderFrontLight:onChangeFlIntensity(ges, direction)
    local powerd = Device:getPowerDevice()
    local gestureScale
    local scale_multiplier
    if ges.ges == "two_finger_swipe" then
        -- for backward compatibility
        scale_multiplier = FRONTLIGHT_SENSITIVITY_DECREASE * 0.8
    elseif ges.ges == "swipe" then
        scale_multiplier = 0.8
    else
        scale_multiplier = 1
    end
    if ges.direction == "south" or ges.direction == "north" then
        gestureScale = Screen:getHeight() * scale_multiplier
    elseif ges.direction == "west" or ges.direction == "east" then
        gestureScale = Screen:getWidth() * scale_multiplier
    else
        local width = Screen:getWidth()
        local height = Screen:getHeight()
        -- diagonal
        gestureScale = math.sqrt(width * width + height * height) * scale_multiplier
    end
    if powerd.fl_intensity == nil then return false end

    local steps_tbl = {}
    local scale = (powerd.fl_max - powerd.fl_min) / 2 / 10.6
    for i = 1, #self.steps_fl, 1
    do
        steps_tbl[i] = math.ceil(self.steps_fl[i] * scale)
    end

    if ges.distance == nil then
        ges.distance = 1
    end
    local step = math.ceil(#steps_tbl * ges.distance / gestureScale)
    local delta_int = steps_tbl[step] or steps_tbl[#steps_tbl]
    if direction ~= -1 and direction ~= 1 then
        -- set default value (increase frontlight)
        direction = 1
    end
    local new_intensity = powerd.fl_intensity + direction * delta_int

    if new_intensity == nil then return true end
    -- when new_intensity <=0, toggle light off
    if new_intensity <= 0 then
        powerd:turnOffFrontlight()
    else
        powerd:setIntensity(new_intensity)
    end
    self:onShowIntensity()
    if self.view and self.view.footer_visible and self.view.footer.settings.frontlight then
        self.view.footer:updateFooter()
    end
    return true
end

-- direction +1 - increase frontlight warmth
-- direction -1 - decrease frontlight warmth
function ReaderFrontLight:onChangeFlWarmth(ges, direction)
    local powerd = Device:getPowerDevice()
    if powerd.fl_warmth == nil then return false end

    if powerd.auto_warmth then
        UIManager:show(Notification:new{
            text = _("Warmth is handled automatically."),
            timeout = 1.0,
        })
        return true
    end

    local gestureScale
    local scale_multiplier
    if ges.ges == "two_finger_swipe" then
        -- for backward compatibility
        scale_multiplier = FRONTLIGHT_SENSITIVITY_DECREASE * 0.8
    elseif ges.ges == "swipe" then
        scale_multiplier = 0.8
    else
        scale_multiplier = 1
    end

    if ges.direction == "south" or ges.direction == "north" then
        gestureScale = Screen:getHeight() * scale_multiplier
    elseif ges.direction == "west" or ges.direction == "east" then
        gestureScale = Screen:getWidth() * scale_multiplier
    else
        local width = Screen:getWidth()
        local height = Screen:getHeight()
        -- diagonal
        gestureScale = math.sqrt(width * width + height * height) * scale_multiplier
    end

    local steps_tbl = {}
    local scale = (powerd.fl_max - powerd.fl_min) / 2 / 10.6
    for i = 1, #self.steps_fl, 1
    do
        steps_tbl[i] = math.ceil(self.steps_fl[i] * scale)
    end

    if ges.distance == nil then
        ges.distance = 1
    end

    local step = math.ceil(#steps_tbl * ges.distance / gestureScale)
    local delta_int = steps_tbl[step] or steps_tbl[#steps_tbl]
    local warmth
    if direction ~= -1 and direction ~= 1 then
        -- set default value (increase frontlight)
        direction = 1
    end
    warmth = powerd.fl_warmth + direction * delta_int
    if warmth > 100 then
        warmth = 100
    elseif warmth < 0 then
        warmth = 0
    end
    powerd:setWarmth(warmth)
    self:onShowWarmth()
    return true
end


function ReaderFrontLight:onShowOnOff()
    local powerd = Device:getPowerDevice()
    local new_text
    if powerd.is_fl_on then
        new_text = _("Frontlight enabled.")
    else
        new_text = _("Frontlight disabled.")
    end
    UIManager:show(Notification:new{
        text = new_text,
        timeout = 1.0,
    })
    return true
end

function ReaderFrontLight:onShowIntensity()
    if not Device:hasFrontlight() then return true end
    local powerd = Device:getPowerDevice()
    local new_text
    if powerd:isFrontlightOff() then
        new_text = _("Frontlight disabled.")
    else
        new_text = T(_("Frontlight intensity set to %1."), powerd:frontlightIntensity())
    end
    UIManager:show(Notification:new{
        text = new_text,
        timeout = 1,
    })
    return true
end

function ReaderFrontLight:onShowWarmth(value)
    local powerd = Device:getPowerDevice()
    if powerd.fl_warmth ~= nil then
        UIManager:show(Notification:new{
            text = T(_("Warmth set to %1."), powerd.fl_warmth),
            timeout = 1.0,
        })
    end
    return true
end

function ReaderFrontLight:onShowFlDialog()
    local FrontLightWidget = require("ui/widget/frontlightwidget")
    UIManager:show(FrontLightWidget:new{})
end

function ReaderFrontLight:close()
    self.fl_dialog:onClose()
    UIManager:close(self.fl_dialog)
end

return ReaderFrontLight
