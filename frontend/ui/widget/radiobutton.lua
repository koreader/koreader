--[[--
Widget that shows a radiobutton checked (`◉`) or unchecked (`◯`)
or nothing of the same size.

Example:

    local RadioButton = require("ui/widget/radiobutton")
    local parent_widget = FrameContainer:new{}
    table.insert(parent_widget, RadioButton:new{
        checkable = false, -- shows nothing when false, defaults to true
        checked = function() end, -- whether the box is checked
    })
    UIManager:show(parent_widget)

]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local RadioButton = InputContainer:new{
    checkable = true,
    checked = false,
    enabled = true,
    face = Font:getFace("smallinfofont"),
    background = Blitbuffer.COLOR_WHITE,
    width = 0,
    height = 0,
}

function RadioButton:init()
    self._checked_widget = TextWidget:new{
        text = "◉ " .. self.text,
        face = self.face,
        max_width = self.max_width,
    }
    self._unchecked_widget = TextWidget:new{
        text = "◯ " .. self.text,
        face = self.face,
        max_width = self.max_width,
    }
    self._empty_widget = TextWidget:new{
        text = "" .. self.text,
        face = self.face,
        max_width = self.max_width,
    }
    self._widget_size = self._unchecked_widget:getSize()
    if self.width == nil then
        self.width = self._widget_size.w
    end
    self._radio_button = self.checkable
                             and (self.checked and self._checked_widget or self._unchecked_widget)
                             or self._empty_widget
    self:update()
    self.dimen = self.frame:getSize()
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

function RadioButton:update()
    self.frame = FrameContainer:new{
        margin = self.margin,
        bordersize = self.bordersize,
        background = self.background,
        radius = self.radius,
        padding = self.padding,
        LeftContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = self._widget_size.h
            },
            self._radio_button,
        }
    }
    self[1] = self.frame
end

function RadioButton:onFocus()
    self.frame.invert = true
    return true
end

function RadioButton:onUnfocus()
    self.frame.invert = false
    return true
end

function RadioButton:onTapCheckButton()
    if self.enabled and self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback()
        else
            -- While I'd like to only flash the button itself, we have to make do with flashing the full width of the TextWidget...
            self.frame.invert = true
            UIManager:widgetRepaint(self.frame, self.dimen.x, self.dimen.y)
            UIManager:setDirty(nil, function()
                return "fast", self.dimen
            end)
            UIManager:tickAfterNext(function()
                self.callback()
                self.frame.invert = false
                UIManager:widgetRepaint(self.frame, self.dimen.x, self.dimen.y)
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

function RadioButton:onHoldCheckButton()
    if self.enabled and self.hold_callback then
        self.hold_callback()
    elseif self.hold_input then
        self:onInput(self.hold_input)
    elseif type(self.hold_input_func) == "function" then
        self:onInput(self.hold_input_func())
    end
    return true
end

function RadioButton:check(callback)
    self._radio_button = self._checked_widget
    self.checked = true
    self:update()
    UIManager:setDirty(self.parent, function()
        return "fast", self.dimen
    end)
end

function RadioButton:unCheck()
    self._radio_button = self._unchecked_widget
    self.checked = false
    self:update()
    UIManager:setDirty(self.parent, function()
        return "fast", self.dimen
    end)
end

return RadioButton
