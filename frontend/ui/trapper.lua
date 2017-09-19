--[[--
Trapper module: provides methods for simple interaction with UI,
without the need for explicit callbacks, for use by linear jobs
between their steps.

Allows code to trap UI (give progress info to UI, ask for user choice),
or get trapped by UI (get interrupted).
Mostly done with coroutines, but hides their usage for simplicity.
]]


local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")

local Trapper = {}

--[[--
Executes a function and allows it to be trapped (that is: to use our
other methods).

Simple wrapper function for a coroutine, which is a prerequisite
for all our methods (this simply abstracts the @{coroutine}
business to our callers), and execute it.

(If some code is not wrap()'ed, most of the other methods, when called,
will simply log or fallback to a non-UI action or OK choice.)

This call should be the last step in some event processing code,
as it may return early (the first @{coroutine.yield|coroutine.yield()} in any of the other
methods will return from this function), and later be resumed by @{ui.uimanager|UIManager}.
So any following (unwrapped) code would be then executed while `func`
is half-done, with unintended consequences.

@param func function reference to function to wrap and execute
]]
function Trapper:wrap(func)
    -- Catch and log any error happening in func (an error happening
    -- in a coroutine just aborts silently the coroutine)
    local pcalled_func = function()
        -- we use xpcall as it can give a whole stacktrace, unlike pcall
        local ok, err = xpcall(func, debug.traceback)
        if not ok then
            logger.warn("error in wrapped function:", err)
            return false
        end
        return true
        -- As a coroutine, we will return at first coroutine.yield(),
        -- and the above true/false won't probably be caught by
        -- any code, but let's do it anyway.
    end
    local co = coroutine.create(pcalled_func)
    return coroutine.resume(co)
end

--- Returns if code is wrapped
--
-- @treturn boolean true if code is wrapped by Trapper, false otherwise
function Trapper:isWrapped()
    if coroutine.running() then
        return true
    end
    return false
end

--- Clears left-over widget
function Trapper:clear()
    if self:isWrapped() then
        if self.current_widget then
            UIManager:close(self.current_widget)
            UIManager:forceRePaint()
            self.current_widget = nil
        end
    end
end

--- Clears left-over widget and resets Trapper state
function Trapper:reset()
    self:clear()
    -- Reset some properties
    self.paused_text = nil
    self.paused_continue_text = nil
    self.paused_abort_text = nil
    return true
end

