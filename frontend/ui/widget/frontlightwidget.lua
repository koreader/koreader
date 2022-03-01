local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
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

local FrontLightWidget = InputContainer:new{
    width = nil,
    height = nil,
    -- This should stay active during natural light configuration
    is_always_active = true,
    rate = Screen.low_pan_rate and 3 or 30,     -- Widget update rate.
    last_time = TimeVal.zero,                   -- Tracks last update time to prevent update spamming.
}

function FrontLightWidget:init()
    -- Layout constants
    self.medium_font_face = Font:getFace("ffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = math.floor(self.screen_width * 0.95)

    -- State constants
    self.powerd = Device:getPowerDevice()

    -- Frontlight
    self.fl = {}
    self.fl.min = self.powerd.fl_min
    self.fl.max = self.powerd.fl_max
    self.fl.cur = self.powerd:frontlightIntensity()
    local fl_steps = self.fl.max - self.fl.min + 1
    self.fl.stride = math.ceil(fl_steps / 25)
    self.fl.steps = math.ceil(fl_steps / self.fl.stride)
    if (self.fl.steps - 1) * self.fl.stride < self.fl.max - self.fl.min then
        self.fl.steps = self.fl.steps + 1
    end
    self.fl.steps = math.min(self.fl.steps, fl_steps)

    -- Warmth
    self.has_nl = Device:hasNaturalLight()
    self.has_nl_mixer = Device:hasNaturalLightMixer()
    self.has_nl_api = Device:hasNaturalLightApi()
    if self.has_nl then
        self.nl = {}
        self.nl.min = self.powerd.fl_warmth_min
        self.nl.max = self.powerd.fl_warmth_max
        self.nl.cur = self.powerd:frontlightWarmth()

        local nl_steps = self.nl.max - self.nl.min + 1
        self.nl.stride = math.ceil(nl_steps / 25)
        self.nl.steps = math.ceil(nl_steps / self.nl.stride)
        if (self.nl.steps - 1) * self.nl.stride < self.nl.max - self.nl.min then
            self.nl.steps = self.nl.steps + 1
        end
        self.nl.steps = math.min(self.nl.steps, nl_steps)
    end

    -- Input
    if Device:hasKeys() then
        self.key_events = {
            Close = { {Device.input.group.Back}, doc = "close frontlight" }
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

    -- Widget layout
    self:layout()
end

function FrontLightWidget:layout()
    -- While the brightness bar uses a ProgressWidget, the warmth bar uses a ButtonProgressWidget
    -- FIXME: Actually move to ButtonProgressWidget ;D
    if self.has_nl then
        -- Button width adapted to screen size
        local button_margin = Size.margin.tiny
        local button_padding = Size.padding.button
        local button_bordersize = Size.border.button

        -- Step 0 doesn't take a button, hence the minus
        local button_width = math.floor(self.screen_width * 0.9 / (self.nl.steps - 1)) -
                             2 * (button_margin + button_padding + button_bordersize)

        self.nl_prog_button = Button:new{
            text = "",
            radius = 0,
            margin = button_margin,
            padding = button_padding,
            bordersize = button_bordersize,
            enabled = true,
            width = button_width,
            show_parent = self,
        }
    end

    self.main_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = math.floor(self.screen_height * 0.2),
        },
    }

    -- Frontlight
    local padding_span = VerticalSpan:new{ width = self.span }
    local fl_group_above = HorizontalGroup:new{ align = "center" }
    local fl_group_below = HorizontalGroup:new{ align = "center" }
    local vertical_group = VerticalGroup:new{ align = "center" }

    local ticks = {}
    for i = 1, self.fl.steps - 2 do
        table.insert(ticks, i * self.fl.stride)
    end

    self.fl_progress = ProgressWidget:new{
        width = math.floor(self.screen_width * 0.9),
        height = Size.item.height_big,
        percentage = self.fl.cur / self.fl.max,
        ticks = ticks,
        tick_width = Screen:scaleBySize(0.5),
        last = self.fl.max,
    }
    local fl_header = TextBoxWidget:new{
        text = _("Brightness"),
        face = self.medium_font_face,
        bold = true,
        alignment = "center",
        width = math.floor(self.screen_width * 0.95),
    }
    self.fl_minus = Button:new{
        text = "-1",
        margin = Size.margin.small,
        radius = 0,
        enabled = self.fl.cur ~= self.fl.min,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.cur - 1)
        end,
    }
    self.fl_plus = Button:new{
        text = "+1",
        margin = Size.margin.small,
        radius = 0,
        enabled = self.fl.cur ~= self.fl.max,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.cur + 1)
        end,
    }
    self.fl_level = TextBoxWidget:new{
        text = self.fl.cur,
        face = self.medium_font_face,
        alignment = "center",
        width = math.floor(self.screen_width * 0.95 - 1.275 * self.fl_minus.width - 1.275 * self.fl_plus.width),
    }
    local fl_min = Button:new{
        text = _("Min"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.min + 1)
        end, -- min is 1 (use toggle for 0)
    }
    local fl_max = Button:new{
        text = _("Max"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.max)
        end,
    }
    local fl_toggle = Button:new{
        text = _("Toggle"),
        margin = Size.margin.small,
        radius = 0,
        enabled = true,
        width = math.floor(self.screen_width * 0.2),
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.min)
        end,
    }
    local fl_spacer = HorizontalSpan:new{
        width = math.floor((self.screen_width * 0.95 - 1.2 * self.fl_minus.width - 1.2 * self.fl_plus.width - 1.2 * fl_toggle.width) / 2),
    }
    local fl_buttons_above = HorizontalGroup:new{
        align = "center",
        self.fl_minus,
        self.fl_level,
        self.fl_plus,
    }
    local fl_buttons_below = HorizontalGroup:new{
        align = "center",
        fl_min,
        fl_spacer,
        fl_toggle,
        fl_spacer,
        fl_max,
    }

    if self.has_nl then
        -- Only insert 'Brightness' caption if we also add 'warmth' widgets below.
        table.insert(vertical_group, fl_header)
    end
    table.insert(fl_group_above, fl_buttons_above)
    table.insert(fl_group_below, fl_buttons_below)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, fl_group_above)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, self.fl_progress)
    table.insert(vertical_group, padding_span)
    table.insert(vertical_group, fl_group_below)
    table.insert(vertical_group, padding_span)

    -- Warmth
    if self.has_nl then
        local nl_group_above = HorizontalGroup:new{ align = "center" }
        local nl_group_below = HorizontalGroup:new{ align = "center" }
        self.nl_group = HorizontalGroup:new{ align = "center" }

        self:rebuildWarmthProgress()

        local nl_header = TextBoxWidget:new{
            text = "\n" .. _("Warmth"),
            face = self.medium_font_face,
            bold = true,
            alignment = "center",
            width = math.floor(self.screen_width * 0.95),
        }
        self.nl_minus = Button:new{
            text = "-1",
            margin = Size.margin.small,
            radius = 0,
            enabled = self.nl.cur ~= self.nl.min,
            width = math.floor(self.screen_width * 0.2),
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.cur - 1) end,
        }
        self.nl_plus = Button:new{
            text = "+1",
            margin = Size.margin.small,
            radius = 0,
            enabled = self.nl.cur ~= self.nl.max,
            width = math.floor(self.screen_width * 0.2),
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.cur + 1) end,
        }
        self.nl_level = TextBoxWidget:new{
            text = self.nl.cur,
            face = self.medium_font_face,
            alignment = "center",
            width = math.floor(self.screen_width * 0.95 - 1.275 * self.nl_minus - 1.275 * self.nl_plus.width),
        }
        local nl_min = Button:new{
            text = _("Min"),
            margin = Size.margin.small,
            radius = 0,
            enabled = true,
            width = math.floor(self.screen_width * 0.2),
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.min)
            end,
        }
        local nl_max = Button:new{
            text = _("Max"),
            margin = Size.margin.small,
            radius = 0,
            enabled = true,
            width = math.floor(self.screen_width * 0.2),
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.max)
            end,
        }
        local nl_spacer = HorizontalSpan:new{
            width = math.floor((self.screen_width * 0.95 - 1.2 * self.nl_minus.width - 1.2 * self.nl_plus.width) / 2),
        }
        local nl_buttons_above = HorizontalGroup:new{
            align = "center",
            self.nl_minus,
            self.nl_level,
            self.nl_plus,
        }
        local nl_buttons_below = HorizontalGroup:new{
            align = "center",
            nl_min,
            nl_spacer,
            nl_max,
        }

        table.insert(vertical_group, nl_header)
        table.insert(nl_group_above, nl_buttons_above)
        table.insert(nl_group_below, nl_buttons_below)

        table.insert(vertical_group, padding_span)
        table.insert(vertical_group, nl_group_above)
        table.insert(vertical_group, padding_span)
        table.insert(vertical_group, self.nl_group)
        table.insert(vertical_group, padding_span)
        table.insert(vertical_group, nl_group_below)
        table.insert(vertical_group, padding_span)

        -- Aura One R/G/B widget
        if not self.has_nl_mixer and not self.has_nl_api then
            local nl_setup =  Button:new{
                text = _("Configure"),
                margin = Size.margin.small,
                radius = 0,
                width = math.floor(self.screen_width * 0.2),
                show_parent = self,
                callback = function()
                    UIManager:show(NaturalLight:new{fl_widget = self})
                end,
            }
            table.insert(vertical_group, nl_setup)
        end
    end

    table.insert(self.main_container, vertical_group)

    -- Common
    local title_bar = TitleBar:new{
        title = _("Frontlight"),
        width = self.width,
        align = "left",
        with_bottom_line = true,
        bottom_v_padding = 0,
        close_callback = function()
            self:onClose()
        end,
        show_parent = self,
    }
    local inner_frame = FrameContainer:new{
        padding = Size.padding.button,
        margin = Size.margin.small,
        bordersize = 0,
        self.main_container,
    }
    self.frame = FrameContainer:new{
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
                    h = inner_frame:getSize().h,
                },
                inner_frame,
            },
        }
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        FrameContainer:new{
            bordersize = 0,
            self.frame,
        },
    }
