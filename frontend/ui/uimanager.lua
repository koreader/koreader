--[[--
This module manages widgets.
]]

local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local TimeVal = require("ui/timeval")
local dbg = require("dbg")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local DEFAULT_FULL_REFRESH_COUNT = 6

-- there is only one instance of this
local UIManager = {
    -- trigger a full refresh when counter reaches FULL_REFRESH_COUNT
    FULL_REFRESH_COUNT =
        G_reader_settings:isTrue("night_mode") and G_reader_settings:readSetting("night_full_refresh_count") or G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT,
    refresh_count = 0,
    currently_scrolling = false,

    -- How long to wait between ZMQ wakeups: 50ms.
    ZMQ_TIMEOUT = 50 * 1000,

    event_handlers = nil,

    _running = true,
    _now = TimeVal:now(),
    _window_stack = {},
    _task_queue = {},
    _task_queue_dirty = false,
    _dirty = {},
    _zeromqs = {},
    _refresh_stack = {},
    _refresh_func_stack = {},
    _entered_poweroff_stage = false,
    _exit_code = nil,
    _prevent_standby_count = 0,
    _prev_prevent_standby_count = 0,
    _discard_events_till = nil,

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
        self._entered_poweroff_stage = true
        Device.orig_rotation_mode = Device.screen:getRotationMode()
        Screen:setRotationMode(Screen.ORIENTATION_PORTRAIT)
        local Screensaver = require("ui/screensaver")
        Screensaver:setup("poweroff", _("Powered off"))
        if Device:hasEinkScreen() and Screensaver:modeIsImage() then
            if Screensaver:withBackground() then
                Screen:clear()
            end
            Screen:refreshFull()
        end
        Screensaver:show()
        if Device:needsScreenRefreshAfterResume() then
            Screen:refreshFull()
        end
        UIManager:nextTick(function()
            Device:saveSettings()
            if Device:isKobo() then
                self._exit_code = 88
            end
            self:broadcastEvent(Event:new("Close"))
            Device:powerOff()
        end)
    end
    self.reboot_action = function()
        self._entered_poweroff_stage = true
        Device.orig_rotation_mode = Device.screen:getRotationMode()
        Screen:setRotationMode(Screen.ORIENTATION_PORTRAIT)
        local Screensaver = require("ui/screensaver")
        Screensaver:setup("reboot", _("Rebooting…"))
        if Device:hasEinkScreen() and Screensaver:modeIsImage() then
            if Screensaver:withBackground() then
                Screen:clear()
            end
            Screen:refreshFull()
        end
        Screensaver:show()
        if Device:needsScreenRefreshAfterResume() then
            Screen:refreshFull()
        end
        UIManager:nextTick(function()
            Device:saveSettings()
            if Device:isKobo() then
                self._exit_code = 88
            end
            self:broadcastEvent(Event:new("Close"))
            Device:reboot()
        end)
    end
    if Device:isPocketBook() then
        -- Only fg/bg state plugin notifiers, not real power event.
        self.event_handlers["Suspend"] = function()
            self:_beforeSuspend()
        end
        self.event_handlers["Resume"] = function()
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
        if G_reader_settings:isTrue("ignore_power_sleepcover") then
            -- NOTE: The hardware event itself will wake the kernel up if it's in suspend (:/).
            --       Let the unexpected wakeup guard handle that.
            self.event_handlers["SleepCoverClosed"] = nil
            self.event_handlers["SleepCoverOpened"] = nil
        elseif G_reader_settings:isTrue("ignore_open_sleepcover") then
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
            -- NOTE: Plug/unplug events will wake the device up, which is why we put it back to sleep.
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
        self.event_handlers["UsbPlugIn"] = function()
            self:_beforeCharging()
            -- NOTE: Plug/unplug events will wake the device up, which is why we put it back to sleep.
            if Device.screen_saver_mode then
                self:suspend()
            else
                -- Potentially start an USBMS session
                local MassStorage = require("ui/elements/mass_storage")
                MassStorage:start()
            end
        end
        self.event_handlers["UsbPlugOut"] = function()
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
            else
                -- Potentially start an USBMS session
                local MassStorage = require("ui/elements/mass_storage")
                MassStorage:start()
            end
        end
        self.event_handlers["UsbPlugOut"] = function()
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

Widgets are registered in a stack, from bottom to top in registration order,
with a few tweaks to handle modals & toasts:
toast widgets are stacked together on top,
then modal widgets are stacked together, and finally come standard widgets.

If you think about how painting will be handled (also bottom to top), this makes perfect sense ;).

For more details about refreshtype, refreshregion & refreshdither see the description of `setDirty`.
If refreshtype is omitted, no refresh will be enqueued at this time.

