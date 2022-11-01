local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local Event = require("ui/event")
local _ = require("gettext")

local ReaderRotation = InputContainer:extend{
    current_rotation = 0,
}

function ReaderRotation:init()
    self:registerKeyEvents()
    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderRotation:onGesture() end

function ReaderRotation:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events = {
            -- these will all generate the same event, just with different arguments
            RotateLeft = {
                { "J" },
                event = "Rotate",
                args = -90
            },
            RotateRight = {
                { "K" },
                event = "Rotate",
                args = 90
            },
        }
    end
end

ReaderRotation.onPhysicalKeyboardConnected = ReaderRotation.registerKeyEvents

--- @todo Reset rotation on new document, maybe on new page?

function ReaderRotation:onRotate(rotate_by)
    self.current_rotation = (self.current_rotation + rotate_by) % 360
    self.ui:handleEvent(Event:new("RotationUpdate", self.current_rotation))
    return true
end

return ReaderRotation
