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

local HyphenationLimitsWidget = InputContainer:new{
    title_text = _("Hyphenation limits"),
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
    -- Min (2) and max (10) values are enforced by crengine
    left_min = 1,
    left_max = 10,
    left_value = 2,
    left_default = nil,
    right_min = 1,
    right_max = 10,
    right_value = 2,
    right_default = nil,
}

function HyphenationLimitsWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    -- let room on the widget sides so we can see
    -- the hyphenation changes happening
    self.width = self.screen_width * 0.6
    self.picker_width = self.screen_width * 0.25
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
    self:update()
end

function HyphenationLimitsWidget:update()
    -- This picker_update_callback will be redefined later. It is needed
    -- so we can have our MovableContainer repainted on NumberPickerWidgets
    -- update It is needed if we have enabled transparency on MovableContainer,
    -- otherwise the NumberPicker area gets opaque on update.
    local picker_update_callback = function() end
    local left_widget = NumberPickerWidget:new{
        show_parent = self,
        width = self.picker_width,
        value = self.left_value,
        value_min = self.left_min,
        value_max = self.left_max,
        wrap = false,
        update_callback = function() picker_update_callback() end,
    }
    local right_widget = NumberPickerWidget:new{
        show_parent = self,
        width = self.picker_width,
        value = self.right_value,
        value_min = self.right_min,
        value_max = self.right_max,
        wrap = false,
        update_callback = function() picker_update_callback() end,
    }
    local hyph_group = HorizontalGroup:new{
        align = "center",
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            TextBoxWidget:new{
                text = _("Left"),
                alignment = "center",
                face = self.title_face,
                width = self.picker_width,
            },
            left_widget,
        },
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            TextBoxWidget:new{
                text = _("Right"),
                alignment = "center",
                face = self.title_face,
                width = self.picker_width,
            },
            right_widget,
        },
    }

    local hyph_title = FrameContainer:new{
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
    local hyph_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local hyph_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = hyph_title:getSize().h
        },
        hyph_title,
        CloseButton:new{ window = self, padding_top = Size.margin.title, },
    }

    local hyph_into_text = _([[
Set minimum length before hyphenation occurs.
These settings will apply to all books with any hyphenation dictionary.
'Use language defaults' resets them.]])
    local hyph_info = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.small,
        bordersize = 0,
        TextBoxWidget:new{
            text = hyph_into_text,
            face = Font:getFace("x_smallinfofont"),
            width = self.width * 0.9,
        }
    }

    local buttons = {
        {
            {
                text = _("Close"),
                callback = function()
                    self:onClose()
                end,
            },
            {
                text = _("Apply"),
                callback = function()
                    if self.callback then
                        self.callback(left_widget:getValue(), right_widget:getValue())
                    end
                end,
            },
        },
        {
            {
                text = _("Use language defaults"),
                callback = function()
                    left_widget.value = self.left_default
                    right_widget.value = self.right_default
                    left_widget:update()
                    right_widget:update()
                    self.callback(nil, nil)
                end,
            },
        }
    }

    local button_table = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    self.hyph_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            hyph_bar,
            hyph_line,
            hyph_info,
            VerticalSpan:new{ width = Size.span.vertical_large },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = hyph_group:getSize().h,
                },
                hyph_group
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
        self.hyph_frame,
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
        return "ui", self.hyph_frame.dimen
    end)
    picker_update_callback = function()
        UIManager:setDirty("all", function()
            return "ui", self.movable.dimen
        end)
        -- If we'd like to have the values auto-applied, uncomment this:
        -- self.callback(left_widget:getValue(), right_widget:getValue())
    end
end

function HyphenationLimitsWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.hyph_frame.dimen
    end)
    return true
end

function HyphenationLimitsWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.hyph_frame.dimen
    end)
    return true
end

function HyphenationLimitsWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function HyphenationLimitsWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.hyph_frame.dimen) then
        self:onClose()
    end
    return true
end

function HyphenationLimitsWidget:onClose()
    UIManager:close(self)
    return true
end

return HyphenationLimitsWidget
