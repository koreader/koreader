local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")

local Screenshoter = InputContainer:new{
    prefix = 'Screenshot',
}

function Screenshoter:init()
    local screenshots_dir = DataStorage:getDataDir() .. "/screenshots/"
    self.screenshot_fn_fmt = screenshots_dir .. self.prefix .. "_%Y-%b-%d_%H%M%S.png"
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

function Screenshoter:onScreenshot(filename)
    local screenshot_name = filename or os.date(self.screenshot_fn_fmt)
    Screen:shot(screenshot_name)
    local widget = ConfirmBox:new{
        text = T( _("Saved screenshot to %1.\nWould you like to set it as screensaver?"), screenshot_name),
        ok_text = _("Yes"),
        ok_callback = function()
            G_reader_settings:saveSetting("screensaver_type", "image_file")
            G_reader_settings:saveSetting("screensaver_image", screenshot_name)
        end,
        cancel_text = _("No"),
    }
    UIManager:show(widget)
    -- trigger full refresh
    UIManager:setDirty(nil, "full")
    return true
end

function Screenshoter:onTapDiagonal()
    return self:onScreenshot()
end

function Screenshoter:onSwipeDiagonal()
    return self:onScreenshot()
end

return Screenshoter
