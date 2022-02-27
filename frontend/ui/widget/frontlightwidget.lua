local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Math = require("optmath")
local NaturalLight = require("ui/widget/naturallightwidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TimeVal = require("ui/timeval")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local FrontLightWidget = FocusManager:new{
    width = nil,
    height = nil,
    -- This should stay active during natural light configuration
    is_always_active = true,
    rate = Screen.low_pan_rate and 3 or 30,     -- Widget update rate.
    last_time = TimeVal.zero,                   -- Tracks last update time to prevent update spamming.
}

function FrontLightWidget:init()
    self.medium_font_face = Font:getFace("ffont")
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

        -- NOTE: fl_warmth is always [0...100] even when internal scale is [0...10],
        --       but we want the UI to reflect the *internal* scale.
        self.nl_scale = (100 / self.nl_max)

        local steps_nl = self.nl_max - self.nl_min + 1
        self.one_step_nl = math.ceil(steps_nl / 25)
        self.steps_nl = math.ceil(steps_nl / self.one_step_nl)
        if (self.steps_nl - 1) * self.one_step_nl < self.nl_max - self.nl_min then
            self.steps_nl = self.steps_nl + 1
        end
        self.steps_nl = math.min(self.steps_nl, steps_nl)
    end

    -- button width to fit screen size
    local button_margin = Size.margin.tiny
    local button_padding = Size.padding.button
    local button_bordersize = Size.border.button
    -- Step 0 doesn't take a button
    self.button_width = math.floor(self.screen_width * 0.9 / (self.steps_nl - 1)) -
            2 * (button_margin + button_padding + button_bordersize)

    self.nl_prog_button = Button:new{
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
        self.key_events.Close = { {Device.input.group.Back}, doc = "close frontlight" }
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

function FrontLightWidget:generateProgressGroup(width, height, fl_level, step, step_nl)
    self.fl_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    self:setProgress(fl_level, step, step_nl)
    return self.fl_container
end

function FrontLightWidget:setProgress(num, step, step_nl, num_warmth)
    self.fl_container:clear()
    local padding_span = VerticalSpan:new{ width = self.span }
    local button_group_down = HorizontalGroup:new{ align = "center" }
    local button_group_up = HorizontalGroup:new{ align = "center" }
    local vertical_group = VerticalGroup:new{ align = "center" }
    local enable_button_plus = true
    local enable_button_minus = true
    if self.natural_light then
        num_warmth = num_warmth or math.floor(self.powerd.fl_warmth / self.nl_scale + 0.5)
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
    for i = 1, self.steps - 2 do
        table.insert(ticks, i * self.one_step)
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
        callback = function() self:setProgress(self.fl_cur - 1, step, step_nl) end,
    }
    local button_plus = Button:new{
        text = "+1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_plus,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur + 1, step, step_nl) end,
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
        callback = function() self:setProgress(self.fl_min + 1, step, step_nl) end, -- min is 1 (use toggle for 0)
    }
    local button_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_max, step, step_nl) end,
    }
    local button_toggle = Button:new{
        text = _("Toggle"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setProgress(self.fl_min, step, step_nl)
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
    self.layout[1] = {button_minus, button_plus}
    local button_table_down = HorizontalGroup:new{
        align = "center",
        button_min,
        empty_space,
        button_toggle,
        empty_space,
        button_max,
    }
    self.layout[2] = {button_min, button_toggle, button_max}
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
        self:addWarmthWidgets(num_warmth, step, step_nl, vertical_group)
        if not self.has_nl_mixer and not self.has_nl_api then
            self.configure_button =  Button:new{
                text = _("Configure"),
                margin = Size.margin.small,
                radius = 0,
                width = math.floor(self.screen_width * 0.2),
                show_parent = self,
                callback = function()
                    UIManager:show(NaturalLight:new{fl_widget = self})
                end,
            }
            table.insert(vertical_group, self.configure_button)
            self.layout[5] = {self.configure_button}
        end
    end
    table.insert(self.fl_container, vertical_group)
    -- Reset container height to what it actually contains
    self.fl_container.dimen.h = vertical_group:getSize().h
    self:refocusWidget()
    UIManager:setDirty(self, function()
        return "ui", self.light_frame.dimen
    end)
    return true
end

-- Currently, we are assuming the 'warmth' has the same min/max limits as 'brightness'.
function FrontLightWidget:addWarmthWidgets(num_warmth, step, step_nl, vertical_group)
    local button_group_down = HorizontalGroup:new{ align = "center" }
    local button_group_up = HorizontalGroup:new{ align = "center" }
    local warmth_group = HorizontalGroup:new{ align = "center" }
    local padding_span = VerticalSpan:new{ width = self.span }
    local enable_button_plus = true
    local enable_button_minus = true

    if self[1] then
        --- @note Don't set the same value twice, to play nice with the update() sent by the swipe handler on the FL bar
        if num_warmth ~= math.floor(self.powerd.fl_warmth / self.nl_scale + 0.5) then
            self.powerd:setWarmth(math.floor(num_warmth * self.nl_scale + 0.5))
        end
    end

    if self.natural_light and num_warmth then
        local curr_warmth_step = math.floor(num_warmth / step_nl)
        if curr_warmth_step > 0 then
            for i = 1, curr_warmth_step do
                table.insert(warmth_group, self.nl_prog_button:new{
                                text = "",
                                preselect = curr_warmth_step > 0 and true or false,
                                callback = function()
                                    self:setProgress(self.fl_cur, step, step_nl, i * step_nl)
                                end
                })
            end
        end

        for i = curr_warmth_step + 1, self.steps_nl - 1 do
            table.insert(warmth_group, self.nl_prog_button:new{
                             text = "",
                             callback = function()
                                 self:setProgress(self.fl_cur, step, step_nl, i * step_nl)
                             end
            })
        end
    end

    if num_warmth == self.nl_max then enable_button_plus = false end
    if num_warmth == self.nl_min then enable_button_minus = false end

    local text_warmth = TextBoxWidget:new{
        text = "\n" .. _("Warmth"),
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
        callback = function()  self:setProgress(self.fl_cur, step, step_nl, num_warmth - 1) end,
    }
    local button_plus = Button:new{
        text = "+1",
        margin = Size.margin.small,
        radius = 0,
        enabled = enable_button_plus,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, step_nl, num_warmth + 1) end,
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
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, step_nl, self.nl_min) end,
    }
    local button_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function() self:setProgress(self.fl_cur, step, step_nl, self.nl_max) end,
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
    self.layout[3] = {button_minus, button_plus}
    local button_table_down = HorizontalGroup:new{
        align = "center",
        button_min,
        empty_space,
        button_max,
    }
    self.layout[4] = {button_min, button_max}

    table.insert(vertical_group, text_warmth)
    table.insert(button_group_up, button_table_up)
    table.insert(button_group_down, button_table_down)

    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_up)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, warmth_group)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, button_group_down)
    table.insert(vertical_group, padding_span)
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
    self.layout = {}
    local title_bar = TitleBar:new{
        title = _("Frontlight"),
        width = self.width,
        align = "left",
        with_bottom_line = true,
        bottom_v_padding = 0,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    local light_level = FrameContainer:new{
        padding = Size.padding.button,
        margin = Size.margin.small,
        bordersize = 0,
        self:generateProgressGroup(self.width, math.floor(self.screen_height * 0.2), self.fl_cur, self.one_step, self.one_step_nl)
    }
    self.light_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_bar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
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
        },
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