end

function FrontLightWidget:update()
    -- Reset container height to what it actually contains
    -- FIXME: Was a getSize on vertical_group only...
    self.main_container.dimen.h = self.main_container:getSize().h

    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
    return true
end

function FrontLightWidget:rebuildWarmthProgress()
    self.nl_group:clear()

    local curr_warmth_step = math.floor(self.nl.cur / self.nl.stride)
    if curr_warmth_step > 0 then
        for i = 1, curr_warmth_step do
            table.insert(self.nl_group, self.nl_prog_button:new{
                            text = "",
                            preselect = curr_warmth_step > 0 and true or false,
                            callback = function()
                                self:setWarmth(i * self.nl.stride)
                            end
            })
        end
    end

    for i = curr_warmth_step + 1, self.nl.steps - 1 do
        table.insert(self.nl_group, self.nl_prog_button:new{
                        text = "",
                        callback = function()
                            self:setWarmth(i * self.nl.stride)
                        end
        })
    end
end

function FrontLightWidget:setBrightness(intensity)
    if intensity == self.fl.cur then
        return
    end

    -- Set brightness
    self:setFrontLightIntensity(intensity)

    -- Update the progress bar
    self.fl_progress:setPercentage(self.fl.cur / self.fl.max)
    self.fl_level:setText(self.fl.cur)
    if self.fl.cur == self.fl.min then
        self.fl_minus:disable()
    else
        self.fl_minus:enable()
    end
    if self.fl.cur == self.fl.max then
        self.fl_plus:disable()
    else
        self.fl_plus:enable()
    end

    -- Refresh widget
    self:update()
