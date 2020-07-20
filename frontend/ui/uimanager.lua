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
local DEFAULT_FULL_REFRESH_COUNT = 6

-- there is only one instance of this
local UIManager = {
    -- trigger a full refresh when counter reaches FULL_REFRESH_COUNT
    FULL_REFRESH_COUNT =
        G_reader_settings:isTrue("night_mode") and G_reader_settings:readSetting("night_full_refresh_count") or G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT,
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
        Screen:setRotationMode(Screen.ORIENTATION_PORTRAIT)
        require("ui/screensaver"):show("poweroff", _("Powered off"))
        if Device:needsScreenRefreshAfterResume() then
            Screen:refreshFull()
        end
        UIManager:nextTick(function()
            Device:saveSettings()
            self:broadcastEvent(Event:new("Close"))
            Device:powerOff()
        end)
    end
    self.reboot_action = function()
        self._entered_poweroff_stage = true;
        Screen:setRotationMode(Screen.ORIENTATION_PORTRAIT)
        require("ui/screensaver"):show("reboot", _("Rebooting…"))
        if Device:needsScreenRefreshAfterResume() then
            Screen:refreshFull()
        end
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
        -- resume. Done via the plugin's onSuspend/onResume handlers.
        self.event_handlers["Suspend"] = function()
            -- Ignore the accelerometer (if that's not already the case) while we're alseep
            if G_reader_settings:nilOrFalse("input_ignore_gsensor") then
                Device:toggleGSensor(false)
            end
            self:_beforeSuspend()
            Device:onPowerEvent("Suspend")
        end
        self.event_handlers["Resume"] = function()
            Device:onPowerEvent("Resume")
            self:_afterResume()
            -- Stop ignoring the accelerometer (unless requested) when we wakeup
            if G_reader_settings:nilOrFalse("input_ignore_gsensor") then
                Device:toggleGSensor(true)
            end
        end
        self.event_handlers["PowerPress"] = function()
            -- Always schedule power off.
            -- Press the power button for 2+ seconds to shutdown directly from suspend.
            UIManager:scheduleIn(2, self.poweroff_action)
        end
        self.event_handlers["PowerRelease"] = function()
            if not self._entered_poweroff_stage then
                UIManager:unschedule(self.poweroff_action)
                -- resume if we were suspended
                if Device.screen_saver_mode then
                    self:resume()
                else
                    self:suspend()
                end
            end
        end
        -- Sleep Cover handling
        if G_reader_settings:readSetting("ignore_power_sleepcover") then
            -- NOTE: The hardware event itself will wake the kernel up if it's in suspend (:/).
            --       Let the unexpected wakeup guard handle that.
            self.event_handlers["SleepCoverClosed"] = nil
            self.event_handlers["SleepCoverOpened"] = nil
        elseif G_reader_settings:readSetting("ignore_open_sleepcover") then
            -- Just ignore wakeup events, and do NOT set is_cover_closed,
            -- so device/generic/device will let us use the power button to wake ;).
            self.event_handlers["SleepCoverClosed"] = function()
                self:suspend()
            end
            self.event_handlers["SleepCoverOpened"] = function()
                Device.is_cover_closed = false
            end
        else
            self.event_handlers["SleepCoverClosed"] = function()
                Device.is_cover_closed = true
                self:suspend()
            end
            self.event_handlers["SleepCoverOpened"] = function()
                Device.is_cover_closed = false
                self:resume()
            end
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
            -- Suspension in Kobo can be interrupted by screen updates. We ignore user touch input
            -- in screen_saver_mode so screen updates won't be triggered in suspend mode.
            -- We should not call self:suspend() in screen_saver_mode lest we stay on forever
            -- trying to reschedule suspend. Other systems take care of unintended wake-up.
            if not Device.screen_saver_mode then
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
    elseif Device:isRemarkable() then
        self.event_handlers["PowerPress"] = function()
            UIManager:scheduleIn(2, self.poweroff_action)
        end
        self.event_handlers["PowerRelease"] = function()
            if not self._entered_poweroff_stage then
                UIManager:unschedule(self.poweroff_action)
                -- resume if we were suspended
                if Device.screen_saver_mode then
                    self:resume()
                else
                    self:suspend()
                end
            end
        end
        self.event_handlers["Suspend"] = function()
            self:_beforeSuspend()
            Device:intoScreenSaver()
            Device:suspend()
        end
        self.event_handlers["Resume"] = function()
            Device:resume()
            Device:outofScreenSaver()
            self:_afterResume()
        end
        self.event_handlers["__default__"] = function(input_event)
            -- Same as in Kobo: we want to ignore keys during suspension
            if not Device.screen_saver_mode then
                self:sendEvent(input_event)
            end
        end
    elseif Device:isSonyPRSTUX() then
        self.event_handlers["PowerPress"] = function()
            UIManager:scheduleIn(2, self.poweroff_action)
        end
        self.event_handlers["PowerRelease"] = function()
            if not self._entered_poweroff_stage then
                UIManager:unschedule(self.poweroff_action)
                -- resume if we were suspended
                if Device.screen_saver_mode then
                    self:resume()
                else
                    self:suspend()
                end
            end
        end
        self.event_handlers["Suspend"] = function()
            self:_beforeSuspend()
            Device:intoScreenSaver()
            Device:suspend()
        end
        self.event_handlers["Resume"] = function()
            Device:resume()
            Device:outofScreenSaver()
            self:_afterResume()
        end
        self.event_handlers["Charging"] = function()
            self:_beforeCharging()
        end
        self.event_handlers["NotCharging"] = function()
            self:_afterNotCharging()
        end
        self.event_handlers["UsbPlugIn"] = function()
            if Device.screen_saver_mode then
                Device:resume()
                Device:outofScreenSaver()
                self:_afterResume()
            end
            Device:usbPlugIn()
        end
        self.event_handlers["UsbPlugOut"] = function()
            Device:usbPlugOut()
        end
        self.event_handlers["__default__"] = function(input_event)
            -- Same as in Kobo: we want to ignore keys during suspension
            if not Device.screen_saver_mode then
                self:sendEvent(input_event)
            end
        end
    elseif Device:isCervantes() then
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
                -- resume if we were suspended
                if Device.screen_saver_mode then
                    self:resume()
                else
                    self:suspend()
                end
            end
        end
        self.event_handlers["Charging"] = function()
            self:_beforeCharging()
            if Device.screen_saver_mode then
                self:suspend()
            end
        end
        self.event_handlers["NotCharging"] = function()
            self:_afterNotCharging()
            if Device.screen_saver_mode then
                self:suspend()
            end
        end
        self.event_handlers["UsbPlugIn"] = function()
            self:_beforeCharging()
            if Device.screen_saver_mode then
                self:suspend()
            end
        end
        self.event_handlers["USbPlugOut"] = function()
            self:_afterNotCharging()
            if Device.screen_saver_mode then
                self:suspend()
            end
        end
        self.event_handlers["__default__"] = function(input_event)
            -- Same as in Kobo: we want to ignore keys during suspension
            if not Device.screen_saver_mode then
                self:sendEvent(input_event)
            end
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
---- @param refreshtype "full", "flashpartial", "flashui", "partial", "ui", "fast"
---- @param refreshregion a Geom object
---- @int x
---- @int y
---- @param refreshdither an optional bool
---- @see setDirty
function UIManager:show(widget, refreshtype, refreshregion, x, y, refreshdither)
    if not widget then
        logger.dbg("widget not exist to be shown")
        return
    end
    logger.dbg("show widget:", widget.id or widget.name or tostring(widget))

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
    self:setDirty(widget, refreshtype, refreshregion, refreshdither)
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
---- @param refreshtype "full", "flashpartial", "flashui", "partial", "ui", "fast"
---- @param refreshregion a Geom object
---- @param refreshdither an optional bool
---- @see setDirty
function UIManager:close(widget, refreshtype, refreshregion, refreshdither)
    if not widget then
        logger.dbg("widget to be closed does not exist")
        return
    end
    logger.dbg("close widget:", widget.name or widget.id or tostring(widget))
    local dirty = false
    -- Ensure all the widgets can get onFlushSettings event.
    widget:handleEvent(Event:new("FlushSettings"))
    -- first send close event to widget
    widget:handleEvent(Event:new("CloseWidget"))
    -- make it disabled by default and check if any widget wants it disabled or enabled
    Input.disable_double_tap = true
    local requested_disable_double_tap = nil
    -- then remove all references to that widget on stack and refresh
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == widget then
            self._dirty[self._window_stack[i].widget] = nil
            table.remove(self._window_stack, i)
            dirty = true
        else
            -- If anything else on the stack was dithered, honor the hint
            if self._window_stack[i].widget.dithered then
                refreshdither = true
                logger.dbg("Lower widget", self._window_stack[i].widget.name or self._window_stack[i].widget.id or tostring(self._window_stack[i].widget), "was dithered, honoring the dithering hint")
            end

            -- Set double tap to how the topmost specifying widget wants it
            if requested_disable_double_tap == nil and self._window_stack[i].widget.disable_double_tap ~= nil then
                requested_disable_double_tap = self._window_stack[i].widget.disable_double_tap
            end
        end
    end
    if requested_disable_double_tap ~= nil then
        Input.disable_double_tap = requested_disable_double_tap
    end
    if dirty and not widget.invisible then
        -- schedule remaining widgets to be painted
        for i = 1, #self._window_stack do
            self:setDirty(self._window_stack[i].widget)
        end
        self:_refresh(refreshtype, refreshregion, refreshdither)
    end
end

-- schedule an execution task, task queue is in ascendant order
function UIManager:schedule(time, action, ...)
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
    table.insert(self._task_queue, p, {
        time = time,
        action = action,
        args = {...},
    })
    self._task_queue_dirty = true
end
dbg:guard(UIManager, 'schedule',
    function(self, time, action)
        assert(time[1] >= 0 and time[2] >= 0, "Only positive time allowed")
        assert(action ~= nil)
    end)

--- Schedules task in a certain amount of seconds (fractions allowed) from now.
function UIManager:scheduleIn(seconds, action, ...)
    local when = { util.gettime() }
    local s = math.floor(seconds)
    local usecs = (seconds - s) * MILLION
    when[1] = when[1] + s
    when[2] = when[2] + usecs
    if when[2] >= MILLION then
        when[1] = when[1] + 1
        when[2] = when[2] - MILLION
    end
    self:schedule(when, action, ...)
end
dbg:guard(UIManager, 'scheduleIn',
    function(self, seconds, action)
        assert(seconds >= 0, "Only positive seconds allowed")
    end)

function UIManager:nextTick(action)
    return self:scheduleIn(0, action)
end

-- Useful to run UI callbacks ASAP without skipping repaints
function UIManager:tickAfterNext(action)
    return self:nextTick(function() self:nextTick(action) end)
end
--[[
-- NOTE: This appears to work *nearly* just as well, but does sometimes go too fast (might depend on kernel HZ & NO_HZ settings?)
function UIManager:tickAfterNext(action)
    return self:scheduleIn(0.001, action)
end
--]]

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
Here's a quick rundown of what each refreshtype should be used for:
full: high-fidelity flashing refresh (e.g., large images).
      Highest quality, but highest latency.
      Don't abuse if you only want a flash (in this case, prefer flashpartial or flashui).
partial: medium fidelity refresh (e.g., text on a white background).
         Can be promoted to flashing after FULL_REFRESH_COUNT refreshes.
         Don't abuse to avoid spurious flashes.
ui: medium fidelity refresh (e.g., mixed content).
    Should apply to most UI elements.
fast: low fidelity refresh (e.g., monochrome content).
      Should apply to most highlighting effects achieved through inversion.
      Note that if your highlighted element contains text,
      you might want to keep the unhighlight refresh as "ui" instead, for crisper text.
      (Or optimize that refresh away entirely, if you can get away with it).
flashui: like ui, but flashing.
         Can be used when showing a UI element for the first time, to avoid ghosting.
flashpartial: like partial, but flashing (and not counting towards flashing promotions).
              Can be used when closing an UI element, to avoid ghosting.
              You can even drop the region in these cases, to ensure a fullscreen flash.
              NOTE: On REAGL devices, "flashpartial" will NOT actually flash (by design).
                    As such, even onClose, you might prefer "flashui" in some rare instances.

NOTE: You'll notice a trend on UI elements that are usually shown *over* some kind of text
      of using "ui" onShow & onUpdate, but "partial" onClose.
      This is by design: "partial" is what the reader uses, as it's tailor-made for pure text
      over a white background, so this ensures we resume the usual flow of the reader.
      The same dynamic is true for their flashing counterparts, in the rare instances we enforce flashes.
      Any kind of "partial" refresh *will* count towards a flashing promotion after FULL_REFRESH_COUNT refreshes,
      so making sure your stuff only applies to the proper region is key to avoiding spurious large black flashes.
      That said, depending on your use case, using "ui" onClose can be a perfectly valid decision, and will ensure
      never seeing a flash because of that widget.

The final parameter (refreshdither) is an optional hint for devices with hardware dithering support that this repaint
could benefit from dithering (i.e., it contains an image).

@usage

UIManager:setDirty(self.widget, "partial")
UIManager:setDirty(self.widget, "partial", Geom:new{x=10,y=10,w=100,h=50})
UIManager:setDirty(self.widget, function() return "ui", self.someelement.dimen end)

--]]
---- @param widget a widget object
---- @param refreshtype "full", "flashpartial", "flashui", "partial", "ui", "fast"
---- @param refreshregion a Geom object
---- @param refreshdither an optional bool
function UIManager:setDirty(widget, refreshtype, refreshregion, refreshdither)
    if widget then
        if widget == "all" then
            -- special case: set all top-level widgets as being "dirty".
            for i = 1, #self._window_stack do
                self._dirty[self._window_stack[i].widget] = true
                -- If any of 'em were dithered, honor their dithering hint
                if self._window_stack[i].widget.dithered then
                    -- NOTE: That works when refreshtype is NOT a function,
                    --       which is why _repaint does another pass of this check ;).
                    logger.dbg("setDirty on all widgets: found a dithered widget, infecting the refresh queue")
                    refreshdither = true
                end
            end
        elseif not widget.invisible then
            -- We only ever check the dirty flag on top-level widgets, so only set it there!
            -- NOTE: Enable verbose debug to catch misbehaving widgets via our post-guard.
            for i = 1, #self._window_stack do
                if self._window_stack[i].widget == widget then
                    self._dirty[widget] = true
                end
            end
            -- Again, if it's flagged as dithered, honor that
            if widget.dithered then
                refreshdither = true
            end
        end
    else
        -- Another special case: if we did NOT specify a widget, but requested a full refresh nonetheless (i.e., a diagonal swipe),
        -- we'll want to check the window stack in order to honor dithering...
        if refreshtype == "full" then
            for i = 1, #self._window_stack do
                -- If any of 'em were dithered, honor their dithering hint
                if self._window_stack[i].widget.dithered then
                    logger.dbg("setDirty full on no specific widget: found a dithered widget, infecting the refresh queue")
                    refreshdither = true
                end
            end
        end
    end
    -- handle refresh information
    if type(refreshtype) == "function" then
        -- callback, will be issued after painting
        table.insert(self._refresh_func_stack, refreshtype)
        if dbg.is_on then
            --- @fixme We can't consume the return values of refreshtype by running it, because for a reason that is beyond me (scoping? gc?), that renders it useless later, meaning we then enqueue refreshes with bogus arguments...
            --        Thankfully, we can track them in _refresh()'s logging very soon after that...
            logger.dbg("setDirty via a func from widget", widget and (widget.name or widget.id or tostring(widget)) or "nil")
        end
    else
        -- otherwise, enqueue refresh
        self:_refresh(refreshtype, refreshregion, refreshdither)
        if dbg.is_on then
            if refreshregion then
                logger.dbg("setDirty", refreshtype and refreshtype or "nil", "from widget", widget and (widget.name or widget.id or tostring(widget)) or "nil", "w/ region", refreshregion.x, refreshregion.y, refreshregion.w, refreshregion.h, refreshdither and "AND w/ HW dithering" or "")
            else
                logger.dbg("setDirty", refreshtype and refreshtype or "nil", "from widget", widget and (widget.name or widget.id or tostring(widget)) or "nil", "w/ NO region", refreshdither and "AND w/ HW dithering" or "")
            end
        end
    end
