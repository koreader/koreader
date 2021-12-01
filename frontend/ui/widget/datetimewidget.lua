--[[--
Widget for setting the date or time.

Example for input a time:
    local DateTimeWidget = require("ui/widget/datetimewidget")
    local @{gettext|_} = require("gettext")

    local time_widget = DateTimeWidget:new{
        is_date = false,
        hour = 10,
        min = 30,
        ok_text = _("Set time"),
        title_text = _("Set time"),
        callback = function(time)
            -- use time.hour and time.min here
        end
    }
    UIManager:show(time_widget)

Example for input a date:
    local DateTimeWidget = require("ui/widget/datetimewidget")
    local @{gettext|_} = require("gettext")

    local date_widget = DateTimeWidget:new{
        year = 2021,
        month = 12,
        day = 31,
        ok_text = _("Set date"),
        title_text = _("Set date"),
        callback = function(time)
            -- use time.year, time.month, time.day here
        end
    }
    UIManager:show(date_widget)

--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local NumberPickerWidget = require("ui/widget/numberpickerwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local DateTimeWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    info_text = nil,
    width = nil,
    height = nil,
    is_date = true,
    day = 1,
    month = 1,
    year = 2021,
    hour = 12,
    hour_max = 23,
    min = 0,
    ok_text = _("Apply"),
    cancel_text = _("Close"),
    -- Optional extra button on bottom
    extra_text = nil,
    extra_callback = nil,
}

function DateTimeWidget:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.width = self.width or math.floor(math.min(self.screen_width, self.screen_height) *
        (self.is_date and 0.8 or 0.6))
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
    self:layout()
end

local year_widget, month_hour_widget, day_min_widget
function DateTimeWidget:layout()
    year_widget = NumberPickerWidget:new{
        show_parent = self,
        value = self.year,
        value_min = 2021,
        value_max = 2041,
        value_step = 1,
        value_hold_step = self.year_hold_step or 4,
    }
    month_hour_widget = NumberPickerWidget:new{
        show_parent = self,
        value = self.is_date and self.month or self.hour,
        value_min = self.hour_min or self.month_min or (self.is_date and 1 or 0),
        value_max = self.hour_max or self.month_max or (self.is_date and 12 or 24),
        value_step = 1,
        value_hold_step = self.hour_hold_step or self.month_hold_step or 3,
    }
    day_min_widget = NumberPickerWidget:new{
        show_parent = self,
        value = self.is_date and self.day or self.min,
        value_min = self.min_min or self.day_min or (self.is_date and 1 or 0),
        value_max = self.min_max or self.day_max or (self.is_date and 31 or 59),
        value_step = 1,
        value_hold_step = self.day_hold_step or self.min_hold_step or (self.is_date and 5 or 10),
        date_month_hour = month_hour_widget,
        date_year = year_widget,
    }
    local separator_space = TextBoxWidget:new{
        text = self.is_date and "–" or ":",
        alignment = "center",
        face = self.title_face,
        bold = true,
        width = math.floor(math.min(self.screen_width, self.screen_height) *
            (self.is_date and 0.02 or 0.05)),
    }
    local date_group = HorizontalGroup:new{
            align = "center",
            year_widget,
            separator_space,
            month_hour_widget,
            separator_space,
            day_min_widget,
        }
    if not self.is_date then
        table.remove(date_group, 2)
        table.remove(date_group, 1)
    end

    local date_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = self.title_text,
            face = self.title_face,
            max_width = self.width - 2 * (Size.padding.default + Size.margin.title),
        },
    }
    local date_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local date_info
    if self.info_text then
        date_info = FrameContainer:new{
            padding = Size.padding.default,
            margin = Size.margin.small,
            bordersize = 0,
            TextBoxWidget:new{
                text = self.info_text,
                face = Font:getFace("x_smallinfofont"),
                width = math.floor(self.width * 0.9),
            }
        }
    else
        date_info = VerticalSpan:new{ width = 0 }
    end

    local buttons = {}
    if self.default_value then
        table.insert(buttons, {
            {
                text = self.default_text or T(_("Default value: %1"), self.default_value),
                callback = function()
                    if self.default_callback then
                        self.default_callback(year_widget:getValue(), month_hour_widget:getValue(),
                            day_min_widget:getValue())
                    end
                    if not self.keep_shown_on_apply then -- assume extra wants it same as ok
                        self:onClose()
                    end
                end,
            },
        })
    end
    if self.extra_text then
        table.insert(buttons, {
            {
                text = self.extra_text,
                callback = function()
                    self.extra_callback(self)
                end,
            },
        })
    end
    table.insert(buttons, {
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
                    if self.is_date then
                        self.month = month_hour_widget:getValue()
                        self.day = day_min_widget:getValue()
                    else
                        self.hour = month_hour_widget:getValue()
                        self.min = day_min_widget:getValue()
                    end
                    self:callback(self)
                end
                self:onClose()
            end,
        },
    })

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
            date_title,
            date_line,
            date_info,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
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

function DateTimeWidget:update(left, mid, right)
    year_widget.value = left
    year_widget:update()
    month_hour_widget.value = mid
    month_hour_widget:update()
    day_min_widget.value = right
    day_min_widget:update()
end

function DateTimeWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.date_frame.dimen
    end)
end

function DateTimeWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.date_frame.dimen
    end)
    return true
end

function DateTimeWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function DateTimeWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.date_frame.dimen) then
        self:onClose()
    end
    return true
end

function DateTimeWidget:onClose()
    UIManager:close(self)
    return true
end

return DateTimeWidget
