local Device = require("ui/device")
local Screen = require("ui/screen")
local Input = require("ui/input")
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")
local util = require("ffi/util")

-- initialize output module, this must be initialized before Input
Screen:init()
-- initialize the input handling
Input:init()

-- NOTE: Those have been confirmed on Kindle devices. Might be completely different on Kobo (except for AUTO)!
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

local WAVEFORM_MODE_AUTO        = 0x101

-- there is only one instance of this
local UIManager = {
    default_refresh_type = 0, -- 0 for partial refresh, 1 for full refresh
    default_waveform_mode = WAVEFORM_MODE_GC16, -- high fidelity waveform
    fast_waveform_mode = WAVEFORM_MODE_A2,
    full_refresh_waveform_mode = WAVEFORM_MODE_GC16,
    partial_refresh_waveform_mode = WAVEFORM_MODE_GC16,
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
    FULL_REFRESH_COUNT = DRCOUNTMAX,
    refresh_count = 0,

    event_handlers = nil,

    _running = true,
    _window_stack = {},
    _execution_stack = {},
    _dirty = {},
    _zeromqs = {},
}


function UIManager:init()
    -- For the Kobo Aura an offset is needed, because the bezel make the
    -- visible screen smaller.
    
    function self:offsetX() return Screen:offsetX() end
    function self:offsetY() return Screen:offsetY() end

    self.event_handlers = {
        __default__ = function(input_event)
            self:sendEvent(input_event)
        end,
        SaveState = function()
            self:sendEvent(Event:new("FlushSettings"))
        end
    }
    if Device:isKobo() then
        -- lazy create suspend_msg to avoid dependence loop
        local suspend_msg = nil
        function kobo_power(input_event)
            if (input_event == "Power" or input_event == "Suspend")
                    and not Device.screen_saver_mode then
                if not suspend_msg then
                    local InfoMessage = require("ui/widget/infomessage")
                    suspend_msg = InfoMessage:new{ text = _("Suspended") }
                end
                self:show(suspend_msg)
                self:sendEvent(Event:new("FlushSettings"))
                Device:prepareSuspend()
                self:scheduleIn(2, function() Device:Suspend() end)
            elseif (input_event == "Power" or input_event == "Resume")
                    and Device.screen_saver_mode then
                Device:Resume()
                self:sendEvent(Event:new("Resume"))
                if suspend_msg then
                    self:close(suspend_msg)
                end
            end
        end
        self.event_handlers["Power"] = kobo_power
        self.event_handlers["Suspend"] = kobo_power
        self.event_handlers["Resume"] = kobo_power
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
    elseif Device:isKindle() then
        self.event_handlers["IntoSS"] = function()
            self:sendEvent(Event:new("FlushSettings"))
            Device:intoScreenSaver()
        end
        self.event_handlers["OutOfSS"] = function()
            Device:outofScreenSaver()
        end
        self.event_handlers["Charging"] = function()
            Device:usbPlugIn()
        end
        self.event_handlers["NotCharging"] = function()
            Device:usbPlugOut()
            self:sendEvent(Event:new("NotCharging"))
        end
        -- Emulate the stock reader refresh behavior...
        --[[
            NOTE: For ref, on a Touch (debugPaint is my new best friend):
                UI: gc16_fast
                Reader: When flash: if to/from img: gc16, else gc16_fast; when non-flash: auto (seems to prefer gl16_fast); Waiting for marker only on flash
            On a PW2:
                Same as Touch, except reader uses reagl on non-flash, non-flash lasts longer (12 pgs); Always waits for marker
        --]]
        -- We don't really have an easy way to know if we're refreshing the UI, or a page, or if said page contains an image, so go with the highest fidelity option
        self.full_refresh_waveform_mode = WAVEFORM_MODE_GC16
        -- We spend much more time in the reader than the UI, and our UI isn't very graphic anyway, so go with the reader behavior
        if Device:getModel() == "KindlePaperWhite2" then
            self.partial_refresh_waveform_mode = WAVEFORM_MODE_REAGL
        else
            self.partial_refresh_waveform_mode = WAVEFORM_MODE_GL16_FAST
            -- NOTE: Or we could go back to what KOReader did before fa55acc in koreader-base, which was also use WAVEFORM_MODE_AUTO ;). I have *no* idea how the driver makes its choice though...
            --self.partial_refresh_waveform_mode = WAVEFORM_MODE_AUTO
        end
    end
end

-- register & show a widget
function UIManager:show(widget, x, y)
    -- put widget on top of stack
    table.insert(self._window_stack, {x = x or 0, y = y or 0, widget = widget})
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

-- register a widget to be repainted
function UIManager:setDirty(widget, refresh_type)
    -- "auto": request full refresh
    -- "full": force full refresh
    -- "partial": partial refresh
    if not refresh_type then
        refresh_type = "auto"
    end
    self._dirty[widget] = refresh_type
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

-- signal to quit
function UIManager:quit()
    self._running = false
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
    return wait_until
end

-- this is the main loop of the UI controller
-- it is intended to manage input events and delegate
-- them to dialogs
function UIManager:run()
    self._running = true
    while self._running do
        local now = { util.gettime() }
        local wait_until = self:checkTasks()

        --DEBUG("---------------------------------------------------")
        --DEBUG("exec stack", self._execution_stack)
        --DEBUG("window stack", self._window_stack)
        --DEBUG("dirty stack", self._dirty)
        --DEBUG("---------------------------------------------------")

        -- stop when we have no window to show
        if #self._window_stack == 0 then
            DEBUG("no dialog left to show, would loop endlessly")
            self:quit()
            return nil
        end

        -- repaint dirty widgets
        local dirty = false
        local request_full_refresh = false
        local force_full_refresh = false
        local force_partial_refresh = false
        local force_fast_refresh = false
        for _, widget in ipairs(self._window_stack) do
            if self.repaint_all or self._dirty[widget.widget] then
                widget.widget:paintTo(Screen.bb,
                                      widget.x + UIManager:offsetX(),
                                      widget.y + UIManager:offsetY())
                if self._dirty[widget.widget] == "auto" then
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
        if dirty then
            if force_partial_refresh or force_fast_refresh then
                refresh_type = 0
            elseif force_full_refresh or self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
                refresh_type = 1
            end
            -- Handle the waveform mode selection...
            if refresh_type == 1 then
                waveform_mode = self.full_refresh_waveform_mode
            else
                waveform_mode = self.partial_refresh_waveform_mode
            end
            if force_fast_refresh then
                waveform_mode = self.fast_waveform_mode
            end
            if self.update_region_func then
                local update_region = self.update_region_func()
                -- in some rare cases update region has 1 pixel offset
                Screen:refresh(refresh_type, waveform_mode,
                               update_region.x-1, update_region.y-1,
                               update_region.w+2, update_region.h+2)
            else
                Screen:refresh(refresh_type, waveform_mode)
            end
            if self.refresh_type == 1 then
                self.refresh_count = 0
            elseif not force_partial_refresh and not force_full_refresh then
                self.refresh_count = (self.refresh_count + 1)%self.FULL_REFRESH_COUNT
            end
            self.update_region_func = nil
        end

        self:checkTasks()

        -- wait for next event
        -- note that we will skip that if in the meantime we have tasks that are ready to run
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
                -- no pending task, wait endlessly
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

UIManager:init()
return UIManager

