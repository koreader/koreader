local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local NaturalLightWidget = InputContainer:new{
    is_always_active = true,
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
    textbox_width = 0.1,
    button_width = 0.07,
    text_width = 0.3,
    white_gain = nil,
    white_offset = nil,
    red_gain = nil,
    red_offset = nil,
    green_gain = nil,
    green_offset = nil,
    exponent = nil,
    fl_widget = nil,
    old_values = nil
}

function NaturalLightWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.nl_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = math.floor(self.screen_width * 0.95)
    self.button_width = 0.08 * self.width
    self.textbox_width = 0.1 * self.width
    self.text_width = 0.2 * self.width
    self.powerd = Device:getPowerDevice()
    self:createFrame()
end

function NaturalLightWidget:applyValues()
    self.powerd.fl.white_gain = self.white_gain[2]:getText()
    self.powerd.fl.white_offset = self.white_offset[2]:getText()
    self.powerd.fl.red_gain = self.red_gain[2]:getText()
    self.powerd.fl.red_offset = self.red_offset[2]:getText()
    self.powerd.fl.green_gain = self.green_gain[2]:getText()
    self.powerd.fl.green_offset = self.green_offset[2]:getText()
    self.powerd.fl.exponent = self.exponent[2]:getText()
    self.powerd.fl:setNaturalBrightness()
end

-- Create an InputText with '-' and '+' button next to it. Tapping
-- those buttons will de/increase by 'step', and 'step/10' on hold.
function NaturalLightWidget:adaptableNumber(initial, step)
    local minus_number_plus = HorizontalGroup:new{ align = "center" }
    local input_text = InputText:new{
        parent = self,
        text = initial,
        input_type = "number",
        hint = "",
        width = self.textbox_width,
        enter_callback = function()
            self:closeKeyboard()
            self:applyValues()
            UIManager:setDirty(self._current_input, "fast")
        end
    }
    input_text:unfocus()
    local button_minus = Button:new{
        text = "−",
        margin = Size.margin.small,
        radius = 0,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:closeKeyboard()
            self:setValueTextBox(input_text, input_text:getText() - step)
            self:applyValues()
        end,
        hold_callback = function()
            self:closeKeyboard()
            self:setValueTextBox(input_text, input_text:getText() - step/10.0)
            self:applyValues()
        end,
    }
    local button_plus = Button:new{
        text = "＋",
        margin = Size.margin.small,
        radius = 0,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:closeKeyboard()
            self:setValueTextBox(input_text, input_text:getText() + step)
            self:applyValues()
            end,
        hold_callback = function()
            self:closeKeyboard()
            self:setValueTextBox(input_text, input_text:getText() + step/10)
            self:applyValues()
            end,
    }
    table.insert(minus_number_plus, button_minus)
    table.insert(minus_number_plus, input_text)
    table.insert(minus_number_plus, button_plus)
    return minus_number_plus
end

-- Get current values that are used in sysfs_light
function NaturalLightWidget:getCurrentValues()
    return {white_gain =
                self.powerd.fl.white_gain,
            white_offset =
                self.powerd.fl.white_offset,
            red_gain =
                self.powerd.fl.red_gain,
            red_offset =
                self.powerd.fl.red_offset,
            green_gain =
                self.powerd.fl.green_gain,
            green_offset =
                self.powerd.fl.green_offset,
            exponent =
                self.powerd.fl.exponent}
end

function NaturalLightWidget:createFrame()
    self.nl_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = _("Natural light configuration"),
            face = self.title_face,
            bold = true,
            width = math.floor(self.screen_width * 0.95),
        },
    }
    local main_content = FrameContainer:new{
        padding = Size.padding.button,
        margin = Size.margin.small,
        bordersize = 0,
        self:createMainContent(math.floor(self.screen_width * 0.95),
                               math.floor(self.screen_height * 0.2))
    }
    local nl_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    self.nl_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = self.nl_title:getSize().h
        },
        self.nl_title,
    }
    self.nl_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.nl_bar,
            nl_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = nl_line:getSize().w,
                    h = main_content:getSize().h,
                },
                main_content,
            },
        }
    }
    self[1] = WidgetContainer:new{
        align = "top",
        dimen =Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        FrameContainer:new{
            bordersize = 0,
            self.nl_frame,
        }
    }
