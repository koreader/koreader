local Device = require("device")
local Screen = Device.screen
local Input = require("device").input
local Event = require("ui/event")
local util = require("ffi/util")
local DEBUG = require("dbg")
local _ = require("gettext")

-- there is only one instance of this
local UIManager = {
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
    -- TODO: Why do we the following?
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
    -- flag in which we will record if we did any repaints at all
    -- will trigger a refresh if set.
    local dirty = false

    -- we use this to record requests for certain refresh types
    -- TODO: fix this, see below
    local force_full_refresh = self.full_refresh
    self.full_refresh = false

    local force_partial_refresh = self.partial_refresh
    self.partial_refresh = false

    local force_fast_refresh = false

    for _, widget in ipairs(self._window_stack) do
        -- paint if repaint_all is request
        -- paint also if current widget or any widget underneath is dirty
        if self.repaint_all or dirty or self._dirty[widget.widget] then
            widget.widget:paintTo(Screen.bb, widget.x, widget.y)

            -- self._dirty[widget.widget] may also be "auto"
            if self._dirty[widget.widget] == "full" then
                force_full_refresh = true
            elseif self._dirty[widget.widget] == "partial" then
                force_partial_refresh = true
            elseif self._dirty[widget.widget] == "fast" then
                force_fast_refresh = true
            end

            -- and remove from list after painting
            self._dirty[widget.widget] = nil

            -- trigger repaint
            dirty = true
        end
    end
    self.repaint_all = false

    if dirty then
        -- select proper refresh mode
        -- TODO: fix this. We should probably do separate refreshes
        -- by regional refreshes (e.g. fast refresh, some partial refreshes)
        -- and full-screen full refresh
        local refresh

        if force_fast_refresh then
            refresh = Screen.refreshFast
        elseif force_partial_refresh then
            refresh = Screen.refreshPartial
        elseif force_full_refresh or self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
            refresh = Screen.refreshFull
            -- a full refresh will reset the counter which leads to an automatic full refresh
            self.refresh_count = 0
        else
            -- default
            refresh = Screen.refreshPartial
            -- increment refresh counter in this case
            self.refresh_count = (self.refresh_count + 1) % self.FULL_REFRESH_COUNT
        end

        if self.update_regions_func then
            local update_regions = self.update_regions_func()
            for _, update_region in ipairs(update_regions) do
                -- in some rare cases update region has 1 pixel offset
                refresh(Screen, refresh_type, waveform_mode, wait_for_marker,
                               update_region.x-1, update_region.y-1,
                               update_region.w+2, update_region.h+2)
            end
        else
            refresh(Screen, refresh_type, waveform_mode, wait_for_marker)
        end
    end
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