@param widget a @{ui.widget.widget|widget} object
@string refreshtype `"full"`, `"flashpartial"`, `"flashui"`, `"partial"`, `"ui"`, `"fast"` (optional)
@param refreshregion a rectangle @{ui.geometry.Geom|Geom} object (optional, requires refreshtype to be set)
@int x horizontal screen offset (optional, `0` if omitted)
@int y vertical screen offset (optional, `0` if omitted)
@bool refreshdither `true` if widget requires dithering (optional, requires refreshtype to be set)
@see setDirty
]]
function UIManager:show(widget, refreshtype, refreshregion, x, y, refreshdither)
    if not widget then
        logger.dbg("widget not exist to be shown")
        return
    end
    logger.dbg("show widget:", widget.id or widget.name or tostring(widget))

    self._running = true
    local window = {x = x or 0, y = y or 0, widget = widget}
    -- put this window on top of the topmost non-modal window
    for i = #self._window_stack, 0, -1 do
        local top_window = self._window_stack[i]
        -- toasts are stacked on top of other toasts,
        -- then come modals, and then other widgets
        if top_window and top_window.widget.toast then
            if widget.toast then
                table.insert(self._window_stack, i + 1, window)
                break
            end
        elseif widget.modal or not top_window or not top_window.widget.modal then
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
    -- a widget may override tap interval (when it doesn't, nil restores the default)
    Input.tap_interval_override = widget.tap_interval_override
end

--[[--
Unregisters a widget.

It will be removed from the stack.
Will flag uncovered widgets as dirty.

For more details about refreshtype, refreshregion & refreshdither see the description of `setDirty`.
If refreshtype is omitted, no extra refresh will be enqueued at this time, leaving only those from the uncovered widgets.

@param widget a @{ui.widget.widget|widget} object
@string refreshtype `"full"`, `"flashpartial"`, `"flashui"`, `"partial"`, `"ui"`, `"fast"` (optional)
@param refreshregion a rectangle @{ui.geometry.Geom|Geom} object (optional, requires refreshtype to be set)
@bool refreshdither `true` if the refresh requires dithering (optional, requires refreshtype to be set)
@see setDirty
]]
function UIManager:close(widget, refreshtype, refreshregion, refreshdither)
    if not widget then
        logger.dbg("widget to be closed does not exist")
        return
    end
    logger.dbg("close widget:", widget.name or widget.id or tostring(widget))
    local dirty = false
    -- First notify the closed widget to save its settings...
    widget:handleEvent(Event:new("FlushSettings"))
    -- ...and notify it that it ought to be gone now.
    widget:handleEvent(Event:new("CloseWidget"))
    -- Make sure it's disabled by default and check if there are any widgets that want it disabled or enabled.
    Input.disable_double_tap = true
    local requested_disable_double_tap = nil
    local is_covered = false
    local start_idx = 1
    -- Then remove all references to that widget on stack and refresh.
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == widget then
            self._dirty[self._window_stack[i].widget] = nil
            table.remove(self._window_stack, i)
            dirty = true
        else
            -- If anything else on the stack not already hidden by (i.e., below) a fullscreen widget was dithered, honor the hint
            if self._window_stack[i].widget.dithered and not is_covered then
                refreshdither = true
                logger.dbg("Lower widget", self._window_stack[i].widget.name or self._window_stack[i].widget.id or tostring(self._window_stack[i].widget), "was dithered, honoring the dithering hint")
            end

            -- Remember the uppermost widget that covers the full screen, so we don't bother calling setDirty on hidden (i.e., lower) widgets in the following dirty loop.
            -- _repaint already does that later on to skip the actual paintTo calls, so this ensures we limit the refresh queue to stuff that will actually get painted.
            if not is_covered and self._window_stack[i].widget.covers_fullscreen then
                is_covered = true
                start_idx = i
                logger.dbg("Lower widget", self._window_stack[i].widget.name or self._window_stack[i].widget.id or tostring(self._window_stack[i].widget), "covers the full screen")
                if i > 1 then
                    logger.dbg("not refreshing", i-1, "covered widget(s)")
                end
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
    if #self._window_stack > 0 then
        -- set tap interval override to what the topmost widget specifies (when it doesn't, nil restores the default)
        Input.tap_interval_override = self._window_stack[#self._window_stack].widget.tap_interval_override
    end
    if dirty and not widget.invisible then
        -- schedule the remaining visible (i.e., uncovered) widgets to be painted
        for i = start_idx, #self._window_stack do
            self:setDirty(self._window_stack[i].widget)
        end
        self:_refresh(refreshtype, refreshregion, refreshdither)
    end
end

-- schedule an execution task, task queue is in ascendant order
function UIManager:schedule(time, action, ...)
    local p, s, e = 1, 1, #self._task_queue
    if e ~= 0 then
        -- do a binary insert
        repeat
            p = math.floor(s + (e - s) / 2)
            local p_time = self._task_queue[p].time
            if time > p_time then
                if s == e then
                    p = e + 1
                    break
                elseif s + 1 == e then
                    s = e
                else
                    s = p
                end
            elseif time < p_time then
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
        argc = select('#', ...),
        args = {...},
    })
    self._task_queue_dirty = true
end
dbg:guard(UIManager, 'schedule',
    function(self, time, action)
        assert(time.sec >= 0, "Only positive time allowed")
        assert(action ~= nil)
    end)

--[[--
Schedules a task to be run a certain amount of seconds from now.

@number seconds scheduling delay in seconds (supports decimal values, 1ms resolution).
@func action reference to the task to be scheduled (may be anonymous)
@param ... optional arguments passed to action

@see unschedule
]]
function UIManager:scheduleIn(seconds, action, ...)
    -- We might run significantly late inside an UI frame, so we can't use the cached value here.
    -- It would also cause some bad interactions with the way nextTick & co behave.
    local when = TimeVal:now() + TimeVal:fromnumber(seconds)
    self:schedule(when, action, ...)
end
dbg:guard(UIManager, 'scheduleIn',
    function(self, seconds, action)
        assert(seconds >= 0, "Only positive seconds allowed")
    end)

--[[--
Schedules a task for the next UI tick.

@func action reference to the task to be scheduled (may be anonymous)
@param ... optional arguments passed to action
@see scheduleIn
]]
function UIManager:nextTick(action, ...)
    return self:scheduleIn(0, action, ...)
end

--[[--
Schedules a task to be run two UI ticks from now.

Useful to run UI callbacks ASAP without skipping repaints.

@func action reference to the task to be scheduled (may be anonymous)
@param ... optional arguments passed to action
@see nextTick
]]
function UIManager:tickAfterNext(action, ...)
    -- Storing varargs is a bit iffy as we don't build LuaJIT w/ 5.2 compat, so we don't have access to table.pack...
    -- c.f., http://lua-users.org/wiki/VarargTheSecondClassCitizen
    local n = select('#', ...)
    local va = {...}
    return self:nextTick(function() self:nextTick(action, unpack(va, 1, n)) end)
end
--[[
-- NOTE: This appears to work *nearly* just as well, but does sometimes go too fast (might depend on kernel HZ & NO_HZ settings?)
function UIManager:tickAfterNext(action)
    return self:scheduleIn(0.001, action)
end
--]]

--[[--
Unschedules a previously scheduled task.

In order to unschedule anonymous functions, store a reference.

@func action
@see scheduleIn

@usage

self.anonymousFunction = function() self:regularFunction() end
UIManager:scheduleIn(10.5, self.anonymousFunction)
UIManager:unschedule(self.anonymousFunction)
]]
function UIManager:unschedule(action)
    local removed = false
    for i = #self._task_queue, 1, -1 do
        if self._task_queue[i].action == action then
            table.remove(self._task_queue, i)
            removed = true
        end
    end
    return removed
end
dbg:guard(UIManager, 'unschedule',
    function(self, action) assert(action ~= nil) end)

--[[--
Mark a window-level widget as dirty, enqueuing a repaint & refresh request for that widget, to be processed on the next UI tick.

The second parameter (refreshtype) can either specify a refreshtype
(optionally in combination with a refreshregion - which is suggested,
and an even more optional refreshdither flag if the content requires dithering);
or a function that returns a refreshtype, refreshregion tuple (or a refreshtype, refreshregion, refreshdither triple),
which will be called *after* painting the widget.
This is an interesting distinction, because a widget's geometry,
usually stored in a field named `dimen`, is (generally) only computed at painting time (e.g., during `paintTo`).
The TL;DR being: if you already know the region, you can pass everything by value directly,
(it'll make for slightly more readable debug logs),
but if the region will only be known after the widget has been painted, pass a function.
Note that, technically, it means that stuff passed by value will be enqueued earlier in the refresh stack.
In practice, since the stack of (both types of) refreshes is optimized into as few actual refresh ioctls as possible,
and that during the next `_repaint` tick (which is when `paintTo` for dirty widgets happens),
this shouldn't change much in the grand scheme of things, but it ought to be noted ;).

See `_repaint` for more details about how the repaint & refresh queues are processed,
and `handleInput` for more details about when those queues are actually drained.
What you should essentially remember is that `setDirty` doesn't actually "do" anything visible on its own.
It doesn't block, and when it returns, nothing new has actually been painted or refreshed.
It just appends stuff to the paint and/or refresh queues.

Here's a quick rundown of what each refreshtype should be used for:

* `full`: high-fidelity flashing refresh (e.g., large images).
          Highest quality, but highest latency.
          Don't abuse if you only want a flash (in this case, prefer `flashui` or `flashpartial`).
* `partial`: medium fidelity refresh (e.g., text on a white background).
             Can be promoted to flashing after `FULL_REFRESH_COUNT` refreshes.
             Don't abuse to avoid spurious flashes.
             In practice, this means this should mostly always be limited to ReaderUI.
* `ui`: medium fidelity refresh (e.g., mixed content).
        Should apply to most UI elements.
        When in doubt, use this.
* `fast`: low fidelity refresh (e.g., monochrome content).
          Should apply to most highlighting effects achieved through inversion.
          Note that if your highlighted element contains text,
          you might want to keep the unhighlight refresh as `"ui"` instead, for crisper text.
          (Or optimize that refresh away entirely, if you can get away with it).
* `flashui`: like `ui`, but flashing.
             Can be used when showing a UI element for the first time, or when closing one, to avoid ghosting.
* `flashpartial`: like `partial`, but flashing (and not counting towards flashing promotions).
                  Can be used when closing an UI element (usually over ReaderUI), to avoid ghosting.
                  You can even drop the region in these cases, to ensure a fullscreen flash.
                  NOTE: On REAGL devices, `flashpartial` will NOT actually flash (by design).
                        As such, even onCloseWidget, you might prefer `flashui` in most instances.

NOTE: You'll notice a trend on UI elements that are usually shown *over* some kind of text (generally ReaderUI)
of using `"ui"` onShow & onUpdate, but `"partial"` onCloseWidget.
This is by design: `"partial"` is what the reader (ReaderUI) uses, as it's tailor-made for pure text
over a white background, so this ensures we resume the usual flow of the reader.
The same dynamic is true for their flashing counterparts, in the rare instances we enforce flashes.
Any kind of `"partial"` refresh *will* count towards a flashing promotion after `FULL_REFRESH_COUNT` refreshes,
so making sure your stuff only applies to the proper region is key to avoiding spurious large black flashes.
That said, depending on your use case, using `"ui"` onCloseWidget can be a perfectly valid decision,
and will ensure never seeing a flash because of that widget.
Remember that the FM uses `"ui"`, so, if said widgets are shown over the FM,
prefer using `"ui"` or `"flashui"` onCloseWidget.

The final parameter (refreshdither) is an optional hint for devices with hardware dithering support that this repaint
could benefit from dithering (e.g., because it contains an image).

As far as the actual lifecycle of a widget goes, the rules are:

* What you `show`, you `close`.
* If you know the dimensions of the widget (or simply of the region you want to refresh), you can pass it directly:
    * to `show` (as `show` calls `setDirty`),
    * to `close` (as `close` will also call `setDirty` on the remaining dirty and visible widgets,
      and will also enqueue a refresh based on that if there are dirty widgets).
* Otherwise, you can use, respectively, a widget's `Show` & `CloseWidget` handlers for that via `setDirty` calls.
  This can also be useful if *child* widgets have specific needs (e.g., flashing, dithering) that they want to inject in the refresh queue.
* Remember that events propagate children first (in array order, starting at the top), and that if *any* event handler returns true,
  the propagation of that specific event for this widget tree stops *immediately*.
  (This generally means that, unless you know what you're doing (e.g., a widget that will *always* be used as a parent),
   you generally *don't* want to return true in `Show` or `CloseWidget` handlers).
* If any widget requires freeing non-Lua resources (e.g., FFI/C), having a `free` method called from its `CloseWidget` handler is ideal:
  this'll ensure that *any* widget including it will be sure that resources are freed when it (or its parent) are closed.
* Note that there *is* a `Close` event, but it has very specific use-cases, generally involving *programmatically* `close`ing a `show`n widget:
    * It is broadcast (e.g., sent to every widget in the window stack; the same rules about propagation apply, but only per *window-level widget*)
      at poweroff/reboot.
    * It can also be used as a keypress handler by @{ui.widget.container.inputcontainer|InputContainer}, generally bound to the Back key.

Please refrain from implementing custom `onClose` methods if that's not their intended purpose ;).

On the subject of widgets and child widgets,
you might have noticed an unspoken convention across the codebase of widgets having a field called `show_parent`.
Since handling this is entirely at the programmer's behest, here's how we usually use it:
Basically, we cascade a field named `show_parent` to every child widget that matter
(e.g., those that serve an UI purpose, as opposed to, say, a container).
This ensures that every subwidget can reference its actual parent
(ideally, all the way to the window-level widget it belongs to, i.e., the one that was passed to `show`, hence the name ;)),
to, among other things, flag the right widget for repaint via `setDirty` (c.f., those pesky debug warnings when that's done wrong ;p) when they want to request a repaint.
This is why you often see stuff doing, when instantiating a new widget, `FancyWidget:new{ show_parent = self.show_parent or self }`;
meaning, if I'm already a subwidget, cascade my parent, otherwise, it means I'm a window-level widget, so cascade myself as that widget's parent ;).

Another convention (that a few things rely on) is naming a (persistent) MovableContainer wrapping a full widget `movable`, accessible as an instance field.
This is useful when it's used for transparency purposes, which, e.g., `setDirty` and @{ui.widget.button|Button} rely on to handle updating translucent widgets properly,
by checking if self.show_parent.movable exists and is currently translucent ;).

When I mentioned passing the *right* widget to `setDirty` earlier, what I meant is that `setDirty` will only actually flag a widget for repaint
*if* that widget is a window-level widget (that is, a widget that was passed to `show` earlier and hasn't been `close`'d yet),
hence the `self.show_parent` convention detailed above to get at the proper widget from within a subwidget ;).
Otherwise, you'll notice in debug mode that a debug guard will shout at you if that contract is broken,
and what happens in practice is the same thing as if an explicit `nil` were passed: no widgets will actually be flagged for repaint,
and only the *refresh* matching the requested region *will* be enqueued.
This is why you'll find a number of valid use-cases for passing a `nil` here, when you *just* want a screen refresh without a repaint :).
The string `"all"` is also accepted in place of a widget, and will do the obvious thing: flag the *full* window stack, bottom to top, for repaint,
while still honoring the refresh region (e.g., this doesn't enforce a full-screen refresh).

@usage

UIManager:setDirty(self.widget, "partial")
UIManager:setDirty(self.widget, "partial", Geom:new{x=10,y=10,w=100,h=50})
UIManager:setDirty(self.widget, function() return "ui", self.someelement.dimen end)

@param widget a window-level widget object, `"all"`, or `nil`
@param refreshtype `"full"`, `"flashpartial"`, `"flashui"`, `"partial"`, `"ui"`, `"fast"` (or a lambda, see description above)
@param refreshregion a rectangle @{ui.geometry.Geom|Geom} object (optional, omitting it means the region will cover the full screen)
@bool refreshdither `true` if widget requires dithering (optional)
]]
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
            -- NOTE: If our widget is translucent, or belongs to a translucent MovableContainer,
            --       we'll want to flag everything below it as dirty, too,
            --       because doing transparency right requires having an up to date background against which to blend.
            --       (The typecheck is because some widgets use an alpha boolean trap for internal alpha handling (e.g., ImageWidget)).
            local handle_alpha = false
            -- NOTE: We only ever check the dirty flag on top-level widgets, so only set it there!
            --       Enable verbose debug to catch misbehaving widgets via our post-guard.
            for i = #self._window_stack, 1, -1 do
                if handle_alpha then
                    self._dirty[self._window_stack[i].widget] = true
                    logger.dbg("setDirty: Marking as dirty widget:", self._window_stack[i].widget.name or self._window_stack[i].widget.id or tostring(self._window_stack[i].widget), "because it's below translucent widget:", widget.name or widget.id or tostring(widget))
                    -- Stop flagging widgets at the uppermost one that covers the full screen
                    if self._window_stack[i].widget.covers_fullscreen then
                        break
                    end
                end

                if self._window_stack[i].widget == widget then
                    self._dirty[widget] = true

                    -- We've got a match, now check if it's translucent...
                    handle_alpha = (widget.alpha and type(widget.alpha) == "number" and widget.alpha < 1 and widget.alpha > 0)
                                or (widget.movable and widget.movable.alpha and widget.movable.alpha < 1 and widget.movable.alpha > 0)
                    -- We shouldn't be seeing the same widget at two different spots in the stack, so, we're done,
                    -- except when we need to keep looping to flag widgets below us in order to handle a translucent widget...
                    if not handle_alpha then
                        break
                    end
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
            for i = #self._window_stack, 1, -1 do
                -- If any of 'em were dithered, honor their dithering hint
                if self._window_stack[i].widget.dithered then
                    logger.dbg("setDirty full on no specific widget: found a dithered widget, infecting the refresh queue")
                    refreshdither = true
                    -- One is enough ;)
                    break
                end
            end
        end
    end
    -- handle refresh information
    if type(refreshtype) == "function" then
        -- callback, will be issued after painting
        table.insert(self._refresh_func_stack, refreshtype)
        if dbg.is_on then
            -- NOTE: It's too early to tell what the function will return (especially the region), because the widget hasn't been painted yet.
            --       Consuming the lambda now also appears have nasty side-effects that render it useless later, subtly breaking a whole lot of things...
            --       Thankfully, we can track them in _refresh()'s logging very soon after that...
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
        -- when debugging, we check if we were handed a valid window-level widget,
        -- which would be a widget that was previously passed to `show`.
        local found = false
        for i = 1, #self._window_stack do
            if self._window_stack[i].widget == widget then
                found = true
                break
            end
        end
        if not found then
            dbg:v("INFO: invalid widget for setDirty()", debug.traceback())
        end
    end)

