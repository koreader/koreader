local Device = require("device")
local Screen = Device.screen
local Input = require("device").input
local Event = require("ui/event")
local Geom = require("ui/geometry")
local util = require("ffi/util")
local DEBUG = require("dbg")
local _ = require("gettext")

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
        local kobo_light_on_start = tonumber(KOBO_LIGHT_ON_START)
        if kobo_light_on_start then
            local new_intensity
            local new_state
            if kobo_light_on_start > 0 then
                new_intensity = math.min(kobo_light_on_start, 100)
                new_state = true
            elseif kobo_light_on_start == 0 then
                new_state = false
            elseif kobo_light_on_start == -2 then
                local NickelConf = require("device/kobo/nickel_conf")
                new_intensity = NickelConf.frontLightLevel.get()
                new_state = NickelConf.frontLightState:get()
                if new_state == nil then
                    -- this device does not support frontlight toggle,
                    -- we set the state based on frontlight intensity.
                    if new_intensity > 0 then
                        new_state = true
                    else
                        new_state = false
                    end
                end
            end
            -- Since this kobo-specific, we save all values in settings here
            -- and let the code (reader.lua) pick it up later during bootstrap.
            if new_intensity then
                G_reader_settings:saveSetting("frontlight_intensity",
                                              new_intensity)
            end
            G_reader_settings:saveSetting("frontlight_state", new_state)
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
    DEBUG("show widget", widget._name)
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
    if widget.disable_double_tap then
        Input.disable_double_tap = true
    end
end

-- unregister a widget
-- for refreshtype & refreshregion see description of setDirty()
function UIManager:close(widget, refreshtype, refreshregion)
    if not widget then
        DEBUG("widget not exist to be closed")
        return
    end
    DEBUG("close widget", widget.id)
    -- TODO: Why do we the following?
    Input.disable_double_tap = DGESDETECT_DISABLE_DOUBLE_TAP
    local dirty = false
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == widget then
            -- tell the widget that it is closed now
            widget:handleEvent(Event:new("CloseWidget"))
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
                -- for fairness, it's better to make p+1 is strictly less than p
                -- might want to revisit here in the future
                break
            end
        until e < s
    end
    table.insert(self._task_queue, p, { time = time, action = action })
    self._task_queue_dirty = true
end

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
        local task = self._task_queue[i]
        if task.action == action then
            -- remove from table
            table.remove(self._task_queue, i)
        end
    end
end

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
            if DEBUG.is_on then
                -- when debugging, we check if we get handed a valid widget,
                -- which would be a dialog that was previously passed via show()
                local found = false
                for i = 1, #self._window_stack do
                    if self._window_stack[i].widget == widget then found = true end
                end
                if not found then
                    DEBUG("INFO: invalid widget for setDirty()", debug.traceback())
                end
            end
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
    DEBUG("quiting uimanager")
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

function UIManager:_checkTasks()
    local now = { util.gettime() }
    local now_us = now[1] * MILLION + now[2]
    local wait_until = nil

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

    self._task_queue_dirty = false
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
            DEBUG("promote refresh to full refresh")
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

    -- we should have at least one refresh if we did repaint.
    -- If we don't, we add one now and print a warning if we
    -- are debugging
    if dirty and #self._refresh_stack == 0 then
        DEBUG("WARNING: no refresh got enqueued. Will do a partial full screen refresh, which might be inefficient")
        self:_refresh("partial")
    end

    -- execute refreshes:
    for _, refresh in ipairs(self._refresh_stack) do
        DEBUG("triggering refresh", refresh)
        Screen[refresh_methods[refresh.mode]](Screen,
            refresh.region.x - 1, refresh.region.y - 1,
            refresh.region.w + 2, refresh.region.h + 2)
    end
    self._refresh_stack = {}
    self.refresh_counted = false
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
        --DEBUG("---------------------------------------------------")
        --DEBUG("exec stack", self._task_queue)
        --DEBUG("window stack", self._window_stack)
        --DEBUG("dirty stack", self._dirty)
        --DEBUG("---------------------------------------------------")

        -- stop when we have no window to show
        if #self._window_stack == 0 and not self._run_forever then
            DEBUG("no dialog left to show")
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
        local wait_for = { s = wait_until[1] - now[1], us = wait_until[2] - now[2] }
        if wait_for.us < 0 then
            wait_for.s = wait_for.s - 1
            wait_for.us = MILLION + wait_for.us
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

    if self.looper then
        DEBUG("handle input in turbo I/O looper")
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

UIManager:init()
return UIManager