end

function NaturalLightWidget:createMainContent(width, height)
    self.fl_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    self.white_gain = self:adaptableNumber(self.powerd.fl.white_gain, 1)
    self.white_offset = self:adaptableNumber(self.powerd.fl.white_offset, 1)
    self.red_gain = self:adaptableNumber(self.powerd.fl.red_gain, 1)
    self.red_offset = self:adaptableNumber(self.powerd.fl.red_offset, 1)
    self.green_gain = self:adaptableNumber(self.powerd.fl.green_gain, 1)
    self.green_offset = self:adaptableNumber(self.powerd.fl.green_offset, 1)
    self.exponent = self:adaptableNumber(self.powerd.fl.exponent, 0.1)

    local separator = HorizontalSpan:new{ width = Size.span.horizontal_default }
    local vspan = VerticalSpan:new{ width = Size.span.vertical_large * 2}
    local vertical_group = VerticalGroup:new{ align = "center" }
    local title_group = HorizontalGroup:new{ align = "center" }
    local white_group = HorizontalGroup:new{ align = "center" }
    local red_group = HorizontalGroup:new{ align = "center" }
    local green_group = HorizontalGroup:new{ align = "center" }
    local exponent_group = HorizontalGroup:new{ align = "center" }
    local button_group = HorizontalGroup:new{ align = "center" }
    local text_gain = TextBoxWidget:new{
        text = _("Amplification"),
        face = self.medium_font_face,
        bold = true,
        alignment = "left",
        width = self.textbox_width + 2 * self.button_width
    }
    local text_offset = TextBoxWidget:new{
        text = _("Offset"),
        face = self.medium_font_face,
        bold = true,
        alignment = "left",
        width = self.textbox_width + self.button_width
    }
    local text_white = TextBoxWidget:new{
        text = _("White"),
        face = self.medium_font_face,
        bold = true,
        alignment = "left",
        width = self.text_width
    }
    local text_red = TextBoxWidget:new{
        text = _("Red"),
        face = self.medium_font_face,
        bold = true,
        alignment = "left",
        width = self.text_width
    }
    local text_green = TextBoxWidget:new{
        text = _("Green"),
        face = self.medium_font_face,
        bold = true,
        alignment = "left",
        width = self.text_width
    }
    local text_exponent = TextBoxWidget:new{
        text = _("Exponent"),
        face = self.medium_font_face,
        bold = true,
        alignment = "left",
        width = self.text_width
    }
    local button_defaults = Button:new{
        text = "Restore Defaults",
        margin = Size.margin.small,
        radius = 0,
        width = math.floor(self.width * 0.35),
        show_parent = self,
        callback = function()
            self:setAllValues({white_gain = 25,
                               white_offset = -25,
                               red_gain = 24,
                               red_offset = 0,
                               green_gain = 24,
                               green_offset = -65,
                               exponent = 0.25})
        end,
    }
    local button_cancel = Button:new{
        text = "Cancel",
        margin = Size.margin.small,
        radius = 0,
        width = math.floor(self.width * 0.2),
        show_parent = self,
        callback = function()
            self:setAllValues(self.old_values)
            self:onClose()
        end,
    }
    local button_ok = Button:new{
        text = "Save",
        margin = Size.margin.small,
        radius = 0,
        width = math.floor(self.width * 0.2),
        show_parent = self,
        callback = function()
            G_reader_settings:saveSetting("natural_light_config",
                                          self:getCurrentValues())
            self:onClose()
        end,
    }

    table.insert(title_group, HorizontalSpan:new{
                     width = self.text_width + self.button_width
    })
    table.insert(title_group, text_gain)
    table.insert(title_group, separator)
    table.insert(title_group, HorizontalSpan:new{
                     width = self.button_width
    })
    table.insert(title_group, text_offset)
    table.insert(white_group, text_white)
    table.insert(white_group, self.white_gain)
    table.insert(white_group, separator)
    table.insert(white_group, self.white_offset)

    table.insert(red_group, text_red)
    table.insert(red_group, self.red_gain)
    table.insert(red_group, separator)
    table.insert(red_group, self.red_offset)

    table.insert(green_group, text_green)
    table.insert(green_group, self.green_gain)
    table.insert(green_group, separator)
    table.insert(green_group, self.green_offset)

    table.insert(exponent_group, text_exponent)
    table.insert(exponent_group, self.exponent)

    table.insert(button_group, button_defaults)
    table.insert(button_group, HorizontalSpan:new{
                     width = 0.05*self.width
    })
    table.insert(button_group, button_cancel)
    table.insert(button_group, button_ok)

    table.insert(vertical_group, title_group)
    table.insert(vertical_group, white_group)
    table.insert(vertical_group, red_group)
    table.insert(vertical_group, green_group)
    table.insert(vertical_group, vspan)
    table.insert(vertical_group, exponent_group)
    table.insert(vertical_group, vspan)
    table.insert(vertical_group, button_group)
    table.insert(self.fl_container, vertical_group)
    -- Reset container height to what it actually contains
    self.fl_container.dimen.h = vertical_group:getSize().h
    UIManager:setDirty(self, "ui")
    return self.fl_container
