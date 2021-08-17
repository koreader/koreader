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
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
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

local DoubleSpinWidget = InputContainer:new{
    title_text = "",
    title_face = Font:getFace("x_smalltfont"),
    info_text = nil,
    width = nil,
    height = nil,
    left_min = 1,
    left_max = 20,
    left_value = 1,
    left_default = nil,
    left_text = _("Left"),
    right_min = 1,
    right_max = 20,
    right_value = 1,
    right_default = nil,
    right_text = _("Right"),
    cancel_text = _("Close"),
    ok_text = _("Apply"),
    cancel_callback = nil,
    callback = nil,
    close_callback = nil,
    keep_shown_on_apply = false,
    -- Set this to add default button that restores numbers to their default values
    default_values = nil,
    default_text = _("Use defaults"),
    -- Optional extra button on bottom
    extra_text = nil,
    extra_callback = nil,
}

function DoubleSpinWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.width = self.width or math.floor(self.screen_width * 0.8)
    self.picker_width = math.floor(self.screen_width * 0.25)
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

function DoubleSpinWidget:update()
    local left_widget = NumberPickerWidget:new{
        show_parent = self,
        width = self.picker_width,
        value = self.left_value,
        value_min = self.left_min,
        value_max = self.left_max,
        value_step = self.left_step,
        value_hold_step = self.left_hold_step,
        wrap = false,
    }
    local right_widget = NumberPickerWidget:new{
        show_parent = self,
        width = self.picker_width,
        value = self.right_value,
        value_min = self.right_min,
        value_max = self.right_max,
        value_step = self.right_step,
        value_hold_step = self.right_hold_step,
        wrap = false,
    }
    local left_vertical_group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Size.span.vertical_large },
        TextWidget:new{
            text = self.left_text,
            face = self.title_face,
            max_width = 0.95 * self.width / 2,
        },
        left_widget,
    }
    local right_vertical_group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Size.span.vertical_large },
        TextWidget:new{
            text = self.right_text,
            face = self.title_face,
            max_width = 0.95 * self.width / 2,
        },
        right_widget,
    }
    local widget_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width / 2,
                h = left_vertical_group:getSize().h,
            },
            left_vertical_group
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width / 2,
                h = right_vertical_group:getSize().h,
            },
            right_vertical_group
        }
    }
    local widget_title = FrameContainer:new{
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
    local widget_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local widget_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = widget_title:getSize().h
        },
        widget_title,
        CloseButton:new{ window = self, padding_top = Size.margin.title, },
    }
    local widget_info
    if self.info_text then
        widget_info = FrameContainer:new{
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
        widget_info = VerticalSpan:new{ width = 0 }
    end
    local buttons = {
        {
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
                callback = function()
                    if self.callback then
                        self.callback(left_widget:getValue(), right_widget:getValue())
                    end
                    if not self.keep_shown_on_apply then
                        self:onClose()
                    end
                end,
            },
        },
    }
    if self.default_values then
        table.insert(buttons,{
            {
                text = self.default_text,
                callback = function()
                    left_widget.value = self.left_default
                    right_widget.value = self.right_default
                    left_widget:update()
                    right_widget:update()
                    self.callback(nil, nil)
                end,
            }
        })
    end
    if self.extra_text then
        table.insert(buttons,{
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

    local button_table = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    self.widget_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            widget_bar,
            widget_line,
            widget_info,
            VerticalSpan:new{ width = Size.span.vertical_large },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = widget_group:getSize().h,
                },
                widget_group
            },
            VerticalSpan:new{ width = Size.span.vertical_large },
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

function DoubleSpinWidget:onAnyKeyPressed()
    self:onClose()
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