--[[--
Displays an InfoMessage, and catches dismissal.

Display a InfoMessage with text, or keep existing InfoMessage if text = nil,
and return true.

UNLESS the previous widget was itself a InfoMessage and it has been
dismissed (by Tap on the screen), in which case the new InfoMessage
is not displayed, and false is returned.

One can only know a InfoMessage has been dismissed when trying to
display a new one (we can't do better than that with coroutines).
So, don't hesitate to call it regularly (each call costs 100ms), between
steps of the work, to provide good responsiveness.

Trapper:info() is a shortcut to get dismiss info while keeping
the existing InfoMessage displayed.

@string text text to display as an InfoMessage (or nil to keep existing one)
@treturn boolean true if InfoMessage was not dismissed, false if dismissed

@usage
    Trapper:info("some text about step or progress")
    go_on = Trapper:info()
]]
function Trapper:info(text)
    local _coroutine = coroutine.running()
    if not _coroutine then
        logger.info("unwrapped info:", text)
        return true -- not dismissed
    end

    if self.current_widget and self.current_widget.is_infomessage then
        -- We are replacing a InfoMessage with a new InfoMessage: we want to check
        -- if the previous one was dismissed.
        -- We added a dismiss_callback to our previous InfoMessage. For a Tap
        -- to get processed and get our dismiss_callback called, we need to give
        -- control for a short time to UIManager: this will be done with
        -- the coroutine.yield() that follows.
        -- If no dismiss_callback was fired, we need to get this code resumed:
        -- that will be done with the following go_on_func schedule in 0.1 second.
        local go_on_func = function() coroutine.resume(_coroutine, true) end
        -- delay matters: 0.05 or 0.1 seems fine
        -- 0.01 is too fast: go_on_func is called before our dismiss_callback is processed
        UIManager:scheduleIn(0.1, go_on_func)

        local go_on = coroutine.yield() -- gives control back to UIManager
        -- go_on is the 2nd arg given to the coroutine.resume() that got us resumed:
        -- false if it was a dismiss_callback
        -- true if it was the schedule go_on_func

        if not go_on then -- dismiss_callback called
            UIManager:unschedule(go_on_func) -- no more need for this scheduled action
            -- Don't just return false without confirmation (this tap may have been
            -- made by error, and we don't want to just cancel a long running job)
            local abort_box = ConfirmBox:new{
                text = self.paused_text and self.paused_text or _("Paused"),
                -- ok and cancel reversed, as tapping outside will
                -- get cancel_callback called: if tap outside was the
                -- result of a tap error, we want to continue. Cancelling
                -- will need an explicit tap on the ok_text button.
                cancel_text = self.paused_continue_text and self.paused_continue_text or _("Continue"),
                ok_text = self.paused_abort_text and self.paused_abort_text or _("Abort"),
                cancel_callback = function()
                    coroutine.resume(_coroutine, true)
                end,
                ok_callback = function()
                    coroutine.resume(_coroutine, false)
                end,
            }
            UIManager:show(abort_box)
            -- no need to forceRePaint, UIManager will do it when we yield()
            go_on = coroutine.yield() -- abort_box ok/cancel from their coroutine.resume()
            UIManager:close(abort_box)
            if not go_on then
                UIManager:close(self.current_widget)
                UIManager:forceRePaint()
                return false
            end
            if self.current_widget then
                -- Re-show current widget that was dismissed
                -- (this is fine for our simple InfoMessage)
                UIManager:show(self.current_widget)
            end
            UIManager:forceRePaint()
        end
        -- go_on_func returned result = true, or abort_box did not abort:
        -- continue processing
    end

    -- TODO We should try to flush any pending tap, so past
    -- events won't be considered action on the yet to be displayed
    -- widget

    -- We're going to display a new widget, close previous one
    if self.current_widget then
        UIManager:close(self.current_widget)
        -- no repaint here, we'll do that below when a new one is shown
    end

    -- dismiss_callback will be checked for at start of next call
    self.current_widget = InfoMessage:new{
        text = text,
        dismiss_callback = function()
            coroutine.resume(_coroutine, false)
        end,
        is_infomessage = true -- flag on our InfoMessages
    }
    logger.dbg("Showing InfoMessage:", text)
    UIManager:show(self.current_widget)
    UIManager:forceRePaint()
    return true
end

--[[--
Overrides text and button texts on the Paused ConfirmBox.

A ConfirmBox is displayed when an InfoMessage is dismissed
in Trapper:info(), with default text "Paused", and default
buttons "Abort" and "Continue".

@string text ConfirmBox text (default: "Paused")
@string abort_text ConfirmBox "Abort" button text (Trapper:info() returns false)
@string continue_text ConfirmBox "Continue" button text
]]
function Trapper:setPausedText(text, abort_text, continue_text)
    if self:isWrapped() then
        self.paused_text = text
        self.paused_abort_text = abort_text
        self.paused_continue_text = continue_text
    end
end


--[[--
Displays a ConfirmBox and gets user's choice.

Display a ConfirmBox with the text and cancel_text/ok_text buttons,
block and wait for user's choice, and return the choice made:
false if Cancel tapped or dismissed, true if OK tapped

@string text text to display in a ConfirmBox
@string cancel_text text for ConfirmBox Cancel button
@string ok_text text for ConfirmBox Ok button
@treturn boolean false if Cancel tapped or dismissed, true if OK tapped

@usage
    go_on = Trapper:confirm("Do you want to go on?")
    that_selected = Trapper:confirm("Do you want to do this or that?", "this", "that"))
]]
function Trapper:confirm(text, cancel_text, ok_text)
    -- With ConfirmBox, Cancel button is on the left, OK button on the right,
    -- so buttons order is consistent with this function args
    local _coroutine = coroutine.running()
    if not _coroutine then
        logger.info("unwrapped confirm, returning true to:", text)
        return true -- always select "OK" in ConfirmBox if no UI
    end

    -- TODO We should try to flush any pending tap, so past
    -- events won't be considered action on the yet to be displayed
    -- widget

    -- Close any previous widget
    if self.current_widget then
        UIManager:close(self.current_widget)
        -- no repaint here, we'll do that below when a new one is shown
    end

    -- We will yield(), and both callbacks will resume() us
    self.current_widget = ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        cancel_text = cancel_text,
        cancel_callback = function()
            coroutine.resume(_coroutine, false)
        end,
        ok_callback = function()
            coroutine.resume(_coroutine, true)
        end,
    }
    logger.dbg("Showing ConfirmBox and waiting for answer:", text)
    UIManager:show(self.current_widget)
    -- no need to forceRePaint, UIManager will do it when we yield()
    local ret = coroutine.yield() -- wait for ConfirmBox callback
    logger.dbg("ConfirmBox answers", ret)
    return ret
