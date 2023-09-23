local Screensaver = require("ui/screensaver")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local function hasLastFile()
    local last_file = G_reader_settings:readSetting("lastfile")
    return last_file and lfs.attributes(last_file, "mode") == "file"
end

local function isReaderProgressEnabled()
    return Screensaver.getReaderProgress ~= nil and hasLastFile()
end

local function genMenuItem(text, setting, value, enabled_func, separator)
    return {
        text = text,
        enabled_func = enabled_func,
        checked_func = function()
            return G_reader_settings:readSetting(setting) == value
        end,
        callback = function()
            G_reader_settings:saveSetting(setting, value)
        end,
        radio = true,
        separator = separator,
    }
end

return {
    genMenuItem(_("Use last book's cover as screensaver"), "screensaver_type", "cover", hasLastFile),
    genMenuItem(_("Use book status as screensaver"), "screensaver_type", "bookstatus", hasLastFile),
    genMenuItem(_("Use random image from folder as screensaver"), "screensaver_type", "random_image"),
    genMenuItem(_("Use document cover as screensaver"), "screensaver_type", "document_cover"),
    genMenuItem(_("Use image as screensaver"), "screensaver_type", "image_file"),
    genMenuItem(_("Use reading progress as screensaver"), "screensaver_type", "readingprogress", isReaderProgressEnabled),
    genMenuItem(_("Leave screen as-is"), "screensaver_type", "disable", nil, true),
    -- separator
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
    -- separator
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
                    genMenuItem(_("Black background"), "screensaver_img_background", "black"),
                    genMenuItem(_("White background"), "screensaver_img_background", "white"),
                    genMenuItem(_("Leave background as-is"), "screensaver_img_background", "none", nil, true),
                    -- separator
                    {
                        text_func = function()
                            local percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage")
                            if G_reader_settings:isTrue("screensaver_stretch_images") and percentage then
                                return T(_("Stretch to fit screen (with limit: %1 %)"), percentage)
                            end
                            return _("Stretch to fit screen")
                        end,
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_stretch_images")
                        end,
                        callback = function(touchmenu_instance)
                            Screensaver:setStretchLimit(touchmenu_instance)
                        end,
                    },
                },
            },
            {
                text = _("Message settings"),
                sub_item_table = {
                    genMenuItem(_("Black background behind message"), "screensaver_msg_background", "black"),
                    genMenuItem(_("White background behind message"), "screensaver_msg_background", "white"),
                    genMenuItem(_("Leave background as-is behind message"), "screensaver_msg_background", "none", nil, true),
                    -- separator
                    genMenuItem(_("Message position: top"), "screensaver_message_position", "top"),
                    genMenuItem(_("Message position: middle"), "screensaver_message_position", "middle"),
                    genMenuItem(_("Message position: bottom"), "screensaver_message_position", "bottom", nil, true),
                    -- separator
                    {
                        text = _("Hide reboot/poweroff message"),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_hide_fallback_msg")
                        end,
                        callback = function()
                            G_reader_settings:toggle("screensaver_hide_fallback_msg")
                        end,
                    },
                },
            },
            {
                text = _("Keep the screensaver on screen after wakeup"),
                sub_item_table = {
                    genMenuItem(_("Disable"), "screensaver_delay", "disable"),
                    genMenuItem(_("For 1 second"), "screensaver_delay", "1"),
                    genMenuItem(_("For 3 second"), "screensaver_delay", "3"),
                    genMenuItem(_("For 5 second"), "screensaver_delay", "5"),
                    genMenuItem(_("Until a tap"), "screensaver_delay", "tap"),
                    genMenuItem(_("Until 'Exit screensaver' gesture"), "screensaver_delay", "gesture"),
                },
            },
        },
    },
}
