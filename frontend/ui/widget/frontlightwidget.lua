local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
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
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local time = require("ui/time")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

local FrontLightWidget = FocusManager:extend{
    name = "FrontLightWidget",
    width = nil,
    height = nil,
    -- This should stay active during natural light configuration
    is_always_active = true,
    rate = Screen.low_pan_rate and 3 or 30,     -- Widget update rate.
    last_time = 0,                              -- Tracks last update time to prevent update spamming.
}

function FrontLightWidget:init()
    -- Layout constants
    self.medium_font_face = Font:getFace("ffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = Math.round(self.screen_height * 0.01)
    self.width = math.floor(self.screen_width * 0.95)
    self.inner_width = self.width - 2 * Size.padding.large
    self.button_width = math.floor(self.inner_width / 4)

    -- State constants
    self.powerd = Device:getPowerDevice()

    -- Frontlight
    self.fl = {}
    self.fl.min = self.powerd.fl_min
    self.fl.max = self.powerd.fl_max
    self.fl.cur = self.powerd:frontlightIntensity()
    local fl_steps = self.fl.max - self.fl.min + 1
    self.fl.stride = math.ceil(fl_steps * (1/25))
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
        self.nl.cur = self.powerd:toNativeWarmth(self.powerd:frontlightWarmth())

        local nl_steps = self.nl.max - self.nl.min + 1
        self.nl.stride = math.ceil(nl_steps * (1/25))
        self.nl.steps = math.ceil(nl_steps / self.nl.stride)
        if (self.nl.steps - 1) * self.nl.stride < self.nl.max - self.nl.min then
            self.nl.steps = self.nl.steps + 1
        end
        self.nl.steps = math.min(self.nl.steps, nl_steps)
    end

    -- Input
    if Device:hasKeys() then
      local close_keys = Device:hasFewKeys() and { Device.input.group.Back, "Left" } or Device.input.group.Back
      self.key_events.Close = { { close_keys } }
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
    self.layout = {}

    local main_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = math.floor(self.screen_height * 0.2),
        },
    }

    -- Frontlight
    -- Bigger spans, as ProgressWidget appears to be ever so slightly smaller than ButtonProgressWidget ;).
    local fl_padding_span = VerticalSpan:new{ width = Math.round(self.span * 1.5) }
    local fl_group_above = HorizontalGroup:new{ align = "center" }
    local fl_group_below = HorizontalGroup:new{ align = "center" }
    local main_group = VerticalGroup:new{ align = "center" }

    local ticks = {}
    for i = 1, self.fl.steps - 2 do
        table.insert(ticks, i * self.fl.stride)
    end

    self.fl_progress = ProgressWidget:new{
        width = self.inner_width,
        height = Size.item.height_big,
        percentage = self.fl.cur / self.fl.max,
        ticks = ticks,
        tick_width = Screen:scaleBySize(0.5),
        last = self.fl.max,
    }
    local fl_header = TextWidget:new{
        text = _("Brightness"),
        face = self.medium_font_face,
        bold = true,
        max_width = self.inner_width,
    }
    self.fl_minus = Button:new{
        text = "−",
        enabled = self.fl.cur ~= self.fl.min,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.cur - 1)
        end,
    }
    self.fl_plus = Button:new{
        text = "＋",
        enabled = self.fl.cur ~= self.fl.max,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.cur + 1)
        end,
    }
    self.fl_level = TextWidget:new{
        text = tostring(self.fl.cur),
        face = self.medium_font_face,
        max_width = self.inner_width - 2*self.button_width,
    }
    local fl_level_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.fl_level.max_width,
            h = self.fl_level:getSize().h
        },
        self.fl_level,
    }
    local fl_min = Button:new{
        text = C_("Extrema", "Min"),
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.min + 1)
        end, -- min is 1 (We use 0 to mean "toggle")
    }
    local fl_max = Button:new{
        text = C_("Extrema", "Max"),
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.max)
        end,
    }
    local fl_toggle = Button:new{
        text = _("Toggle"),
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:setBrightness(self.fl.min)
        end,
    }
    local fl_spacer = HorizontalSpan:new{
        width = math.floor((self.inner_width - 3 * self.button_width) / 2)
    }
    local fl_buttons_above = HorizontalGroup:new{
        align = "center",
        self.fl_minus,
        fl_level_container,
        self.fl_plus,
    }
    self.layout[1] = {self.fl_minus, self.fl_plus}
    local fl_buttons_below = HorizontalGroup:new{
        align = "center",
        fl_min,
        fl_spacer,
        fl_toggle,
        fl_spacer,
        fl_max,
    }
    self.layout[2] = {fl_min, fl_toggle, fl_max}

    if self.has_nl then
        -- Only insert a "Brightness" caption if we also add the full set of warmth widgets below,
        -- otherwise, it's implied by the title bar ;).
        table.insert(main_group, fl_header)
    end
    table.insert(fl_group_above, fl_buttons_above)
    table.insert(fl_group_below, fl_buttons_below)
    table.insert(main_group, fl_padding_span)
    table.insert(main_group, fl_group_above)
    table.insert(main_group, fl_padding_span)
    table.insert(main_group, self.fl_progress)
    table.insert(main_group, fl_padding_span)
    table.insert(main_group, fl_group_below)
    table.insert(main_group, fl_padding_span)

    -- Warmth
    if self.has_nl then
        -- Smaller spans, as ButtonProgressWidget appears to be ever so slightly taller than ProgressWidget ;).
        local nl_padding_span = VerticalSpan:new{ width = self.span }
        local nl_group_above = HorizontalGroup:new{ align = "center" }
        local nl_group_below = HorizontalGroup:new{ align = "center" }

        self.nl_progress = ButtonProgressWidget:new{
            width = self.inner_width,
            font_size = 20, -- match Button's default
            padding = 0,
            thin_grey_style = false,
            num_buttons = self.nl.steps - 1, -- no button for step 0
            position = math.floor(self.nl.cur / self.nl.stride),
            default_position = math.floor(self.nl.cur / self.nl.stride),
            callback = function(i)
                self:setWarmth(Math.round(i * self.nl.stride), false)
            end,
            show_parent = self,
            enabled = true,
        }
        -- We want a wider gap between the two sets of widgets
        local nl_span = VerticalSpan:new{ width = Size.span.vertical_large * 4 }
        local nl_header = TextWidget:new{
            text = _("Warmth"),
            face = self.medium_font_face,
            bold = true,
            max_width = self.inner_width,
        }
        self.nl_minus = Button:new{
            text = "−",
            enabled = self.nl.cur ~= self.nl.min,
            width = self.button_width,
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.cur - 1, true) end,
        }
        self.nl_plus = Button:new{
            text = "＋",
            enabled = self.nl.cur ~= self.nl.max,
            width = self.button_width,
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.cur + 1, true) end,
        }
        self.nl_level = TextWidget:new{
            text = tostring(self.nl.cur),
            face = self.medium_font_face,
            max_width = self.inner_width - 2*self.button_width,
        }
        local nl_level_container = CenterContainer:new{
            dimen = Geom:new{
                w = self.nl_level.max_width,
                h = self.nl_level:getSize().h
            },
            self.nl_level,
        }
        local nl_min = Button:new{
            text = C_("Extrema", "Min"),
            enabled = true,
            width = self.button_width,
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.min, true)
            end,
        }
        local nl_max = Button:new{
            text = C_("Extrema", "Max"),
            enabled = true,
            width = self.button_width,
            show_parent = self,
            callback = function()
                self:setWarmth(self.nl.max, true)
            end,
        }
        local nl_setup
        local nl_spacer_width
        -- Aura One R/G/B widget
        if not self.has_nl_mixer and not self.has_nl_api then
            nl_setup =  Button:new{
                text = _("Configure"),
                width = self.button_width,
                show_parent = self,
                callback = function()
                    UIManager:show(NaturalLight:new{fl_widget = self})
                end,
            }
            nl_spacer_width = math.floor((self.inner_width - 3 * self.button_width) / 2)
        else
            nl_spacer_width = self.inner_width - 2 * self.button_width
        end
        local nl_spacer = HorizontalSpan:new{
            width = nl_spacer_width
        }
        local nl_buttons_above = HorizontalGroup:new{
            align = "center",
            self.nl_minus,
            nl_level_container,
            self.nl_plus,
        }
        self.layout[3] = {self.nl_minus, self.nl_plus}
        self:mergeLayoutInVertical(self.nl_progress) -- move it as self.layout[4]
        local nl_buttons_below = HorizontalGroup:new{
            align = "center",
            nl_min,
            nl_spacer,
            nl_max,
        }
        self.layout[5] = {nl_min, nl_max}
        if nl_setup then
            table.insert(nl_buttons_below, 3, nl_setup)
            table.insert(nl_buttons_below, 4, nl_spacer)
            table.insert(self.layout[5], 2, nl_setup)
        end

        table.insert(main_group, nl_span)
        table.insert(main_group, nl_header)
        table.insert(nl_group_above, nl_buttons_above)
        table.insert(nl_group_below, nl_buttons_below)

        table.insert(main_group, nl_padding_span)
        table.insert(main_group, nl_group_above)
        table.insert(main_group, nl_padding_span)
        table.insert(main_group, self.nl_progress)
        table.insert(main_group, nl_padding_span)
        table.insert(main_group, nl_group_below)
        table.insert(main_group, nl_padding_span)

    end

    table.insert(main_container, main_group)
    -- Reset container height to what it actually contains
    main_container.dimen.h = main_group:getSize().h

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
        main_container,
    }
    local center_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = inner_frame:getSize().h,
        },
        inner_frame,
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
            center_container,
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
    self:refocusWidget()

    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
    return true
