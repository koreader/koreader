local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Device = require("device")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local Screen = require("device").screen
local _ = require("gettext")

local Screenshoter = InputContainer:extend{
    prefix = "Screenshot",
    default_dir = DataStorage:getFullDataDir() .. "/screenshots",
}

function Screenshoter:init()
    self:registerKeyEvents()
    if not Device:isTouchDevice() then return end

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

function Screenshoter:getScreenshotDir()
    local screenshot_dir = G_reader_settings:readSetting("screenshot_dir")
    if screenshot_dir and util.makePath(screenshot_dir) then
        return screenshot_dir:gsub("/$", "")
    end
    return self.default_dir
end

function Screenshoter:onScreenshot(screenshot_name, caller_callback)
    local prefix = self.prefix
    local file = self.ui.document and self.ui.document.file -- currently opened book
    if file then
        local curr_page = "p" .. self.ui:getCurrentPage()
        if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
            curr_page = "p_" .. self.ui.pagemap:getCurrentPageLabel(true)
        end
        prefix = self.prefix .. "_" .. ffiutil.basename(file) .. "_" .. curr_page
    end
    if not screenshot_name then
        screenshot_name = os.date(self:getScreenshotDir() .. "/" .. prefix .. "_%Y-%m-%d_%H%M%S.png")
    end
    Screen:shot(screenshot_name)

    local dialog
    local buttons = {
        {
            {
                text = _("Delete"),
                callback = function()
                    os.remove(screenshot_name)
                    dialog:onClose()
                end,
            },
            {
                text = _("Set as book cover"),
                enabled = file and true or false,
                callback = function()
                    self.ui.bookinfo:setCustomCoverFromImage(file, screenshot_name)
                    os.remove(screenshot_name)
                    dialog:onClose()
                end,
            },
        },
        {
            {
                text = _("View"),
                callback = function()
                    local ImageViewer = require("ui/widget/imageviewer")
                    local image_viewer = ImageViewer:new{
                        file = screenshot_name,
                        modal = true,
                        with_title_bar = false,
                        buttons_visible = true,
                    }
                    UIManager:show(image_viewer)
                end,
            },
        },
    }
    if Device:supportsScreensaver() then
        table.insert(buttons[2], {
            text = _("Set as wallpaper"),
            callback = function()
                G_reader_settings:saveSetting("screensaver_type", "document_cover")
                G_reader_settings:saveSetting("screensaver_document_cover", screenshot_name)
                dialog:onClose()
            end,
        })
    end
    dialog = ButtonDialog:new{
        title = _("Screenshot saved to:") .. "\n\n" .. BD.filepath(screenshot_name) .. "\n",
        modal = true,
        buttons = buttons,
        tap_close_callback = function()
            if type(caller_callback) == "function" then
                caller_callback()
            end
            local current_path = self.ui.file_chooser and self.ui.file_chooser.path
            if current_path and current_path .. "/" == screenshot_name:match(".*/") then
                self.ui.file_chooser:refreshPath()
            end
        end,
    }
    UIManager:show(dialog)
    -- trigger full refresh
    UIManager:setDirty(nil, "full")
    return true
end

Screenshoter.onKeyPressShoot = Screenshoter.onScreenshot
Screenshoter.onTapDiagonal = Screenshoter.onScreenshot
Screenshoter.onSwipeDiagonal = Screenshoter.onScreenshot

function Screenshoter:chooseFolder()
    local title_header = _("Current screenshot folder:")
    local current_path = G_reader_settings:readSetting("screenshot_dir")
    local default_path = self.default_dir
    local caller_callback = function(path)
        G_reader_settings:saveSetting("screenshot_dir", path)
    end
    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
end

function Screenshoter:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.KeyPressShoot = {
            { "Alt", "Shift", "G" }, -- same as stock Kindle firmware
        }
    elseif Device:hasScreenKB() then
        -- kindle 4 case: same as stock firmware.
        self.key_events.KeyPressShoot = {
            { "ScreenKB", "Menu" },
        }
        -- unable to add other non-touch devices as simultaneous key presses won't work without modifiers
    end
end

Screenshoter.onPhysicalKeyboardConnected = Screenshoter.registerKeyEvents

return Screenshoter
