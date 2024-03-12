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
        text = _("Lock Screen"),
        sub_item_table = {
            
                genMenuItem(_("Show book cover on lock screen"), "screensaver_type", "cover", hasLastFile),
                genMenuItem(_("Show custom image on lock screen"), "screensaver_type", "image_file"),
                genMenuItem(_("Show multiple custom images on lock screen"), "screensaver_type", "random_image"),
                genMenuItem(_("Show document cover on lock screen"), "screensaver_type", "document_cover"),
                genMenuItem(_("Show reading progress on lock screen"), "screensaver_type", "readingprogress", isReaderProgressEnabled),
                genMenuItem(_("Show book status on lock screen"), "screensaver_type", "bookstatus", hasLastFile),
                genMenuItem(_("Lock the screen in current state"), "screensaver_type", "disable", nil, true),
                separator = true,
                
        
            {
                text = _("Fill-in Borders"),
                sub_item_table = {
                    genMenuItem(_("Black"), "screensaver_img_background", "black"),
                    genMenuItem(_("White"), "screensaver_img_background", "white"),
                    genMenuItem(_("Current state"), "screensaver_img_background", "none", nil, true),
                    -- separator
                        {
                            text_func = function()
                                local percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage")
                                if G_reader_settings:isTrue("screensaver_stretch_images") and percentage then
                                    return T(_("Stretch to fit screen (with limit: %1 %)"), percentage)
                                end
                                return _("Stretch Cover to Fit Screen")
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
                text = _("Unlock Screen Delay"),
                sub_item_table = {
                    genMenuItem(_("Never"), "screensaver_delay", "disable"),
                    genMenuItem(_("1 second"), "screensaver_delay", "1"),
                    genMenuItem(_("3 seconds"), "screensaver_delay", "3"),
                    genMenuItem(_("5 seconds"), "screensaver_delay", "5"),
                    genMenuItem(_("Unlock with tap"), "screensaver_delay", "tap"),
                    genMenuItem(_("Unlock with 'Exit Screensaver' gesture"), "screensaver_delay", "gesture"),
                },
            },
        },
    },

    {
        text = _("Lock Screen Message"),
        sub_item_table = {
            {
                text = _("Add Custom Message to Lock Screen"),
                checked_func = function()
                    return G_reader_settings:isTrue("screensaver_show_message")
                end,
                callback = function()
                    G_reader_settings:toggle("screensaver_show_message")
                end,
                separator = true,
            },
            {
            text = _("Edit Lock Screen Message"),
            keep_menu_open = true,
                callback = function()
                    Screensaver:setMessage()
                end,
            },
            {
                text = _("Fill-in Background"), 
                sub_item_table = {
                    genMenuItem(_("Black"), "screensaver_msg_background", "black"),
                    genMenuItem(_("White"), "screensaver_msg_background", "white"),
                    genMenuItem(_("Current state"), "screensaver_msg_background", "none", nil, true),
                },
            },
            {
                text = _("Message Position"),
                sub_item_table = {
                    genMenuItem(_("Top"), "screensaver_message_position", "top"),
                    genMenuItem(_("Middle"), "screensaver_message_position", "middle"),
                    genMenuItem(_("Bottom"), "screensaver_message_position", "bottom", nil, true),
                },
            },
            {
                text = _("Hide reboot/poweroff Message"),
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
        text = _("Custom Images"),
        sub_item_table = {
            {
                text = _("Select Custom Image"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:chooseFile()
                end,
            },
            {
                text = _("Folder used for custom images"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:chooseFolder()
                end,
            },
            
            {
                text = _("Document Cover"),
                keep_menu_open = true,
                callback = function()
                    Screensaver:chooseFile(true)
                end,
            },
        },
    },
}
