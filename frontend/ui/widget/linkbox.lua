local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local Blitbuffer = require("ffi/blitbuffer")

local LinkBox = InputContainer:new{
    box = nil,
    color = Blitbuffer.gray(0.5),
    radius = 0,
    bordersize = 2,
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

function LinkBox:onShow()
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

