local Device = require("device")
local Screen = Device.screen
local Input = require("device").input
local Event = require("ui/event")
local Geom = require("ui/geometry")
local util = require("ffi/util")
local dbg = require("dbg")
local _ = require("gettext")

local noop = function() end
local MILLION = 1000000

-- there is only one instance of this
local UIManager = {
    -- trigger a full refresh when counter reaches FULL_REFRESH_COUNT
    FULL_REFRESH_COUNT =
        G_reader_settings:readSetting("full_refresh_count") or DRCOUNTMAX,
    refresh_count = 0,

    event_handlers = nil,

    _running = true,
    _window_stack = {},
    _task_queue = {},
    _task_queue_dirty = false,
    _dirty = {},
    _zeromqs = {},
    _refresh_stack = {},
    _refresh_func_stack = {},
    _power_ev_handled = false,
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
        -- We do not want auto suspend procedure to waste battery during
        -- suspend. So let's unschedule it when suspending, and restart it after
        -- resume.
        self:_initAutoSuspend()
        self.event_handlers["Suspend"] = function()
            self:_stopAutoSuspend()
            Device:onPowerEvent("Suspend")
        end
        self.event_handlers["Resume"] = function()
            Device:onPowerEvent("Resume")
            self:sendEvent(Event:new("Resume"))
            self:_startAutoSuspend()
        end
        self.event_handlers["PowerPress"] = function()
            self._power_ev_handled = false
            local showPowerOffDialog = function()
                if self._power_ev_handled then return end
                self._power_ev_handled = true
                local ConfirmBox = require("ui/widget/confirmbox")
                UIManager:show(ConfirmBox:new{
                    text = _("Power off?"),
                    ok_callback = function()
                        local InfoMessage = require("ui/widget/infomessage")

                        UIManager:show(InfoMessage:new{
                            text = _("Powered off."),
                        })
                        -- The message can fail to render if this is executed directly
                        UIManager:scheduleIn(0.1, function()
                            self:broadcastEvent(Event:new("Close"))
                            Device:powerOff()
                        end)
                    end,
                })
            end
            UIManager:scheduleIn(3, showPowerOffDialog)
        end
        self.event_handlers["PowerRelease"] = function()
            if not self._power_ev_handled then
              self._power_ev_handled = true
              self.event_handlers["Suspend"]()
            end
        end
        if not G_reader_settings:readSetting("ignore_power_sleepcover") then
            self.event_handlers["SleepCoverClosed"] = function()
                Device.is_cover_closed = true
                self.event_handlers["Suspend"]()
            end
            self.event_handlers["SleepCoverOpened"] = function()
                Device.is_cover_closed = false
                self.event_handlers["Resume"]()
            end
        else
            -- Closing/opening the cover will still wake up the device, so we
            -- need to put it back to sleep if we are in screen saver mode
            self.event_handlers["SleepCoverClosed"] = function()
                if Device.screen_saver_mode then
                    self.event_handlers["Suspend"]()
                end
            end
            self.event_handlers["SleepCoverOpened"] = self.event_handlers["SleepCoverClosed"]
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
    elseif Device:isKindle() then
        self.event_handlers["IntoSS"] = function()
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
    end
end

-- register & show a widget
-- modal widget should be always on the top
-- for refreshtype & refreshregion see description of setDirty()
function UIManager:show(widget, refreshtype, refreshregion, x, y)
    if not widget then
        dbg("widget not exist to be closed")
        return
    end
    dbg("show widget", widget.id or widget.name or "unknown")

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

-- unregister a widget
-- for refreshtype & refreshregion see description of setDirty()
function UIManager:close(widget, refreshtype, refreshregion)
    if not widget then
        dbg("widget not exist to be closed")
        return
    end
    dbg("close widget", widget.id or widget.name)
    local dirty = false
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
    if dirty then
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

-- schedule task in a certain amount of seconds (fractions allowed) from now
function UIManager:scheduleIn(seconds, action)
    local when = { util.gettime() }
    local s = math.floor(seconds)
    local usecs = (seconds - s) * MILLION
    when[1] = when[1] + s
    when[2] = when[2] + usecs
    if when[2] > MILLION then
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

-- unschedule an execution task
-- in order to unschedule anonymous functions, store a reference
-- for example:
-- self.anonymousFunction = function() self:regularFunction() end
-- UIManager:scheduleIn(10, self.anonymousFunction)
-- UIManager:unschedule(self.anonymousFunction)
function UIManager:unschedule(action)
    for i = #self._task_queue, 1, -1 do
        if self._task_queue[i].action == action then
            table.remove(self._task_queue, i)
        end
    end
end
dbg:guard(UIManager, 'unschedule',
    function(self, action) assert(action ~= nil) end)

--[[
register a widget to be repainted and enqueue a refresh

the second parameter (refreshtype) can either specify a refreshtype
(optionally in combination with a refreshregion - which is suggested)
or a function that returns refreshtype AND refreshregion and is called
after painting the widget.

E.g.:
UIManager:setDirty(self.widget, "partial")
UIManager:setDirty(self.widget, "partial", Geom:new{x=10,y=10,w=100,h=50})
UIManager:setDirty(self.widget, function() return "ui", self.someelement.dimen end)
--]]
function UIManager:setDirty(widget, refreshtype, refreshregion)
    if widget then
        if widget == "all" then
            -- special case: set all top-level widgets as being "dirty".
            for i = 1, #self._window_stack do
                self._dirty[self._window_stack[i].widget] = true
            end
        else
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

-- set full refresh rate for e-ink screen
-- and make the refresh rate persistant in global reader settings
function UIManager:setRefreshRate(rate)
    dbg("set screen full refresh rate", rate)
    self.FULL_REFRESH_COUNT = rate
    G_reader_settings:saveSetting("full_refresh_count", rate)
end

-- get full refresh rate for e-ink screen
function UIManager:getRefreshRate(rate)
    return self.FULL_REFRESH_COUNT
end

-- signal to quit
function UIManager:quit()
    dbg("quiting uimanager")
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

-- transmit an event to an active widget
function UIManager:sendEvent(event)
    --dbg:v("send event", event)
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

-- transmit an event to all registered widgets
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
refresh mode comparision

will return the mode that takes precedence
--]]
local function update_mode(mode1, mode2)
    if refresh_modes[mode1] > refresh_modes[mode2] then
        return mode1
    else
        return mode2
    end
