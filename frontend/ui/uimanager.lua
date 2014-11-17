local Device = require("device")
local Screen = Device.screen
local Input = require("device").input
local Event = require("ui/event")
local util = require("ffi/util")
local DEBUG = require("dbg")
local _ = require("gettext")

-- cf. koreader-base/ffi-cdecl/include/mxcfb-kindle.h (UPDATE_MODE_* applies to Kobo, too)
local UPDATE_MODE_PARTIAL       = 0x0
local UPDATE_MODE_FULL          = 0x1

-- Kindle waveform update modes
local WAVEFORM_MODE_INIT        = 0x0    -- Screen goes to white (clears)
local WAVEFORM_MODE_DU          = 0x1    -- Grey->white/grey->black
local WAVEFORM_MODE_GC16        = 0x2    -- High fidelity (flashing)
local WAVEFORM_MODE_GC4         = WAVEFORM_MODE_GC16 -- For compatibility
local WAVEFORM_MODE_GC16_FAST   = 0x3    -- Medium fidelity
local WAVEFORM_MODE_A2          = 0x4    -- Faster but even lower fidelity
local WAVEFORM_MODE_GL16        = 0x5    -- High fidelity from white transition
local WAVEFORM_MODE_GL16_FAST   = 0x6    -- Medium fidelity from white transition
-- Kindle FW >= 5.3
local WAVEFORM_MODE_DU4         = 0x7    -- Medium fidelity 4 level of gray direct update
-- Kindle PW2
local WAVEFORM_MODE_REAGL       = 0x8    -- Ghost compensation waveform
local WAVEFORM_MODE_REAGLD      = 0x9    -- Ghost compensation waveform with dithering
-- Kindle Basic/Kindle Voyage
local WAVEFORM_MODE_GL4         = 0xA    -- 2-bit from white transition
-- TODO: Use me in night mode on those devices?
local WAVEFORM_MODE_GL16_INV    = 0xB    -- High fidelity for black transition

-- Kobo waveform update modes
local NTX_WFM_MODE_INIT         = 0x0    -- WAVEFORM_MODE_INIT
local NTX_WFM_MODE_DU           = 0x1    -- WAVEFORM_MODE_DU
local NTX_WFM_MODE_GC16         = 0x2    -- WAVEFORM_MODE_GC16
local NTX_WFM_MODE_GC4          = 0x3    -- WAVEFORM_MODE_GC4
local NTX_WFM_MODE_A2           = 0x4    -- WAVEFORM_MODE_A2
local NTX_WFM_MODE_GL16         = 0x5    -- WAVEFORM_MODE_GL16
local NTX_WFM_MODE_GLR16        = 0x6    -- WAVEFORM_MODE_REAGL
local NTX_WFM_MODE_GLD16        = 0x7    -- WAVEFORM_MODE_REAGLD

-- Common
local WAVEFORM_MODE_AUTO        = 0x101


-- there is only one instance of this
local UIManager = {
    default_refresh_type = UPDATE_MODE_PARTIAL,
    default_waveform_mode = WAVEFORM_MODE_GC16, -- high fidelity waveform
    fast_waveform_mode = WAVEFORM_MODE_A2,
    full_refresh_waveform_mode = WAVEFORM_MODE_GC16,
    partial_refresh_waveform_mode = WAVEFORM_MODE_GC16,
    wait_for_every_marker = false,
    wait_for_ui_markers = false,
    -- force to repaint all the widget is stack, will be reset to false
    -- after each ui loop
    repaint_all = false,
    -- force to do full refresh, will be reset to false
    -- after each ui loop
    full_refresh = false,
    -- force to do partial refresh, will be reset to false
    -- after each ui loop
    partial_refresh = false,
    -- trigger a full refresh when counter reaches FULL_REFRESH_COUNT
    FULL_REFRESH_COUNT = G_reader_settings:readSetting("full_refresh_count") or DRCOUNTMAX,
    refresh_count = 0,
    -- only update specific regions of the screen
    update_regions_func = nil,

    event_handlers = nil,

    _running = true,
    _window_stack = {},
    _execution_stack = {},
    _execution_stack_dirty = false,
    _dirty = {},
    _zeromqs = {},
}

