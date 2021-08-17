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
local NumberPickerWidget = require("ui/widget/numberpickerwidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local SpinWidget = InputContainer:new{
    title_text = "",
    title_face = Font:getFace("x_smalltfont"),
    info_text = nil,
    width = math.floor(Screen:getWidth() * 0.95),
    height = Screen:getHeight(),
    value_table = nil,
    value_index = nil,
    value = 1,
    value_max = 20,
    value_min = 0,
    value_step = 1,
    value_hold_step = 4,
    cancel_text = _("Close"),
    ok_text = _("Apply"),
    cancel_callback = nil,
    callback = nil,
    close_callback = nil,
    keep_shown_on_apply = false,
    -- Set this to add default button that restores number to its default value
    default_value = nil,
    default_text = _("Use default"),
    -- Optional extra button on bottom
    extra_text = nil,
    extra_callback = nil,
}

function SpinWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close spin widget" }
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

function SpinWidget:update()
    local value_widget = NumberPickerWidget:new{
        show_parent = self,
        width = math.floor(self.screen_width * 0.2),
        value = self.value,
        value_table = self.value_table,
        value_index = self.value_index,
        value_min = self.value_min,
        value_max = self.value_max,
        value_step = self.value_step,
        value_hold_step = self.value_hold_step,
        precision = self.precision,
    }
    local value_group = HorizontalGroup:new{
        align = "center",
        value_widget,
    }

    local close_button = CloseButton:new{ window = self, padding_top = Size.margin.title, }
    local btn_width = close_button:getSize().w + Size.padding.default * 2

    local value_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = self.title_text,
            max_width = self.width - btn_width,
            face = self.title_face,
            bold = true,
        },
    }
    local value_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local value_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = value_title:getSize().h
        },
        value_title,
        close_button,
    }
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
                        self.value, self.value_index = value_widget:getValue()
                        self.callback(self)
                    end
                    if not self.keep_shown_on_apply then
                        self:onClose()
                    end
                end,
            },
        }
    }

    if self.default_value then
        table.insert(buttons,{
            {
                text = self.default_text,
                callback = function()
                    value_widget.value = self.default_value
                    value_widget:update()
                end,
            },
        })
    end
    if self.extra_text then
        table.insert(buttons,{
            {
                text = self.extra_text,
                callback = function()
                    if self.extra_callback then
                        self.value, self.value_index = value_widget:getValue()
                        self.extra_callback(self)
                    end
                    if not self.keep_shown_on_apply then -- assume extra wants it same as ok
                        self:onClose()
                    end
                end,
            },
        })
    end

    local ok_cancel_buttons = ButtonTable:new{
        width = self.width - 2*Size.padding.default,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local vgroup = VerticalGroup:new{
        align = "left",
        value_bar,
        value_line,
    }
    if self.info_text then
        table.insert(vgroup, FrameContainer:new{
            padding = Size.padding.default,
            margin = Size.margin.small,
            bordersize = 0,
            TextBoxWidget:new{
                text = self.info_text,
                face = Font:getFace("x_smallinfofont"),
                width = math.floor(self.width * 0.9),
            }
        })
    end
    table.insert(vgroup, CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = value_group:getSize().h + math.floor(self.screen_height * 0.1),
        },
        value_group
    })
    table.insert(vgroup, CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = ok_cancel_buttons:getSize().h,
        },
        ok_cancel_buttons
    })
    self.spin_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        vgroup,
    }
    self.movable = MovableContainer:new{
        self.spin_frame,
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen =Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        self.movable,
    }
    UIManager:setDirty(self, function()
        return "ui", self.spin_frame.dimen
    end)
end

function SpinWidget:hasMoved()
    local offset = self.movable:getMovedOffset()
    return offset.x ~= 0 or offset.y ~= 0
end

function SpinWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.spin_frame.dimen
    end)
end

function SpinWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.spin_frame.dimen
    end)
    return true
end

function SpinWidget:onAnyKeyPressed()
    self:onClose()
    return true
end

function SpinWidget:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.spin_frame.dimen) then
        self:onClose()
    end
    return true
end

function SpinWidget:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

return SpinWidget
