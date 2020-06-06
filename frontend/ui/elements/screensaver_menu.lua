local Screensaver = require("ui/screensaver")
local _ = require("gettext")

local function screensaverType() return G_reader_settings:readSetting("screensaver_type") end
local function screensaverDelay() return G_reader_settings:readSetting("screensaver_delay") end
local function lastFile()
    local lfs = require("libs/libkoreader-lfs")
    local last_file = G_reader_settings:readSetting("lastfile")
    if last_file and lfs.attributes(last_file, "mode") == "file" then
        return last_file
    end
end
local function whiteBackground() return G_reader_settings:isTrue("screensaver_white_background") end
local function noBackground() return G_reader_settings:isTrue("screensaver_no_background") end
local function stretchImages() return G_reader_settings:isTrue("screensaver_stretch_images") end
local function messagePosition() return G_reader_settings:readSetting("screensaver_message_position") end
local function showMessage() return G_reader_settings:isTrue("screensaver_show_message") end

return {
    {
        text = _("Use last book's cover as screensaver"),
        enabled_func = function() return lastFile() ~= nil end,
        checked_func = function()
            if screensaverType() == "cover" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "cover")
        end
    },
    {
        text = _("Use book status as screensaver"),
        enabled_func = function() return lastFile() ~= nil end,
        checked_func = function()
            if screensaverType() == "bookstatus" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "bookstatus")
        end
    },
    {
        text = _("Use random image from folder as screensaver"),
        checked_func = function()
            if screensaverType() == "random_image" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "random_image")
        end
    },
    {
        text = _("Use document cover as screensaver"),
        checked_func = function()
            if screensaverType() == "document_cover" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "document_cover")
        end
    },
    {
        text = _("Use image as screensaver"),
        checked_func = function()
            if screensaverType() == "image_file" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "image_file")
        end
    },
    {
        text = _("Use reading progress as screensaver"),
        enabled_func = function() return Screensaver.getReaderProgress ~= nil and lastFile() ~= nil end,
        checked_func = function()
            if screensaverType() == "readingprogress" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "readingprogress")
        end
    },
    {
        text = _("Leave screen as it is"),
        checked_func = function()
            if screensaverType() == "disable" then
                return true
            else
                return false
            end
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "disable")
        end,
        separator = true,
    },
    {
        text = _("Add message to screensaver"),
        checked_func = showMessage,
        callback = function()
            G_reader_settings:saveSetting("screensaver_show_message", not showMessage())
        end,
        separator = true,
    },
    {
        text = _("Settings"),
        sub_item_table = {
            {
                text = _("Screensaver folder"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:chooseFolder()
                end,
            },
            {
                text = _("Screensaver image"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:chooseFile()
                end,
            },
            {
                text = _("Document cover"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:chooseFile(true)
                end,
            },
            {
                text = _("Screensaver message"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:setMessage()
                end,
            },
            {
                text = _("White background behind message and images"),
                checked_func = whiteBackground,
                callback = function()
                    G_reader_settings:saveSetting("screensaver_white_background", not whiteBackground())
                    G_reader_settings:flipFalse("screensaver_no_background")
                end,
            },
            {
                text = _("Leave background as-is behind message and images"),
                checked_func = noBackground,
                callback = function()
                    G_reader_settings:saveSetting("screensaver_no_background", not noBackground())
                    G_reader_settings:flipFalse("screensaver_white_background")
                end,
            },
            {
                text = _("Stretch covers and images to fit screen"),
                checked_func = stretchImages,
                callback = function()
                    G_reader_settings:saveSetting("screensaver_stretch_images", not stretchImages())
                end,
                separator = true,
            },
            {
                text = _("Screensaver message position"),
                sub_item_table = {
                    {
                        text = _("Top"),
                        checked_func = function()
                            return messagePosition() == "top"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_message_position", "top")
                        end
                    },
                    {
                        text = _("Middle"),
                        checked_func = function()
                            return messagePosition() == "middle" or messagePosition() == nil
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_message_position", "middle")
                        end
                    },
                    {
                        text = _("Bottom"),
                        checked_func = function()
                            return messagePosition() == "bottom"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_message_position", "bottom")
                        end
                    },
                }
            },
            {
                text = _("Delay when exit from screensaver"),
                sub_item_table = {
                    {
                        text = _("Disable"),
                        checked_func = function()
                            if screensaverDelay() == nil or screensaverDelay() == "disable" then
                                return true
                            else
                                return false
                            end
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "disable")
                        end
                    },
                    {
                        text = _("1 second"),
                        checked_func = function()
                            if screensaverDelay() == "1" then
                                return true
                            else
                                return false
                            end
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "1")
                        end
                    },
                    {
                        text = _("3 seconds"),
                        checked_func = function()
                            if screensaverDelay() == "3" then
                                return true
                            else
                                return false
                            end
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "3")
                        end
                    },
                    {
                        text = _("5 seconds"),
                        checked_func = function()
                            if screensaverDelay() == "5" then
                                return true
                            else
                                return false
                            end
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "5")
                        end
                    },
                    {
                        text = _("Tap to exit screensaver"),
                        checked_func = function()
                            if screensaverDelay() == "tap" then
                                return true
                            else
                                return false
                            end
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "tap")
                        end
                    },
                }
            }
        }
    }
}