function UIManager:init()
    self.event_handlers = {
        __default__ = function(input_event)
            self:sendEvent(input_event)
        end,
        SaveState = function()
            self:sendEvent(Event:new("FlushSettings"))
        end,
        Power = function(input_event)
            Device:onPowerEvent(input_event)
        end,
    }
    if Device:isKobo() then
        self.event_handlers["Suspend"] = function(input_event)
            self:sendEvent(Event:new("FlushSettings"))
            Device:onPowerEvent(input_event)
        end
        self.event_handlers["Resume"] = function(input_event)
            Device:onPowerEvent(input_event)
            self:sendEvent(Event:new("Resume"))
        end
        self.event_handlers["Light"] = function()
            Device:getPowerDevice():toggleFrontlight()
        end
        self.event_handlers["__default__"] = function(input_event)
            if Device.screen_saver_mode then
                -- Suspension in Kobo can be interrupted by screen updates. We
                -- ignore user touch input here so screen udpate won't be
                -- triggered in suspend mode
                return
            else
                self:sendEvent(input_event)
            end
        end
        if KOBO_LIGHT_ON_START and tonumber(KOBO_LIGHT_ON_START) > -1 then
            Device:getPowerDevice():setIntensity( math.max( math.min(KOBO_LIGHT_ON_START,100) ,0) )
        end
        -- Emulate the stock reader's refresh behavior...
        self.full_refresh_waveform_mode = NTX_WFM_MODE_GC16
        -- Request REAGLD waveform mode on devices that support it (Aura & H2O)
        if Device.model == "Kobo_phoenix" or Device.model == "Kobo_dahlia" then
            self.partial_refresh_waveform_mode = NTX_WFM_MODE_GLD16
            -- Since Kobo doesn't have MXCFB_WAIT_FOR_UPDATE_SUBMISSION, enabling this currently has no effect :).
            self.wait_for_every_marker = true
            -- NOTE: The H2O appears to be the odd duck out... Nickel uses AUTO for PARTIAL updates instead of asking for REAGLD specifically...
            -- If we try to ask for FULL REAGLD updates, like on the Aura and the PW2, we get a black flash!
            -- The driver appears to be using some custom Kobo logic (that they only enable in their producttion build?) altering the behavior of AUTO to favor REAGL modes...
            -- Long story short: do the same as nickel: use AUTO, and hope for the best...
            if Device.model == "Kobo_dahlia" then
                self.partial_refresh_waveform_mode = WAVEFORM_MODE_AUTO
            end
        else
            -- Let the driver handle it on those models (asking for NTX_WFM_MODE_GL16 appears to be a very bad idea, #1146)
            self.partial_refresh_waveform_mode = WAVEFORM_MODE_AUTO
            self.wait_for_every_marker = false
            -- NOTE: Let's see if a bit of waiting works around potential timing issues on Kobos when doing *UI* refreshes in fast succession. (Not a concern on Kindle, where we have MXCFB_WAIT_FOR_UPDATE_SUBMISSION).
            self.wait_for_ui_markers = true
        end
        -- Let the driver decide what to do with PARTIAL UI updates...
        self.default_waveform_mode = WAVEFORM_MODE_AUTO
    elseif Device:isKindle() then
        self.event_handlers["IntoSS"] = function()
            self:sendEvent(Event:new("FlushSettings"))
            Device:intoScreenSaver()
        end
        self.event_handlers["OutOfSS"] = function()
            Device:outofScreenSaver()
            self:sendEvent(Event:new("Resume"))
        end
        self.event_handlers["Charging"] = function()
            Device:usbPlugIn()
        end
        self.event_handlers["NotCharging"] = function()
            Device:usbPlugOut()
            self:sendEvent(Event:new("NotCharging"))
        end
        -- Emulate the stock reader's refresh behavior...
        --[[
            NOTE: For ref, on a Touch (debugPaint & a patched strace are your friend!):
                UI: flash: GC16_FAST, non-flash: AUTO (prefers GC16_FAST)
                Reader: When flash: if to/from img: GC16, else GC16_FAST; when non-flash: AUTO (seems to prefer GL16_FAST); Waiting for marker only on flash
            On a PW2:
                UI: flash: GC16_FAST, non-flash: AUTO (prefers GC16_FAST)
                Reader: When flash: if to/from img: GC16, else GC16_FAST; when non-flash: REAGL (w/ UPDATE_MODE_FULL!); Always waits for marker
                    Note that the bottom status bar region is refreshed separately, right after the screen, as a PARTIAL, AUTO (GC16_FAST) update, and it's this marker that's waited after...
                    Non flash lasts longer (dual timeout: 14pgs / 7mins).
        --]]
        -- We don't really have an easy way to know if we're refreshing the UI, or a page, or if said page contains an image, so go with the highest fidelity option
        -- We spend much more time in the reader than the UI, and our UI isn't very graphic anyway, so we'll follow the reader's behaviour above all
        self.full_refresh_waveform_mode = WAVEFORM_MODE_GC16
        -- Request REAGL waveform mode on devices that support it (PW2, KT2, KV) [FIXME: Is that actually true of the KT2?]
        if Device.model == "KindlePaperWhite2" or Device.model == "KindleBasic" or Device.model == "KindleVoyage" then
            self.partial_refresh_waveform_mode = WAVEFORM_MODE_REAGL
            -- We need to wait for every update marker when using REAGL waveform modes. That mostly means we always use MXCFB_WAIT_FOR_UPDATE_SUBMISSION.
            self.wait_for_every_marker = true
        else
            self.partial_refresh_waveform_mode = WAVEFORM_MODE_GL16_FAST
            -- NOTE: Or we could go back to what KOReader did before fa55acc in koreader-base, which was also to use AUTO ;).
            -- That said, we *should* be making more or less the same decisions as AUTO on our own, if I followed things correctly...
            --self.partial_refresh_waveform_mode = WAVEFORM_MODE_AUTO
            -- Only wait for update markers on FULL updates
            self.wait_for_every_marker = false
        end
        -- Default to GC16_FAST (will be used for PARTIAL UI updates)
        self.default_waveform_mode = WAVEFORM_MODE_GC16_FAST
    end
