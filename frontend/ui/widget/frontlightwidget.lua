local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
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
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen


local FrontLightWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
}

function FrontLightWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = self.screen_width * 0.95
    local powerd = Device:getPowerDevice()
    self.fl_min = powerd.fl_min
    self.fl_max = powerd.fl_max
    self.fl_cur = powerd:frontlightIntensity()
    local steps_fl = self.fl_max - self.fl_min + 1
    self.one_step = math.ceil(steps_fl / 25)
    self.steps = math.ceil(steps_fl / self.one_step)
    if (self.steps - 1) * self.one_step < self.fl_max - self.fl_min then
        self.steps = self.steps + 1
    end
    self.steps = math.min(self.steps , steps_fl)

    -- button width to fit screen size
    local button_margin = Size.margin.tiny
    local button_padding = Size.padding.button
    local button_bordersize = Size.border.button
    self.button_width = math.floor(self.screen_width * 0.9 / self.steps) -
            2 * (button_margin + button_padding + button_bordersize)

    self.fl_prog_button = Button:new{
        text = "",
        radius = 0,
        margin = button_margin,
        padding = button_padding,
        bordersize = button_bordersize,
        enabled = true,
        width = self.button_width,
        show_parent = self,
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close frontlight" }
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

function FrontLightWidget:generateProgressGroup(width, height, fl_level, step)
    self.fl_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    self:setProgress(fl_level, step)
    return self.fl_container
end

function FrontLightWidget:setProgress(num, step)
    self.fl_container:clear()
    local padding_span = VerticalSpan:new{ width = self.span }
    local button_group_down = HorizontalGroup:new{ align = "center" }
    local button_group_up = HorizontalGroup:new{ align = "center" }
    local fl_group = HorizontalGroup:new{ align = "center" }
    local vertical_group = VerticalGroup:new{ align = "center" }
    local set_fl
    local enable_button_plus = true
    local enable_button_minus = true
    local step_num = math.floor(num / step)
    local step_min = math.floor(self.fl_min / step)
    if num then
        self.fl_cur = num
        set_fl = math.min(self.fl_cur, self.fl_max)
        -- don't touch frontlight on first call (no self[1] means not yet out of update()),
        -- so that we don't untoggle light
        if self[1] then
            local powerd = Device:getPowerDevice()
            if set_fl == self.fl_min then -- fl_min (which is always 0) means toggle
                powerd:toggleFrontlight()
            else
                powerd:setIntensity(set_fl)
            end
            -- get back the real level (different from set_fl if untoggle)
            self.fl_cur = powerd:frontlightIntensity()
            -- and update our step_num with it for accurate progress bar
            step_num = math.floor(self.fl_cur / step)
        end

        if self.fl_cur == self.fl_max then enable_button_plus = false end
        if self.fl_cur == self.fl_min then enable_button_minus = false end

        for i = step_min, step_num do
            table.insert(fl_group, self.fl_prog_button:new{
                text= "",
                preselect = true,
                callback = function()
                    if i == step_min then
                        self:setProgress(self.fl_min, step)
                    else
                        self:setProgress(i * step, step)
                    end
                end
            })
        end
    end

    for i = step_num + 1, step_min + self.steps -1 do
        table.insert(fl_group, self.fl_prog_button:new{
            callback = function() self:setProgress(i * step, step) end
        })
    end
    local button_minus = Button:new{
        text = "-1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_minus,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()  self:setProgress(self.fl_cur - 1, step) end,
    }
    local button_plus = Button:new{
        text = "+1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_plus,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur + 1, step) end,
    }
    local item_level = TextBoxWidget:new{
        text = self.fl_cur,
        face = self.medium_font_face,
        alignment = "center",
        width = self.screen_width * 0.95 - 1.275 * button_minus.width - 1.275 * button_plus.width,
    }
    local button_min = Button:new{
        text = _("Min"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_min+1, step) end, -- min is 1 (use toggle for 0)
    }
    local button_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_max, step) end,
    }
    local button_toggle = Button:new{
        text = _("Toggle"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()
            self:setProgress(self.fl_min, step)
        end,
    }
    local empty_space = HorizontalSpan:new{
        width = (self.screen_width * 0.95 - 1.2 * button_minus.width - 1.2 * button_plus.width - 1.2 * button_toggle.width) / 2,
    }
    local button_table_up = HorizontalGroup:new{
        align = "center",
        button_minus,
        item_level,
        button_plus,
    }
    local button_table_down = HorizontalGroup:new{
        align = "center",
        button_min,
        empty_space,
        button_toggle,
        empty_space,
        button_max,
    }
    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_up)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,fl_group)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_down)
    table.insert(vertical_group,padding_span)
    table.insert(self.fl_container, vertical_group)
    -- Reset container height to what it actually contains
    self.fl_container.dimen.h = vertical_group:getSize().h

    UIManager:setDirty("all", "ui")
    return true
end

function FrontLightWidget:update()
    -- header
    self.light_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = _("Frontlight"),
            face = self.title_face,
            bold = true,
            width = self.screen_width * 0.95,
        },
    }
    local light_level = FrameContainer:new{
        padding = Size.padding.button,
        margin = Size.margin.small,
        bordersize = 0,
        self:generateProgressGroup(self.screen_width * 0.95, self.screen_height * 0.20,
            self.fl_cur, self.one_step)
    }
    local light_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    self.light_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = self.light_title:getSize().h
        },
        self.light_title,
        CloseButton:new{ window = self, padding_top = Size.margin.title, },
    }
    self.light_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.light_bar,
            light_line,
            CenterContainer:new{
                dimen = Geom:new{
                    w = light_line:getSize().w,
                    h = light_level:getSize().h,
                },
                light_level,
            },
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
            self.light_frame,
        }
    }
end

function FrontLightWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.light_frame.dimen
    end)
    return true
end

function FrontLightWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.light_frame.dimen
    end)
    return true
end

function FrontLightWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function FrontLightWidget:onTapCloseFL(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.light_frame.dimen) then
        self:onClose()
    end
    return true
end

function FrontLightWidget:onClose()
    UIManager:close(self)
    return true
end

return FrontLightWidget
