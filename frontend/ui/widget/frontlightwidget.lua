local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
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
local NaturalLight = require("ui/widget/naturallightwidget")
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
    -- This should stay active during natural light configuration
    is_always_active = true,
}

function FrontLightWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.larger_font_face = Font:getFace("cfont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = self.screen_width * 0.95
    self.powerd = Device:getPowerDevice()
    self.fl_min = self.powerd.fl_min
    self.fl_max = self.powerd.fl_max
    self.fl_cur = self.powerd:frontlightIntensity()
    local steps_fl = self.fl_max - self.fl_min + 1
    self.one_step = math.ceil(steps_fl / 25)
    self.steps = math.ceil(steps_fl / self.one_step)
    if (self.steps - 1) * self.one_step < self.fl_max - self.fl_min then
        self.steps = self.steps + 1
    end
    self.steps = math.min(self.steps , steps_fl)
    self.natural_light = Device:isKobo() and Device:hasNaturalLight()

    -- button width to fit screen size
    local button_margin = Size.margin.tiny
    local button_padding = Size.padding.button
    local button_bordersize = Size.border.button
    self.auto_nl = false
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

function FrontLightWidget:setProgress(num, step, num_warmth)
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
    if self.natural_light then
        num_warmth = num_warmth or self.powerd.fl_warmth
    end
    if num then
        self.fl_cur = num
        set_fl = math.min(self.fl_cur, self.fl_max)
        -- don't touch frontlight on first call (no self[1] means not yet out of update()),
        -- so that we don't untoggle light
        if self[1] then
            if set_fl == self.fl_min then -- fl_min (which is always 0) means toggle
                self.powerd:toggleFrontlight()
            else
                self.powerd:setIntensity(set_fl)
            end
            -- get back the real level (different from set_fl if untoggle)
            self.fl_cur = self.powerd:frontlightIntensity()
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
    local text_br = TextBoxWidget:new{
        text = _("Brightness"),
        face = self.medium_font_face,
        bold = true,
        alignment = "center",
        width = self.screen_width * 0.95
    }
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
    if self.natural_light then
        -- Only insert 'brightness' caption if we also add 'warmth'
        -- widgets below.
        table.insert(vertical_group,text_br)
    end
    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_up)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,fl_group)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_down)
    table.insert(vertical_group,padding_span)
    if self.natural_light then
        -- If the device supports natural light, add the widgets for 'warmth'
        -- and a 'Configure' button
        self:addWarmthWidgets(num_warmth, step, vertical_group)
        self.configure_button =  Button:new{
            text = _("Configure"),
            margin = Size.margin.small,
            radius = 0,
            width = self.screen_width * 0.20,
            enabled = not self.nl_configure_open,
            show_parent = self,
            callback = function()
                UIManager:show(NaturalLight:new{fl_widget = self})
            end,
        }
        table.insert(vertical_group, self.configure_button)
    end
    table.insert(self.fl_container, vertical_group)
    -- Reset container height to what it actually contains
    self.fl_container.dimen.h = vertical_group:getSize().h

    UIManager:setDirty("all", "ui")
    return true
end