end


--[[--
Dismissable wrapper for @{io.popen|io.popen(`cmd`)}.

Notes and limitations:

1) It is dismissable as long as `cmd` as not yet output anything.
   Once output has started, the reading will block till it is done.
   (Some shell tricks, included in `cmd`, could probably be used to
   accumulate `cmd` output in some variable, and to output the whole
   variable to stdout at the end.)

2) `cmd` needs to output something (we will wait till some data is available)
   If there are chances for it to not output anything, append `"; echo"` to `cmd`

3) We need an @{ui.widget.infomessage|InfoMessage}, that, as a modal, will catch
   any @{ui.event|Tap event} happening during `cmd` execution. This can be
   provided as a string (a new InfoMessage will be created), or can be an
   existing already displayed InfoMessage.

If we really need to have more control, we would need to use `select()` via `ffi`
or do low level non-blocking reading on the file descriptor.
If there are `cmd` that may not exit, that we would be trying to
collect indefinitely, the best option would be to compile any `timeout.c`
and use it as a wrapper.

@string cmd shell `cmd` to execute and get output from
@param infomessage string or already shown @{ui.widget.infomessage|InfoMessage} widget instance
@int check_interval_sec[opt=0.1] float interval in second for checking pipe for available output
@treturn boolean completed (`true` if not interrupted, `false` if dismissed)
@treturn string output of command
]]
function Trapper:dismissablePopen(cmd, infomessage, check_interval_sec)
    local _coroutine = coroutine.running()
    -- assert(_coroutine ~= nil, "Need to be called from a coroutine")
    if not _coroutine then
        logger.warn("unwrapped dismissablePopen(), falling back to blocking io.popen()")
        local std_out = io.popen(cmd, "r")
        if std_out then
            local output = std_out:read("*all")
            std_out:close()
            return true, output
        end
        return false
    end

    local own_infomessage = false
    if type(infomessage) == "string" then
        infomessage = InfoMessage:new{text = infomessage}
        UIManager:show(infomessage)
        UIManager:forceRePaint()
        own_infomessage = true
    end
    infomessage.dismiss_callback = function()
        -- this callback will resume us at coroutine.yield() below
        -- with a go_on = false
        coroutine.resume(_coroutine, false)
    end

    if not check_interval_sec then
        check_interval_sec = 0.1 -- default: check for output every 100ms
    end
    local collect_interval_sec = 5 -- collect cancelled cmd every 5 second, no hurry
    local completed = false
    local output = nil

    local std_out = io.popen(cmd, "r")
    if std_out then
        -- We check regularly if data is available to be read, and we give
        -- control in the meantime to UIManager so our InfoMessage.dismiss_callback
        -- get a chance to be triggered, in which case we won't wait for reading,
        -- We'll schedule a background function to collect the uneeded output and
        -- close the pipe later.
        while true do
            -- The following function will resume us at coroutine.yield() below
            -- with a go_on = true
            local go_on_func = function() coroutine.resume(_coroutine, true) end
            UIManager:scheduleIn(check_interval_sec, go_on_func) -- called in 100ms by default
            local go_on = coroutine.yield() -- gives control back to UIManager
            if not go_on then -- the dismiss_callback resumed us
                UIManager:unschedule(go_on_func)
                -- We forget cmd here, but something has to collect
                -- its output and close the pipe to not leak file handles and
                -- zombie processes.
                local collect_and_clean
                collect_and_clean = function()
                    if ffiutil.getNonBlockingReadSize(std_out) ~= 0 then -- cmd started outputing
                        std_out:read("*all")
                        std_out:close()
                        logger.dbg("collected cancelled cmd output")
                    else -- no output yet, reschedule
                        UIManager:scheduleIn(collect_interval_sec, collect_and_clean)
                        logger.dbg("cancelled cmd output not yet collectable")
                    end
                end
                UIManager:scheduleIn(collect_interval_sec, collect_and_clean)
                break
            end
            -- the go_on_func resumed us, check if pipe is ready to be read
            if ffiutil.getNonBlockingReadSize(std_out) ~= 0 then
                -- Some data is available for reading: read it all,
                -- but we may block from now on
                output = std_out:read("*all")
                std_out:close()
                completed = true
                break
            end
            -- logger.dbg("no cmd output yet, will check again soon")
        end
    end
    if own_infomessage then
        -- Remove our own infomessage
        UIManager:close(infomessage)
        UIManager:forceRePaint()
    end
    -- return what we got or not to our caller
    return completed, output
end

return Trapper
