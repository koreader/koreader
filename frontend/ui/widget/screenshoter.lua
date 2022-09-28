local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local DataStorage = require("datastorage")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")

local Screenshoter = InputContainer:extend{
    prefix = 'Screenshot',
}

function Screenshoter:init()
    local diagonal = math.sqrt(Screen:getWidth()^2 + Screen:getHeight()^2)
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

function Screenshoter:onScreenshot(filename, when_done_func)
    local screenshots_dir = G_reader_settings:readSetting("screenshot_dir") or DataStorage:getDataDir() .. "/screenshots/"
    self.screenshot_fn_fmt = screenshots_dir .. self.prefix .. "_%Y-%m-%d_%H%M%S.png"
    local screenshot_name = filename or os.date(self.screenshot_fn_fmt)
    Screen:shot(screenshot_name)
    local confirm_box
    confirm_box = ConfirmBox:new{
        text = T( _("Screenshot saved to:\n%1"), BD.filepath(screenshot_name)),
        keep_dialog_open = true,
        flush_events_on_show = true, -- may be invoked with 2-fingers tap, accidental additional events can happen
        cancel_text = _("Close"),
        cancel_callback = function()
            if when_done_func then when_done_func() end
        end,
        ok_text = _("Set as screensaver"),
        ok_callback = function()
            G_reader_settings:saveSetting("screensaver_type", "image_file")
            G_reader_settings:saveSetting("screensaver_image", screenshot_name)
            UIManager:close(confirm_box)
            if when_done_func then when_done_func() end
        end,
        other_buttons_first = true,
        other_buttons = {{
            {
                text = _("Delete"),
                callback = function()
                    local __ = os.remove(screenshot_name)
                    UIManager:close(confirm_box)
                    if when_done_func then when_done_func() end
                end,
            },
            {
                text = _("View"),
                callback = function()
                    local image_viewer = require("ui/widget/imageviewer"):new{
                        file = screenshot_name,
                        modal = true,
                        with_title_bar = false,
                        buttons_visible = true,
                    }
                    UIManager:show(image_viewer)
                end,
            },
        }},
    }
    UIManager:show(confirm_box)
    -- trigger full refresh
    UIManager:setDirty(nil, "full")
    return true
end

function Screenshoter:chooseFolder()
    local screenshot_dir_default = DataStorage:getFullDataDir() .. "/screenshots/"
    local screenshot_dir = G_reader_settings:readSetting("screenshot_dir") or screenshot_dir_default
    local confirm_box = MultiConfirmBox:new{
        text = T(_("Screenshot folder is set to:\n%1\n\nChoose a new folder for screenshots?"), screenshot_dir),
        choice1_text = _("Use default"),
        choice1_callback = function()
            G_reader_settings:saveSetting("screenshot_dir", screenshot_dir_default)
        end,
        choice2_text = _("Choose folder"),
        choice2_callback = function()
            local path_chooser = require("ui/widget/pathchooser"):new{
                select_file = false,
                show_files = false,
                path = screenshot_dir,
                onConfirm = function(new_path)
                    G_reader_settings:saveSetting("screenshot_dir", new_path .. "/")
                end
            }
            UIManager:show(path_chooser)
        end,
    }
    UIManager:show(confirm_box)
end

function Screenshoter:onTapDiagonal()
    return self:onScreenshot()
end

function Screenshoter:onSwipeDiagonal()
    return self:onScreenshot()
end

return Screenshoter