--[[--
Clear the full repaint & refresh queues.

NOTE: Beware! This doesn't take any prisonners!
You shouldn't have to resort to this unless in very specific circumstances!
plugins/coverbrowser.koplugin/covermenu.lua building a franken-menu out of buttondialogtitle & buttondialog
and wanting to avoid inheriting their original paint/refresh cycle being a prime example.
--]]
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

--[[--
Sets the full refresh rate for e-ink screens (`FULL_REFRESH_COUNT`).

This is the amount of `"partial"` refreshes before the next one gets promoted to `"full"`.

Also makes the refresh rate persistent in global reader settings.

@see setDirty
--]]
function UIManager:setRefreshRate(rate, night_rate)
    logger.dbg("set screen full refresh rate", rate, night_rate)

    if G_reader_settings:isTrue("night_mode") then
        if night_rate then
            self.FULL_REFRESH_COUNT = night_rate
        end
    else
        if rate then
            self.FULL_REFRESH_COUNT = rate
        end
    end

    if rate then
        G_reader_settings:saveSetting("full_refresh_count", rate)
    end
    if night_rate then
        G_reader_settings:saveSetting("night_full_refresh_count", night_rate)
    end
end

--- Returns the full refresh rate for e-ink screens (`FULL_REFRESH_COUNT`).
function UIManager:getRefreshRate()
    return G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT, G_reader_settings:readSetting("night_full_refresh_count") or G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT
