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
local MovableContainer = require("ui/widget/container/movablecontainer")
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

local DoubleSpinWidget = FocusManager:extend{
    title_text = "",
    title_face = Font:getFace("x_smalltfont"),
    info_text = nil,
    width = nil,
    width_factor = nil, -- number between 0 and 1, factor to the smallest of screen width and height
    height = nil,
    left_text = _("Left"),
    left_min = 1,
    left_max = 20,
    left_value = 1,
    left_precision = nil, -- default "%02d" in NumberPickerWidget
    left_wrap = false,
    right_text = _("Right"),
    right_min = 1,
    right_max = 20,
    right_value = 1,
    right_precision = nil,
    right_wrap = false,
    cancel_text = _("Close"),
    ok_text = _("Apply"),
    ok_always_enabled = false, -- set to true to enable OK button for unchanged values
    cancel_callback = nil,
    callback = nil,
    close_callback = nil,
    keep_shown_on_apply = false,
    -- Set both left and right defaults to add upper button that sets spin values to default values
    left_default = nil,
    right_default = nil,
    default_text = nil,
    -- Optional extra button above ok/cancel buttons row
    extra_text = nil,
    extra_callback = nil,
    is_range = false, -- show a range separator in default button and between the spinners
    unit = nil,
}

function DoubleSpinWidget:init()
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if not self.width then
        if not self.width_factor then
            self.width_factor = 0.8 -- default if no width specified
        end
        self.width = math.floor(math.min(self.screen_width, self.screen_height) * self.width_factor)
    end
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

    if self.unit and self.unit ~= "" then
        self.left_precision = self.left_precision and self.left_precision or "%1d"
        self.right_precision = self.right_precision and self.right_precision or "%1d"
    end

    -- Actually the widget layout
    self:update()
end

function DoubleSpinWidget:update(numberpicker_left_value, numberpicker_right_value)
    local prev_movable_offset = self.movable and self.movable:getMovedOffset()
    local prev_movable_alpha = self.movable and self.movable.alpha
    self.layout = {}
    local left_widget = NumberPickerWidget:new{
        show_parent = self,
        value = numberpicker_left_value or self.left_value,
        value_min = self.left_min,
        value_max = self.left_max,
        value_step = self.left_step,
        value_hold_step = self.left_hold_step,
        precision = self.left_precision,
        wrap = self.left_wrap,
        unit = self.unit,
    }
    self:mergeLayoutInHorizontal(left_widget)
    local right_widget = NumberPickerWidget:new{
        show_parent = self,
        value = numberpicker_right_value or self.right_value,
        value_min = self.right_min,
        value_max = self.right_max,
        value_step = self.right_step,
        value_hold_step = self.right_hold_step,
        precision = self.right_precision,
        wrap = self.right_wrap,
        unit = self.unit,
    }
    self:mergeLayoutInHorizontal(right_widget)
    left_widget.picker_updated_callback = function(value)
        self:update(value, right_widget:getValue())
    end
    right_widget.picker_updated_callback = function(value)
        self:update(left_widget:getValue(), value)
    end
    local separator_widget = TextWidget:new{
        text = self.is_range and "–" or "",
        face = self.title_face,
        bold = true,
    }

    local text_max_width = math.floor(0.95 * self.width / 2)
    local left_vertical_group = VerticalGroup:new{
        align = "center",
        left_widget,
    }
    local separator_vertical_group = VerticalGroup:new{
        align = "center",
        separator_widget,
    }
    local right_vertical_group = VerticalGroup:new{
        align = "center",
        right_widget,
    }

    if self.left_text ~= "" or self.right_text ~= "" then
        table.insert(left_vertical_group, 1, TextWidget:new{
            text = self.left_text,
            face = self.title_face,
            max_width = text_max_width,
        })
        table.insert(separator_vertical_group, 1, TextWidget:new{
            text = "",
            face = self.title_face,
        })
        table.insert(right_vertical_group, 1, TextWidget:new{
            text = self.right_text,
            face = self.title_face,
            max_width = text_max_width,
        })
    end

    local widget_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width / 2,
                h = left_vertical_group:getSize().h,
            },
            left_vertical_group,
        },
        CenterContainer:new{
            dimen = Geom:new(),
            separator_vertical_group,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width / 2,
                h = right_vertical_group:getSize().h,
            },
            right_vertical_group,
        },
    }

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
    if self.left_default and self.right_default then
        local separator = self.is_range and "–" or "/"
        local unit = ""
        if self.unit then
            if self.unit == "°" then
                unit = self.unit
            elseif self.unit ~= "" then
                unit = "\u{202F}" .. self.unit -- use Narrow No-Break Space (NNBSP) here
            end
        end
        table.insert(buttons, {
            {
                text = self.default_text or T(_("Default values: %1%3 %4 %2%3"),
                    self.left_precision and string.format(self.left_precision, self.left_default) or self.left_default,
                    self.right_precision and string.format(self.right_precision, self.right_default) or self.right_default,
                    unit, separator),
                callback = function()
                    left_widget.value = self.left_default
                    right_widget.value = self.right_default
                    left_widget:update()
                    right_widget:update()
                end,
            }
        })
    end
    if self.extra_text then
        table.insert(buttons, {
            {
                text = self.extra_text,
                callback = function()
                    if self.extra_callback then
                        self.extra_callback(left_widget:getValue(), right_widget:getValue())
                    end
                    if not self.keep_shown_on_apply then -- assume extra wants it same as ok
                        self:onClose()
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = self.cancel_text,
            callback = function()
                if self.cancel_callback then
                    self.cancel_callback()
                end
                self:onClose()
            end,
        },
        {
            text = self.ok_text,
            enabled = self.ok_always_enabled or self.left_value ~= left_widget:getValue()
                or self.right_value ~= right_widget:getValue(),
            callback = function()
                self.left_value = left_widget:getValue()
                self.right_value = right_widget:getValue()
                if self.callback then
                    self.callback(self.left_value, self.right_value)
                end
                if self.keep_shown_on_apply then
                    self:update()
                else
                    self:onClose()
                end
            end,
        },
    })

    local button_table = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    self:mergeLayoutInVertical(button_table)

    self.widget_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_bar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = widget_group:getSize().h + 4 * Size.padding.large,
                },
                widget_group
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = button_table:getSize().h,
                },
                button_table
            }
        }
    }
    self.movable = MovableContainer:new{
        alpha = prev_movable_alpha,
        self.widget_frame,
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        self.movable,
    }
    if prev_movable_offset then
        self.movable:setMovedOffset(prev_movable_offset)
    end
    self:refocusWidget()
    UIManager:setDirty(self, function()
        return "ui", self.widget_frame.dimen
    end)
end

function DoubleSpinWidget:hasMoved()
    local offset = self.movable:getMovedOffset()
    return offset.x ~= 0 or offset.y ~= 0
end

function DoubleSpinWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.widget_frame.dimen
    end)
end

function DoubleSpinWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.widget_frame.dimen
    end)
    return true
end

function DoubleSpinWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.widget_frame.dimen) then
        self:onClose()
    end
    return true
end

function DoubleSpinWidget:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

return DoubleSpinWidget