end

-- register & show a widget
-- modal widget should be always on the top
function UIManager:show(widget, x, y)
    DEBUG("show widget", widget.id)
    self._running = true
    local window = {x = x or 0, y = y or 0, widget = widget}
    -- put this window on top of the toppest non-modal window
    for i = #self._window_stack, 0, -1 do
        local top_window = self._window_stack[i]
        -- skip modal window
        if not top_window or not top_window.widget.modal then
            table.insert(self._window_stack, i + 1, window)
            break
        end
    end
    -- and schedule it to be painted
    self:setDirty(widget)
    -- tell the widget that it is shown now
    widget:handleEvent(Event:new("Show"))
    -- check if this widget disables double tap gesture
    if widget.disable_double_tap then
        Input.disable_double_tap = true
    end
end

-- unregister a widget
function UIManager:close(widget)
    if not widget then
        DEBUG("widget not exist to be closed")
        return
    end
    DEBUG("close widget", widget.id)
    Input.disable_double_tap = DGESDETECT_DISABLE_DOUBLE_TAP
    local dirty = false
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == widget then
            table.remove(self._window_stack, i)
            dirty = true
        elseif self._window_stack[i].widget.disable_double_tap then
            Input.disable_double_tap = true
        end
    end
    if dirty then
        -- schedule remaining widgets to be painted
        for i = 1, #self._window_stack do
            self:setDirty(self._window_stack[i].widget)
        end
    end
end

-- schedule an execution task
function UIManager:schedule(time, action)
    table.insert(self._execution_stack, { time = time, action = action })
    self._execution_stack_dirty = true
end

-- schedule task in a certain amount of seconds (fractions allowed) from now
function UIManager:scheduleIn(seconds, action)
    local when = { util.gettime() }
    local s = math.floor(seconds)
    local usecs = (seconds - s) * 1000000
    when[1] = when[1] + s
    when[2] = when[2] + usecs
    if when[2] > 1000000 then
        when[1] = when[1] + 1
        when[2] = when[2] - 1000000
    end
    self:schedule(when, action)
end

