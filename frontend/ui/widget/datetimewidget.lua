--[[--
Widget for setting the date or time.

Example for input a time:
    local DateTimeWidget = require("ui/widget/datetimewidget")
    local @{gettext|_} = require("gettext")

    local time_widget = DateTimeWidget:new{
        hour = 10,
        min = 30,
        ok_text = _("Set time"),
        title_text = _("Set time"),
        info_text = _("Some information"),
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

Example to input a duration in days, hours and minutes:
    local DateTimeWidget = require("ui/widget/datetimewidget")
    local @{gettext|_} = require("gettext")

    local date_widget = DateTimeWidget:new{
        day = 5,
        hour = 12,
        min = 0,
        ok_text = _("Set"),
        title_text = _("Set duration"),
        callback = function(time)
            -- use time.day, time.hour, time.min here
        end
    }
    UIManager:show(date_widget)
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local NumberPickerWidget = require("ui/widget/numberpickerwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local DateTimeWidget = FocusManager:extend{
    title_face = Font:getFace("x_smalltfont"),
    info_text = nil,
    width = nil,
    height = nil,
    ok_text = _("Apply"),
    cancel_text = _("Close"),
    -- Optional extra button on bottom
    extra_text = nil,
    extra_callback = nil,
}

function DateTimeWidget:init()
    self.nb_pickers = 0
    if self.year then
        self.nb_pickers = self.nb_pickers + 1
    end
    if self.month then
        self.nb_pickers = self.nb_pickers + 1
    end
    if self.day then
        self.nb_pickers = self.nb_pickers + 1
    end
    if self.hour then
        self.nb_pickers = self.nb_pickers + 1
    end
    if self.min then
        self.nb_pickers = self.nb_pickers + 1
    end
    if self.sec then
        self.nb_pickers = self.nb_pickers + 1
    end

    self.layout = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    local width_scale_factor = 0.6
    if self.nb_pickers == 3 then
        width_scale_factor = 0.8
    elseif self.nb_pickers == 4 then
        width_scale_factor = 0.85
    elseif self.nb_pickers >=5 then
        width_scale_factor = 0.95
    end
    self.width = self.width or math.floor(math.min(self.screen_width, self.screen_height) * width_scale_factor)
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    w = self.screen_width,
                    h = self.screen_height,
                }
            },
        }
    end

    -- Actually the widget layout
    self:createLayout()
end