end

--- Toggles Night Mode (i.e., inverted rendering).
function UIManager:ToggleNightMode(night_mode)
    if night_mode then
        self.FULL_REFRESH_COUNT = G_reader_settings:readSetting("night_full_refresh_count") or G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT
    else
        self.FULL_REFRESH_COUNT = G_reader_settings:readSetting("full_refresh_count") or DEFAULT_FULL_REFRESH_COUNT
    end
end

--- Get top widget (name if possible, ref otherwise).
function UIManager:getTopWidget()
    local top = self._window_stack[#self._window_stack]
    if not top or not top.widget then
        return nil
    end
    if top.widget.name then
        return top.widget.name
    end
    return top.widget
end

--[[--
Get the *second* topmost widget, if there is one (name if possible, ref otherwise).

Useful when VirtualKeyboard is involved, as it *always* steals the top spot ;).

NOTE: Will skip over VirtualKeyboard instances, plural, in case there are multiple (because, apparently, we can do that.. ugh).
--]]
function UIManager:getSecondTopmostWidget()
    if #self._window_stack <= 1 then
        -- Not enough widgets in the stack, bye!
        return nil
    end

    -- Because everything is terrible, you can actually instantiate multiple VirtualKeyboards,
    -- and they'll stack at the top, so, loop until we get something that *isn't* VK...
    for i = #self._window_stack - 1, 1, -1 do
        local sec = self._window_stack[i]
        if not sec or not sec.widget then
            return nil
        end

        if sec.widget.name then
            if sec.widget.name ~= "VirtualKeyboard" then
                return sec.widget.name
            end
            -- Meaning if name is set, and is set to VK => continue, as we want the *next* widget.
            -- I *really* miss the continue keyword, Lua :/.
        else
            return sec.widget
        end
    end

    return nil