-- unschedule an execution task
-- in order to unschedule anonymous functions, store a reference
-- for example:
-- self.anonymousFunction = function() self:regularFunction() end
-- UIManager:scheduleIn(10, self.anonymousFunction)
-- UIManager:unschedule(self.anonymousFunction)
function UIManager:unschedule(action)
    for i = #self._execution_stack, 1, -1 do
        local task = self._execution_stack[i]
        if task.action == action then
            -- remove from table
            table.remove(self._execution_stack, i)
        end
    end
end

-- register a widget to be repainted
function UIManager:setDirty(widget, refresh_type)
    -- "auto": request full refresh
    -- "full": force full refresh
    -- "partial": partial refresh
    if not refresh_type then
        refresh_type = "auto"
    end
    if widget then
        self._dirty[widget] = refresh_type
    end
end

function UIManager:insertZMQ(zeromq)
    table.insert(self._zeromqs, zeromq)
    return zeromq
end

function UIManager:removeZMQ(zeromq)
    for i = #self._zeromqs, 1, -1 do
        if self._zeromqs[i] == zeromq then
            table.remove(self._zeromqs, i)
        end
    end
end

-- set full refresh rate for e-ink screen
-- and make the refresh rate persistant in global reader settings
function UIManager:setRefreshRate(rate)
    DEBUG("set screen full refresh rate", rate)
    self.FULL_REFRESH_COUNT = rate
    G_reader_settings:saveSetting("full_refresh_count", rate)
end

-- get full refresh rate for e-ink screen
function UIManager:getRefreshRate(rate)
    return self.FULL_REFRESH_COUNT
end

-- signal to quit
function UIManager:quit()
    DEBUG("quit uimanager")
    self._running = false
    for i = #self._window_stack, 1, -1 do
        table.remove(self._window_stack, i)
    end
    for i = #self._execution_stack, 1, -1 do
        table.remove(self._execution_stack, i)
    end
    for i = #self._zeromqs, 1, -1 do
        self._zeromqs[i]:stop()
        table.remove(self._zeromqs, i)
    end
end

