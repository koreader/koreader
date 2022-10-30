local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local _ = require("gettext")

local ReaderPanning = InputContainer:extend{
    -- defaults
    panning_steps = {
        normal = 50,
        alt = 25,
        shift = 10,
        altshift = 5
    },
}

function ReaderPanning:init()
    if Device:hasKeyboard() then
        self.key_events = {
            -- these will all generate the same event, just with different arguments
            MoveUp = {
                { "Up" },
                event = "Panning",
                args = {0, -1}
            },
            MoveDown = {
                { "Down" },
                event = "Panning",
                args = {0,  1}
            },
            MoveLeft = {
                { "Left" },
                event = "Panning",
                args = {-1, 0}
            },
            MoveRight = {
                { "Right" },
                event = "Panning",
                args = {1,  0}
            },
        }
    end
    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderPanning:onGesture() end

function ReaderPanning:onSetDimensions(dimensions)
    self.dimen = dimensions
end

function ReaderPanning:onPanning(args, _)
    local dx, dy = unpack(args)
    -- for now, bounds checking/calculation is done in the view
    self.view:PanningUpdate(
        dx * self.panning_steps.normal * self.dimen.w * (1/100),
        dy * self.panning_steps.normal * self.dimen.h * (1/100))
    return true
end

return ReaderPanning
