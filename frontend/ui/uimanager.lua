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

local WAVEFORM_MODE_INIT            = 0x0    -- Screen goes to white (clears)
local WAVEFORM_MODE_DU            = 0x1    -- Grey->white/grey->black
local WAVEFORM_MODE_GC16            = 0x2    -- High fidelity (flashing)
local WAVEFORM_MODE_GC4            = WAVEFORM_MODE_GC16 -- For compatibility
local WAVEFORM_MODE_GC16_FAST        = 0x3    -- Medium fidelity
local WAVEFORM_MODE_A2            = 0x4    -- Faster but even lower fidelity
local WAVEFORM_MODE_GL16            = 0x5    -- High fidelity from white transition
local WAVEFORM_MODE_GL16_FAST        = 0x6    -- Medium fidelity from white transition
local WAVEFORM_MODE_AUTO            = 0x101

-- there is only one instance of this
local UIManager = {
    default_refresh_type = 0, -- 0 for partial refresh, 1 for full refresh
    default_waveform_mode = WAVEFORM_MODE_GC16, -- high fidelity waveform
    fast_waveform_mode = WAVEFORM_MODE_A2,
    -- force to repaint all the widget is stack, will be reset to false
    -- after each ui loop
    repaint_all = false,
    -- force to do full refresh, will be reset to false
    -- after each ui loop
    full_refresh = false,
    -- force to do patial refresh, will be reset to false
    -- after each ui loop
    patial_refresh = false,
    -- trigger a full refresh when counter reaches FULL_REFRESH_COUNT
    FULL_REFRESH_COUNT = DRCOUNTMAX,
    refresh_count = 0,

    _running = true,
    _window_stack = {},
    _execution_stack = {},
    _dirty = {}
}

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

-- signal to quit
function UIManager:quit()
    self._running = false
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
            return nil
        end

        -- repaint dirty widgets
        local dirty = false
        local request_full_refresh = false
        local force_full_refresh = false
        local force_patial_refresh = false
        local force_fast_refresh = false
        for _, widget in ipairs(self._window_stack) do
            if self.repaint_all or self._dirty[widget.widget] then
                widget.widget:paintTo(Screen.bb, widget.x, widget.y)
                if self._dirty[widget.widget] == "auto" then
                    request_full_refresh = true
                end
                if self._dirty[widget.widget] == "full" then
                    force_full_refresh = true
                end
                if self._dirty[widget.widget] == "partial" then
                    force_patial_refresh = true
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

        if self.patial_refresh then
            dirty = true
            force_patial_refresh = true
        end

        self.repaint_all = false
        self.full_refresh = false
        self.patial_refresh = false

        local refresh_type = self.default_refresh_type
        local waveform_mode = self.default_waveform_mode
        if dirty then
            if force_patial_refresh or force_fast_refresh then
                refresh_type = 0
            elseif force_full_refresh or self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
                refresh_type = 1
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
            elseif not force_patial_refresh and not force_full_refresh then
                self.refresh_count = (self.refresh_count + 1)%self.FULL_REFRESH_COUNT
            end
            self.update_region_func = nil
        end

        self:checkTasks()

        -- wait for next event
        -- note that we will skip that if in the meantime we have tasks that are ready to run
        local input_event = nil
        if not wait_until then
            -- no pending task, wait endlessly
            input_event = Input:waitEvent()
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
            --DEBUG("in ui.lua:", input_event)
            if input_event == "IntoSS" then
                Device:intoScreenSaver()
            elseif input_event == "OutOfSS" then
                Device:outofScreenSaver()
            elseif input_event == "Charging" then
                Device:usbPlugIn()
            elseif input_event == "NotCharging" then
                Device:usbPlugOut()
                self:sendEvent(Event:new("NotCharging"))
            elseif input_event == "Light" then
                Device:getPowerDevice():toggleFrontlight()
            elseif (input_event == "Power" and not Device.screen_saver_mode)
                    or input_event == "Suspend" then
                local InfoMessage = require("ui/widget/infomessage")
                self:show(InfoMessage:new{
                    text = _("Standby"),
                    timeout = 1,
                })
                Device:prepareSuspend()
                self:scheduleIn(0.5, function() Device:Suspend() end)
            elseif (input_event == "Power" and Device.screen_saver_mode)
                    or input_event == "Resume" then
                Device:Resume()
                self:sendEvent(Event:new("Resume"))
            else
                self:sendEvent(input_event)
            end
        end
    end
end

return UIManager
