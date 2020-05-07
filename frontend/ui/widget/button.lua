--[[--
A button widget that shows text or an icon and handles callback when tapped.

@usage
    local Button = require("ui/widget/button")
    local button = Button:new{
        text = _("Press me!"),
        enabled = false, -- defaults to true
        callback = some_callback_function,
        width = Screen:scaleBySize(50),
        max_width = Screen:scaleBySize(100),
        bordersize = Screen:scaleBySize(3),
        margin = 0,
        padding = Screen:scaleBySize(2),
    }
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Button = InputContainer:new{
    text = nil, -- mandatory
    text_func = nil,
    icon = nil,
    icon_rotation_angle = 0,
    preselect = false,
    callback = nil,
    enabled = true,
    allow_hold_when_disabled = false,
    margin = 0,
    bordersize = Size.border.button,
    background = Blitbuffer.COLOR_WHITE,
    radius = Size.radius.button,
    padding = Size.padding.button,
    padding_h = nil,
    padding_v = nil,
    width = nil,
    max_width = nil,
    text_font_face = "cfont",
    text_font_size = 20,
    text_font_bold = true,
}

function Button:init()
    -- Prefer an optional text_func over text
    if self.text_func and type(self.text_func) == "function" then
        self.text = self.text_func()
    end

    if not self.padding_h then
        self.padding_h = self.padding
    end
    if not self.padding_v then
        self.padding_v = self.padding
    end

    if self.text then
        self.label_widget = TextWidget:new{
            text = self.text,
            max_width = self.max_width and self.max_width - 2*self.padding_h - 2*self.margin - 2*self.bordersize or nil,
            fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
            bold = self.text_font_bold,
            face = Font:getFace(self.text_font_face, self.text_font_size)
        }
    else
        self.label_widget = ImageWidget:new{
            file = self.icon,
            rotation_angle = self.icon_rotation_angle,
            dim = not self.enabled,
            scale_for_dpi = true,
        }
    end
    local widget_size = self.label_widget:getSize()
    if self.width == nil then
        self.width = widget_size.w
    end
    -- set FrameContainer content
    self.frame = FrameContainer:new{
        margin = self.margin,
        bordersize = self.bordersize,
        background = self.background,
        radius = self.radius,
        padding_top = self.padding_v,
        padding_bottom = self.padding_v,
        padding_left = self.padding_h,
        padding_right = self.padding_h,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = widget_size.h
            },
            self.label_widget,
        }
    }
    if self.preselect then
        self.frame.invert = true
    end
    self.dimen = self.frame:getSize()
    self[1] = self.frame
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelectButton = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Tap Button",
            },
            HoldSelectButton = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Button",
            },
            -- Safe-guard for when used inside a MovableContainer
            HoldReleaseSelectButton = {
                GestureRange:new{
                    ges = "hold_release",
                    range = self.dimen,
                },
            }
        }
    end
end

function Button:setText(text, width)
    self.text = text
    self.width = width
    self:init()
end

function Button:setIcon(icon)
    self.icon = icon
    self.width = nil
    self:init()
end

function Button:onFocus()
    if self.no_focus then return end
    self.frame.invert = true
    return true
end

function Button:onUnfocus()
    if self.no_focus then return end
    self.frame.invert = false
    return true
end

function Button:enable()
    self.enabled = true
    if self.text then
        if self.enabled then
            self.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
        else
            self.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
        end
    else
        self.label_widget.dim = not self.enabled
    end
end

function Button:disable()
    self.enabled = false
    if self.text then
        if self.enabled then
            self.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
        else
            self.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
        end
    else
        self.label_widget.dim = not self.enabled
    end
end

function Button:enableDisable(enable)
    if enable then
        self:enable()
    else
        self:disable()
    end
end

function Button:hide()
    if self.icon then
        self.frame.orig_background = self[1].background
        self.frame.background = nil
        self.label_widget.hide = true
    end
end

function Button:show()
    if self.icon then
        self.label_widget.hide = false
        self.frame.background = self[1].old_background
    end
end

function Button:showHide(show)
    if show then
        self:show()
    else
        self:hide()
    end
end

function Button:onTapSelectButton()
    if self.enabled and self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback()
        else
            -- For most of our buttons, we can't avoid that initial repaint...
            self[1].invert = true
            UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
            -- NOTE: This completely insane double repaint is needed to avoid cosmetic issues with FrameContainer's rounded corners on Text buttons...
            --       On the upside, we now actually get to *see* those rounded corners (as the highlight), where it was a simple square before.
            --       c.f., #4554 & #4541
            -- NOTE: self[1] -> self.frame, if you're confused about what this does vs. onFocus/onUnfocus ;).
            if self.text then
                UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
            end
            UIManager:setDirty(nil, function()
                return "fast", self[1].dimen
            end)
            -- And we also often have to delay the callback to both see the flash and/or avoid tearing artefacts w/ fast refreshes...
            UIManager:tickAfterNext(function()
                self.callback()
                if not self[1] or not self[1].invert or not self[1].dimen then
                    -- widget no more there (destroyed, re-init'ed by setText(), or not inverted: nothing to invert back
                    return
                end
                self[1].invert = false
                UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                if self.text then
                    UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                end
                UIManager:setDirty(nil, function()
                    return "fast", self[1].dimen
                end)
            end)
        end
    elseif self.tap_input then
        self:onInput(self.tap_input)
    elseif type(self.tap_input_func) == "function" then
        self:onInput(self.tap_input_func())
    end
    if self.readonly ~= true then
        return true
    end
end

function Button:onHoldSelectButton()
    if self.hold_callback and (self.enabled or self.allow_hold_when_disabled) then
        self.hold_callback()
    elseif self.hold_input then
        self:onInput(self.hold_input, true)
    elseif type(self.hold_input_func) == "function" then
        self:onInput(self.hold_input_func(), true)
    end
    if self.readonly ~= true then
        return true
    end
end

function Button:onHoldReleaseSelectButton()
    -- Safe-guard for when used inside a MovableContainer,
    -- which would handle HoldRelease and process it like
    -- a Hold if we wouldn't return true here
    if self.hold_callback and (self.enabled or self.allow_hold_when_disabled) then
        return true
    elseif self.hold_input or type(self.hold_input_func) == "function" then
        return true
    end
    return false
end

return Button
