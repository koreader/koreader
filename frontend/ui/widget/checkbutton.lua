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
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local RadioMark = require("ui/widget/radiomark")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local CheckButton = InputContainer:extend{
    callback = nil,
    hold_callback = nil,
    checkable = true, -- empty space when false
    checked = false,
    enabled = true,
    radio = false, -- radio mark when true
    face = Font:getFace("smallinfofont"),
    background = Blitbuffer.COLOR_WHITE,
    text = nil,
    parent = nil, -- parent widget, must be set by the caller
    width = nil, -- default value: parent widget's added widgets available width
    -- If the parent widget has no getAddedWidgetAvailableWidth() method, the width must be set by the caller.
}

function CheckButton:init()
    self:initCheckButton(self.checked)
end

function CheckButton:initCheckButton(checked)
    self.checked = checked
    if self.radio then
        self._checkmark = RadioMark:new{
            checkable = self.checkable,
            checked = self.checked,
            enabled = self.enabled,
            face = self.face,
            parent = self.parent or self,
            show_parent = self.show_parent or self,
        }
    else
        self._checkmark = CheckMark:new{
            checkable = self.checkable,
            checked = self.checked,
            enabled = self.enabled,
            face = self.face,
            parent = self.parent or self,
            show_parent = self.show_parent or self,
        }
    end
    local fgcolor = self.fgcolor or Blitbuffer.COLOR_BLACK
    self._textwidget = TextBoxWidget:new{
        text = self.text,
        face = self.face,
        width = (self.width or self.parent:getAddedWidgetAvailableWidth()) - self._checkmark.dimen.w,
        bold = self.bold,
        fgcolor = self.enabled and fgcolor or Blitbuffer.COLOR_DARK_GRAY,
        bgcolor = self.bgcolor,
    }
    local textbox_shift = math.max(0, self._checkmark.baseline - self._textwidget:getBaseline())
    self._verticalgroup = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{
            width = textbox_shift,
        },
        self._textwidget,
    }
    self._horizontalgroup = HorizontalGroup:new{
        align = "top",
        self._checkmark,
        self._verticalgroup,
    }
    self._frame = FrameContainer:new{
        bordersize = 0,
        background = self.background,
        margin = 0,
        padding = 0,
        show_parent = self.show_parent or self,
        self._horizontalgroup,
    }
    self.dimen = self._frame:getSize()
    self[1] = self._frame

    self.ges_events = {
        TapCheckButton = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldCheckButton = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
        -- Safe-guard for when used inside a MovableContainer
        HoldReleaseCheckButton = {
            GestureRange:new{
                ges = "hold_release",
                range = self.dimen,
            },
        }
    }
end

function CheckButton:onTapCheckButton()
    if not self.enabled then return true end
    if self.tap_input then
        self:onInput(self.tap_input)
    elseif self.tap_input_func then
        self:onInput(self.tap_input_func())
    else
        if G_reader_settings:isFalse("flash_ui") then
            if not self.radio then
                self:toggleCheck()
            end
            if self.callback then
                self.callback()
            end
        else
            -- c.f., ui/widget/iconbutton for the canonical documentation about the flash_ui code flow

            local highlight_dimen = self.dimen

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
            if not self.radio then
                self:toggleCheck()
            end
            if self.callback then
                self.callback()
            end

            UIManager:forceRePaint()
        end
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
        elseif self.hold_input_func then
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

function CheckButton:toggleCheck()
    self:initCheckButton(not self.checked)
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

function CheckButton:onFocus()
    if not self.enabled then
        return false
    end
    self._frame.invert = true
    return true
end

function CheckButton:onUnfocus()
    if not self.enabled then
        return false
    end
    self._frame.invert = false
    return true
end

return CheckButton
