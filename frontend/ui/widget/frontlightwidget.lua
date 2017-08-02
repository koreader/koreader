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
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
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
    self.button_width = math.floor(self.screen_width * 0.9 / self.steps) - 12

    self.fl_prog_button = Button:new{
        text = "",
        bordersize = 3,
        radius = 0,
        margin = 1,
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
        Device:getPowerDevice():setIntensity(set_fl)
        if set_fl == self.fl_max then enable_button_plus = false end
        if set_fl == self.fl_min then enable_button_minus = false end

        for i = step_min, step_num do
            table.insert(fl_group, self.fl_prog_button:new{
                text= "",
                margin = 1,
                preselect = true,
                width = self.button_width,
                callback = function()
                    if i == step_min then
                        self:setProgress(self.fl_min, step)
                    else
                        self:setProgress(i * step, step)
                    end
                end
            })
        end
    else
        num = 0
    end

    for i = step_num + 1, step_min + self.steps -1 do
        table.insert(fl_group, self.fl_prog_button:new{
            callback = function() self:setProgress(i * step, step) end
        })
    end
    local button_minus = Button:new{
        text = "-1",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = enable_button_minus,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()  self:setProgress(num - 1, step) end,
    }
    local button_plus = Button:new{
        text = "+1",
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = enable_button_plus,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(num + 1, step) end,
    }
    local item_level = TextBoxWidget:new{
        text = set_fl,
        face = self.medium_font_face,
        alignment = "center",
        width = self.screen_width * 0.95 - 1.275 * button_minus.width - 1.275 * button_plus.width,
    }
    local button_min = Button:new{
        text = _("Min"),
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_min, step) end,
    }
    local button_max = Button:new{
        text = _("Max"),
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_max, step) end,
    }
    local button_toggle = Button:new{
        text = _("Toggle"),
        bordersize = 2,
        margin = 2,
        radius = 0,
        enabled = true,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()
            local powerd = Device:getPowerDevice()
            powerd:toggleFrontlight()
            self:setProgress(powerd:frontlightIntensity(), step)
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
    table.insert(vertical_group,button_group_up)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,fl_group)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_down)
    table.insert(self.fl_container, vertical_group)

    UIManager:setDirty("all", "ui")
    return true
end

function FrontLightWidget:update()
    -- header
    self.light_title = FrameContainer:new{
        padding = Screen:scaleBySize(5),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        TextWidget:new{
            text = _("Frontlight"),
            face = self.title_face,
            bold = true,
            width = self.screen_width * 0.95,
        },
    }
    local light_level = FrameContainer:new{
        padding = Screen:scaleBySize(2),
        margin = Screen:scaleBySize(2),
        bordersize = 0,
        self:generateProgressGroup(self.screen_width * 0.95, self.screen_height * 0.20,
            self.fl_cur, self.one_step)
    }
    local light_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Screen:scaleBySize(2),
        }
    }
    self.light_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = self.light_title:getSize().h
        },
        self.light_title,
        CloseButton:new{ window = self, },
    }
    self.light_frame = FrameContainer:new{
        radius = 5,
        bordersize = 3,
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
            padding = Screen:scaleBySize(5),
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
