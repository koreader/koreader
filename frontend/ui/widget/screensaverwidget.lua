local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local ScreenSaverWidget = InputContainer:extend{
    name = "ScreenSaver",
    widget = nil,
    background = nil,
}

function ScreenSaverWidget:init()
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Device.input.group.Any }, seqtext = "any key", doc = "close widget" },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {}
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
            self.ges_events["Tap"] = { GestureRange:new{ ges = "tap", range = range } }
        end
    end
    self:update()
end

function ScreenSaverWidget:setupGestureEvents()
    -- The configured gesture(s) won't trigger, because this widget is at top
    -- of the UI stack and will prevent ReaderUI/Filemanager from getting
    -- and handling any configured gesture event.
    -- We need to find all the ones configured for the "exit_screensaver" action,
    -- and clone them so they are handled by this widget.
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI:_getRunningInstance()
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
        -- not filter the one we are insterested with, but also when multiple actions
        -- are assigned to a single gesture).
        self.handleEvent = function(this, event)
            InputContainer.handleEvent(this, event)
            return true
        end
        self.key_events = {} -- also disable exit with keys
    end
end

function ScreenSaverWidget:showWaitForGestureMessage(msg)
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
end

function ScreenSaverWidget:update()
    self.height = Screen:getHeight()
    self.width = Screen:getWidth()

    self.region = Geom:new{
        x = 0, y = 0,
        w = self.width,
        h = self.height,
    }
    self.main_frame = FrameContainer:new{
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = self.background,
        width = self.width,
        height = self.height,
        self.widget,
    }
    self.dithered = true
    self[1] = self.main_frame
    UIManager:setDirty(self, function()
        return "full", self.main_frame.dimen
    end)
end

function ScreenSaverWidget:onShow()
    UIManager:setDirty(self, function()
        return "full", self.main_frame.dimen
    end)
    return true
end

function ScreenSaverWidget:onTap(_, ges)
    if ges.pos:intersectWith(self.main_frame.dimen) then
        self:onClose()
    end
    return true
end

function ScreenSaverWidget:onClose()
    -- If we happened to shortcut a delayed close via user input, unschedule it to avoid a spurious refresh.
    local Screensaver = require("ui/screensaver")
    if Screensaver.delayed_close then
        UIManager:unschedule(Screensaver.close_widget)
    end

    UIManager:close(self)
    return true
end
ScreenSaverWidget.onAnyKeyPressed = ScreenSaverWidget.onClose
ScreenSaverWidget.onExitScreensaver = ScreenSaverWidget.onClose

function ScreenSaverWidget:onCloseWidget()
    -- Restore to previous rotation mode, if need be.
    if Device.orig_rotation_mode then
        Screen:setRotationMode(Device.orig_rotation_mode)
        Device.orig_rotation_mode = nil
    end

    -- Make it full-screen (self.main_frame.dimen might be in a different orientation, and it's already full-screen anyway...)
    UIManager:setDirty(nil, function()
        return "full"
    end)

    -- Will come after the Resume event, iff screensaver_delay is set.
    -- Comes *before* it otherwise.
    UIManager:broadcastEvent(Event:new("OutOfScreenSaver"))
end

return ScreenSaverWidget
