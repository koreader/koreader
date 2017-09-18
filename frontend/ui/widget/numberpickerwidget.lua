local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textboxwidget")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local NumberPickerWidget = InputContainer:new{
    spinner_face = Font:getFace("x_smalltfont",24),
    precision = "%02d",
    width = nil,
    height = nil,
    value = 0,
    value_min = 0,
    value_max = 23,
    value_step = 1,
    value_hold_step = 4,
    value_table = nil,
    -- in case we need calculate number of days in a given month and year
    date_month = nil,
    date_year = nil,
}

function NumberPickerWidget:init()
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    if self.width == nil then
        self.width = self.screen_width * 0.2
    end
    if self.value_table then
        self.value_index = 1
        self.value = self.value_table[self.value_index]
        self.step = 1
        self.value_hold_step = 1
    end
    self:update()
end

function NumberPickerWidget:paintWidget()

    local button_up = Button:new{
        text = "▲",
        bordersize = 2,
        margin = 2,
        radius = 0,
        text_font_size = 24,
        width = self.width,
        show_parent = self.show_parent,
        callback = function()
            if self.date_month and self.date_year then
                self.value_max = self:getDaysInMonth(self.date_month:getValue(), self.date_year:getValue())
            end
            self.value = self:changeValue(self.value, self.value_step, self.value_max, self.value_min)
            self:update()
        end,
        hold_callback = function()
            if self.date_month and self.date_year then
                self.value_max = self:getDaysInMonth(self.date_month:getValue(), self.date_year:getValue())
            end
            self.value = self:changeValue(self.value, self.value_hold_step, self.value_max, self.value_min)
            self:update()
        end
    }
    local button_down = Button:new{
        text = "▼",
        bordersize = 2,
        margin = 2,
        radius = 0,
        text_font_size = 24,
        width = self.width,
        show_parent = self.show_parent,
        callback = function()
            if self.date_month and self.date_year then
                self.value_max = self:getDaysInMonth(self.date_month:getValue(), self.date_year:getValue())
            end
            self.value = self:changeValue(self.value, self.value_step * -1, self.value_max, self.value_min)
            self:update()
        end,
        hold_callback = function()
            if self.date_month and self.date_year then
                self.value_max = self:getDaysInMonth(self.date_month:getValue(), self.date_year:getValue())
            end
            self.value = self:changeValue(self.value, self.value_hold_step * -1, self.value_max, self.value_min)
            self:update()
        end
    }

    local empty_space = VerticalSpan:new{
        width = self.screen_height * 0.01
    }
    local value = self.value
    if self.value_table then
        local text_width = RenderText:sizeUtf8Text(0, self.width, self.spinner_face, self.value, true, true).x
        if self.width < text_width then
            value = RenderText:truncateTextByWidth(self.value, self.spinner_face, self.width,true, true)
        end
    else
        value = string.format(self.precision, value)
    end

    local text_value = TextWidget:new{
        text = value,
        alignment = "center",
        face = self.spinner_face,
        bold = true,
        width = self.width,
    }
    return VerticalGroup:new{
        align = "center",
        button_up,
        empty_space,
        text_value,
        empty_space,
        button_down,
    }
end

function NumberPickerWidget:update()
    local widget_spinner = self:paintWidget()
    self.frame = FrameContainer:new{
        bordersize = 0,
        padding = Screen:scaleBySize(5),
        CenterContainer:new{
            align = "center",
            dimen = Geom:new{
                w = widget_spinner:getSize().w,
                h = widget_spinner:getSize().h
            },
            widget_spinner
        }
    }
    self.dimen = self.frame:getSize()
    self[1] = self.frame
    UIManager:setDirty(self.show_parent, function()
        return "ui", self.dimen
    end)
end

function NumberPickerWidget:changeValue(value, step, max, min)
    if self.value_index then
        self.value_index = self.value_index + step
        if self.value_index > #self.value_table then
            self.value_index = 1
        elseif
        self.value_index < 1 then
            self.value_index = #self.value_table
        end
        value = self.value_table[self.value_index]
    else
        value = value + step
        if value > max then
            value = min
        elseif value < min then
            value = max
        end
    end
    return value
end

function NumberPickerWidget:getDaysInMonth(month, year)
    local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    local days = days_in_month[month]
    -- check for leap year
    if (month == 2) then
        if year % 4 == 0 then
            if year % 100 == 0 then
                if year % 400 == 0 then
                    days = 29
                end
            else
                days = 29
            end
        end
    end
    return days
end

function NumberPickerWidget:getValue()
    return self.value
end

return NumberPickerWidget
