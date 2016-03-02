local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderFrontLight = InputContainer:new{
    steps = {0,1,1,1,1,2,2,2,3,4,5,6,7,8,9,10},
    gestureScale = Screen:getWidth() * FRONTLIGHT_SENSITIVITY_DECREASE,
}

function ReaderFrontLight:init()
    if Device:isTouchDevice() then
        self.ges_events = {
            Adjust = {
                GestureRange:new{
                    ges = "two_finger_pan",
                    rate = Device.model ~= 'Kobo_phoenix' and 3.0 or nil,
                }
            },
            PanRelease= {
                GestureRange:new{
                    ges = "two_finger_pan_release",
                }
            },
            Swipe = {
                GestureRange:new{
                    ges = "two_finger_swipe",
                }
            },
        }
    end

end

function ReaderFrontLight:onAdjust(arg, ges)
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity ~= nil then
        DEBUG("frontlight intensity", powerd.fl_intensity)
        local step = math.ceil(#self.steps * ges.distance / self.gestureScale)
        DEBUG("step = ", step)
        local delta_int = self.steps[step] or self.steps[#self.steps]
        DEBUG("delta_int = ", delta_int)
        local new_intensity
        if ges.direction == "north" then
            new_intensity = powerd.fl_intensity + delta_int
        elseif ges.direction == "south" then
            new_intensity = powerd.fl_intensity - delta_int
        end
        if new_intensity ~= nil then
            powerd:setIntensity(new_intensity)
        end
    end
    return true
end

function ReaderFrontLight:onShowIntensity()
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity ~= nil then
        UIManager:show(Notification:new{
            text = T(_("Frontlight intensity is set to %1."), powerd.fl_intensity),
            timeout = 1.0,
        })
    end
    return true
end

function ReaderFrontLight:onSwipe(arg, ges)
    if ges.direction == "north" or ges.direction == "south" then
        DEBUG("onSwipe activated")
        return self:onShowIntensity()
    end
end

function ReaderFrontLight:onPanRelease(arg, ges)
    DEBUG("onPanRelease activated")
    return self:onShowIntensity()
end

function ReaderFrontLight:onShowFlDialog()
    local powerd = Device:getPowerDevice()
    self.fl_dialog = InputDialog:new{
        title = _("Frontlight level"),
        input_hint = ("(%d - %d)"):format(powerd.fl_min, powerd.fl_max),
        buttons = {
            {
                {
                    text = _("Toggle"),
                    enabled = true,
                    callback = function()
                        self.fl_dialog:setInputText("")
                        powerd:toggleFrontlight()
                    end,
                },
                {
                    text = _("Apply"),
                    enabled = true,
                    callback = function()
                        self:fldialIntensity()
                    end,
                },
                {
                    text = _("OK"),
                    enabled = true,
                    callback = function()
                        self:fldialIntensity()
                        self:close()
                    end,
                },

            },
        },
        input_type = "number",
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    self.fl_dialog:onShowKeyboard()
    UIManager:show(self.fl_dialog)
end

function ReaderFrontLight:close()
    self.fl_dialog:onClose()
    UIManager:close(self.fl_dialog)
end

function ReaderFrontLight:fldialIntensity()
    local number = tonumber(self.fl_dialog:getInputText())
    if number ~= nil then
        Device:getPowerDevice():setIntensity(number)
    end
end

return ReaderFrontLight
