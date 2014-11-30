local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local Screen = require("device").screen
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderScreenshot = InputContainer:new{
    datetime_name = "screenshots/Screenshot_%Y-%b-%d_%H%M%S.png",
}

function ReaderScreenshot:init()
    local diagonal = math.sqrt(
        math.pow(Screen:getWidth(), 2) +
        math.pow(Screen:getHeight(), 2)
    )
    self.ges_events = {
        TapDiagonal = {
            GestureRange:new{
                ges = "two_finger_tap",
                scale = {diagonal - Screen:scaleBySize(200), diagonal},
                rate = 1.0,
            }
        },
        SwipeDiagonal = {
            GestureRange:new{
                ges = "swipe",
                scale = {diagonal - Screen:scaleBySize(200), diagonal},
                rate = 1.0,
            }
        },
    }
end

function ReaderScreenshot:onScreenshot(filename)
    local screenshot_name = filename or os.date(self.datetime_name)
    UIManager:show(InfoMessage:new{
        text = T( _("Saving screenshot to %1."), screenshot_name),
        timeout = 2,
    })
    Screen:shot(screenshot_name)
    -- trigger full refresh
    UIManager:setDirty(nil, "full")
    return true
end

function ReaderScreenshot:onTapDiagonal()
    return self:onScreenshot()
end

function ReaderScreenshot:onSwipeDiagonal()
    return self:onScreenshot()
end

return ReaderScreenshot
