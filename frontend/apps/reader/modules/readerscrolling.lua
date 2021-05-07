local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

-- This module exposes Scrolling settings, and additionnally
-- handles inertial scrolling on non-eInk devices.

local ReaderScrolling = InputContainer:new{
    -- Available scrolling methods
    SCROLL_METHOD_CLASSIC = "classic",
    SCROLL_METHOD_TURBO = "turbo",
    SCROLL_METHOD_ON_RELEASE = "on_release",

    scroll_method = "classic",
    inertial_scroll = false,

    _inertial_scroll_supported = false,
    _inertial_scroll_enabled = false,

    pan_rate = 30,  -- default 30 ops, will be adjusted in readerui
    scroll_friction = 0.2, -- the lower, the sooner inertial scrolling stops
    -- no inertial scrolling if 300ms pause without any movement before release
    pause_before_release_cancel_duration = TimeVal:new{ sec = 0, usec = 300000 },

    -- Callbacks to be updated by readerrolling or readerpaging
    _do_scroll_callback = function(distance) return false end,
    _scroll_done_callback = function() end,

    _inertial_scroll_interval = 1 / 30,
    _inertial_scroll_action_scheduled = false,
    _just_reschedule = false,
    _last_manual_scroll_dy = 0,
    _velocity = 0,
}

function ReaderScrolling:init()
    if not Device:isTouchDevice() then
        -- No scroll support, no menu
        return
    end

    -- The different scrolling methods are handled directly by readerpaging/readerrolling
    self.scroll_method = G_reader_settings:readSetting("scroll_method") or SCROLL_METHOD_CLASSIC

    -- Keep inertial scrolling available on the emulator (which advertizes itself as eInk)
    if not Device:hasEinkScreen() or Device:isEmulator() then
        self._inertial_scroll_supported = true
    end

    if self._inertial_scroll_supported then
        self.inertial_scroll = G_reader_settings:nilOrTrue("inertial_scroll")
        self._inertial_scroll_interval = 1 / self.pan_rate
        -- Set this so we don't have to check for nil, and in case
        -- we miss a first touch event.
        -- We can keep it obsolete, which will result in a long
        -- duration and a small/zero velocity that won't hurt.
        self._last_manual_scroll_timev = TimeVal.zero
        self:_setupAction()
    end

    self.ui.menu:registerToMainMenu(self)
end

function ReaderScrolling:addToMainMenu(menu_items)
    menu_items.scrolling = {
        text = _("Scrolling"),
        enabled_func = function()
            -- Make it only enabled when in continuous/scroll mode
            -- (different setting in self.view whether rolling or paging document)
            if self.view and (self.view.page_scroll or self.view.view_mode == "scroll") then
                return true
            end
            return false
        end,
        sub_item_table = {
            {
                text = _("Classic scrolling"),
                help_text = _([[Classic scrolling will move the document with your finger.]]),
                checked_func = function()
                    return self.scroll_method == self.SCROLL_METHOD_CLASSIC
                end,
                callback = function()
                    if self.scroll_method ~= self.SCROLL_METHOD_CLASSIC then
                        self.scroll_method = self.SCROLL_METHOD_CLASSIC
                        self:applyScrollSettings()
                    end
                end,
            },
            {
                text = _("Turbo scrolling"),
                help_text = _([[
Turbo scrolling will scroll the document, at each step, by the distance from your initial finger position (rather than by the distance from your previous finger position).
It allows for faster scrolling without the need to lift and reposition your finger.]]),
                checked_func = function()
                    return self.scroll_method == self.SCROLL_METHOD_TURBO
                end,
                callback = function()
                    if self.scroll_method ~= self.SCROLL_METHOD_TURBO then
                        self.scroll_method = self.SCROLL_METHOD_TURBO
                        self:applyScrollSettings()
                    end
                end,
            },
            {
                text = _("On-release scrolling"),
                help_text = _([[
On-release scrolling will scroll the document by the panned distance only on finger up.
This is interesting on eInk if you only pan to better adjust page vertical position.]]),
                checked_func = function()
                    return self.scroll_method == self.SCROLL_METHOD_ON_RELEASE
                end,
                callback = function()
                    if self.scroll_method ~= self.SCROLL_METHOD_ON_RELEASE then
                        self.scroll_method = self.SCROLL_METHOD_ON_RELEASE
                        self:applyScrollSettings()
                    end
                end,
                separator = true,
            },
        }
    }
    if self._inertial_scroll_supported then
        table.insert(menu_items.scrolling.sub_item_table, {
            text = _("Allow inertial scrolling"),
            enabled_func = function()
                return self.scroll_method == self.SCROLL_METHOD_CLASSIC
            end,
            checked_func = function()
                return self.scroll_method == self.SCROLL_METHOD_CLASSIC and self.inertial_scroll
            end,
            callback = function()
                self.inertial_scroll = not self.inertial_scroll
                self:applyScrollSettings()
            end,
        })
    end