function DateTimeWidget:createLayout()
    -- Empty table w/ the methods we use NOP'ed
    local dummy_widget = {}
    function dummy_widget:free() end
    function dummy_widget:getValue() end
    function dummy_widget:update() end

    -- The following calculation is stolen from NumberPickerWidget
    local number_picker_widgets_width = math.floor(math.min(self.screen_width, self.screen_height) * 0.2)
    if self.nb_pickers > 3 then
       number_picker_widgets_width = math.floor(number_picker_widgets_width * 3 / self.nb_pickers)
    end

    if self.year then
        self.year_widget = NumberPickerWidget:new{
            show_parent = self,
            value = self.year,
            value_min = self.year_min or 2021,
            value_max = self.year_max or 2525,
            value_step = 1,
            value_hold_step = self.year_hold_step or 4,
            width = number_picker_widgets_width,
        }
        self:mergeLayoutInHorizontal(self.year_widget)
    else
        self.year_widget = dummy_widget
    end
    if self.month then
        self.month_widget = NumberPickerWidget:new{
            show_parent = self,
            value = self.month,
            value_min = self.month_min or 1,
            value_max = self.month_max or 12,
            value_step = 1,
            value_hold_step = self.month_hold_step or 3,
            width = number_picker_widgets_width,
        }
        self:mergeLayoutInHorizontal(self.month_widget)
    else
        self.month_widget = dummy_widget
    end
    if self.day then
        self.day_widget = NumberPickerWidget:new{
            show_parent = self,
            value = self.day,
            value_min = self.day_min or 1,
            value_max = self.day_max or 31,
            value_step = 1,
            value_hold_step = self.day_hold_step or 3,
            width = number_picker_widgets_width,
        }
        self:mergeLayoutInHorizontal(self.day_widget)
    else
        self.day_widget = dummy_widget
    end

    if self.hour then
        self.hour_widget = NumberPickerWidget:new{
            show_parent = self,
            value = self.hour,
            value_min = self.hour_min or 0,
            value_max = self.hour_max or 23,
            value_step = 1,
            value_hold_step = self.hour_hold_step or 4,
            width = number_picker_widgets_width,
        }
        self:mergeLayoutInHorizontal(self.hour_widget)
    else
        self.hour_widget = dummy_widget
    end
    if self.min then
        self.min_widget = NumberPickerWidget:new{
            show_parent = self,
            value = self.min,
            value_min = self.min_min or 0,
            value_max = self.min_max or 59,
            value_step = self.min_step or 1,
            value_hold_step = self.min_hold_step or 10,
            width = number_picker_widgets_width,
        }
        self:mergeLayoutInHorizontal(self.min_widget)
    else
        self.min_widget = dummy_widget
    end
    if self.sec then
        self.sec_widget = NumberPickerWidget:new{
            show_parent = self,
            value = self.sec,
            value_min = self.sec_min or 0,
            value_max = self.sec_max or 59,
            value_step = 1,
            value_hold_step = self.sec_hold_step or 10,
            width = number_picker_widgets_width,
        }
        self:mergeLayoutInHorizontal(self.sec_widget)
    else
        self.sec_widget = dummy_widget
    end

    local separator_date = TextWidget:new{
        text = "–",
        face = self.title_face,
        bold = true,
    }
    local separator_time = TextWidget:new{
        text = ":",
        face = self.title_face,
        bold = true,
    }
    local separator_date_time = TextWidget:new{
        text =  "/",
        face = self.title_face,
        bold = true,
    }
    local date_group = HorizontalGroup:new{
        align = "center",
        self.year_widget, -- 1
        separator_date, -- 2
        self.month_widget, -- 3
        separator_date, -- 4
        self.day_widget, -- 5
        separator_date_time, -- 6
        self.hour_widget, -- 7
        separator_time, -- 8
        self.min_widget, -- 9
        separator_time, -- 10
        self.sec_widget, -- 11
    }

    -- remove empty widgets plus trailing placeholder
    for i = #date_group, 1, -2 do
        if date_group[i] == dummy_widget then
            table.remove(date_group, i)
            table.remove(date_group, i-1)
        end
    end

    -- clean up leading separator
    if date_group[1] == separator_date or date_group[1] == separator_date_time or date_group[1] == separator_time then
        table.remove(date_group, 1)
    end

    local title_bar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title_text,
        title_shrink_font_to_fit = true,
        info_text = self.info_text,
        show_parent = self,
    }

    local buttons = {}
    if self.default_value then
        table.insert(buttons, {
            {
                text = self.default_text or T(_("Default value: %1"), self.default_value),
                callback = function()
                    if self.default_callback then
                        self.default_callback({
                            year = self.year_widget:getValue(),
                            month = self.month_widget:getValue(),
                            day = self.day_widget:getValue(),
                            hour = self.hour_widget:getValue(),
                            minute = self.min_widget:getValue(),
                            second = self.sec_widget:getValue(),
                        })
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
                if self.cancel_callback then
                    self.cancel_callback(self)
                end
                self:onClose()
            end,
        },
        {
            text = self.ok_text,
            callback = function()
                if self.callback then
                    self.year = self.year_widget:getValue()
                    self.month = self.month_widget:getValue()
                    self.day = self.day_widget:getValue()
                    self.hour = self.hour_widget:getValue()
                    self.min = self.min_widget:getValue()
                    self.sec = self.sec_widget:getValue()
                    self:callback(self)
                end
                if not self.keep_shown_on_apply then
                    self:onClose()
                end
            end,
        },
    })

    local ok_cancel_buttons = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    self:mergeLayoutInVertical(ok_cancel_buttons)

    self.date_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_bar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = math.floor(date_group:getSize().h * 1.2),
                },
                date_group,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = ok_cancel_buttons:getSize().h,
                },
                ok_cancel_buttons,
            },
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
    self:refocusWidget()
end

function DateTimeWidget:addWidget(widget)
    table.insert(self.layout, #self.layout, {widget})
    widget = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        widget,
    }
    table.insert(self.date_frame[1],  #self.date_frame[1], widget)
end

function DateTimeWidget:getAddedWidgetAvailableWidth()
    return self.date_frame[1][1].width - 2*Size.padding.default
end


function DateTimeWidget:update(year, month, day, hour, min, sec)
    self.year_widget.value = year
    self.year_widget:update()
    self.month_widget.value = month
    self.month_widget:update()
    self.day_widget.value = day
    self.day_widget:update()
    self.hour_widget.value = hour
    self.hour_widget:update()
    self.min_widget.value = min
    self.min_widget:update()
    self.sec_widget.value = sec
    self.sec_widget:update()
end

function DateTimeWidget:onCloseWidget()
    -- Let our main WidgetContainer free its child widgets
    self[1]:free()

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
