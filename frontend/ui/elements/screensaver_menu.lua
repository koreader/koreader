local Screensaver = require("ui/screensaver")
local _ = require("gettext")

local function hasLastFile()
    if G_reader_settings:hasNot("lastfile") then
        return false
    end

    local lfs = require("libs/libkoreader-lfs")
    local last_file = G_reader_settings:readSetting("lastfile")
    return last_file and lfs.attributes(last_file, "mode") == "file"
end

return {
    {
        text = _("Use last book's cover as screensaver"),
        enabled_func = hasLastFile,
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "cover"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "cover")
        end
    },
    {
        text = _("Use book status as screensaver"),
        enabled_func = hasLastFile,
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "bookstatus"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "bookstatus")
        end
    },
    {
        text = _("Use random image from folder as screensaver"),
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "random_image"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "random_image")
        end
    },
    {
        text = _("Use document cover as screensaver"),
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "document_cover"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "document_cover")
        end
    },
    {
        text = _("Use image as screensaver"),
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "image_file"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "image_file")
        end
    },
    {
        text = _("Use reading progress as screensaver"),
        enabled_func = function()
            return Screensaver.getReaderProgress ~= nil and hasLastFile()
        end,
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "readingprogress"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "readingprogress")
        end
    },
    {
        text = _("Leave screen as it is"),
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "disable"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "disable")
        end,
        separator = true,
    },
    {
        text = _("Add message to screensaver"),
        checked_func = function()
            return G_reader_settings:isTrue("screensaver_show_message")
        end,
        callback = function()
            G_reader_settings:toggle("screensaver_show_message")
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
                text = _("Covers and images settings"),
                sub_item_table = {
                    {
                        text = _("Black background behind covers and images"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_img_background") == "black"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_img_background", "black")
                        end,
                    },
                    {
                        text = _("White background behind covers and images"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_img_background") == "white"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_img_background", "white")
                        end,
                    },
                    {
                        text = _("Leave background as-is behind covers and images"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_img_background") == "none"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_img_background", "none")
                        end,
                    },
                    {
                        text = _("Stretch covers and images to fit screen"),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_stretch_images")
                        end,
                        callback = function()
                            G_reader_settings:toggle("screensaver_stretch_images")
                        end,
                        separator = true,
                    },
                },
            },
            {
                text = _("Message settings"),
                sub_item_table = {
                    {
                        text = _("Black background behind message"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_msg_background") == "black"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_msg_background", "black")
                        end,
                    },
                    {
                        text = _("White background behind message"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_msg_background") == "white"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_msg_background", "white")
                        end,
                    },
                    {
                        text = _("Leave background as-is behind message"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_msg_background") == "none"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_msg_background", "none")
                        end,
                    },
                    {
                        text = _("Message position"),
                        sub_item_table = {
                            {
                                text = _("Top"),
                                checked_func = function()
                                    return G_reader_settings:readSetting("screensaver_message_position") == "top"
                                end,
                                callback = function()
                                    G_reader_settings:saveSetting("screensaver_message_position", "top")
                                end
                            },
                            {
                                text = _("Middle"),
                                checked_func = function()
                                    return G_reader_settings:readSetting("screensaver_message_position") == "middle"
                                end,
                                callback = function()
                                    G_reader_settings:saveSetting("screensaver_message_position", "middle")
                                end
                            },
                            {
                                text = _("Bottom"),
                                checked_func = function()
                                    return G_reader_settings:readSetting("screensaver_message_position") == "bottom"
                                end,
                                callback = function()
                                    G_reader_settings:saveSetting("screensaver_message_position", "bottom")
                                end
                            },
                        },
                    },
                },
            },
            {
                text = _("Keep the screensaver on screen after wakeup"),
                sub_item_table = {
                    {
                        text = _("Disable"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "disable"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "disable")
                        end
                    },
                    {
                        text = _("For 1 second"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "1"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "1")
                        end
                    },
                    {
                        text = _("For 3 seconds"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "3"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "3")
                        end
                    },
                    {
                        text = _("For 5 seconds"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "5"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "5")
                        end
                    },
                    {
                        text = _("Until a tap"),
                        checked_func = function()
                            return G_reader_settings:readSetting("screensaver_delay") == "tap"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("screensaver_delay", "tap")
                        end
                    },
                },
            },
        },
    },
}