end

--- Check if a widget is still in the window stack, or is a subwidget of a widget still in the window stack.
function UIManager:isSubwidgetShown(widget, max_depth)
    for i = #self._window_stack, 1, -1 do
        local matched, depth = util.arrayReferences(self._window_stack[i].widget, widget, max_depth)
        if matched then
            return matched, depth, self._window_stack[i].widget
        end
    end
    return false
end

--- Same as `isSubwidgetShown`, but only check window-level widgets (e.g., what's directly registered in the window stack), don't recurse.
function UIManager:isWidgetShown(widget)
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == widget then
           return true
        end
    end
    return false
end

--[[--
Returns the region of the previous refresh.

@return a rectangle @{ui.geometry.Geom|Geom} object
]]
function UIManager:getPreviousRefreshRegion()
   return self._last_refresh_region
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

--[[--
Request all @{ui.event.Event|Event}s to be ignored for some duration.

@param set_or_seconds either `true`, in which case a platform-specific delay is chosen, or a duration in seconds (***int***).
]]
function UIManager:discardEvents(set_or_seconds)
    if not set_or_seconds then -- remove any previously set
        self._discard_events_till = nil
        return
    end
    local delay
    if set_or_seconds == true then
        -- Use an adequate delay to account for device refresh duration
        -- so any events happening in this delay (ie. before a widget
        -- is really painted on screen) are discarded.
        if Device:hasEinkScreen() then
            -- A screen refresh can take a few 100ms,
            -- sometimes > 500ms on some devices/temperatures.
            -- So, block for 400ms (to have it displayed) + 400ms
            -- for user reaction to it
            delay = TimeVal:new{ sec = 0, usec = 800000 }
        else
            -- On non-eInk screen, display is usually instantaneous
            delay = TimeVal:new{ sec = 0, usec = 400000 }
        end
    else -- we expect a number
        delay = TimeVal:new{ sec = set_or_seconds, usec = 0 }
    end
    self._discard_events_till = self._now + delay
end

--[[--
Transmits an @{ui.event.Event|Event} to active widgets, top to bottom.
Stops at the first handler that returns `true`.
Note that most complex widgets are based on @{ui.widget.container.WidgetContainer|WidgetContainer},
which itself will take care of propagating an event to its members.

@param event an @{ui.event.Event|Event} object
]]
function UIManager:sendEvent(event)
    if #self._window_stack == 0 then return end

    -- Ensure discardEvents
    if self._discard_events_till then
        if TimeVal:now() < self._discard_events_till then
            return
        else
            self._discard_events_till = nil
        end
    end

    -- The top widget gets to be the first to get the event
    local top_widget = self._window_stack[#self._window_stack]

    -- A toast widget gets closed by any event, and
    -- lets the event be handled by a lower widget
    -- (Notification is our single widget with toast=true)
    while top_widget.widget.toast do -- close them all
        self:close(top_widget.widget)
        if #self._window_stack == 0 then return end
        top_widget = self._window_stack[#self._window_stack]
    end

    if top_widget.widget:handleEvent(event) then
        return
    end
    if top_widget.widget.active_widgets then
        for _, active_widget in ipairs(top_widget.widget.active_widgets) do
            if active_widget:handleEvent(event) then return end
        end
    end

    -- If the event was not consumed (no handler returned true), active widgets (from top to bottom) can access it.
    -- NOTE: _window_stack can shrink/grow when widgets are closed (CloseWidget & Close events) or opened.
    --       Simply looping in reverse would only cover the list shrinking, and that only by a *single* element,
    --       something we can't really guarantee, hence the more dogged iterator below,
    --       which relies on a hash check of already processed widgets (LuaJIT actually hashes the table's GC reference),
    --       rather than a simple loop counter, and will in fact iterate *at least* #items ^ 2 times.
    --       Thankfully, that list should be very small, so the overhead should be minimal.
    local checked_widgets = {top_widget}
    local i = #self._window_stack
    while i > 0 do
        local widget = self._window_stack[i]
        if checked_widgets[widget] == nil then
            checked_widgets[widget] = true
            -- Widget's active widgets have precedence to handle this event
            -- NOTE: While FileManager only has a single (screenshotter), ReaderUI has many active_widgets (each ReaderUI module gets added to the list).
            if widget.widget.active_widgets then
                for _, active_widget in ipairs(widget.widget.active_widgets) do
                    if active_widget:handleEvent(event) then return end
                end
            end
            if widget.widget.is_always_active then
                -- Widget itself is flagged always active, let it handle the event
                -- NOTE: is_always_active widgets currently are widgets that want to show a VirtualKeyboard or listen to Dispatcher events
                if widget.widget:handleEvent(event) then return end
            end
            i = #self._window_stack
        else
            i = i - 1
        end
    end
end

--[[--
Transmits an @{ui.event.Event|Event} to all registered widgets.

@param event an @{ui.event.Event|Event} object
]]
function UIManager:broadcastEvent(event)
    -- Unlike sendEvent, we send the event to *all* (window-level) widgets (i.e., we don't stop, even if a handler returns true).
    -- NOTE: Same defensive approach to _window_stack changing from under our feet as above.
    local checked_widgets = {}
    local i = #self._window_stack
    while i > 0 do
        local widget = self._window_stack[i]
        if checked_widgets[widget] == nil then
            checked_widgets[widget] = true
            widget.widget:handleEvent(event)
            i = #self._window_stack
        else
            i = i - 1
        end
    end
end

function UIManager:_checkTasks()
    self._now = TimeVal:now()
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
        local task_tv = task.time or TimeVal.zero
        if task_tv <= self._now then
            -- remove from table
            table.remove(self._task_queue, 1)
            -- task is pending to be executed right now. do it.
            -- NOTE: be careful that task.action() might modify
            -- _task_queue here. So need to avoid race condition
            task.action(unpack(task.args, 1, task.argc))
        else
            -- queue is sorted in ascendant order, safe to assume all items
            -- are future tasks for now
            wait_until = task.time
            break
        end
    end

    return wait_until, self._now
end

--[[--
Returns a TimeVal object corresponding to the last UI tick.

This is essentially a cached TimeVal:now(), computed at the top of every iteration of the main UI loop,
(right before checking/running scheduled tasks).
This is mainly useful to compute/schedule stuff in the same time scale as the UI loop (i.e., MONOTONIC),
without having to resort to a syscall.
It should never be significantly stale (i.e., it should be precise enough),
unless you're blocking the UI for a significant amount of time in the same UI tick.

Prefer the appropriate TimeVal method for your needs if you require perfect accuracy
(e.g., when you're actually working on the event loop *itself* (UIManager, Input, GestureDetector)).

This is *NOT* wall clock time (REALTIME).
]]
function UIManager:getTime()
    return self._now
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
]]
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
]]
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

Widgets call this in their `paintTo()` method in order to notify
UIManager that a certain part of the screen is to be refreshed.

@string mode
    refresh mode (`"full"`, `"flashpartial"`, `"flashui"`, `"partial"`, `"ui"`, `"fast"`)
@param region
    A rectangle @{ui.geometry.Geom|Geom} object that specifies the region to be updated.
    Optional, update will affect whole screen if not specified.
    Note that this should be the exception.
@bool dither
    A hint to request hardware dithering (if supported).
    Optional, no dithering requested if not specified or not supported.

@local Not to be used outside of UIManager!
]]
function UIManager:_refresh(mode, region, dither)
    if not mode then
        -- If we're trying to float a dither hint up from a lower widget after a close, mode might be nil...
        -- So use the lowest priority refresh mode (short of fast, because that'd do half-toning).
        if dither then
            mode = "ui"
        else
            -- Otherwise, this is most likely from a `show` or `close` that wasn't passed specific refresh details,
            -- (which is the vast majority of them), in which case we drop it to avoid enqueuing a useless full-screen refresh.
            return
        end
    end
    -- Downgrade all refreshes to "fast" when ReaderPaging or ReaderScrolling have set this flag
    if self.currently_scrolling then
        mode = "fast"
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

    -- if no region is specified, use the screen's dimensions
    region = region or Geom:new{w=Screen:getWidth(), h=Screen:getHeight()}

    -- if no dithering hint was specified, don't request dithering
    dither = dither or false

    -- NOTE: While, ideally, we shouldn't merge refreshes w/ different waveform modes,
    --       this allows us to optimize away a number of quirks of our rendering stack
    --       (e.g., multiple setDirty calls queued when showing/closing a widget because of update mechanisms),
    --       as well as a few actually effective merges
    --       (e.g., the disappearance of a selection HL with the following menu update).
    for i = 1, #self._refresh_stack do
        -- Check for collision with refreshes that are already enqueued
        -- NOTE: intersect *means* intersect: we won't merge edge-to-edge regions (but the EPDC probably will).
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

--[[--
Repaints dirty widgets.

This will also drain the refresh queue, effectively refreshing the screen region(s) matching those freshly repainted widgets.

There may be refreshes enqueued without any widgets needing to be repainted (c.f., `setDirty`'s behavior when passed a `nil` widget),
in which case, nothing is repainted, but the refreshes are still drained and executed.

@local Not to be used outside of UIManager!
--]]
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

    -- Show IDs of covered widgets when debugging
    --[[
    if start_idx > 1 then
        for i = 1, start_idx-1 do
            local widget = self._window_stack[i]
            logger.dbg("NOT painting widget:", widget.widget.name or widget.widget.id or tostring(widget))
        end
    end
    --]]

    for i = start_idx, #self._window_stack do
        local widget = self._window_stack[i]
        -- paint if current widget or any widget underneath is dirty
        if dirty or self._dirty[widget.widget] then
            -- pass hint to widget that we got when setting widget dirty
            -- the widget can use this to decide which parts should be refreshed
            logger.dbg("painting widget:", widget.widget.name or widget.widget.id or tostring(widget))
            Screen:beforePaint()
            -- NOTE: Nothing actually seems to use the final argument?
            --       Could be used by widgets to know whether they're being repainted because they're actually dirty (it's true),
            --       or because something below them was (it's nil).
            widget.widget:paintTo(Screen.bb, widget.x, widget.y, self._dirty[widget.widget])

            -- and remove from list after painting
            self._dirty[widget.widget] = nil

            -- trigger a repaint for every widget above us, too
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
        -- Remember the refresh region
        self._last_refresh_region = refresh.region
        Screen[refresh_methods[refresh.mode]](Screen,
            refresh.region.x, refresh.region.y,
            refresh.region.w, refresh.region.h,
            refresh.dither)
    end

    -- Don't trigger afterPaint if we did not, in fact, paint anything
    if dirty then
        Screen:afterPaint()
    end

    self._refresh_stack = {}
    self.refresh_counted = false
end

--- Explicitly drain the paint & refresh queues *now*, instead of waiting for the next UI tick.
function UIManager:forceRePaint()
    self:_repaint()
end

--[[--
Ask the EPDC to *block* until our previous refresh ioctl has completed.

This interacts sanely with the existing low-level handling of this in `framebuffer_mxcfb`
(i.e., it doesn't even try to wait for a marker that fb has already waited for, and vice-versa).

Will return immediately if it has already completed.

If the device isn't a Linux + MXCFB device, this is a NOP.
]]
function UIManager:waitForVSync()
    Screen:refreshWaitForLast()
end

--[[--
Yield to the EPDC.

This is a dumb workaround for potential races with the EPDC when we request a refresh on a specific region,
and then proceed to *write* to the framebuffer, in the same region, very, very, very soon after that.

This basically just puts ourselves to sleep for a very short amount of time, to let the kernel do its thing in peace.

@int sleep_us Amount of time to sleep for (in µs). (Optional, defaults to 1ms).
]]
function UIManager:yieldToEPDC(sleep_us)
    if Device:hasEinkScreen() then
        -- NOTE: Early empiric evidence suggests that going as low as 1ms is enough to do the trick.
        --       Consider jumping to the jiffy resolution (100Hz/10ms) if it turns out it isn't ;).
        ffiUtil.usleep(sleep_us or 1000)
    end
end

--[[--
Used to repaint a specific sub-widget that isn't on the `_window_stack` itself.

Useful to avoid repainting a complex widget when we just want to invert an icon, for instance.
No safety checks on x & y *by design*. I want this to blow up if used wrong.

This is an explicit repaint *now*: it bypasses and ignores the paint queue (unlike `setDirty`).

@param widget a @{ui.widget.widget|widget} object
@int x left origin of widget (in the Screen buffer, e.g., `widget.dimen.x`)
@int y top origin of widget (in the Screen buffer, e.g., `widget.dimen.y`)
]]
function UIManager:widgetRepaint(widget, x, y)
    if not widget then return end

    logger.dbg("Explicit widgetRepaint:", widget.name or widget.id or tostring(widget), "@ (", x, ",", y, ")")
    widget:paintTo(Screen.bb, x, y)
end

--[[--
Same idea as `widgetRepaint`, but does a simple `bb:invertRect` on the Screen buffer, without actually going through the widget's `paintTo` method.

@param widget a @{ui.widget.widget|widget} object
@int x left origin of the rectangle to invert (in the Screen buffer, e.g., `widget.dimen.x`)
@int y top origin of the rectangle (in the Screen buffer, e.g., `widget.dimen.y`)
@int w width of the rectangle (optional, will use `widget.dimen.w` like `paintTo` would if omitted)
@int h height of the rectangle (optional, will use `widget.dimen.h` like `paintTo` would if omitted)
@see widgetRepaint
--]]
function UIManager:widgetInvert(widget, x, y, w, h)
    if not widget then return end

    logger.dbg("Explicit widgetInvert:", widget.name or widget.id or tostring(widget), "@ (", x, ",", y, ")")
    Screen.bb:invertRect(x, y, w or widget.dimen.w, h or widget.dimen.h)
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
        for input_event in zeromq.waitEvent, zeromq do
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
        --dbg("wait_until", wait_until)
        --dbg("now", now)
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

    -- NOTE: Compute deadline *before* processing ZMQs, in order to be able to catch tasks scheduled *during*
    --       the final ZMQ callback.
    --       This ensures that we get to honor a single ZMQ_TIMEOUT *after* the final ZMQ callback,
    --       which gives us a chance for another iteration, meaning going through _checkTasks to catch said scheduled tasks.
    -- Figure out how long to wait.
    -- Ultimately, that'll be the earliest of INPUT_TIMEOUT, ZMQ_TIMEOUT or the next earliest scheduled task.
    local deadline
    -- Default to INPUT_TIMEOUT (which may be nil, i.e. block until an event happens).
    local wait_us = self.INPUT_TIMEOUT

    -- If we have any ZMQs registered, ZMQ_TIMEOUT is another upper bound.
    if #self._zeromqs > 0 then
        wait_us = math.min(wait_us or math.huge, self.ZMQ_TIMEOUT)
    end

    -- We pass that on as an absolute deadline, not a relative wait time.
    if wait_us then
        deadline = now + TimeVal:new{ usec = wait_us }
    end

    -- If there's a scheduled task pending, that puts an upper bound on how long to wait.
    if wait_until and (not deadline or wait_until < deadline) then
        --             ^ We don't have a TIMEOUT induced deadline, making the choice easy.
        --                             ^ We have a task scheduled for *before* our TIMEOUT induced deadline.
        deadline = wait_until
    end

    -- Run ZMQs if any
    self:processZMQs()

    -- If allowed, entering standby (from which we can wake by input) must trigger in response to event
    -- this function emits (plugin), or within waitEvent() right after (hardware).
    -- Anywhere else breaks preventStandby/allowStandby invariants used by background jobs while UI is left running.
    self:_standbyTransition()

    -- wait for next batch of events
    local input_events = Input:waitEvent(now, deadline)

    -- delegate each input event to handler
    if input_events then
        -- Handle the full batch of events
        for __, ev in ipairs(input_events) do
            self:handleInputEvent(ev)
        end
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
                os.exit(1, true)
            end)
        end)
    end
end


function UIManager:onRotation()
    self:setDirty("all", "full")
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

--[[--
This is the main loop of the UI controller.

It is intended to manage input events and delegate them to dialogs.
--]]
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

-- The common operations that should be performed before suspending the device.
function UIManager:_beforeSuspend()
    self:flushSettings()
    self:broadcastEvent(Event:new("Suspend"))

    -- Reset gesture detection state to a blank slate (anything power-management related emits KEY events, which don't need gesture detection).
    Input:resetState()
end

-- The common operations that should be performed after resuming the device.
function UIManager:_afterResume()
    self:broadcastEvent(Event:new("Resume"))
end

-- The common operations that should be performed when the device is plugged to a power source.
function UIManager:_beforeCharging()
    if G_reader_settings:nilOrTrue("enable_charging_led") then
        Device:toggleChargingLED(true)
    end
    self:broadcastEvent(Event:new("Charging"))
end

-- The common operations that should be performed when the device is unplugged from a power source.
function UIManager:_afterNotCharging()
    if G_reader_settings:nilOrTrue("enable_charging_led") then
        Device:toggleChargingLED(false)
    end
    self:broadcastEvent(Event:new("NotCharging"))
end

--[[--
Executes all the operations of a suspension (i.e., sleep) request.

This function usually puts the device into suspension.
]]
function UIManager:suspend()
    if Device:isCervantes() or Device:isKobo() or Device:isSDL() or Device:isRemarkable() or Device:isSonyPRSTUX() then
        self.event_handlers["Suspend"]()
    elseif Device:isKindle() then
        Device.powerd:toggleSuspend()
    elseif Device.isPocketBook() and Device.canSuspend() then
        Device:suspend()
    end
end

--[[--
Executes all the operations of a resume (i.e., wakeup) request.

This function usually wakes up the device.
]]
function UIManager:resume()
    if Device:isCervantes() or Device:isKobo() or Device:isSDL() or Device:isRemarkable() or Device:isSonyPRSTUX() then
        self.event_handlers["Resume"]()
    elseif Device:isKindle() then
        self.event_handlers["OutOfSS"]()
    end
end

--[[--
Release standby lock.

Called once we're done with whatever we were doing in the background.
Standby is re-enabled only after all issued prevents are paired with allowStandby for each one.
]]
function UIManager:allowStandby()
    assert(self._prevent_standby_count > 0, "allowing standby that isn't prevented; you have an allow/prevent mismatch somewhere")
    self._prevent_standby_count = self._prevent_standby_count - 1
end

--[[--
Prevent standby.

i.e., something is happening in background, yet UI may tick.
]]
function UIManager:preventStandby()
    self._prevent_standby_count = self._prevent_standby_count + 1
end

-- The allow/prevent calls above can interminently allow standbys, but we're not interested until
-- the state change crosses UI tick boundary, which is what self._prev_prevent_standby_count is tracking.
function UIManager:_standbyTransition()
    if self._prevent_standby_count == 0 and self._prev_prevent_standby_count > 0 then
        -- edge prevent->allow
        logger.dbg("allow standby")
        Device:setAutoStandby(true)
        self:broadcastEvent(Event:new("AllowStandby"))
    elseif self._prevent_standby_count > 0 and self._prev_prevent_standby_count == 0 then
        -- edge allow->prevent
        logger.dbg("prevent standby")
        Device:setAutoStandby(false)
        self:broadcastEvent(Event:new("PreventStandby"))
    end
    self._prev_prevent_standby_count = self._prevent_standby_count
end

--- Broadcasts a `FlushSettings` Event to *all* widgets.
function UIManager:flushSettings()
    self:broadcastEvent(Event:new("FlushSettings"))
end

--- Sanely restart KOReader (on supported platforms).
function UIManager:restartKOReader()
    self:quit()
    -- This is just a magic number to indicate the restart request for shell scripts.
    self._exit_code = 85
end

--- Sanely abort KOReader (e.g., exit sanely, but with a non-zero return code).
function UIManager:abort()
    self:quit()
    self._exit_code = 1
end

UIManager:init()
return UIManager
