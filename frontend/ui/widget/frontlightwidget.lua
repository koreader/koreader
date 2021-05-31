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
local Math = require("optmath")
local NaturalLight = require("ui/widget/naturallightwidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TimeVal = require("ui/timeval")
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
    rate = Screen.low_pan_rate and 3 or 30,     -- Widget update rate.
    last_time = TimeVal.zero,                   -- Tracks last update time to prevent update spamming.
}

function FrontLightWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.larger_font_face = Font:getFace("cfont")
    self.light_bar = {}
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = math.floor(self.screen_width * 0.95)
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
    self.steps = math.min(self.steps, steps_fl)
    self.natural_light = Device:hasNaturalLight()
    self.has_nl_mixer = Device:hasNaturalLightMixer()
    self.has_nl_api = Device:hasNaturalLightApi()
    -- Handle Warmth separately, because it may use a different scale
    if self.natural_light then
        self.nl_min = self.powerd.fl_warmth_min
        self.nl_max = self.powerd.fl_warmth_max
        -- NOTE: fl_warmth is always [0...100] even when internal scale is [0...10]
        self.nl_scale = (100 / self.nl_max)
    end

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
            TapProgress = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                },
            },
            PanProgress = {
                GestureRange:new{
                    ges = "pan",
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
    local vertical_group = VerticalGroup:new{ align = "center" }
    local enable_button_plus = true
    local enable_button_minus = true
    if self.natural_light then
        num_warmth = num_warmth or self.powerd.fl_warmth
    end
    if num then
        --- @note Don't set the same value twice, to play nice with the update() sent by the swipe handler on the FL bar
        --        Except for fl_min, as that's how setFrontLightIntensity detects a toggle...
        if num == self.fl_min or num ~= self.fl_cur then
            self:setFrontLightIntensity(num)
        end

        if self.fl_cur == self.fl_max then enable_button_plus = false end
        if self.fl_cur == self.fl_min then enable_button_minus = false end
    end

    local ticks = {}
    for i = 1, self.steps-2 do
        table.insert(ticks, i*self.one_step)
    end

    self.fl_group = ProgressWidget:new{
        width = math.floor(self.screen_width * 0.9),
        height = Size.item.height_big,
        percentage = self.fl_cur / self.fl_max,
        ticks = ticks,
        tick_width = Screen:scaleBySize(0.5),
        last = self.fl_max,
    }
    local text_br = TextBoxWidget:new{
        text = _("Brightness"),
        face = self.medium_font_face,
        bold = true,
        alignment = "center",
        width = math.floor(self.screen_width * 0.95),
    }
    local button_minus = Button:new{
        text = "-1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_minus,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()  self:setProgress(self.fl_cur - 1, step) end,
    }
    local button_plus = Button:new{
        text = "+1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_plus,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur + 1, step) end,
    }
    local item_level = TextBoxWidget:new{
        text = self.fl_cur,
        face = self.medium_font_face,
        alignment = "center",
        width = math.floor(self.screen_width * 0.95 - 1.275 * button_minus.width - 1.275 * button_plus.width),
    }
    local button_min = Button:new{
        text = _("Min"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_min+1, step) end, -- min is 1 (use toggle for 0)
    }
    local button_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_max, step) end,
    }
    local button_toggle = Button:new{
        text = _("Toggle"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setProgress(self.fl_min, step)
        end,
    }
    local empty_space = HorizontalSpan:new{
        width = math.floor((self.screen_width * 0.95 - 1.2 * button_minus.width - 1.2 * button_plus.width - 1.2 * button_toggle.width) / 2),
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
        table.insert(vertical_group, text_br)
    end
    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_up)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, self.fl_group)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_down)
    table.insert(vertical_group, padding_span)
    if self.natural_light then
        -- If the device supports natural light, add the widgets for 'warmth',
        -- as well as a 'Configure' button for devices *without* a mixer
        self:addWarmthWidgets(num_warmth, step, vertical_group)
        if not self.has_nl_mixer and not self.has_nl_api then
            self.configure_button =  Button:new{
                text = _("Configure"),
                margin = Size.margin.small,
                radius = 0,
                width = math.floor(self.screen_width * 0.2),
                enabled = not self.nl_configure_open,
                show_parent = self,
                callback = function()
                    UIManager:show(NaturalLight:new{fl_widget = self})
                end,
            }
            table.insert(vertical_group, self.configure_button)
        end
    end
    table.insert(self.fl_container, vertical_group)
    -- Reset container height to what it actually contains
    self.fl_container.dimen.h = vertical_group:getSize().h

    UIManager:setDirty(self, function()
        return "ui", self.light_frame.dimen
    end)
    return true
