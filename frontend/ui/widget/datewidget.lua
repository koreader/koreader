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

local DateWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
    day = 1,
    month = 1,
    year = 2017,
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
}

function DateWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.width = math.floor(self.screen_width * 0.95)
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close date widget" }
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

function DateWidget:update()
    local year_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.screen_width * 0.2),
        value = self.year,
        value_min = 2017,
        value_max = 2037,
        value_step = 1,
        value_hold_step = 4,
    }
    local month_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.screen_width * 0.2),
        value = self.month,
        value_min = 1,
        value_max = 12,
        value_step = 1,
        value_hold_step = 3,
    }
    local day_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.screen_width * 0.2),
        value = self.day,
        value_min = 1,
        value_max = 31,
        value_step = 1,
        value_hold_step = 5,
        date_month = month_widget,
        date_year = year_widget,
    }
    local dash_space = TextBoxWidget:new{
        text = "–",
        alignment = "center",
        face = self.title_face,
        bold = true,
        width = math.floor(self.screen_width * 0.1),
    }
    local date_group = HorizontalGroup:new{
        align = "center",
        year_widget,
        dash_space,
        month_widget,
        dash_space,
        day_widget,
    }

    local date_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = self.title_text,
            face = self.title_face,
            bold = true,
            width = math.floor(self.screen_width * 0.95),
        },
    }
    local date_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local date_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = date_title:getSize().h
        },
        date_title,
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
                        self.year = year_widget:getValue()
                        self.month = month_widget:getValue()
                        self.day = day_widget:getValue()
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

    self.date_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            date_bar,
            date_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = math.floor(self.screen_width * 0.95),
                    h = math.floor(date_group:getSize().h * 1.2),
                },
                date_group
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
            padding = Size.padding.default,
            self.date_frame,
        }
    }
    UIManager:setDirty(self, function()
        return "ui", self.date_frame.dimen
    end)
end

function DateWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.date_frame.dimen
    end)
end

function DateWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.date_frame.dimen
    end)
    return true
end

function DateWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function DateWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.date_frame.dimen) then
        self:onClose()
    end
    return true
end

function DateWidget:onClose()
    UIManager:close(self)
    return true
end

return DateWidget