end

function NaturalLightWidget:setAllValues(values)
    self:setValueTextBox(self.white_gain[2], values.white_gain)
    self:setValueTextBox(self.white_offset[2], values.white_offset)
    self:setValueTextBox(self.red_gain[2], values.red_gain)
    self:setValueTextBox(self.red_offset[2], values.red_offset)
    self:setValueTextBox(self.green_gain[2], values.green_gain)
    self:setValueTextBox(self.green_offset[2], values.green_offset)
    self:setValueTextBox(self.exponent[2], values.exponent)
    self:applyValues()
end

function NaturalLightWidget:setValueTextBox(widget, val)
    widget:focus()
    widget:setText(val)
    widget:unfocus()
end

function NaturalLightWidget:onCloseWidget()
    self:closeKeyboard()
    UIManager:setDirty(nil, function()
        return "flashui", self.nl_frame.dimen
    end)
    -- Tell frontlight widget that we're closed
    self.fl_widget:naturalLightConfigClose()
end

function NaturalLightWidget:onShow()
    UIManager:setDirty(self, function()
                           return "ui", self.nl_frame.dimen
    end)
    -- Tell the frontlight widget that we're open
    self.fl_widget:naturalLightConfigOpen()
    -- Store values in case user cancels
    self.old_values = self:getCurrentValues()
    return true
end

function NaturalLightWidget:onClose()
    UIManager:close(self)
    return true
end

function NaturalLightWidget:onShowKeyboard()
    if self._current_input then
        self._current_input:onShowKeyboard()
        self._current_input:focus()
    end
end

function NaturalLightWidget:onCloseKeyboard()
    if self._current_input then
        self._current_input:onCloseKeyboard()
        self._current_input:unfocus()
        -- Make sure the cursor is deleted
        UIManager:setDirty(self._current_input, "fast")
    end
end

function NaturalLightWidget:onSwitchFocus(inputbox)
    self:onCloseKeyboard()
    self._current_input = inputbox
    self:applyValues()
    self:onShowKeyboard()
end

function NaturalLightWidget:closeKeyboard()
    if self._current_input then
        self._current_input:onCloseKeyboard()
        self._current_input:unfocus()
    end
end

return NaturalLightWidget
