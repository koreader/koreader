local CenterContainer = require("ui/widget/container/centercontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local _ = require("gettext")

--[[
a button widget that shows text or a icon and handles callback when tapped
--]]
local Button = InputContainer:new{
    text = nil, -- mandatory
    icon = nil,
    preselect = false,
    callback = nil,
    enabled = true,
    margin = 0,
    bordersize = 3,
    background = Blitbuffer.COLOR_WHITE,
    radius = 15,
    padding = 2,
    width = nil,
    max_width = nil,
    text_font_face = "cfont",
    text_font_size = 20,
    text_font_bold = true,
}

function Button:init()
    if self.text then
        self.label_widget = TextWidget:new{
            text = self.text,
            max_width = self.max_width and self.max_width - 2*self.padding - 2*self.margin - 2*self.bordersize or nil,
            fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GREY,
            bold = self.text_font_bold,
            face = Font:getFace(self.text_font_face, self.text_font_size)
        }
    else
        self.label_widget = ImageWidget:new{
            file = self.icon,
            dim = not self.enabled,
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
        padding = self.padding,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = widget_size.h
            },
            self.label_widget,
        }
    }
    if self.preselect then
        self:onFocus()
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
            }
        }
    end
end

function Button:setText(text)
    self.text = text
    self.width = nil
    self:init()
end

function Button:setIcon(icon)
    self.icon = icon
    self.width = nil
    self:init()
end

function Button:onFocus()
    self.frame.invert = true
    return true
end

function Button:onUnfocus()
    self.frame.invert = false
    return true
end

function Button:enable()
    self.enabled = true
    if self.text then
        if self.enabled then
            self.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
        else
            self.label_widget.fgcolor = Blitbuffer.COLOR_GREY
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
            self.label_widget.fgcolor = Blitbuffer.COLOR_GREY
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
        UIManager:scheduleIn(0.0, function()
            self[1].invert = true
            UIManager:setDirty(self.show_parent, function()
                return "ui", self[1].dimen
            end)
        end)
        UIManager:scheduleIn(0.1, function()
            self.callback()
            self[1].invert = false
            UIManager:setDirty(self.show_parent, function()
                return "ui", self[1].dimen
            end)
        end)
    elseif self.tap_input then
        self:onInput(self.tap_input)
    elseif type(self.tap_input_func) == "function" then
        self:onInput(self.tap_input_func())
    end
    return true
end

function Button:onHoldSelectButton()
    if self.enabled and self.hold_callback then
        self.hold_callback()
    elseif self.hold_input then
        self:onInput(self.hold_input)
    elseif type(self.hold_input_func) == "function" then
        self:onInput(self.hold_input_func())
    end
    return true
end

return Button
