local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local ScreenSaverLockWidget = InputContainer:extend{
    name = "ScreenSaverLock",
    modal = true,     -- So it's on top the window stack
    invisible = true, -- So UIManager ignores it refresh-wise
}

function ScreenSaverLockWidget:init()
    if Device:isTouchDevice() then
        if G_reader_settings:readSetting("screensaver_delay") == "gesture" then
            self:setupGestureEvents()
        end
        if not self.has_exit_screensaver_gesture then
            -- Exit with gesture not enabled, or no configured gesture found: allow exiting with tap
            local range = Geom:new{
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
            self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = range } }
        end
    end

    self.is_infomessage_visible = false
end

function ScreenSaverLockWidget:setupGestureEvents()
    -- The configured gesture(s) won't trigger, because this widget is at top
    -- of the UI stack and will prevent ReaderUI/Filemanager from getting
    -- and handling any configured gesture event.
    -- We need to find all the ones configured for the "exit_screensaver" action,
    -- and clone them so they are handled by this widget.
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI.instance
    if not ui then
        local FileManager = require("apps/filemanager/filemanager")
        ui = FileManager.instance
    end
    if ui and ui.gestures and ui.gestures.gestures then
        local multiswipe_already_met = false
        for gesture, actions in pairs(ui.gestures.gestures) do
            if util.stringStartsWith(gesture, "multiswipe") then
                -- All multiswipes are handled by the single handler for "multiswipe"
                -- We only need to clone one of them
                gesture = "multiswipe"
            end
            if actions["exit_screensaver"] and (gesture ~= "multiswipe" or not multiswipe_already_met) then
                if gesture == "multiswipe" then
                    multiswipe_already_met = true
                end
                -- Clone the gesture found in our self.ges_events
                local ui_gesture = ui._zones[gesture]
                if ui_gesture and ui_gesture.handler then
                    -- We can reuse its GestureRange object
                    self.ges_events[gesture] = { ui_gesture.gs_range }
                    -- For each of them, we need a distinct event and its handler.
                    -- This handler will call the original handler (created by gestures.koplugin)
                    -- which, after some checks (like swipe distance and direction, and multiswipe
                    -- directions), will emit normally the configured real ExitScreensaver event,
                    -- that this widget (being at top of the UI stack) will get and that
                    -- onExitScreensaver() will handle.
                    local event_name = "TriggerExitScreensaver_" .. gesture
                    self.ges_events[gesture].event = event_name
                    self["on"..event_name] = function(this, args, ev)
                        ui_gesture.handler(ev)
                        return true
                    end
                end
            end
        end
    end
    if next(self.ges_events) then -- we found a gesture configured
        self.has_exit_screensaver_gesture = true
        -- Override handleEvent(), so we can stop any event from propagating to widgets
        -- below this one (we may get some from other multiswipe as the handler does
        -- not filter the one we are interested with, but also when multiple actions
        -- are assigned to a single gesture).
        self.handleEvent = function(this, event)
            InputContainer.handleEvent(this, event)
            return true
        end
    end
end

function ScreenSaverLockWidget:showWaitForGestureMessage()
    -- We just paint an InfoMessage on screen directly: we don't want
    -- another widget that we would need to prevent catching events
    local infomsg = InfoMessage:new{
        text = self.has_exit_screensaver_gesture
                    and _("Waiting for specific gesture to exit screensaver.")
                     or _("No exit screensaver gesture configured. Tap to exit.")
    }
    infomsg:paintTo(Screen.bb, 0, 0)
    infomsg:onShow() -- get the screen refreshed
    infomsg:free()

    -- Notify our Resume/Suspend handlers that this is visible, so they know what to do
    self.is_infomessage_visible = true
end

function ScreenSaverLockWidget:onClose()
    UIManager:close(self)
    -- Close the actual Screensaver, if any
    local Screensaver = require("ui/screensaver")
    if Screensaver.screensaver_widget then
        Screensaver.screensaver_widget:onClose()
    end
    return true
end
-- That's the Event Dispatcher will send us ;)
ScreenSaverLockWidget.onExitScreensaver = ScreenSaverLockWidget.onClose
ScreenSaverLockWidget.onTap = ScreenSaverLockWidget.onClose

function ScreenSaverLockWidget:onCloseWidget()
    -- If we don't have a ScreenSaverWidget, request a full repaint to dismiss our InfoMessage.
    local Screensaver = require("ui/screensaver")
    if not Screensaver.screensaver_widget then
        UIManager:setDirty("all", "full")

        -- And take care of cleanup in its place, too
        Screensaver:cleanup()
    end
end

-- NOTE: We duplicate this bit of logic from ScreenSaverWidget, because not every Screensaver config will spawn one...
function ScreenSaverLockWidget:onResume()
    Device.screen_saver_lock = true

    -- Show the not-a-widget InfoMessage, if it isn't already visible
    if not self.is_infomessage_visible then
        self:showWaitForGestureMessage()
    end
end

function ScreenSaverLockWidget:onSuspend()
    Device.screen_saver_lock = false

    -- Drop the not-a-widget InfoMessage, if any
    if self.is_infomessage_visible then
        UIManager:setDirty("all", "full")
        self.is_infomessage_visible = false
    end
end

return ScreenSaverLockWidget
