local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("ui/device")
local Screen = require("ui/screen")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local DEBUG = require("dbg")

local ReaderScreenshot = InputContainer:new{}

function ReaderScreenshot:init()
    local diagonal = math.sqrt(
        math.pow(Screen:getWidth(), 2) +
        math.pow(Screen:getHeight(), 2)
    )
    self.ges_events = {
        Screenshot = {
            GestureRange:new{
                ges = "two_finger_tap",
                scale = {diagonal - Screen:scaleByDPI(200), diagonal},
                rate = 1.0,
            }
        },
    }
end

function ReaderScreenshot:onScreenshot()
    if os.execute("screenshot") ~= 0 then
        Screen.bb:invert()
        local screenshot_name = os.date("screenshots/Screenshot_%Y-%B-%d_%Hh%M.pam")
        UIManager:show(InfoMessage:new{
            text = _("Writing screen to ")..screenshot_name,
            timeout = 2,
        })
        Screen.bb:writePAM(screenshot_name)
        DEBUG(screenshot_name)
        Screen.bb:invert()
    end
    UIManager.full_refresh = true
    return true
end

return ReaderScreenshot
