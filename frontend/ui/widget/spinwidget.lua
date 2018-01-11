local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local NumberPickerWidget = require("ui/widget/numberpickerwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local SpinWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = Screen:getWidth() * 0.95,
    height = Screen:getHeight(),
    value = 1,
    value_max = 20,
    value_min = 0,
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
}

function SpinWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close spin widget" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                },
            },
         }
    end
    self:update()
end

function SpinWidget:update()
    local value_widget = NumberPickerWidget:new{
        show_parent = self,
        width = self.screen_width * 0.2,
        value = self.value,
        value_min = self.value_min,
        value_max = self.value_max,
        value_step = 1,
        value_hold_step = 4,
    }
    local value_group = HorizontalGroup:new{
        align = "center",
        value_widget,
    }

    local value_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = self.title_text,
            face = self.title_face,
            bold = true,
            width = self.width,
        },
    }
    local value_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local value_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = value_title:getSize().h
        },
        value_title,
        CloseButton:new{ window = self, padding_top = Size.margin.title, },
    }
    local buttons = {
        {
            {
                text = self.cancel_text,
                callback = function()
                    self:onClose()
                end,
            },
            {
                text = self.ok_text,
                callback = function()
                    if self.callback then
                        self.value = value_widget:getValue()
                        self:callback(self)
                    end
                    self:onClose()
                end,
            },
        }
    }

    local ok_cancel_buttons = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    self.spin_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            value_bar,
            value_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = value_group:getSize().h + self.screen_height * 0.1,
                },
                value_group
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = ok_cancel_buttons:getSize().h,
                },
                ok_cancel_buttons
            }
        }
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen =Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        FrameContainer:new{
            bordersize = 0,
            self.spin_frame,
        }
    }
    UIManager:setDirty(self, function()
        return "ui", self.spin_frame.dimen
    end)
end

function SpinWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.spin_frame.dimen
    end)
    return true
end

function SpinWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.spin_frame.dimen
    end)
    return true
end

function SpinWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function SpinWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.spin_frame.dimen) then
        self:onClose()
    end
    return true
end

function SpinWidget:onClose()
    UIManager:close(self)
    return true
end

return SpinWidget