end

--[[
enqueue a refresh

Widgets call this in their paintTo() method in order to notify
UIManager that a certain part of the screen is to be refreshed.

mode:   refresh mode ("full", "partial", "ui", "fast")
region: Rect() that specifies the region to be updated
        optional, update will affect whole screen if not specified.
        Note that this should be the exception.
--]]
function UIManager:_refresh(mode, region)
    if not mode then return end
    -- special case: full screen partial update
    -- will get promoted every self.FULL_REFRESH_COUNT updates
    -- since _refresh can be called mutiple times via setDirty called in
    -- different widget before a real screen repaint, we should make sure
    -- refresh_count is incremented by only once at most for each repaint
    if not region and mode == "partial" and not self.refresh_counted then
        self.refresh_count = (self.refresh_count + 1) % self.FULL_REFRESH_COUNT
        if self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
            dbg("promote refresh to full refresh")
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

-- repaint dirty widgets
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
        dbg("WARNING: no refresh got enqueued. Will do a partial full screen refresh, which might be inefficient")
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
            dbg("no dialog left to show")
            self:quit()
            return nil
        end

        self:_repaint()
    until not self._task_queue_dirty

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
            input_event = Input:waitEvent(self.INPUT_TIMEOUT)
        end
    elseif wait_until[1] > now[1]
    or wait_until[1] == now[1] and wait_until[2] > now[2] then
        -- wait until next task is pending
        local wait_us = (wait_until[1] - now[1]) * MILLION
                        + (wait_until[2] - now[2])
        input_event = Input:waitEvent(wait_us)
    end

    -- delegate input_event to handler
    if input_event then
        self:_resetAutoSuspendTimer()
        local handler = self.event_handlers[input_event]
        if handler then
            handler(input_event)
        else
            self.event_handlers["__default__"](input_event)
        end
    end

    if self.looper then
        dbg("handle input in turbo I/O looper")
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
end

-- run uimanager forever for testing purpose
function UIManager:runForever()
    self._run_forever = true
    self:run()
end

-- Kobo does not have an auto suspend function, so we implement it ourselves.
function UIManager:_initAutoSuspend()
    local function isAutoSuspendEnabled()
        return Device:isKobo() and self.auto_suspend_sec > 0
    end

    local sec = G_reader_settings:readSetting("auto_suspend_timeout_seconds")
    if sec then
        self.auto_suspend_sec = sec
    else
        -- default setting is 60 minutes
        self.auto_suspend_sec = 60 * 60
    end

    if isAutoSuspendEnabled() then
        self.auto_suspend_action = function()
            local now = util.gettime()
            -- Do not repeat auto suspend procedure after suspend.
            if self.last_action_sec + self.auto_suspend_sec <= now then
                Device:onPowerEvent("Suspend")
            else
                self:scheduleIn(
                    self.last_action_sec + self.auto_suspend_sec - now,
                    self.auto_suspend_action)
            end
        end

        function UIManager:_startAutoSuspend()
            self.last_action_sec = util.gettime()
            self:nextTick(self.auto_suspend_action)
        end
        dbg:guard(UIManager, '_startAutoSuspend',
            function()
                assert(isAutoSuspendEnabled())
            end)

        function UIManager:_stopAutoSuspend()
            self:unschedule(self.auto_suspend_action)
        end

        function UIManager:_resetAutoSuspendTimer()
            self.last_action_sec = util.gettime()
        end

        self:_startAutoSuspend()
    else
        self._startAutoSuspend = noop
        self._stopAutoSuspend = noop
    end
end

UIManager._resetAutoSuspendTimer = noop

UIManager:init()
return UIManager
