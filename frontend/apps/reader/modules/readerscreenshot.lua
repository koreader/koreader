local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("ui/device")
local Screen = require("ui/screen")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local Geom = require("ui/geometry")
local DEBUG = require("dbg")

local ReaderScreenshot = InputContainer:new{}

function ReaderScreenshot:init()
    if DSCREENSHOT_WITH_DOUBLE_TAP then
        self.ges_events = {
                Screenshot = {
                    GestureRange:new{
                        ges = "double_tap",
                        range = Geom:new{
                            x = Screen:getWidth()*DTAP_ZONE_SCREENSHOT.x,
                            y = Screen:getHeight()*DTAP_ZONE_SCREENSHOT.y,
                            w = Screen:getWidth()*DTAP_ZONE_SCREENSHOT.w,
                            h = Screen:getHeight()*DTAP_ZONE_SCREENSHOT.h,
                        }
                    }
                },
            }
    else
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
