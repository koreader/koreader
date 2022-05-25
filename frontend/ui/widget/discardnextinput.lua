--[[--
Widget that just suppressed the next user input.
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Input = Device.input
local Screen = Device.screen

local DiscardNextInput = InputContainer:new{
    HorizontalSpan:new{}
}

function DiscardNextInput:init()
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any },
                seqtext = "any key", doc = "close dialog" }
        }
    end
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

function DiscardNextInput:onAnyKeyPressed()
    UIManager:close(self)
end

function DiscardNextInput:onTapClose()
    UIManager:close(self)
end

return DiscardNextInput