end

function FrontLightWidget:setWarmth(warmth)
    if warmth == self.nl.cur then
        return
    end

    -- Set warmth
    self.nl.cur = warmth
    self.powerd:setWarmth(self.powerd:fromNativeWarmth(self.nl.cur))

    -- Update the progress bar
    self:rebuildWarmthProgress()
    self.nl_level:setText(self.nl.cur)
    if self.nl.cur == self.nl.min then
        self.nl_minus:disable()
    else
        self.nl_minus:enable()
    end
    if self.nl.cur == self.nl.max then
        self.nl_plus:disable()
    else
        self.nl_plus:enable()
    end

    -- Refresh widget
    self:update()
end

function FrontLightWidget:setFrontLightIntensity(intensity)
    self.fl.cur = intensity

    -- min (which is always 0) means toggle
    if self.fl.cur == self.fl.min then
        self.powerd:toggleFrontlight()
    else
        self.powerd:setIntensity(self.fl.cur)
    end

    -- Retrieve the real level (different from set_fl on toggle)
    self.fl.cur = self.powerd:frontlightIntensity()
end

function FrontLightWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "flashui", self.frame.dimen
    end)
end

function FrontLightWidget:onShow()
    -- NOTE: Keep this one as UI, it'll get coalesced...
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
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
    if not self.fl_progress.dimen or not self.frame.dimen then
        return true
    end

    if ges_ev.pos:intersectWith(self.fl_progress.dimen) then
        -- Unschedule any pending updates.
        UIManager:unschedule(self.update)

        local perc = self.fl_progress:getPercentageFromPosition(ges_ev.pos)
        if not perc then
            return true
        end
        local num = Math.round(perc * self.fl.max)

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
    elseif not ges_ev.pos:intersectWith(self.frame.dimen) and ges_ev.ges == "tap" then
        -- close if tap outside
        self:onClose()
    end
    -- otherwise, do nothing (it's easy missing taping a button)
    return true
end

FrontLightWidget.onPanProgress = FrontLightWidget.onTapProgress

return FrontLightWidget