end
dbg:guard(UIManager, 'setDirty',
    nil,
    function(self, widget, refreshtype, refreshregion, refreshdither)
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

-- Clear the full repaint & refreshes queues.
-- NOTE: Beware! This doesn't take any prisonners!
--       You shouldn't have to resort to this unless in very specific circumstances!
--       plugins/coverbrowser.koplugin/covermenu.lua building a franken-menu out of buttondialogtitle & buttondialog
--       and wanting to avoid inheriting their original paint/refresh cycle being a prime example.
function UIManager:clearRenderStack()
    logger.dbg("clearRenderStack: Clearing the full render stack!")
    self._dirty = {}
    self._refresh_func_stack = {}
    self._refresh_stack = {}
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

--- Sets full refresh rate for e-ink screen.
--
-- Also makes the refresh rate persistent in global reader settings.
function UIManager:setRefreshRate(rate, night_rate)
    logger.dbg("set screen full refresh rate", rate)
    self.FULL_REFRESH_COUNT =  G_reader_settings:isTrue("night_mode") and night_rate or rate
    G_reader_settings:saveSetting("full_refresh_count", rate)
    G_reader_settings:saveSetting("night_full_refresh_count", night_rate)
end

--- Gets full refresh rate for e-ink screen.
function UIManager:getRefreshRate()
    return G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT, G_reader_settings:readSetting("night_full_refresh_count") or G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT
end

function UIManager:ToggleNightMode(night_mode)
    if night_mode then
        self.FULL_REFRESH_COUNT = G_reader_settings:readSetting("night_full_refresh_count") or G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT
    else
        self.FULL_REFRESH_COUNT = G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT
    end
end

--- Get top widget.
function UIManager:getTopWidget()
    return ((self._window_stack[#self._window_stack] or {}).widget or {}).name
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
                -- Note: is_always_active widgets currently are widgets that want to show a keyboard
                -- and readerconfig
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
            task.action(unpack(task.args or {}))
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
local refresh_modes = { fast = 1, ui = 2, partial = 3, flashui = 4, flashpartial = 5, full = 6 }
-- NOTE: We might want to introduce a "force_fast" that points to fast, but has the highest priority,
--       for the few cases where we might *really* want to enforce fast (for stuff like panning or skimming?).
-- refresh methods in framebuffer implementation
local refresh_methods = {
    fast = "refreshFast",
    ui = "refreshUI",
    partial = "refreshPartial",
    flashui = "refreshFlashUI",
    flashpartial = "refreshFlashPartial",
    full = "refreshFull",
}

--[[
Compares refresh mode.

Will return the mode that takes precedence.
--]]
local function update_mode(mode1, mode2)
    if refresh_modes[mode1] > refresh_modes[mode2] then
        logger.dbg("update_mode: Update refresh mode", mode2, "to", mode1)
        return mode1
    else
        return mode2
    end
end

--[[
Compares dither hints.

Dither always wins.
--]]
local function update_dither(dither1, dither2)
    if dither1 and not dither2 then
        logger.dbg("update_dither: Update dither hint", dither2, "to", dither1)
        return dither1
    else
        return dither2
    end
end

--[[--
Enqueues a refresh.

Widgets call this in their paintTo() method in order to notify
UIManager that a certain part of the screen is to be refreshed.

@param mode
    refresh mode ("full", "flashpartial", "flashui", "partial", "ui", "fast")
@param region
    Rect() that specifies the region to be updated
    optional, update will affect whole screen if not specified.
    Note that this should be the exception.
@param dither
    Bool, a hint to request hardware dithering (if supported)
    optional, no dithering requested if not specified or not supported.
--]]
function UIManager:_refresh(mode, region, dither)
    if not mode then
        -- If we're trying to float a dither hint up from a lower widget after a close, mode might be nil...
        -- So use the lowest priority refresh mode (short of fast, because that'd do half-toning).
        if dither then
            mode = "ui"
        else
            return
        end
    end
    if not region and mode == "full" then
        self.refresh_count = 0 -- reset counter on explicit full refresh
    end
    -- Handle downgrading flashing modes to non-flashing modes, according to user settings.
    -- NOTE: Do it before "full" promotion and collision checks/update_mode.
    if G_reader_settings:isTrue("avoid_flashing_ui") then
        if mode == "flashui" then
            mode = "ui"
            logger.dbg("_refresh: downgraded flashui refresh to", mode)
        elseif mode == "flashpartial" then
            mode = "partial"
            logger.dbg("_refresh: downgraded flashpartial refresh to", mode)
        elseif mode == "partial" and region then
            mode = "ui"
            logger.dbg("_refresh: downgraded regional partial refresh to", mode)
        end
    end
    -- special case: "partial" refreshes
    -- will get promoted every self.FULL_REFRESH_COUNT refreshes
    -- since _refresh can be called mutiple times via setDirty called in
    -- different widgets before a real screen repaint, we should make sure
    -- refresh_count is incremented by only once at most for each repaint
    -- NOTE: Ideally, we'd only check for "partial"" w/ no region set (that neatly narrows it down to just the reader).
    --       In practice, we also want to promote refreshes in a few other places, except purely text-poor UI elements.
    --       (Putting "ui" in that list is problematic with a number of UI elements, most notably, ReaderHighlight,
    --       because it is implemented as "ui" over the full viewport, since we can't devise a proper bounding box).
    --       So we settle for only "partial", but treating full-screen ones slightly differently.
    if mode == "partial" and not self.refresh_counted then
        self.refresh_count = (self.refresh_count + 1) % self.FULL_REFRESH_COUNT
        if self.refresh_count == self.FULL_REFRESH_COUNT - 1 then
            -- NOTE: Promote to "full" if no region (reader), to "flashui" otherwise (UI)
            if region then
                mode = "flashui"
            else
                mode = "full"
            end
            logger.dbg("_refresh: promote refresh to", mode)
        end
        self.refresh_counted = true
    end

    -- if no region is specified, define default region
    region = region or Geom:new{w=Screen:getWidth(), h=Screen:getHeight()}

    -- if no dithering hint was specified, don't request dithering
    dither = dither or false

    -- NOTE: While, ideally, we shouldn't merge refreshes w/ different waveform modes,
    --       this allows us to optimize away a number of quirks of our rendering stack
    --       (e.g., multiple setDirty calls queued when showing/closing a widget because of update mechanisms),
    --       as well as a few actually effective merges
    --       (e.g., the disappearance of a selection HL with the following menu update).
    for i = 1, #self._refresh_stack do
        -- check for collision with refreshes that are already enqueued
        if region:intersectWith(self._refresh_stack[i].region) then
            -- combine both refreshes' regions
            local combined = region:combine(self._refresh_stack[i].region)
            -- update the mode, if needed
            mode = update_mode(mode, self._refresh_stack[i].mode)
            -- dithering hints are viral, one is enough to infect the whole queue
            dither = update_dither(dither, self._refresh_stack[i].dither)
            -- remove colliding refresh
            table.remove(self._refresh_stack, i)
            -- and try again with combined data
            return self:_refresh(mode, combined, dither)
        end
    end

    -- if we've stopped hitting collisions, enqueue the refresh
    logger.dbg("_refresh: Enqueued", mode, "update for region", region.x, region.y, region.w, region.h, dither and "w/ HW dithering" or "")
    table.insert(self._refresh_stack, {mode = mode, region = region, dither = dither})
end


-- A couple helper functions to compute aligned values...
-- c.f., <linux/kernel.h> & ffi/framebuffer_linux.lua
local function ALIGN_DOWN(x, a)
    -- x & ~(a-1)
    local mask = a - 1
    return bit.band(x, bit.bnot(mask))
end

local function ALIGN_UP(x, a)
    -- (x + (a-1)) & ~(a-1)
    local mask = a - 1
    return bit.band(x + mask, bit.bnot(mask))
end

--- Repaints dirty widgets.
function UIManager:_repaint()
    -- flag in which we will record if we did any repaints at all
    -- will trigger a refresh if set.
    local dirty = false
    -- remember if any of our repaints were dithered
    local dithered = false

    -- We don't need to call paintTo() on widgets that are under
    -- a widget that covers the full screen
    local start_idx = 1
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget.covers_fullscreen then
            start_idx = i
            if i > 1 then
                logger.dbg("not painting", i-1, "covered widget(s)")
            end
            break
        end
    end

    for i = start_idx, #self._window_stack do
        local widget = self._window_stack[i]
        -- paint if current widget or any widget underneath is dirty
        if dirty or self._dirty[widget.widget] then
            -- pass hint to widget that we got when setting widget dirty
            -- the widget can use this to decide which parts should be refreshed
            logger.dbg("painting widget:", widget.widget.name or widget.widget.id or tostring(widget))
            widget.widget:paintTo(Screen.bb, widget.x, widget.y, self._dirty[widget.widget])

            -- and remove from list after painting
            self._dirty[widget.widget] = nil

            -- trigger repaint
            dirty = true

            -- if any of 'em were dithered, we'll want to dither the final refresh
            if widget.widget.dithered then
                logger.dbg("_repaint: it was dithered, infecting the refresh queue")
                dithered = true
            end
        end
    end

    -- execute pending refresh functions
    for _, refreshfunc in ipairs(self._refresh_func_stack) do
        local refreshtype, region, dither = refreshfunc()
        -- honor dithering hints from *anywhere* in the dirty stack
        dither = update_dither(dither, dithered)
        if refreshtype then self:_refresh(refreshtype, region, dither) end
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
        -- Honor dithering hints from *anywhere* in the dirty stack
        refresh.dither = update_dither(refresh.dither, dithered)
        -- If HW dithering is disabled, unconditionally drop the dither flag
        if not Screen.hw_dithering then
            refresh.dither = nil
        end
        dbg:v("triggering refresh", refresh)
        -- NOTE: If we're requesting hardware dithering on a partial update, make sure the rectangle is using
        --       coordinates aligned to the previous multiple of 8, and dimensions aligned to the next multiple of 8.
        --       Otherwise, some unlucky coordinates will play badly with the PxP's own alignment constraints,
        --       leading to a refresh where content appears to have moved a few pixels to the side...
        --       (Sidebar: this is probably a kernel issue, the EPDC driver is responsible for the alignment fixup,
        --       c.f., epdc_process_update @ drivers/video/fbdev/mxc/mxc_epdc_v2_fb.c on a Kobo Mk. 7 kernel...).
        if refresh.dither then
            -- NOTE: Make sure the coordinates are positive, first! Otherwise, we'd gladly align further down below 0,
            --       which would skew the rectangle's position/dimension after checkBounds...
            local x_fixup = 0
            if refresh.region.x > 0 then
                local x_orig = refresh.region.x
                refresh.region.x = ALIGN_DOWN(x_orig, 8)
                x_fixup = x_orig - refresh.region.x
            end
            local y_fixup = 0
            if refresh.region.y > 0 then
                local y_orig = refresh.region.y
                refresh.region.y = ALIGN_DOWN(y_orig, 8)
                y_fixup = y_orig - refresh.region.y
            end
            -- And also make sure we won't be inadvertently cropping our rectangle in case of severe alignment fixups...
            refresh.region.w = ALIGN_UP(refresh.region.w + (x_fixup * 2), 8)
            refresh.region.h = ALIGN_UP(refresh.region.h + (y_fixup * 2), 8)
        end
        Screen[refresh_methods[refresh.mode]](Screen,
            refresh.region.x, refresh.region.y,
            refresh.region.w, refresh.region.h,
            refresh.dither)
    end
    self._refresh_stack = {}
    self.refresh_counted = false
end

function UIManager:forceRePaint()
    self:_repaint()
end

-- Used to repaint a specific sub-widget that isn't on the _window_stack itself
-- Useful to avoid repainting a complex widget when we just want to invert an icon, for instance.
-- No safety checks on x & y *by design*. I want this to blow up if used wrong.
function UIManager:widgetRepaint(widget, x, y)
    if not widget then return end

    logger.dbg("Explicit widgetRepaint:", widget.name or widget.id or tostring(widget), "@ (", x, ",", y, ")")
    widget:paintTo(Screen.bb, x, y)
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
            --- @fixme Force close looper when there is unhandled error,
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
    if Device:isCervantes() or Device:isKobo() or Device:isSDL() or Device:isRemarkable() or Device:isSonyPRSTUX() then
        self.event_handlers["Suspend"]()
    elseif Device:isKindle() then
        Device.powerd:toggleSuspend()
    end
end

-- Executes all the operations of a resume request. This function usually wakes up the device.
function UIManager:resume()
    if Device:isCervantes() or Device:isKobo() or Device:isSDL() or Device:isRemarkable() or Device:isSonyPRSTUX() then
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
