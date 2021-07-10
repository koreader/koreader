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
    face = Font:getFace("smallinfofont"),
    background = Blitbuffer.COLOR_WHITE,
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
        background = self.background,
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
            },
            -- Safe-guard for when used inside a MovableContainer
            HoldReleaseCheckButton = {
                GestureRange:new{
                    ges = "hold_release",
                    range = self.dimen,
                },
                doc = "Hold Release Button",
            }
        }
    end
end

function CheckButton:onTapCheckButton()
    if self.enabled and self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback()
        else
            -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

            -- Unlike RadioButton, the frame's width stops at the text width, but we want our highlight to span the full width...
            -- (That's when we have one, some callers don't pass a width, so, handle that, too).
            local highlight_dimen = self.dimen
            highlight_dimen.w = self.width and self.width or self.dimen.w

            -- Highlight
            --
            self[1].invert = true
            UIManager:widgetInvert(self[1], highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "fast", highlight_dimen)

            UIManager:forceRePaint()
            UIManager:yieldToEPDC()

            -- Unhighlight
            --
            self[1].invert = false
            UIManager:widgetInvert(self[1], highlight_dimen.x, highlight_dimen.y, highlight_dimen.w)
            UIManager:setDirty(nil, "ui", highlight_dimen)

            -- Callback
            --
            self.callback()

            UIManager:forceRePaint()
        end
    elseif self.tap_input then
        self:onInput(self.tap_input)
    elseif type(self.tap_input_func) == "function" then
        self:onInput(self.tap_input_func())
    end
    return true
end

function CheckButton:onHoldCheckButton()
    -- If we're going to process this hold, we must make
    -- sure to also handle its hold_release below, so it's
    -- not propagated up to a MovableContainer
    self._hold_handled = nil
    if self.enabled then
        if self.hold_callback then
            self.hold_callback()
            self._hold_handled = true
        elseif self.hold_input then
            self:onInput(self.hold_input, true)
            self._hold_handled = true
        elseif type(self.hold_input_func) == "function" then
            self:onInput(self.hold_input_func(), true)
            self._hold_handled = true
        end
    end
    return true
end

function CheckButton:onHoldReleaseCheckButton()
    if self._hold_handled then
        self._hold_handled = nil
        return true
    end
    return false
end

function CheckButton:check()
    self:initCheckButton(true)
    UIManager:setDirty(self.parent, function()
        return "ui", self.dimen
    end)
end

function CheckButton:unCheck()
    self:initCheckButton(false)
    UIManager:setDirty(self.parent, function()
        return "ui", self.dimen
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
    end)
end

return CheckButton