end

-- Currently, we are assuming the 'warmth' has the same min/max limits as 'brightness'.
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
        --- @note Don't set the same value twice, to play nice with the update() sent by the swipe handler on the FL bar
        if num_warmth ~= self.powerd.fl_warmth then
            self.powerd:setWarmth(num_warmth)
        end
    end

    if self.powerd.auto_warmth then
        enable_button_plus = false
        enable_button_minus = false
        button_color = Blitbuffer.COLOR_DARK_GRAY
    else
        if math.floor(num_warmth / self.nl_scale) <= self.nl_min then enable_button_minus = false end
        if math.ceil(num_warmth / self.nl_scale) >= self.nl_max then enable_button_plus = false end
    end

    if self.natural_light and num_warmth then
        local curr_warmth_step = math.floor(num_warmth / step)
        for i = 0, curr_warmth_step do
            table.insert(warmth_group, self.fl_prog_button:new{
                             text = "",
                             preselect = curr_warmth_step > 0 and true or false,
                             enabled = not self.powerd.auto_warmth,
                             background = curr_warmth_step > 0 and button_color or nil,
                             callback = function()
                                 self:setProgress(self.fl_cur, step, i * step)
                             end
            })
        end

        for i = curr_warmth_step + 1, self.steps - 1 do
            table.insert(warmth_group, self.fl_prog_button:new{
                             text = "",
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
        width = math.floor(self.screen_width * 0.95),
    }
    local button_minus = Button:new{
        text = "-" .. (1 * self.nl_scale),
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_minus,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()  self:setProgress(self.fl_cur, step, (num_warmth - (1 * self.nl_scale))) end,
    }
    local button_plus = Button:new{
        text = "+" .. (1 * self.nl_scale),
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_plus,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, (num_warmth + (1 * self.nl_scale))) end,
    }
    local item_level = TextBoxWidget:new{
        text = num_warmth,
        face = self.medium_font_face,
        alignment = "center",
        width = math.floor(self.screen_width * 0.95 - 1.275 * button_minus.width - 1.275 * button_plus.width),
    }
    local button_min = Button:new{
        text = _("Min"),
        margin = Size.margin.small,
        radius = 0,
        enabled = not self.powerd.auto_warmth,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, self.nl_min) end,
    }
    local button_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = not self.powerd.auto_warmth,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, (self.nl_max * self.nl_scale)) end,
    }
    local empty_space = HorizontalSpan:new{
        width = math.floor((self.screen_width * 0.95 - 1.2 * button_minus.width - 1.2 * button_plus.width) / 2),
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

    local text_auto_nl, text_hour, button_minus_one_hour, button_plus_one_hour

    if not self.has_nl_api then
        text_auto_nl = TextBoxWidget:new{
            --- @todo Implement padding_right (etc.) on TextBoxWidget and remove the two-space hack.
            text = _("Max. at:") .. "  ",
            face = self.larger_font_face,
            alignment = "right",
            fgcolor = self.powerd.auto_warmth and Blitbuffer.COLOR_BLACK or
                Blitbuffer.COLOR_DARK_GRAY,
            width = math.floor(self.screen_width * 0.3),
        }
        text_hour = TextBoxWidget:new{
            text = " " .. math.floor(self.powerd.max_warmth_hour) .. ":" ..
                self.powerd.max_warmth_hour % 1 * 6 .. "0",
            face = self.larger_font_face,
            alignment = "center",
            fgcolor =self.powerd.auto_warmth and Blitbuffer.COLOR_BLACK or
                Blitbuffer.COLOR_DARK_GRAY,
            width = math.floor(self.screen_width * 0.15),
        }
        button_minus_one_hour = Button:new{
            text = "−",
            margin = Size.margin.small,
            radius = 0,
            enabled = self.powerd.auto_warmth,
            width = math.floor(self.screen_width * 0.1),
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
        button_plus_one_hour = Button:new{
            text = "＋",
            margin = Size.margin.small,
            radius = 0,
            enabled = self.powerd.auto_warmth,
            width = math.floor(self.screen_width * 0.1),
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
    end

    table.insert(vertical_group, text_warmth)
    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)
    table.insert(auto_nl_group, checkbutton_auto_nl)
    table.insert(auto_nl_group, text_auto_nl)
    table.insert(auto_nl_group, button_minus_one_hour)
    table.insert(auto_nl_group, text_hour)
    table.insert(auto_nl_group, button_plus_one_hour)

    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_up)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, warmth_group)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_down)
    table.insert(vertical_group, padding_span)

    if not self.has_nl_api then
        table.insert(vertical_group, auto_nl_group)
    end
