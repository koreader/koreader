local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local DEBUG = require("dbg")
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
                    rate = Device:getModel() ~= 'Kobo_phoenix' and 3.0 or nil,
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
        self.ui.menu:registerToMainMenu(self)
    end

end

function ReaderFrontLight:onAdjust(arg, ges)
    local powerd = Device:getPowerDevice()
    if powerd.flIntensity ~= nil then
        DEBUG("frontlight intensity", powerd.flIntensity)
        local step = math.ceil(#self.steps * ges.distance / self.gestureScale)
        DEBUG("step = ", step)
        local delta_int = self.steps[step] or self.steps[#self.steps]
        DEBUG("delta_int = ", delta_int)
        if ges.direction == "north" then
            powerd:setIntensity(powerd.flIntensity + delta_int)
        elseif ges.direction == "south" then
            powerd:setIntensity(powerd.flIntensity - delta_int)
        end
    end
    return true
end

function ReaderFrontLight:onShowIntensity()
    local powerd = Device:getPowerDevice()
    if powerd.flIntensity ~= nil then
        UIManager:show(Notification:new{
            text = _("Frontlight intensity is set to ")..powerd.flIntensity,
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

function ReaderFrontLight:addToMainMenu(tab_item_table)
    -- insert fldial command to setting tab of reader menu
    table.insert(tab_item_table.setting, {
        text = _("Frontlight settings"),
        callback = function()
            self:onShowFlDialog()
        end,
    })
end

function ReaderFrontLight:onShowFlDialog()
    local powerd = Device:getPowerDevice()
    self.fl_dialog = InputDialog:new{
        title = _("Frontlight Level"),
        input_hint = ("(%d - %d)"):format(powerd.fl_min, powerd.fl_max),
        buttons = {
            {
                {
                    text = _("Toggle"),
                    enabled = true,
                    callback = function()
                        self.fl_dialog.input:setText("")
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
    G_reader_settings:saveSetting("frontlight_intensity", Device:getPowerDevice().flIntensity)
    UIManager:close(self.fl_dialog)
end

function ReaderFrontLight:fldialIntensity()
    local number = tonumber(self.fl_dialog:getInputText())
    if number ~= nil then
        Device:getPowerDevice():setIntensity(number)
    end
end

return ReaderFrontLight
