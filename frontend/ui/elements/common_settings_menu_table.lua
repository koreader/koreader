local DateWidget = require("ui/widget/datewidget")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Language = require("ui/language")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local TimeWidget = require("ui/widget/timewidget")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local common_settings = {}

if Device:hasFrontlight() then
    local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")
    common_settings.frontlight = {
        text = _("Frontlight"),
        callback = function()
            ReaderFrontLight:onShowFlDialog()
        end,
    }
end

if Device:setDateTime() then
    common_settings.time = {
        text = _("Time and date"),
        sub_item_table = {
            {
                text = _("Set time"),
                callback = function()
                    local now_t = os.date("*t")
                    local curr_hour = now_t.hour
                    local curr_min = now_t.min
                    local time_widget = TimeWidget:new{
                        hour = curr_hour,
                        min = curr_min,
                        ok_text = _("Set time"),
                        title_text =  _("Set time"),
                        callback = function(time)
                            if Device:setDateTime(nil, nil, nil, time.hour, time.min) then
                                now_t = os.date("*t")
                                UIManager:show(InfoMessage:new{
                                    text = T(_("Current time: %1:%2"), string.format("%02d", now_t.hour),
                                        string.format("%02d", now_t.min))
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Time couldn't be set"),
                                })
                            end
                        end
                    }
                    UIManager:show(time_widget)
                end,
            },
            {
                text = _("Set date"),
                callback = function()
                    local now_t = os.date("*t")
                    local curr_year = now_t.year
                    local curr_month = now_t.month
                    local curr_day = now_t.day
                    local date_widget = DateWidget:new{
                        year = curr_year,
                        month = curr_month,
                        day = curr_day,
                        ok_text = _("Set date"),
                        title_text =  _("Set date"),
                        callback = function(time)
                            now_t = os.date("*t")
                            if Device:setDateTime(time.year, time.month, time.day, now_t.hour, now_t.min, now_t.sec) then
                                now_t = os.date("*t")
                                UIManager:show(InfoMessage:new{
                                    text = T(_("Current date: %1-%2-%3"), now_t.year, string.format("%02d", now_t.month),
                                        string.format("%02d", now_t.day))
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Date couldn't be set"),
                                })
                            end
                        end
                    }
                    UIManager:show(date_widget)
                end,
            }
        }
    }
end

common_settings.night_mode = {
    text = _("Night mode"),
    checked_func = function() return G_reader_settings:readSetting("night_mode") end,
    callback = function()
        local night_mode = G_reader_settings:readSetting("night_mode") or false
        Screen:toggleNightMode()
        UIManager:setDirty(nil, "full")
        G_reader_settings:saveSetting("night_mode", not night_mode)
    end
}
common_settings.network = {
    text = _("Network"),
}
NetworkMgr:getMenuTable(common_settings)

common_settings.screen = {
    text = _("Screen"),
    sub_item_table = {
        require("ui/elements/screen_dpi_menu_table"),
        require("ui/elements/refresh_menu_table"),
        require("ui/elements/screen_eink_opt_menu_table"),
        require("ui/elements/menu_activate"),
        require("ui/elements/screen_disable_double_tap_table"),
        require("ui/elements/flash_ui"),
        require("ui/elements/flash_keyboard"),
        require("ui/elements/avoid_flashing_ui"),
    },
}
if Screen.isColorScreen() then
    table.insert(common_settings.screen.sub_item_table, 4, require("ui/elements/screen_color_menu_table"))
    common_settings.screen.sub_item_table[4].separator = true
else
    common_settings.screen.sub_item_table[3].separator = true
end
if Device:isAndroid() then
    table.insert(common_settings.screen.sub_item_table, require("ui/elements/screen_fullscreen_menu_table"))
end

if Device:hasKeys() then
    common_settings.navigation = {
        text = _("Navigation"),
        sub_item_table = {
            {
                text = _("Back key to exit KOReader"),
                sub_item_table = {
                    {
                        text = _("Prompt"),
                        checked_func = function()
                            local setting = G_reader_settings:readSetting("back_to_exit")
                            return setting == "prompt" or setting == nil
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("back_to_exit", "prompt")
                        end,
                    },
                    {
                        text = _("Always"),
                        checked_func = function()
                            return G_reader_settings:readSetting("back_to_exit")
                                       == "always"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("back_to_exit", "always")
                        end,
                    },
                    {
                        text = _("Disable"),
                        checked_func = function()
                            return G_reader_settings:readSetting("back_to_exit")
                                       == "disable"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("back_to_exit", "disable")
                        end,
                    },
                },
            },
        }
    }
end
common_settings.document = {
    text = _("Document"),
    sub_item_table = {
        {
            text = _("Save document (write highlights into PDF)"),
            sub_item_table = {
                {
                    text = _("Prompt"),
                    checked_func = function()
                        local setting = G_reader_settings:readSetting("save_document")
                        return setting == "prompt" or setting == nil
                    end,
                    callback = function()
                        G_reader_settings:delSetting("save_document")
                    end,
                },
                {
                    text = _("Always"),
                    checked_func = function()
                        return G_reader_settings:readSetting("save_document")
                                   == "always"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("save_document", "always")
                    end,
                },
                {
                    text = _("Disable"),
                    checked_func = function()
                        return G_reader_settings:readSetting("save_document")
                                   == "disable"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("save_document", "disable")
                    end,
                },
            },
        },
        {
            text = _("End of document action"),
            sub_item_table = {
                {
                    text = _("Ask with pop-up dialog"),
                    checked_func = function()
                        local setting = G_reader_settings:readSetting("end_document_action")
                        return setting == "pop-up" or setting == nil
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("end_document_action", "pop-up")
                    end,
                },
                {
                    text = _("Do nothing"),
                    checked_func = function()
                        return G_reader_settings:readSetting("end_document_action") == "nothing"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("end_document_action", "nothing")
                    end,
                },
                {
                    text = _("Book status"),
                    checked_func = function()
                        return G_reader_settings:readSetting("end_document_action") == "book_status"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("end_document_action", "book_status")
                    end,
                },
                {
                    text = _("Open next file"),
                    enabled_func = function()
                        return G_reader_settings:readSetting("collate")
                            ~= "access"
                    end,
                    checked_func = function()
                        return G_reader_settings:readSetting("end_document_action") == "next_file"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("end_document_action", "next_file")
                    end,
                },
                {
                    text = _("Return to file browser"),
                    checked_func = function()
                        return G_reader_settings:readSetting("end_document_action") == "file_browser"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("end_document_action", "file_browser")
                    end,
                },
                {
                    text = _("Book status and return to file browser"),
                    checked_func = function()
                        return G_reader_settings:readSetting("end_document_action") == "book_status_file_browser"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("end_document_action", "book_status_file_browser")
                    end,
                },

            }
        },
    },
}
common_settings.language = Language:getLangMenuTable()

return common_settings