-- Currently, we are assuming the 'warmth' has the same min/max limits
-- as 'brightness'.
function FrontLightWidget:addWarmthWidgets(num_warmth, step, vertical_group)
    local button_group_down = HorizontalGroup:new{ align = "center" }
    local button_group_up = HorizontalGroup:new{ align = "center" }
    local warmth_group = HorizontalGroup:new{ align = "center" }
    local auto_nl_group = HorizontalGroup:new{ align = "center" }
    local padding_span = VerticalSpan:new{ width = self.span }
    local enable_button_plus = true
    local enable_button_minus = true
    local button_color = Blitbuffer.COLOR_WHITE

    if self[1] then
        self.powerd:setWarmth(num_warmth)
    end

    if self.powerd.auto_warmth then
        enable_button_plus = false
        enable_button_minus = false
        button_color = Blitbuffer.COLOR_GREY
    else
        if num_warmth == self.fl_max then enable_button_plus = false end
        if num_warmth == self.fl_min then enable_button_minus = false end
    end

    if self.natural_light and num_warmth then
        for i = 0, math.floor(num_warmth / step) do
            table.insert(warmth_group, self.fl_prog_button:new{
                             text = "",
                             preselect = true,
                             enabled = not self.powerd.auto_warmth,
                             background = button_color,
                             callback = function()
                                 self:setProgress(self.fl_cur, step, i * step)
                             end
            })
        end

        for i = math.floor(num_warmth / step) + 1, self.steps - 1 do
            table.insert(warmth_group, self.fl_prog_button:new{
                             text="",
                             enabled = not self.powerd.auto_warmth,
                             callback = function()
                                 self:setProgress(self.fl_cur, step, i * step)
                             end
            })
        end
    end

    local text_warmth = TextBoxWidget:new{
        text = "\n" .. _("Warmth"),
        face = self.medium_font_face,
        bold = true,
        alignment = "center",
        width = self.screen_width * 0.95
    }
    local button_minus = Button:new{
        text = "-1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_minus,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function()  self:setProgress(self.fl_cur, step, num_warmth - 1) end,
    }
    local button_plus = Button:new{
        text = "+1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_plus,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, num_warmth + 1) end,
    }
    local item_level = TextBoxWidget:new{
        text = num_warmth,
        face = self.medium_font_face,
        alignment = "center",
        width = self.screen_width * 0.95 - 1.275 * button_minus.width - 1.275 * button_plus.width,
    }
    local button_min = Button:new{
        text = _("Min"),
        margin = Size.margin.small,
        radius = 0,
        enabled = not self.powerd.auto_warmth,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, self.fl_min) end,
    }
    local button_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = not self.powerd.auto_warmth,
        width = self.screen_width * 0.20,
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, self.fl_max) end,
    }
    local empty_space = HorizontalSpan:new{
        width = (self.screen_width * 0.95 - 1.2 * button_minus.width - 1.2 * button_plus.width) / 2,
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
        button_max,
    }
    local checkbutton_auto_nl = CheckButton:new({
            text = _("Auto"),
            checked = self.powerd.auto_warmth,
            callback = function()
                if self.powerd.auto_warmth then
                    self.powerd.auto_warmth = false
                else
                    self.powerd.auto_warmth = true
                    self.powerd:calculateAutoWarmth()
                end
                self:setProgress(self.fl_cur, step)
            end
        })

    local text_auto_nl = TextBoxWidget:new{
        -- @TODO implement padding_right (etc.) on TextBoxWidget and remove the two-space hack
        text = _("Max. at:") .. "  ",
        face = self.larger_font_face,
        alignment = "right",
        fgcolor = self.powerd.auto_warmth and Blitbuffer.COLOR_BLACK or
            Blitbuffer.COLOR_GREY,
        width = self.screen_width * 0.3
    }
    local text_hour = TextBoxWidget:new{
        text = " " .. math.floor(self.powerd.max_warmth_hour) .. ":" ..
            self.powerd.max_warmth_hour % 1 * 6 .. "0",
        face = self.larger_font_face,
        alignment = "center",
        fgcolor =self.powerd.auto_warmth and Blitbuffer.COLOR_BLACK or
            Blitbuffer.COLOR_GREY,
        width = self.screen_width * 0.15
    }
    local button_minus_one_hour = Button:new{
        text = "−",
        margin = Size.margin.small,
        radius = 0,
        enabled = self.powerd.auto_warmth,
        width = self.screen_width * 0.1,
        show_parent = self,
        callback = function()
            self.powerd.max_warmth_hour =
                (self.powerd.max_warmth_hour - 1) % 24
            self.powerd:calculateAutoWarmth()
            self:setProgress(self.fl_cur, step)
        end,
        hold_callback = function()
            self.powerd.max_warmth_hour =
                (self.powerd.max_warmth_hour - 0.5) % 24
            self.powerd:calculateAutoWarmth()
            self:setProgress(self.fl_cur, step)
        end,
    }
    local button_plus_one_hour = Button:new{
        text = "+",
        margin = Size.margin.small,
        radius = 0,
        enabled = self.powerd.auto_warmth,
        width = self.screen_width * 0.1,
        show_parent = self,
        callback = function()
            self.powerd.max_warmth_hour =
                (self.powerd.max_warmth_hour + 1) % 24
            self.powerd:calculateAutoWarmth()
            self:setProgress(self.fl_cur, step)
        end,
        hold_callback = function()
            self.powerd.max_warmth_hour =
                (self.powerd.max_warmth_hour + 0.5) % 24
            self.powerd:calculateAutoWarmth()
            self:setProgress(self.fl_cur, step)
        end,
    }

    table.insert(vertical_group,text_warmth)
    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)
    table.insert(auto_nl_group, checkbutton_auto_nl)
    table.insert(auto_nl_group, text_auto_nl)
    table.insert(auto_nl_group, button_minus_one_hour)
    table.insert(auto_nl_group, text_hour)
    table.insert(auto_nl_group, button_plus_one_hour)

    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_up)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,warmth_group)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,button_group_down)
    table.insert(vertical_group,padding_span)
    table.insert(vertical_group,auto_nl_group)
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
    -- Do not close when natural light configuration is open
    if not self.nl_configure_open then
        if ges_ev.pos:notIntersectWith(self.light_frame.dimen) then
            self:onClose()
        end
    end
    return true
end

function FrontLightWidget:onClose()
    UIManager:close(self)
    return true
end

-- This is called when natural light configuration is shown
function FrontLightWidget:naturalLightConfigOpen()
    -- Remove the close button
    table.remove(self.light_bar)
    -- Disable the 'configure' button
    self.configure_button:disable()
    self.nl_configure_open = true
    -- Move to the bottom to make place for the new widget
    self[1].align="bottom"
    UIManager:setDirty("all", "ui")
end

function FrontLightWidget:naturalLightConfigClose()
    table.insert(self.light_bar,
                 CloseButton:new{window = self,
                                 padding_top = Size.margin.title})
    self.configure_button:enable()
    self.nl_configure_open = false
    self[1].align="center"
    UIManager:setDirty("all", "ui")
end

return FrontLightWidget
