local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local ScreenSaverWidget = InputContainer:extend{
    name = "ScreenSaver",
    widget = nil,
    background = nil,
}

function ScreenSaverWidget:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()

    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h } }
        }
    end

    self[1] = FrameContainer:new{
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = self.background,
        width = screen_w,
        height = screen_h,
        self.widget,
    }
end

function ScreenSaverWidget:onShow()
    UIManager:setDirty(self, function()
        return "full", self[1].dimen
    end)
    return true
end

function ScreenSaverWidget:onClose(arg)
    if arg and arg.keep_screensaver then return true end -- poweroff, reboot
    -- If we happened to shortcut a delayed close via user input, unschedule it to avoid a spurious refresh.
    local Screensaver = require("ui/screensaver")
    if Screensaver.delayed_close then
        UIManager:unschedule(Screensaver.close_widget)
    end

    UIManager:close(self)
    return true
end
ScreenSaverWidget.onAnyKeyPressed = ScreenSaverWidget.onClose
ScreenSaverWidget.onTap = ScreenSaverWidget.onClose
ScreenSaverWidget.onExitScreensaver = ScreenSaverWidget.onClose

function ScreenSaverWidget:onCloseWidget()
    -- Restore to previous rotation mode, if need be.
    if Device.orig_rotation_mode then
        Screen:setRotationMode(Device.orig_rotation_mode)
        Device.orig_rotation_mode = nil
    end

    -- Make it full-screen (self.main_frame.dimen might be in a different orientation, and it's already full-screen anyway...)
    UIManager:setDirty(nil, "full")

    -- Will come after the Resume event, iff screensaver_delay is set.
    -- Comes *before* it otherwise.
    UIManager:broadcastEvent(Event:new("OutOfScreenSaver"))

    -- NOTE: ScreenSaver itself is neither a Widget nor an instantiated object, so make sure we cleanup behind us...
    local Screensaver = require("ui/screensaver")
    Screensaver:cleanup()
end

function ScreenSaverWidget:onResume()
    -- If we actually catch this event, it means screensaver_delay is set.
    -- Tell Device about it, so that further power button presses while we're still shown send us back to suspend.
    -- NOTE: This only affects devices where we handle Power events ourselves (i.e., rely on Device -> Generic's onPowerEvent),
    --       and it *always* implies that Device.screen_saver_mode is true.
    Device.screen_saver_lock = true
end

function ScreenSaverWidget:onSuspend()
    -- Also flip this back on suspend, in case we suspend again on a delayed screensaver (e.g., via SleepCover or AutoSuspend).
    Device.screen_saver_lock = false
end

return ScreenSaverWidget