end

function ReaderScrolling:onReaderReady()
    self:applyScrollSettings()
end

function ReaderScrolling:applyScrollSettings()
    G_reader_settings:saveSetting("scroll_method", self.scroll_method)
    G_reader_settings:saveSetting("inertial_scroll", self.inertial_scroll)
    if self.scroll_method == self.SCROLL_METHOD_CLASSIC then
        self._inertial_scroll_enabled = self.inertial_scroll
    else
        self._inertial_scroll_enabled = false
    end
    self:setupTouchZones()
    self.ui:handleEvent(Event:new("ScrollSettingsUpdated", self.scroll_method, self._inertial_scroll_enabled))
end

function ReaderScrolling:setupTouchZones()
    self.ges_events = {}
    self.onGesture = nil

    local zones = {
        {
            id = "inertial_scrolling_touch",
            ges = "touch",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges)
                -- A touch might set the start of the first pan event,
                -- that we need to compute its duration
                self._last_manual_scroll_timev = ges.time
                -- If we are scrolling, a touch cancels it. We want its release
                -- (which will trigger a tap) to not change pages.
                self._ignore_next_tap = self._inertial_scroll_action
                                            and self._inertial_scroll_action(false)
                                             or false
            end,
        },
        {
            id = "inertial_scrolling_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            overrides = {
                "tap_forward",
                "tap_backward",
                "readermenu_tap",
                "readermenu_ext_tap",
                "readerconfigmenu_tap",
                "readerconfigmenu_ext_tap",
                "readerfooter_tap",
                "readerhighlight_tap",
                "tap_link",
            },
            handler = function()
                if self._ignore_next_tap then
                    -- Ignore tap if requested
                    self._ignore_next_tap = false
                    return true
                end
                -- Otherwise, let it be handled by other tap handlers
            end,
        },
    }
    if self._inertial_scroll_enabled then
        self.ui:registerTouchZones(zones)
    else
        self.ui:unRegisterTouchZones(zones)
    end
end

function ReaderScrolling:isInertialScrollingEnabled()
    return self._inertial_scroll_enabled
end

function ReaderScrolling:setInertialScrollCallbacks(do_scroll_callback, scroll_done_callback)
    self._do_scroll_callback = do_scroll_callback
    self._scroll_done_callback = scroll_done_callback
end

function ReaderScrolling:startInertialScroll()
    if not self._inertial_scroll_enabled then
        return false
    end
    return self._inertial_scroll_action(true)
end

function ReaderScrolling:cancelInertialScroll()
    if not self._inertial_scroll_enabled then
        return
    end
    return self._inertial_scroll_action(false)
end

function ReaderScrolling:accountManualScroll(dy, timev)
    if not self._inertial_scroll_enabled then
        return
    end
    self._last_manual_scroll_dy = dy
    self._last_manual_scroll_duration = timev - self._last_manual_scroll_timev
    self._last_manual_scroll_timev = timev
