local BD = require("ui/bidi")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")

local Screenshoter = InputContainer:new{
    prefix = 'Screenshot',
}

function Screenshoter:init()
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
    local screenshots_dir = G_reader_settings:readSetting("screenshot_dir") or DataStorage:getDataDir() .. "/screenshots/"
    self.screenshot_fn_fmt = screenshots_dir .. self.prefix .. "_%Y-%m-%d_%H%M%S.png"
    local screenshot_name = filename or os.date(self.screenshot_fn_fmt)
    Screen:shot(screenshot_name)
    local widget = ConfirmBox:new{
        text = T( _("Saved screenshot to %1.\nWould you like to set it as screensaver?"), BD.filepath(screenshot_name)),
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

function Screenshoter:chooseFolder()
    local buttons = {}
    table.insert(buttons, {
        {
            text = _("Choose screenshot directory"),
            callback = function()
                UIManager:close(self.choose_dialog)
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        G_reader_settings:saveSetting("screenshot_dir", path .. "/")
                        UIManager:show(InfoMessage:new{
                            text = T(_("Screenshot directory set to:\n%1"), BD.dirpath(path)),
                            timeout = 3,
                        })
                    end,
                }:chooseDir()
            end,
        }
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(self.choose_dialog)
            end,
        }
    })
    local screenshot_dir = G_reader_settings:readSetting("screenshot_dir") or DataStorage:getDataDir() .. "/screenshots/"
    self.choose_dialog = ButtonDialogTitle:new{
        title = T(_("Current screenshot directory:\n%1"), BD.dirpath(screenshot_dir)),
        buttons = buttons
    }
    UIManager:show(self.choose_dialog)
end

function Screenshoter:onTapDiagonal()
    return self:onScreenshot()
end

function Screenshoter:onSwipeDiagonal()
    return self:onScreenshot()
end

return Screenshoter