-- transmit an event to registered widgets
function UIManager:sendEvent(event)
    if #self._window_stack == 0 then return end
    -- top level widget has first access to the event
    if self._window_stack[#self._window_stack].widget:handleEvent(event) then
        return
    end

    -- if the event is not consumed, active widgets can access it
    for _, widget in ipairs(self._window_stack) do
        if widget.widget.is_always_active then
            if widget.widget:handleEvent(event) then return end
        end
        if widget.widget.active_widgets then
            for _, active_widget in ipairs(widget.widget.active_widgets) do
                if active_widget:handleEvent(event) then return end
            end
        end
    end
end

function UIManager:checkTasks()
    local now = { util.gettime() }

    -- check if we have timed events in our queue and search next one
    local wait_until = nil
    local all_tasks_checked
    repeat
        all_tasks_checked = true
        for i = #self._execution_stack, 1, -1 do
            local task = self._execution_stack[i]
            if not task.time
                or task.time[1] < now[1]
                or task.time[1] == now[1] and task.time[2] < now[2] then
                -- task is pending to be executed right now. do it.
                task.action()
                -- and remove from table
                table.remove(self._execution_stack, i)
                -- start loop again, since new tasks might be on the
                -- queue now
                all_tasks_checked = false
            elseif not wait_until
                or wait_until[1] > task.time[1]
                or wait_until[1] == task.time[1] and wait_until[2] > task.time[2] then
                -- task is to be run in the future _and_ is scheduled
                -- earlier than the tasks we looked at already
                -- so adjust to the currently examined task instead.
                wait_until = task.time
            end
        end
    until all_tasks_checked
    self._execution_stack_dirty = false
    return wait_until, now
end

-- repaint dirty widgets
function UIManager:repaint()
    local dirty = false
    local request_full_refresh = false
    local force_full_refresh = false
    local force_partial_refresh = false
    local force_fast_refresh = false
    for _, widget in ipairs(self._window_stack) do
        -- paint if repaint_all is request
        -- paint also if current widget or any widget underneath is dirty
        if self.repaint_all or dirty or self._dirty[widget.widget] then
            widget.widget:paintTo(Screen.bb, widget.x, widget.y)

            if self._dirty[widget.widget] == "auto" then
                -- Most likely a 'reader' refresh. 'request' in the sense once we hit our FULL_REFRESH_COUNT ;).
                request_full_refresh = true
            end
            if self._dirty[widget.widget] == "full" then
                force_full_refresh = true
            end
            if self._dirty[widget.widget] == "partial" then
                force_partial_refresh = true
            end
            if self._dirty[widget.widget] == "fast" then
                force_fast_refresh = true
            end
            -- and remove from list after painting
            self._dirty[widget.widget] = nil
            -- trigger repaint
            dirty = true
        end
    end

    if self.full_refresh then
        dirty = true
        force_full_refresh = true
    end

    if self.partial_refresh then
        dirty = true
        force_partial_refresh = true
    end

    self.repaint_all = false
    self.full_refresh = false
    self.partial_refresh = false

    local refresh_type = self.default_refresh_type
    local waveform_mode = self.default_waveform_mode
    local wait_for_marker = self.wait_for_every_marker
    if dirty then
        if force_partial_refresh or force_fast_refresh or self.update_regions_func then
            refresh_type = UPDATE_MODE_PARTIAL
            -- Override wait_for_marker if we need to enable the Kobo timing workaround on UI refreshes
            if self.wait_for_ui_markers then
                wait_for_marker = true
            end
        elseif force_full_refresh or self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
            refresh_type = UPDATE_MODE_FULL
        end
        -- Handle the waveform mode selection...
        if refresh_type == UPDATE_MODE_FULL then
            waveform_mode = self.full_refresh_waveform_mode
        else
            waveform_mode = self.partial_refresh_waveform_mode
        end
        if force_fast_refresh then
            waveform_mode = self.fast_waveform_mode
            -- FIXME: Should we also avoid doing an MXCFB_WAIT_FOR_UPDATE_SUBMISSION for this update?
            --wait_for_marker = false
        end
        -- If the device is REAGL-aware, we're specifically asking for a REAGL update, and we're doing a PARTIAL *reader* refresh, apply some trickery to match the stock reader's behavior
        -- (On most device, REAGL updates are always FULL, but there's no black flash. On devices where this isn't the case [H2O], we're letting the driver do the job by using AUTO).
        if not force_partial_refresh and not force_fast_refresh and refresh_type == UPDATE_MODE_PARTIAL and (waveform_mode == WAVEFORM_MODE_REAGL or waveform_mode == NTX_WFM_MODE_GLD16) then
            refresh_type = UPDATE_MODE_FULL
        end
        -- On the other hand, if we asked for a PARTIAL *UI* refresh, fall back to the default waveform mode, which is tailored per-device to hopefully be more appropriate in this instance than the one we use in the reader.
        if force_partial_refresh then
            -- NOTE: Using default_waveform_mode might seem counter-intuitive when we have partial_refresh_waveform_mode, but partial_refresh_waveform_mode is mostly there as a means to flag REAGL-aware devices ;).
            -- Here, we're actually interested in handling PARTIAL, regional (be it properly flagged or not) updates, and not the PARTIAL updates from the reader that actually refresh the whole screen (i.e., those between black flashes).
            waveform_mode = self.default_waveform_mode
        end
        if self.update_regions_func then
            local update_regions = self.update_regions_func()
            for _, update_region in ipairs(update_regions) do
                -- in some rare cases update region has 1 pixel offset
                Screen:refresh(refresh_type, waveform_mode, wait_for_marker,
                               update_region.x-1, update_region.y-1,
                               update_region.w+2, update_region.h+2)
            end
        else
            Screen:refresh(refresh_type, waveform_mode, wait_for_marker)
        end
        -- REAGL refreshes are always FULL (but without a black flash), but we want to keep our black flash timeout working, so don't reset the counter on FULL REAGL refreshes...
        if refresh_type == UPDATE_MODE_FULL and waveform_mode ~= WAVEFORM_MODE_REAGL and waveform_mode ~= NTX_WFM_MODE_GLD16 then
            self.refresh_count = 0
        elseif not force_partial_refresh and not force_full_refresh and not self.update_regions_func then
            self.refresh_count = (self.refresh_count + 1)%self.FULL_REFRESH_COUNT
        end
    end
    self.update_regions_func = nil
