local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local TimeWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
    hour = 0,
    min = 0,
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
}

function TimeWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.light_bar = {}
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    self.width = self.screen_width * 0.95
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close time" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapCloseFL = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                },
            },
         }
    end

    self:update()
end

function TimeWidget:changeHours(hour, change)
    hour = hour + change
    if hour > 23 then
        hour = hour - 24
    elseif hour < 0 then
        hour = 24 + hour
    end
    return hour
end

function TimeWidget:changeMin(min, change)
    min = min + change
    if min > 59 then
        min = min - 60
    elseif min < 0 then
        min = 60 + min
    end
    return min
end

function TimeWidget:paintContainer()
    local padding_span = VerticalSpan:new{ width = math.ceil(self.screen_height * 0.01) }
    local padding_span_top_bottom = VerticalSpan:new{ width = math.ceil(self.screen_height * 0.20) }
    local button_group_down = HorizontalGroup:new{ align = "center" }
    local button_group_up = HorizontalGroup:new{ align = "center" }
    local vertical_group = VerticalGroup:new{ align = "center" }

    local button_up_hours = Button:new{
        text = "▲",
        bordersize = 2,
        margin = 2,
        radius = 0,
        text_font_size = 24,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()
            self.hour = self:changeHours(self.hour, 1)
            self:update()
        end,
        hold_callback = function()
            self.hour = self:changeHours(self.hour, 6)
            self:update()
        end
    }
    local button_down_hours = Button:new{
        text = "▼",
        bordersize = 2,
        margin = 2,
        radius = 0,
        text_font_size = 24,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()
            self.hour = self:changeHours(self.hour, -1)
            self:update()
        end,
        hold_callback = function()
            self.hour = self:changeHours(self.hour, -6)
            self:update()
        end
    }

    local button_up_minutes = Button:new{
        text = "▲",
        bordersize = 2,
        margin = 2,
        radius = 0,
        text_font_size = 24,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()
            self.min = self:changeMin(self.min, 1)
            self:update()
        end,
        hold_callback = function()
            self.min = self:changeMin(self.min, 15)
            self:update()
        end
    }
    local button_down_minutes = Button:new{
        text = "▼",
        bordersize = 2,
        margin = 2,
        radius = 0,
        text_font_size = 24,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()
            self.min = self:changeMin(self.min, -1)
            self:update()
        end,
        hold_callback = function()
            self.min = self:changeMin(self.min, -15)
            self:update()
        end
    }
    local empty_space = HorizontalSpan:new{
        width = self.screen_width * 0.20
    }

    local text_hours = TextBoxWidget:new{
        text = string.format("%02d", self.hour),
        alignment = "center",
        face = self.title_face,
        text_font_size = 24,
        bold = true,
        width = self.screen_width * 0.20,
    }
    local text_minutes = TextBoxWidget:new{
        text = string.format("%02d", self.min),
        alignment = "center",
        face = self.title_face,
        text_font_size = 24,
        bold = true,
        width = self.screen_width * 0.20,
    }

    local colon_space = TextBoxWidget:new{
        text = ":",
        alignment = "center",
        face = self.title_face,
        bold = true,
        width = self.screen_width * 0.20 + 2 * button_up_hours.bordersize + 2 * button_up_minutes.bordersize
    }

    local button_table_up = HorizontalGroup:new{
        align = "center",
        button_up_hours,
        empty_space,
        button_up_minutes,
    }
    local time_text_table = HorizontalGroup:new{
        align = "center",
        text_hours,
        colon_space,
        text_minutes,
    }
    local button_table_down = HorizontalGroup:new{
        align = "center",
        button_down_hours,
        empty_space,
        button_down_minutes,
    }

    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)
    table.insert(vertical_group, padding_span_top_bottom)
    table.insert(vertical_group, button_group_up)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, time_text_table)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_down)
    table.insert(vertical_group, padding_span_top_bottom)

    return CenterContainer:new{
        dimen = Geom:new{
            w = self.screen_width * 0.95,
            h = vertical_group:getSize().h
        },
        vertical_group
    }
end

function TimeWidget:update()
    local time_title = FrameContainer:new{
        padding = Screen:scaleBySize(5),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        TextWidget:new{
            text = self.title_text,
            face = self.title_face,
            bold = true,
            width = self.screen_width * 0.95,
        },
    }
    local time_container = FrameContainer:new{
        padding = Screen:scaleBySize(2),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        self:paintContainer()
    }
    local time_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Screen:scaleBySize(2),
        }
    }
    local time_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = time_title:getSize().h
        },
        time_title,
        CloseButton:new{ window = self, },
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
                        self:callback(self)
                    end
                    self:onClose()
                end,
            },
        }
    }

    local ok_cancel_buttons = ButtonTable:new{
        width = Screen:getWidth()*0.9,
        buttons = buttons,
        show_parent = self,
    }

    self.time_frame = FrameContainer:new{
        radius = 5,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            time_bar,
            time_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.screen_width * 0.95,
                    h = self.screen_height * 0.25
                },
                time_container,
            },
            time_line,
            ok_cancel_buttons
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
            padding = Screen:scaleBySize(5),
            self.time_frame,
        }
    }

    UIManager:setDirty(self, function()
        return "ui", self.time_frame.dimen
    end)
end

function TimeWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.time_frame.dimen
    end)
    return true
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

function TimeWidget:onTapCloseFL(arg, ges_ev)
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
