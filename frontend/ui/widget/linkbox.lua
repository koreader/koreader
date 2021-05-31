local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local LinkBox = InputContainer:new{
    box = nil,
    color = Blitbuffer.COLOR_DARK_GRAY,
    radius = 0,
    bordersize = Size.line.medium,
}

function LinkBox:init()
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end
end

function LinkBox:paintTo(bb)
    bb:paintBorder(self.box.x, self.box.y, self.box.w, self.box.h,
            self.bordersize, self.color, self.radius)
end

function LinkBox:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.box
    end)
end

function LinkBox:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.box
    end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function()
            UIManager:close(self)
            if self.callback then self.callback() end
        end)
    end
    return true
end

function LinkBox:onTapClose()
    UIManager:close(self)
    self.callback = nil
    return true
end

return LinkBox
