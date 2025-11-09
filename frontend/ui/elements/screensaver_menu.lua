local Device = require("device")
local Screensaver = require("ui/screensaver")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance

local function hasLastFile()
    local last_file = G_reader_settings:readSetting("lastfile")
    return last_file and lfs.attributes(last_file, "mode") == "file"
end

local function isReaderProgressEnabled()
    return ui.statistics ~= nil
end

local function allowRandomImageFolder()
    local may_ignore_book_cover = G_reader_settings:isTrue("screensaver_exclude_on_hold_books")
        or G_reader_settings:isTrue("screensaver_exclude_finished_books")
        or G_reader_settings:isTrue("screensaver_hide_cover_in_filemanager")
        or Screensaver.isExcluded(ui)
    return G_reader_settings:readSetting("screensaver_type") == "random_image"
            or (G_reader_settings:readSetting("screensaver_type") == "cover" and may_ignore_book_cover)
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
            -- separator
            {
                text = _("Ignore book cover"),
                help_text = _("Choose when to ignore showing book covers on the sleep screen."),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "cover"
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_hide_cover_in_filemanager")
                            or G_reader_settings:isTrue("screensaver_exclude_finished_books")
                            or G_reader_settings:isTrue("screensaver_exclude_on_hold_books")
                end,
                sub_item_table = {
                    {
                        text = _("For books on hold"),
                        help_text = _("When the device is locked and the current book has been marked as on hold, both the cover and sleep screen message of the book will not be shown."),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_exclude_on_hold_books")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_exclude_on_hold_books")
                        end,
                    },
                    {
                        text = _("For finished books"),
                        help_text = _("When the device is locked and the current book has been marked as finished, both the cover and sleep screen message of the book will not be shown."),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_exclude_finished_books")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_exclude_finished_books")
                        end,
                    },
                    {
                        text = _("When in file browser"),
                        help_text = _("When the device is locked from the file browser, both the cover and sleep screen message of the last opened book will not be shown."),
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_hide_cover_in_filemanager")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_hide_cover_in_filemanager")
                        end,
                    },
                },
                separator = true,
            },
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
                    genMenuItem(Device:isTouchDevice() and _("Until a tap") or _("Until a key press"), "screensaver_delay", "tap"),
                    Device:isTouchDevice() and genMenuItem(_("Until 'exit sleep screen' gesture"), "screensaver_delay", "gesture") or nil,
                },
            },
            {
                text = _("Custom images"),
                enabled_func = function()
                    return allowRandomImageFolder() or G_reader_settings:readSetting("screensaver_type") == "document_cover"
                end,
                sub_item_table = {
                    {
                        text = _("Choose image or document cover"),
                        enabled_func = function()
                            return G_reader_settings:readSetting("screensaver_type") == "document_cover"
                        end,
                        keep_menu_open = true,
                        callback = Screensaver.chooseFile,
                    },
                    {
                        text = _("Choose random image folder"),
                        enabled_func = allowRandomImageFolder,
                        keep_menu_open = true,
                        callback = Screensaver.chooseFolder,
                        separator = true,
                    },
                    {
                        text = _("Cycle through images in order"),
                        help_text = _("When enabled, all images (up to 256) will be displayed at least once on the sleep screen in sequence before repeating the cycle."),
                        enabled_func = allowRandomImageFolder,
                        checked_func = function()
                            return G_reader_settings:isTrue("screensaver_cycle_images_alphabetically")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("screensaver_cycle_images_alphabetically")
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
                text = _("Container and position"),
                enabled_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                sub_item_table = {
                    genMenuItem(_("Banner"), "screensaver_message_container", "banner"),
                    genMenuItem(_("Box"), "screensaver_message_container", "box", nil, true),
                    {
                        text_func = function()
                            local percent = G_reader_settings:readSetting("screensaver_message_vertical_position")
                            local value
                            if percent == 100 then
                                value = _("top")
                            elseif percent == 50 then
                                value = _("middle")
                            elseif percent == 0 then
                                value = _("bottom")
                            else
                                value = percent .. "\xE2\x80\xAF%" -- narrow no-break space
                            end
                            return T(_("Vertical position: %1"), value)
                        end,
                        help_text = _("Set a custom vertical position for the sleep screen message."),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            Screensaver:setCustomPosition(touchmenu_instance)
                        end,
                    },
                    {
                        text_func = function()
                            local alpha = G_reader_settings:readSetting("screensaver_message_alpha", 100)
                            return T(_("Message opacity: %1"), alpha) .. "\xE2\x80\xAF%"
                        end,
                        help_text = _("Set the opacity level of the sleep screen message."),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            Screensaver:setMessageOpacity(touchmenu_instance)
                        end,
                    },
                },
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
                    genMenuItem(_("No fill"), "screensaver_msg_background", "none"),
                },
            },
            (Device:canReboot() and Device:canPowerOff()) and {
                text = _("Hide reboot/poweroff message"),
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_hide_fallback_msg")
                end,
                callback = function()
                    G_reader_settings:toggle("screensaver_hide_fallback_msg")
                end,
            } or nil,
        },
    },
}
