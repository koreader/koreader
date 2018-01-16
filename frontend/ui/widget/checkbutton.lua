--[[--
Button widget that shows a checkmark (`✓`) when checked and an empty box (`□`)
when unchecked.

Example:

    local CheckButton = require("ui/widget/CheckButton")
    local parent_widget = OverlapGroup:new{}
    table.insert(parent_widget, CheckButton:new{
        text = _("Show password"),
        callback = function() end,
    })
    UIManager:show(parent_widget)

]]

local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local CheckButton = InputContainer:new{
    callback = nil,
    hold_callback = nil,
    checked = false,
    enabled = true,
    face = Font:getFace("cfont"),
    overlap_align = "right",
    text = nil,
    toggle_text = nil,
    window = nil,

    padding = Screen:scaleBySize(5),
    margin = Screen:scaleBySize(5),
    bordersize = Screen:scaleBySize(3),
}

function CheckButton:init()
    self:initCheckButton(self.checked)
end

function CheckButton:initCheckButton(checked)
    self.checked = checked
    self._checkmark = CheckMark:new{
        checked = self.checked,
    }
    self._textwidget = TextWidget:new{
        text = self.text,
        face = self.face,
    }
    self._horizontalgroup = HorizontalGroup:new{
        self._checkmark,
        self._textwidget,
    }
    self._frame = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        self._horizontalgroup,
    }
    self[1] = self._frame
    self.dimen = self._frame:getSize()
    if Device:isTouchDevice() then
        self.ges_events = {
            TapCheckButton = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Tap Button",
            },
            HoldCheckButton = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Button",
            }
        }
    end
end

function CheckButton:onTapCheckButton()
    if self.enabled and self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback()
        else
            UIManager:scheduleIn(0.0, function()
                self.invert = true
                UIManager:setDirty(self.show_parent, function()
                    return "ui", self.dimen
                end)
            end)
            UIManager:scheduleIn(0.1, function()
                self.callback()
                self.invert = false
                UIManager:setDirty(self.show_parent, function()
                    return "ui", self.dimen
                end)
            end)
        end
    elseif self.tap_input then
        self:onInput(self.tap_input)
    elseif type(self.tap_input_func) == "function" then
        self:onInput(self.tap_input_func())
    end
    return true
end

function CheckButton:onHoldCheckButton()
    if self.enabled and self.hold_callback then
        self.hold_callback()
    elseif self.hold_input then
        self:onInput(self.hold_input)
    elseif type(self.hold_input_func) == "function" then
        self:onInput(self.hold_input_func())
    end
    return true
end

function CheckButton:check()
    self:initCheckButton(true)
    UIManager:setDirty(self.parent, function()
        return "partial", self.dimen
    end)
end

function CheckButton:unCheck()
    self:initCheckButton(false)
    UIManager:setDirty(self.parent, function()
        return "partial", self.dimen
    end)
end

return CheckButton
