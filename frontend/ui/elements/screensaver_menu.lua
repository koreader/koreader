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
    {
        text = _("Wallpaper"),
        sub_item_table = {
            genMenuItem(_("Show book cover on sleep screen"), "screensaver_type", "cover", hasLastFile),
            genMenuItem(_("Show custom image or cover on sleep screen"), "screensaver_type", "document_cover"),
            genMenuItem(_("Show random image from folder on sleep screen"), "screensaver_type", "random_image"),
            genMenuItem(_("Show reading progress on sleep screen"), "screensaver_type", "readingprogress", isReaderProgressEnabled),
            genMenuItem(_("Show book status on sleep screen"), "screensaver_type", "bookstatus", hasLastFile),
            genMenuItem(_("Leave screen as-is"), "screensaver_type", "disable", nil, true),
            separator = true,
            {
                text = _("Border fill, rotation, and fit"),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "cover"
                           or G_reader_settings:readSetting("screensaver_type") == "document_cover"
                           or G_reader_settings:readSetting("screensaver_type") == "random_image"
                end,
                sub_item_table = {
                    genMenuItem(_("Black fill"), "screensaver_img_background", "black"),
                    genMenuItem(_("White fill"), "screensaver_img_background", "white"),
                    genMenuItem(_("No fill"), "screensaver_img_background", "none", nil, true),
                    -- separator
                    {
                        text_func = function()
                            local percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage")
                            if G_reader_settings:isTrue("screensaver_stretch_images") and percentage then
                                return T(_("Stretch to fit screen (with limit: %1 %)"), percentage)
                            end
                            return _("Stretch cover to fit screen")
                        end,
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_stretch_images")
                        end,
                        callback = function(touchmenu_instance)
                            Screensaver:setStretchLimit(touchmenu_instance)
                        end,
                    },
                    {
                        text = _("Rotate cover for best fit"),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit")
                        end,
                        callback = function(touchmenu_instance)
                            G_reader_settings:flipNilOrFalse("screensaver_rotate_auto_for_best_fit")
                            touchmenu_instance:updateItems()
                        end,
                    }
                },
            },
            {
                text = _("Postpone screen update after wake-up"),
                sub_item_table = {
                    genMenuItem(_("Never"), "screensaver_delay", "disable"),
                    genMenuItem(_("1 second"), "screensaver_delay", "1"),
                    genMenuItem(_("3 seconds"), "screensaver_delay", "3"),
                    genMenuItem(_("5 seconds"), "screensaver_delay", "5"),
                    genMenuItem(_("Until a tap"), "screensaver_delay", "tap"),
                    genMenuItem(_("Until 'exit sleep screen' gesture"), "screensaver_delay", "gesture"),
                },
            },
            {
                text = _("Custom images"),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "random_image"
                           or G_reader_settings:readSetting("screensaver_type") == "document_cover"
                end,
                sub_item_table = {
                    {
                        text = _("Choose image or document cover"),
                        enabled_func = function()
                            return G_reader_settings:readSetting("screensaver_type") == "document_cover"
                        end,
                        keep_menu_open = true,
                        callback = function()
                            Screensaver:chooseFile()
                        end,
                    },
                    {
                        text = _("Choose random image folder"),
                        enabled_func = function()
                            return G_reader_settings:readSetting("screensaver_type") == "random_image"
                        end,
                        keep_menu_open = true,
                        callback = function()
                            Screensaver:chooseFolder()
                        end,
                    },
                },
            },
        },
    },
    {
        text = _("Sleep screen message"),
        sub_item_table = {
            {
                text = _("Add custom message to sleep screen"),
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                callback = function()
                    G_reader_settings:toggle("screensaver_show_message")
                end,
                separator = true,
            },
            {
                text = _("Edit sleep screen message"),
                enabled_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                keep_menu_open = true,
                callback = function()
                    Screensaver:setMessage()
                end,
            },
            {
                text = _("Background fill"),
                help_text = _("This option will only become available, if you have selected 'Leave screen as-is' as wallpaper and have 'Sleep screen message' on."),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "disable" and G_reader_settings:isTrue("screensaver_show_message")
                end,
                sub_item_table = {
                    genMenuItem(_("Black fill"), "screensaver_msg_background", "black"),
                    genMenuItem(_("White fill"), "screensaver_msg_background", "white"),
                    genMenuItem(_("No fill"), "screensaver_msg_background", "none", nil, true),
                },
            },
            {
                text = _("Message position"),
                enabled_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                sub_item_table = {
                    genMenuItem(_("Top"), "screensaver_message_position", "top"),
                    genMenuItem(_("Middle"), "screensaver_message_position", "middle"),
                    genMenuItem(_("Bottom"), "screensaver_message_position", "bottom", nil, true),
                },
            },
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
}
