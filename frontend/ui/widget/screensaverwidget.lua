local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local ScreenSaverWidget = InputContainer:new{
    name = "Screensaver",
    widget = nil,
    background = nil,
}

function ScreenSaverWidget:init()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {Device.input.group.Back}, doc = "close widget" },
        }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = range } },
        }
    end
    self:update()
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
        Screensaver.delayed_close = nil
    end

    UIManager:close(self)
    return true
end

function ScreenSaverWidget:onAnyKeyPressed()
    self:onClose()
    return true
end

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