end

function FrontLightWidget:setFrontLightIntensity(num)
    self.fl_cur = num
    local set_fl = math.min(self.fl_cur, self.fl_max)
    -- Don't touch frontlight on first call (no self[1] means not yet out of update()),
    -- so that we don't untoggle light.
    if self[1] then
        if set_fl == self.fl_min then -- fl_min (which is always 0) means toggle
            self.powerd:toggleFrontlight()
        else
            self.powerd:setIntensity(set_fl)
        end

        -- get back the real level (different from set_fl if untoggle)
        self.fl_cur = self.powerd:frontlightIntensity()
    end
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
            width = math.floor(self.screen_width * 0.95),
        },
    }
    local light_level = FrameContainer:new{
        padding = Size.padding.button,
        margin = Size.margin.small,
        bordersize = 0,
        self:generateProgressGroup(math.floor(self.screen_width * 0.95), math.floor(self.screen_height * 0.2),
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
        return "flashui", self.light_frame.dimen
    end)
end

function FrontLightWidget:onShow()
    -- NOTE: Keep this one as UI, it'll get coalesced...
    UIManager:setDirty(self, function()
        return "ui", self.light_frame.dimen
    end)
    return true
end

function FrontLightWidget:onAnyKeyPressed()
    UIManager:close(self)
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
    UIManager:setDirty(self, "ui")
end

function FrontLightWidget:naturalLightConfigClose()
    table.insert(self.light_bar,
                 CloseButton:new{window = self,
                                 padding_top = Size.margin.title})
    self.configure_button:enable()
    self.nl_configure_open = false
    self[1].align="center"
    UIManager:setDirty(self, "ui")
end

function FrontLightWidget:onTapProgress(arg, ges_ev)
    -- The throttling has a tendency to wreak a bit of a havoc,
    -- so, if the widget hasn't been repainted yet, go away.
    if not self.fl_group.dimen or not self.light_frame.dimen then
        return true
    end

    if ges_ev.pos:intersectWith(self.fl_group.dimen) then
        -- Unschedule any pending updates.
        UIManager:unschedule(self.update)

        local perc = self.fl_group:getPercentageFromPosition(ges_ev.pos)
        if not perc then
            return true
        end
        local num = Math.round(perc * self.fl_max)

        -- Always set the frontlight intensity.
        self:setFrontLightIntensity(num)

        -- But limit the widget update frequency on E Ink.
        if Screen.low_pan_rate then
            local current_time = TimeVal:now()
            local last_time = self.last_time or TimeVal.zero
            if current_time - last_time > TimeVal:new{ usec = 1000000 / self.rate } then
                self.last_time = current_time
            else
                -- Schedule a final update after we stop panning.
                UIManager:scheduleIn(0.075, self.update, self)
                return true
            end
        end

        self:update()
    elseif not ges_ev.pos:intersectWith(self.light_frame.dimen) and ges_ev.ges == "tap" then
        -- close if tap outside
        self:onClose()
    end
    -- otherwise, do nothing (it's easy missing taping a button)
    return true
end

FrontLightWidget.onPanProgress = FrontLightWidget.onTapProgress

return FrontLightWidget
