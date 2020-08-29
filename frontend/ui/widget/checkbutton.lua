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

local Blitbuffer = require("ffi/blitbuffer")
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
    max_width = nil,
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
        enabled = self.enabled,
        parent = self.parent or self,
        show_parent = self.show_parent or self,
    }
    self._textwidget = TextWidget:new{
        text = self.text,
        face = self.face,
        max_width = self.max_width,
        fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
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
    self.dimen = self._frame:getSize()
    self[1] = self._frame

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
            self[1].invert = true
            UIManager:widgetRepaint(self[1], self.dimen.x, self.dimen.y)
            UIManager:setDirty(nil, function()
                return "fast", self.dimen
            end)
            UIManager:tickAfterNext(function()
                self.callback()
                self[1].invert = false
                UIManager:widgetRepaint(self[1], self.dimen.x, self.dimen.y)
                UIManager:setDirty(nil, function()
                    return "fast", self.dimen
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
        return "fast", self.dimen
    end)
end

function CheckButton:unCheck()
    self:initCheckButton(false)
    UIManager:setDirty(self.parent, function()
        return "fast", self.dimen
    end)
end

function CheckButton:enable()
    self.enabled = true
    self:initCheckButton(self.checked)
    UIManager:setDirty(self.parent, function()
        return "ui", self.dimen
    end)
end

function CheckButton:disable()
    self.enabled = false
    self:initCheckButton(false)
    UIManager:setDirty(self.parent, function()
        return "ui", self.dimen
        -- best to use "ui" instead of "fast" when we make things gray
    end)
end

return CheckButton