end

function ReaderScrolling:_setupAction()
    self._inertial_scroll_action = function(action)
        -- action can be:
        -- - true: stop any previous ongoing inertial scroll, then start a new one
        --   (returns true if we started one)
        -- - false: just stop any previous ongoing inertial scroll
        --   (returns true if we did cancel one)
        if action ~= nil then
            local cancelled = false
            if self._inertial_scroll_action_scheduled then
                UIManager:unschedule(self._inertial_scroll_action)
                self._inertial_scroll_action_scheduled = false
                cancelled = true
                self._scroll_done_callback()
                logger.dbg("inertial scrolling cancelled")
            end
            if action == false then
                self._last_manual_scroll_dy = 0
                return cancelled
            end

            -- Initiate inertial scrolling (action=true), unless we should not
            local delay = UIManager:getTime() - self._last_manual_scroll_timev
            if UIManager:getTime() - self._last_manual_scroll_timev >= self.pause_before_release_cancel_duration then
                -- but not if no finger move for 0.3s before finger up
                self._last_manual_scroll_dy = 0
                return false
            end
            if self._last_manual_scroll_duration:isZero() or self._last_manual_scroll_dy == 0 then
                return false
            end

            -- Initial velocity is the one of the last pan scroll given to accountManualScroll()
            local delay = self._last_manual_scroll_duration:tousecs()
            if delay < 1 then delay = 1 end -- safety check
            self._velocity = self._last_manual_scroll_dy * 1000000 / delay
            self._last_manual_scroll_dy = 0

            self._inertial_scroll_action_scheduled = true
            -- We'll keep re-scheduling this same action, which will do
            -- alternatively thanks to the _just_reschedule flag:
            -- * either, in _inertial_scroll_interval, do a scroll
            -- * or, then, at next tick, reschedule 1)
            -- This is needed as the first one will cause a repaint that
            -- may take more than _inertial_scroll_interval, which if we
            -- didn't do that could be run before we process any input,
            -- not allowing us to interrupt this inertial scrolling.
            self._just_reschedule = false
            UIManager:scheduleIn(self._inertial_scroll_interval, self._inertial_scroll_action)
            -- self._stats_scroll_iterations = 0
            -- self._stats_scroll_distance = 0
            logger.dbg("inertial scrolling started")
            return true
        end
        if not self._inertial_scroll_action_scheduled then
            -- Safety check, shouldn't happen
            return
        end
        if not self.ui.document then
            -- might happen if scheduled and run after document is closed
            return
        end

        if self._just_reschedule then
            -- just re-schedule this, so a real scrolling is done after the delay
            self._just_reschedule = false
            UIManager:scheduleIn(self._inertial_scroll_interval, self._inertial_scroll_action)
            return
        end

        -- Decrease velocity at each step
        self._velocity = self._velocity * math.pow(self.scroll_friction, self._inertial_scroll_interval)
        local dist = math.floor(self._velocity * self._inertial_scroll_interval)
        -- self._stats_scroll_iterations = self._stats_scroll_iterations + 1
        -- self._stats_scroll_distance = self._stats_scroll_distance + dist

        logger.dbg("inertial scrolling by", dist)
        local did_scroll = self._do_scroll_callback(dist)

        if did_scroll and (dist >= 2 or dist <= -2) then
            UIManager.refresh_count = 0 -- avoid partial to full promotion
            -- Schedule at next tick the real re-scheduling
            self._just_reschedule = true
            UIManager:nextTick(self._inertial_scroll_action)
            return
        end

        -- We're done
        self._inertial_scroll_action_scheduled = false
        self._scroll_done_callback()
        logger.dbg("inertial scrolling ended")

        --[[
        local Notification = require("ui/widget/notification")
        UIManager:show(Notification:new{
            text = string.format("%d iterations, %d px scrolled",
                    self._stats_scroll_iterations, self._stats_scroll_distance),
        })
        ]]--
    end
end

return ReaderScrolling
