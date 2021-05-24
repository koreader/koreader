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
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local TimeWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
    hour = 0,
    hour_max = 23,
    min = 0,
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
}

function TimeWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.width = math.floor(self.screen_width * 0.95)
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close time widget" }
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

    -- Actually the widget layout
    self:update()
end

function TimeWidget:update()
    local hour_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.screen_width * 0.2),
        value = self.hour,
        value_min = 0,
        value_max = self.hour_max,
        value_step = 1,
        value_hold_step = 4,
    }
    local min_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.screen_width * 0.2),
        value = self.min,
        value_min = 0,
        value_max = 59,
        value_step = 1,
        value_hold_step = 10,
    }
    local colon_space = TextBoxWidget:new{
        text = ":",
        alignment = "center",
        face = self.title_face,
        bold = true,
        width = math.floor(self.screen_width * 0.2),
    }
    local time_group = HorizontalGroup:new{
        align = "center",
        hour_widget,
        colon_space,
        min_widget,
    }

    local closebutton = CloseButton:new{ window = self, padding_top = Size.margin.title, }
    local time_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = self.title_text,
            face = self.title_face,
            bold = true,
            max_width = math.floor(self.screen_width * 0.95) - closebutton:getSize().w,
        },
    }
    local time_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local time_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = time_title:getSize().h
        },
        time_title,
        closebutton,
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
                        self.hour = hour_widget:getValue()
                        self.min = min_widget:getValue()
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

    self.time_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            time_bar,
            time_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = math.floor(self.screen_width * 0.95),
                    h = math.floor(time_group:getSize().h * 1.2),
                },
                time_group
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
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        FrameContainer:new{
            bordersize = 0,
            self.time_frame,
        }
    }
    UIManager:setDirty(self, function()
        return "ui", self.time_frame.dimen
    end)
end

function TimeWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.time_frame.dimen
    end)
end

function TimeWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.time_frame.dimen
    end)
    return true
end

function TimeWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function TimeWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.time_frame.dimen) then
        self:onClose()
    end
    return true
end

function TimeWidget:onClose()
    UIManager:close(self)
    return true
end

return TimeWidget