end

function FrontLightWidget:updateBrightnessWidgets()
    self.fl_progress:setPercentage(self.fl.cur / self.fl.max)
    self.fl_level:setText(tostring(self.fl.cur))
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
end

function FrontLightWidget:refreshBrightnessWidgets()
    self:updateBrightnessWidgets()
    self:update()
end

function FrontLightWidget:setBrightness(intensity)
    -- Let fl.min through, as that's what we use for the Toggle button ;).
    if intensity ~= self.fl.min and intensity == self.fl.cur then
        return
    end

    -- Set brightness
    self:setFrontLightIntensity(intensity)

    -- Update the progress bar
    self:updateBrightnessWidgets()

    -- Refresh widget
    self:update()
end

function FrontLightWidget:setWarmth(warmth, update_position)
    if warmth == self.nl.cur then
        return
    end

    -- Set warmth
    self.powerd:setWarmth(self.powerd:fromNativeWarmth(warmth))
    -- Retrieve the value PowerD actually set, in case there were rounding shenanigans and we blew the range...
    self.nl.cur = self.powerd:toNativeWarmth(self.powerd:frontlightWarmth())

    -- If we were not called by ButtonProgressWidget's callback, we'll have to update its progress bar ourselves.
    if update_position then
        self.nl_progress:setPosition(math.floor(self.nl.cur / self.nl.stride), self.nl_progress.default_position)
    end

    self.nl_level:setText(tostring(self.nl.cur))
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
    self.powerd:updateResumeFrontlightState()

    -- Retrieve the real level set by PowerD (will be different from `intensity` on toggle)
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
        local perc = self.fl_progress:getPercentageFromPosition(ges_ev.pos)
        if not perc then
            return true
        end
        -- Unschedule any pending updates.
        UIManager:unschedule(self.refreshBrightnessWidgets)

        local num = Math.round(perc * self.fl.max)
        -- Always set the frontlight intensity.
        self:setFrontLightIntensity(num)

        -- But limit the widget update frequency on E Ink.
        if Screen.low_pan_rate then
            local current_time = time.now()
            local last_time = self.last_time or 0
            if current_time - last_time > time.s(1 / self.rate) then
                self.last_time = current_time
            else
                -- Schedule a final update after we stop panning.
                UIManager:scheduleIn(0.075, self.refreshBrightnessWidgets, self)
                return true
            end
        end

        self:refreshBrightnessWidgets()
    elseif not ges_ev.pos:intersectWith(self.frame.dimen) and ges_ev.ges == "tap" then
        -- Close when tapping outside.
        self:onClose()
    end
    -- Otherwise, do nothing (it's easy to miss a button).
    return true
end

FrontLightWidget.onPanProgress = FrontLightWidget.onTapProgress

return FrontLightWidget