end

-- this is the main loop of the UI controller
-- it is intended to manage input events and delegate
-- them to dialogs
function UIManager:run()
    self._running = true
    while self._running do
        local wait_until, now
        -- run this in a loop, so that paints can trigger events
        -- that will be honored when calculating the time to wait
        -- for input events:
        repeat
            wait_until, now = self:checkTasks()

            --DEBUG("---------------------------------------------------")
            --DEBUG("exec stack", self._execution_stack)
            --DEBUG("window stack", self._window_stack)
            --DEBUG("dirty stack", self._dirty)
            --DEBUG("---------------------------------------------------")

            -- stop when we have no window to show
            if #self._window_stack == 0 then
                DEBUG("no dialog left to show")
                self:quit()
                return nil
            end

            self:repaint()
        until not self._execution_stack_dirty

        -- wait for next event
        -- note that we will skip that if we have tasks that are ready to run
        local input_event = nil
        if not wait_until then
            if #self._zeromqs > 0 then
                -- pending message queue, wait 100ms for input
                input_event = Input:waitEvent(1000*100)
                if not input_event or input_event.handler == "onInputError" then
                    for _, zeromq in ipairs(self._zeromqs) do
                        input_event = zeromq:waitEvent()
                        if input_event then break end
                    end
                end
            else
                -- no pending task, wait without timeout
                input_event = Input:waitEvent()
            end
        elseif wait_until[1] > now[1]
        or wait_until[1] == now[1] and wait_until[2] > now[2] then
            local wait_for = { s = wait_until[1] - now[1], us = wait_until[2] - now[2] }
            if wait_for.us < 0 then
                wait_for.s = wait_for.s - 1
                wait_for.us = 1000000 + wait_for.us
            end
            -- wait until next task is pending
            input_event = Input:waitEvent(wait_for.us, wait_for.s)
        end

        -- delegate input_event to handler
        if input_event then
            local handler = self.event_handlers[input_event]
            if handler then
                handler(input_event)
            else
                self.event_handlers["__default__"](input_event)
            end
        end
    end
end

function UIManager:getRefreshMenuTable()
    local function custom_1() return G_reader_settings:readSetting("refresh_rate_1") or 12 end
    local function custom_2() return G_reader_settings:readSetting("refresh_rate_2") or 22 end
    local function custom_3() return G_reader_settings:readSetting("refresh_rate_3") or 99 end
    local function custom_input(name)
        return {
            title = _("Input page number for a full refresh"),
            type = "number",
            hint = "(1 - 99)",
            callback = function(input)
                local rate = tonumber(input)
                G_reader_settings:saveSetting(name, rate)
                UIManager:setRefreshRate(rate)
            end,
        }
    end
    return {
        text = _("E-ink full refresh rate"),
        sub_item_table = {
            {
                text = _("Every page"),
                checked_func = function() return UIManager:getRefreshRate() == 1 end,
                callback = function() UIManager:setRefreshRate(1) end,
            },
            {
                text = _("Every 6 pages"),
                checked_func = function() return UIManager:getRefreshRate() == 6 end,
                callback = function() UIManager:setRefreshRate(6) end,
            },
            {
                text_func = function() return _("Custom ") .. "1: " .. custom_1() .. _(" pages") end,
                checked_func = function() return UIManager:getRefreshRate() == custom_1() end,
                callback = function() UIManager:setRefreshRate(custom_1()) end,
                hold_input = custom_input("refresh_rate_1")
            },
            {
                text_func = function() return _("Custom ") .. "2: " .. custom_2() .. _(" pages") end,
                checked_func = function() return UIManager:getRefreshRate() == custom_2() end,
                callback = function() UIManager:setRefreshRate(custom_2()) end,
                hold_input = custom_input("refresh_rate_2")
            },
            {
                text_func = function() return _("Custom ") .. "3: " .. custom_3() .. _(" pages") end,
                checked_func = function() return UIManager:getRefreshRate() == custom_3() end,
                callback = function() UIManager:setRefreshRate(custom_3()) end,
                hold_input = custom_input("refresh_rate_3")
            },
        }
    }
end

UIManager:init()
return UIManager

