local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local ScreenSaverWidget = InputContainer:new{
    widget = nil,
    background = nil,
}

function ScreenSaverWidget:init()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close widget" },
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
    self[1] = self.main_frame
    UIManager:setDirty("all", function()
        local update_region = self.main_frame.dimen
        return "partial", update_region
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
        UIManager:setDirty("all", "full")
    end
    return true
end

function ScreenSaverWidget:onClose()
    UIManager:close(self)
    UIManager:setDirty("all", "full")
    return true
end

function ScreenSaverWidget:onAnyKeyPressed()
    self:onClose()
    return true
end

function ScreenSaverWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.main_frame.dimen
    end)
    return true
end

return ScreenSaverWidget
