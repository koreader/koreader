--[[--
This module manages widgets.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local dbg = require("dbg")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local MILLION = 1000000

-- there is only one instance of this
local UIManager = {
    -- trigger a full refresh when counter reaches FULL_REFRESH_COUNT
    FULL_REFRESH_COUNT =
        G_reader_settings:readSetting("full_refresh_count") or DRCOUNTMAX,
    refresh_count = 0,

    -- How long to wait between ZMQ wakeups: 50ms.
    ZMQ_TIMEOUT = 50 * 1000,

    event_handlers = nil,

    _running = true,
    _window_stack = {},
    _task_queue = {},
    _task_queue_dirty = false,
    _dirty = {},
    _zeromqs = {},
    _refresh_stack = {},
    _refresh_func_stack = {},
    _entered_poweroff_stage = false,
    _exit_code = nil,

    event_hook = require("ui/hook_container"):new()
}

function UIManager:init()
    self.event_handlers = {
        __default__ = function(input_event)
            self:sendEvent(input_event)
        end,
        SaveState = function()
            self:flushSettings()
        end,
        Power = function(input_event)
            Device:onPowerEvent(input_event)
        end,
    }
    self.poweroff_action = function()
        self._entered_poweroff_stage = true;
        Screen:setRotationMode(0)
        require("ui/screensaver"):show("poweroff", _("Powered off"))
        Screen:refreshFull()
        UIManager:nextTick(function()
            Device:saveSettings()
            self:broadcastEvent(Event:new("Close"))
            Device:powerOff()
        end)
    end
    self.reboot_action = function()
        self._entered_poweroff_stage = true;
        Screen:setRotationMode(0)
        require("ui/screensaver"):show("reboot", _("Rebooting..."))
        Screen:refreshFull()
        UIManager:nextTick(function()
            Device:saveSettings()
            self:broadcastEvent(Event:new("Close"))
            Device:reboot()
        end)
    end
    if Device:isPocketBook() then
        self.event_handlers["Suspend"] = function()
            self:_beforeSuspend()
            Device:onPowerEvent("Power")
        end
        self.event_handlers["Resume"] = function()
            Device:onPowerEvent("Power")
            self:_afterResume()
        end
    end
    if Device:isKobo() then
        -- We do not want auto suspend procedure to waste battery during
        -- suspend. So let's unschedule it when suspending, and restart it after
        -- resume.
        self.event_handlers["Suspend"] = function()
            self:_beforeSuspend()
            Device:onPowerEvent("Suspend")
        end
        self.event_handlers["Resume"] = function()
            Device:onPowerEvent("Resume")
            self:_afterResume()
        end
        self.event_handlers["PowerPress"] = function()
            UIManager:scheduleIn(2, self.poweroff_action)
        end
        self.event_handlers["PowerRelease"] = function()
            if not self._entered_poweroff_stage then
                UIManager:unschedule(self.poweroff_action)
                self:suspend()
            end
        end
        if not G_reader_settings:readSetting("ignore_power_sleepcover") then
            self.event_handlers["SleepCoverClosed"] = function()
                Device.is_cover_closed = true
                self:suspend()
            end
            self.event_handlers["SleepCoverOpened"] = function()
                Device.is_cover_closed = false
                self:resume()
            end
        else
            -- Closing/opening the cover will still wake up the device, so we
            -- need to put it back to sleep if we are in screen saver mode
            self.event_handlers["SleepCoverClosed"] = function()
                if Device.screen_saver_mode then
                    self:suspend()
                end
            end
            self.event_handlers["SleepCoverOpened"] = self.event_handlers["SleepCoverClosed"]
        end
        self.event_handlers["Light"] = function()
            Device:getPowerDevice():toggleFrontlight()
        end
        self.event_handlers["Charging"] = function()
            self:_beforeCharging()
            if Device.screen_saver_mode then
                self:suspend()
            end
        end
        self.event_handlers["NotCharging"] = function()
            -- We need to put the device into suspension, other things need to be done before it.
            self:_afterNotCharging()
            if Device.screen_saver_mode then
                self:suspend()
            end
        end
        self.event_handlers["__default__"] = function(input_event)
            if Device.screen_saver_mode then
                -- Suspension in Kobo can be interrupted by screen updates. We
                -- ignore user touch input here so screen udpate won't be
                -- triggered in suspend mode
                self:suspend()
            else
                self:sendEvent(input_event)
            end
        end
    elseif Device:isKindle() then
        self.event_handlers["IntoSS"] = function()
            self:_beforeSuspend()
            Device:intoScreenSaver()
        end
        self.event_handlers["OutOfSS"] = function()
            Device:outofScreenSaver()
            self:_afterResume();
        end
        self.event_handlers["Charging"] = function()
            self:_beforeCharging()
            Device:usbPlugIn()
        end
        self.event_handlers["NotCharging"] = function()
            Device:usbPlugOut()
            self:_afterNotCharging()
        end
    elseif Device:isSDL() then
        self.event_handlers["Suspend"] = function()
            self:_beforeSuspend()
            Device:simulateSuspend()
        end
        self.event_handlers["Resume"] = function()
            Device:simulateResume()
            self:_afterResume()
        end
    end
end

--[[--
Registers and shows a widget.

Modal widget should be always on top.
For refreshtype & refreshregion see description of setDirty().
]]
---- @param widget a widget object
---- @param refreshtype "full", "partial", "ui", "fast"
---- @param refreshregion a Geom object
---- @int x
---- @int y
---- @see setDirty
function UIManager:show(widget, refreshtype, refreshregion, x, y)
    if not widget then
        logger.dbg("widget not exist to be shown")
        return
    end
    logger.dbg("show widget", widget.id or widget.name or "unknown")

    self._running = true
    local window = {x = x or 0, y = y or 0, widget = widget}
    -- put this window on top of the toppest non-modal window
    for i = #self._window_stack, 0, -1 do
        local top_window = self._window_stack[i]
        -- skip modal window
        if widget.modal or not top_window or not top_window.widget.modal then
            table.insert(self._window_stack, i + 1, window)
            break
        end
    end
    -- and schedule it to be painted
    self:setDirty(widget, refreshtype, refreshregion)
    -- tell the widget that it is shown now
    widget:handleEvent(Event:new("Show"))
    -- check if this widget disables double tap gesture
    if widget.disable_double_tap == false then
        Input.disable_double_tap = false
    else
        Input.disable_double_tap = true
    end
end

--[[--
Unregisters a widget.

For refreshtype & refreshregion see description of setDirty().
]]
---- @param widget a widget object
---- @param refreshtype "full", "partial", "ui", "fast"
---- @param refreshregion a Geom object
---- @see setDirty
function UIManager:close(widget, refreshtype, refreshregion)
    if not widget then
        logger.dbg("widget not exist to be closed")
        return
    end
    logger.dbg("close widget", widget.id or widget.name)
    local dirty = false
    -- Ensure all the widgets can get onFlushSettings event.
    widget:handleEvent(Event:new("FlushSettings"))
    -- first send close event to widget
    widget:handleEvent(Event:new("CloseWidget"))
    -- make it disabled by default and check any widget that enables it
    Input.disable_double_tap = true
    -- then remove all reference to that widget on stack and update
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == widget then
            table.remove(self._window_stack, i)
            dirty = true
        elseif self._window_stack[i].widget.disable_double_tap == false then
            Input.disable_double_tap = false
        end
    end
    if dirty and not widget.invisible then
        -- schedule remaining widgets to be painted
        for i = 1, #self._window_stack do
            self:setDirty(self._window_stack[i].widget)
        end
        self:_refresh(refreshtype, refreshregion)
    end
end

-- schedule an execution task, task queue is in ascendant order
function UIManager:schedule(time, action)
    local p, s, e = 1, 1, #self._task_queue
    if e ~= 0 then
        local us = time[1] * MILLION + time[2]
        -- do a binary insert
        repeat
            p = math.floor(s + (e - s) / 2)
            local ptime = self._task_queue[p].time
            local ptus = ptime[1] * MILLION + ptime[2]
            if us > ptus then
                if s == e then
                    p = e + 1
                    break
                elseif s + 1 == e then
                    s = e
                else
                    s = p
                end
            elseif us < ptus then
                e = p
                if s == e then
                    break
                end
            else
                -- for fairness, it's better to make p+1 is strictly less than
                -- p might want to revisit here in the future
                break
            end
        until e < s
    end
    table.insert(self._task_queue, p, { time = time, action = action })
    self._task_queue_dirty = true
end
dbg:guard(UIManager, 'schedule',
    function(self, time, action)
        assert(time[1] >= 0 and time[2] >= 0, "Only positive time allowed")
        assert(action ~= nil)
    end)

--- Schedules task in a certain amount of seconds (fractions allowed) from now.
function UIManager:scheduleIn(seconds, action)
    local when = { util.gettime() }
    local s = math.floor(seconds)
    local usecs = (seconds - s) * MILLION
    when[1] = when[1] + s
    when[2] = when[2] + usecs
    if when[2] >= MILLION then
        when[1] = when[1] + 1
        when[2] = when[2] - MILLION
    end
    self:schedule(when, action)
end
dbg:guard(UIManager, 'scheduleIn',
    function(self, seconds, action)
        assert(seconds >= 0, "Only positive seconds allowed")
    end)

function UIManager:nextTick(action)
    return self:scheduleIn(0, action)
end

--[[-- Unschedules an execution task.

In order to unschedule anonymous functions, store a reference.

@usage

self.anonymousFunction = function() self:regularFunction() end
UIManager:scheduleIn(10, self.anonymousFunction)
UIManager:unschedule(self.anonymousFunction)
]]
function UIManager:unschedule(action)
    for i = #self._task_queue, 1, -1 do
        if self._task_queue[i].action == action then
            table.remove(self._task_queue, i)
        end
    end
end
dbg:guard(UIManager, 'unschedule',
    function(self, action) assert(action ~= nil) end)

--[[--
Registers a widget to be repainted and enqueues a refresh.

the second parameter (refreshtype) can either specify a refreshtype
(optionally in combination with a refreshregion - which is suggested)
or a function that returns refreshtype AND refreshregion and is called
after painting the widget.

@usage

UIManager:setDirty(self.widget, "partial")
UIManager:setDirty(self.widget, "partial", Geom:new{x=10,y=10,w=100,h=50})
UIManager:setDirty(self.widget, function() return "ui", self.someelement.dimen end)

--]]
---- @param widget a widget object
---- @param refreshtype "full", "partial", "ui", "fast"
---- @param refreshregion a Geom object
function UIManager:setDirty(widget, refreshtype, refreshregion)
    if widget then
        if widget == "all" then
            -- special case: set all top-level widgets as being "dirty".
            for i = 1, #self._window_stack do
                self._dirty[self._window_stack[i].widget] = true
            end
        elseif not widget.invisible then
            self._dirty[widget] = true
        end
    end
    -- handle refresh information
    if type(refreshtype) == "function" then
        -- callback, will be issued after painting
        table.insert(self._refresh_func_stack, refreshtype)
    else
        -- otherwise, enqueue refresh
        self:_refresh(refreshtype, refreshregion)
    end
end
dbg:guard(UIManager, 'setDirty',
    nil,
    function(self, widget, refreshtype, refreshregion)
        if not widget or widget == "all" then return end
        -- when debugging, we check if we get handed a valid widget,
        -- which would be a dialog that was previously passed via show()
        local found = false
        for i = 1, #self._window_stack do
            if self._window_stack[i].widget == widget then found = true end
        end
        if not found then
            dbg:v("INFO: invalid widget for setDirty()", debug.traceback())
        end
    end)

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

--- Sets full refresh rate for e-ink screen.
--
-- Also makes the refresh rate persistent in global reader settings.
function UIManager:setRefreshRate(rate)
    logger.dbg("set screen full refresh rate", rate)
    self.FULL_REFRESH_COUNT = rate
    G_reader_settings:saveSetting("full_refresh_count", rate)
end

--- Gets full refresh rate for e-ink screen.
function UIManager:getRefreshRate(rate)
    return self.FULL_REFRESH_COUNT
end

--- Signals to quit.
function UIManager:quit()
    if not self._running then return end
    logger.info("quitting uimanager")
    self._task_queue_dirty = false
    self._running = false
    self._run_forever = nil
    for i = #self._window_stack, 1, -1 do
        table.remove(self._window_stack, i)
    end
    for i = #self._task_queue, 1, -1 do
        table.remove(self._task_queue, i)
    end
    for i = #self._zeromqs, 1, -1 do
        self._zeromqs[i]:stop()
        table.remove(self._zeromqs, i)
    end
    if self.looper then
        self.looper:close()
        self.looper = nil
    end
end

--- Transmits an event to an active widget.
function UIManager:sendEvent(event)
    if #self._window_stack == 0 then return end

    local top_widget = self._window_stack[#self._window_stack]
    -- top level widget has first access to the event
    if top_widget.widget:handleEvent(event) then
        return
    end
    if top_widget.widget.active_widgets then
        for _, active_widget in ipairs(top_widget.widget.active_widgets) do
            if active_widget:handleEvent(event) then return end
        end
    end

    -- if the event is not consumed, active widgets (from top to bottom) can
    -- access it. NOTE: _window_stack can shrink on close event
    local checked_widgets = {top_widget}
    for i = #self._window_stack, 1, -1 do
        local widget = self._window_stack[i]
        if checked_widgets[widget] == nil then
            -- active widgets has precedence to handle this event
            -- Note: ReaderUI currently only has one active_widget: readerscreenshot
            if widget.widget.active_widgets then
                checked_widgets[widget] = true
                for _, active_widget in ipairs(widget.widget.active_widgets) do
                    if active_widget:handleEvent(event) then return end
                end
            end
            if widget.widget.is_always_active then
                -- active widgets will handle this event
                -- Note: is_always_active widgets currently are vitualkeyboard and
                -- readerconfig
                checked_widgets[widget] = true
                if widget.widget:handleEvent(event) then return end
            end
        end
    end
end

--- Transmits an event to all registered widgets.
function UIManager:broadcastEvent(event)
    -- the widget's event handler might close widgets in which case
    -- a simple iterator like ipairs would skip over some entries
    local i = 1
    while i <= #self._window_stack do
        local prev_widget = self._window_stack[i].widget
        self._window_stack[i].widget:handleEvent(event)
        local top_widget = self._window_stack[i]
        if top_widget == nil then
            -- top widget closed itself
            break
        elseif top_widget.widget == prev_widget then
            i = i + 1
        end
    end
end

function UIManager:_checkTasks()
    local now = { util.gettime() }
    local now_us = now[1] * MILLION + now[2]
    local wait_until = nil

    -- task.action may schedule other events
    self._task_queue_dirty = false
    while true do
        local nu_task = #self._task_queue
        if nu_task == 0 then
            -- all tasks checked
            break
        end
        local task = self._task_queue[1]
        local task_us = 0
        if task.time ~= nil then
            task_us = task.time[1] * MILLION + task.time[2]
        end
        if task_us <= now_us then
            -- remove from table
            table.remove(self._task_queue, 1)
            -- task is pending to be executed right now. do it.
            -- NOTE: be careful that task.action() might modify
            -- _task_queue here. So need to avoid race condition
            task.action()
        else
            -- queue is sorted in ascendant order, safe to assume all items
            -- are future tasks for now
            wait_until = task.time
            break
        end
    end

    return wait_until, now
end

-- precedence of refresh modes:
local refresh_modes = { fast = 1, ui = 2, partial = 3, full = 4 }
-- refresh methods in framebuffer implementation
local refresh_methods = {
    fast = "refreshFast",
    ui = "refreshUI",
    partial = "refreshPartial",
    full = "refreshFull",
}

--[[
Compares refresh mode.

Will return the mode that takes precedence.
--]]
local function update_mode(mode1, mode2)
    if refresh_modes[mode1] > refresh_modes[mode2] then
        return mode1
    else
        return mode2
    end
end

--[[--
Enqueues a refresh.

Widgets call this in their paintTo() method in order to notify
UIManager that a certain part of the screen is to be refreshed.

@param mode
    refresh mode ("full", "partial", "ui", "fast")
@param region
    Rect() that specifies the region to be updated
    optional, update will affect whole screen if not specified.
    Note that this should be the exception.
--]]
function UIManager:_refresh(mode, region)
    if not mode then return end
    if not region and mode == "full" then
        self.refresh_count = 0 -- reset counter on explicit full refresh
    end
    -- special case: full screen partial update
    -- will get promoted every self.FULL_REFRESH_COUNT updates
    -- since _refresh can be called mutiple times via setDirty called in
    -- different widget before a real screen repaint, we should make sure
    -- refresh_count is incremented by only once at most for each repaint
    if not region and mode == "partial" and not self.refresh_counted then
        self.refresh_count = (self.refresh_count + 1) % self.FULL_REFRESH_COUNT
        if self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
            logger.dbg("promote refresh to full refresh")
            mode = "full"
        end
        self.refresh_counted = true
    end

    -- if no region is specified, define default region
    region = region or Geom:new{w=Screen:getWidth(), h=Screen:getHeight()}

    for i = 1, #self._refresh_stack do
        -- check for collision with updates that are already enqueued
        if region:intersectWith(self._refresh_stack[i].region) then
            -- combine both refreshes' regions
            local combined = region:combine(self._refresh_stack[i].region)
            -- update the mode, if needed
            mode = update_mode(mode, self._refresh_stack[i].mode)
            -- remove colliding update
            table.remove(self._refresh_stack, i)
            -- and try again with combined data
            return self:_refresh(mode, combined)
        end
    end
    -- if we hit no (more) collides, enqueue the update
    table.insert(self._refresh_stack, {mode = mode, region = region})
end

--- Repaints dirty widgets.
function UIManager:_repaint()
    -- flag in which we will record if we did any repaints at all
    -- will trigger a refresh if set.
    local dirty = false

    for _, widget in ipairs(self._window_stack) do
        -- paint if current widget or any widget underneath is dirty
        if dirty or self._dirty[widget.widget] then
            -- pass hint to widget that we got when setting widget dirty
            -- the widget can use this to decide which parts should be refreshed
            widget.widget:paintTo(Screen.bb, widget.x, widget.y, self._dirty[widget.widget])

            -- and remove from list after painting
            self._dirty[widget.widget] = nil

            -- trigger repaint
            dirty = true
        end
    end

    -- execute pending refresh functions
    for _, refreshfunc in ipairs(self._refresh_func_stack) do
        local refreshtype, region = refreshfunc()
        if refreshtype then self:_refresh(refreshtype, region) end
    end
    self._refresh_func_stack = {}

    -- we should have at least one refresh if we did repaint.  If we don't, we
    -- add one now and log a warning if we are debugging
    if dirty and #self._refresh_stack == 0 then
        logger.dbg("no refresh got enqueued. Will do a partial full screen refresh, which might be inefficient")
        self:_refresh("partial")
    end

    -- execute refreshes:
    for _, refresh in ipairs(self._refresh_stack) do
        dbg:v("triggering refresh", refresh)
        Screen[refresh_methods[refresh.mode]](Screen,
            refresh.region.x - 1, refresh.region.y - 1,
            refresh.region.w + 2, refresh.region.h + 2)
    end
    self._refresh_stack = {}
    self.refresh_counted = false
end

function UIManager:forceRePaint()
    self:_repaint()
end

function UIManager:setInputTimeout(timeout)
    self.INPUT_TIMEOUT = timeout or 200*1000
end

function UIManager:resetInputTimeout()
    self.INPUT_TIMEOUT = nil
end

function UIManager:handleInputEvent(input_event)
    if input_event.handler ~= "onInputError" then
        self.event_hook:execute("InputEvent", input_event)
    end
    local handler = self.event_handlers[input_event]
    if handler then
        handler(input_event)
    else
        self.event_handlers["__default__"](input_event)
    end
end

-- Process all pending events on all registered ZMQs.
function UIManager:processZMQs()
    for _, zeromq in ipairs(self._zeromqs) do
        for input_event in zeromq.waitEvent,zeromq do
            self:handleInputEvent(input_event)
        end
    end
end

function UIManager:handleInput()
    local wait_until, now
    -- run this in a loop, so that paints can trigger events
    -- that will be honored when calculating the time to wait
    -- for input events:
    repeat
        wait_until, now = self:_checkTasks()
        --dbg("---------------------------------------------------")
        --dbg("exec stack", self._task_queue)
        --dbg("window stack", self._window_stack)
        --dbg("dirty stack", self._dirty)
        --dbg("---------------------------------------------------")

        -- stop when we have no window to show
        if #self._window_stack == 0 and not self._run_forever then
            logger.info("no dialog left to show")
            self:quit()
            return nil
        end

        self:_repaint()
    until not self._task_queue_dirty

    -- run ZMQs if any
    self:processZMQs()

    -- Figure out how long to wait.
    -- Default to INPUT_TIMEOUT (which may be nil, i.e. block until an event happens).
    local wait_us = self.INPUT_TIMEOUT

    -- If there's a timed event pending, that puts an upper bound on how long to wait.
    if wait_until then
        wait_us = math.min(
            wait_us or math.huge,
            (wait_until[1] - now[1]) * MILLION
            + (wait_until[2] - now[2]))
    end

    -- If we have any ZMQs registered, ZMQ_TIMEOUT is another upper bound.
    if #self._zeromqs > 0 then
        wait_us = math.min(wait_us or math.huge, self.ZMQ_TIMEOUT)
    end

    -- wait for next event
    local input_event = Input:waitEvent(wait_us)

    -- delegate input_event to handler
    if input_event then
        self:handleInputEvent(input_event)
    end

    if self.looper then
        logger.info("handle input in turbo I/O looper")
        self.looper:add_callback(function()
            -- FIXME: force close looper when there is unhandled error,
            -- otherwise the looper will hang. Any better solution?
            xpcall(function() self:handleInput() end, function(err)
                io.stderr:write(err .. "\n")
                io.stderr:write(debug.traceback() .. "\n")
                io.stderr:flush()
                self.looper:close()
                os.exit(1)
            end)
        end)
    end
end


function UIManager:onRotation()
    self:setDirty('all', 'full')
    self:forceRePaint()
end

function UIManager:initLooper()
    if DUSE_TURBO_LIB and not self.looper then
        TURBO_SSL = true -- luacheck: ignore
        __TURBO_USE_LUASOCKET__ = true -- luacheck: ignore
        local turbo = require("turbo")
        self.looper = turbo.ioloop.instance()
    end
end

-- this is the main loop of the UI controller
-- it is intended to manage input events and delegate
-- them to dialogs
function UIManager:run()
    self._running = true
    self:initLooper()
    -- currently there is no Turbo support for Windows
    -- use our own main loop
    if not self.looper then
        while self._running do
            self:handleInput()
        end
    else
        self.looper:add_callback(function() self:handleInput() end)
        self.looper:start()
    end

    return self._exit_code
end

-- run uimanager forever for testing purpose
function UIManager:runForever()
    self._run_forever = true
    return self:run()
end

-- The common operations should be performed before suspending the device. Ditto.
function UIManager:_beforeSuspend()
    self:flushSettings()
    self:broadcastEvent(Event:new("Suspend"))
end

-- The common operations should be performed after resuming the device. Ditto.
function UIManager:_afterResume()
    self:broadcastEvent(Event:new("Resume"))
end

function UIManager:_beforeCharging()
    self:broadcastEvent(Event:new("Charging"))
end

function UIManager:_afterNotCharging()
    self:broadcastEvent(Event:new("NotCharging"))
end

-- Executes all the operations of a suspending request. This function usually puts the device into
-- suspension.
function UIManager:suspend()
    if Device:isKobo() or Device:isSDL() then
        self.event_handlers["Suspend"]()
    elseif Device:isKindle() then
        self.event_handlers["IntoSS"]()
    end
end

-- Executes all the operations of a resume request. This function usually wakes up the device.
function UIManager:resume()
    if Device:isKobo() or Device:isSDL() then
        self.event_handlers["Resume"]()
    elseif Device:isKindle() then
        self.event_handlers["OutOfSS"]()
    end
end

function UIManager:flushSettings()
    self:broadcastEvent(Event:new("FlushSettings"))
end

function UIManager:restartKOReader()
    self:quit()
    -- This is just a magic number to indicate the restart request for shell scripts.
    self._exit_code = 85
end

UIManager:init()
return UIManager
