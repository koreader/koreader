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

if Device:canToggleMassStorage() then
    local MassStorage = require("ui/elements/mass_storage")

    -- mass storage settings
    common_settings.mass_storage_settings = {
        text = _("USB mass storage"),
        sub_item_table = MassStorage:getSettingsMenuTable()
    }

    -- mass storage actions
    common_settings.mass_storage_actions = {
        text = _("Start USB storage"),
        callback = function() MassStorage:start() end,
    }
end

if Device:setDateTime() then
    common_settings.time = {
        text = _("Time and date"),
        sub_item_table = {
            {
                text = _("Set time"),
                keep_menu_open = true,
                callback = function()
                    local now_t = os.date("*t")
                    local curr_hour = now_t.hour
                    local curr_min = now_t.min
                    local time_widget = TimeWidget:new{
                        hour = curr_hour,
                        min = curr_min,
                        ok_text = _("Set time"),
                        title_text = _("Set time"),
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
                keep_menu_open = true,
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
                        title_text = _("Set date"),
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

if Device:isKobo() then
    common_settings.sleepcover = {
        text = _("Ignore sleepcover events"),
        checked_func = function()
            return G_reader_settings:isTrue("ignore_power_sleepcover")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("ignore_power_sleepcover")
            UIManager:show(InfoMessage:new{
                text = _("This will take effect on next restart."),
            })
        end
    }
end

common_settings.night_mode = {
    text = _("Night mode"),
    checked_func = function() return G_reader_settings:isTrue("night_mode") end,
    callback = function()
        local night_mode = G_reader_settings:isTrue("night_mode")
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
}
common_settings.screen_dpi = require("ui/elements/screen_dpi_menu_table")
common_settings.screen_eink_opt = require("ui/elements/screen_eink_opt_menu_table")
common_settings.menu_activate = require("ui/elements/menu_activate")
common_settings.screen_disable_double_tab = require("ui/elements/screen_disable_double_tap_table")

if Device:canToggleGSensor() then
    common_settings.screen_toggle_gsensor = require("ui/elements/screen_toggle_gsensor")
end

if Screen.isColorScreen() then
    common_settings.color_rendering = require("ui/elements/screen_color_menu_table")
end

if Device:isAndroid() then
    -- android common settings
    local isAndroid, android = pcall(require, "android")
    if not isAndroid then return end

    -- keep screen on
    common_settings.keep_screen_on = {
        text = _("Keep screen on"),
        checked_func = function() return G_reader_settings:isTrue("enable_android_wakelock") end,
        callback = function() require("ui/elements/screen_android"):toggleWakelock() end,
    }

    -- fullscreen
    if Device.firmware_rev <= 16 then
        common_settings.fullscreen = {
            text = _("Fullscreen"),
            checked_func = function() return android.isFullscreen() end,
            callback = function() require("ui/elements/screen_android"):toggleFullscreen() end,
        }
    end
end

if Device:isTouchDevice() then
    common_settings.taps_and_gestures = {
        text = _("Taps and gestures"),
    }
end

common_settings.navigation = {
    text = _("Navigation"),
}
local back_to_exit_str = {
    prompt = {_("Prompt"), _("prompt")},
    always = {_("Always"), _("always")},
    disable ={_("Disable"), _("disable")},
}
common_settings.back_to_exit = {
    text_func = function()
        local back_to_exit = G_reader_settings:readSetting("back_to_exit") or "prompt"
        return T(_("Back to exit (%1)"),
                 back_to_exit_str[back_to_exit][2])
    end,
    sub_item_table = {
        {
            text = back_to_exit_str.prompt[1],
            checked_func = function()
                local setting = G_reader_settings:readSetting("back_to_exit")
                return setting == "prompt" or setting == nil
            end,
            callback = function()
                G_reader_settings:saveSetting("back_to_exit", "prompt")
            end,
        },
        {
            text = back_to_exit_str.always[1],
            checked_func = function()
                return G_reader_settings:readSetting("back_to_exit")
                           == "always"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_to_exit", "always")
            end,
        },
        {
            text = back_to_exit_str.disable[1],
            checked_func = function()
                return G_reader_settings:readSetting("back_to_exit")
                           == "disable"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_to_exit", "disable")
            end,
        },
    },
}
common_settings.back_in_filemanager = {
    text = _("Back in file browser"),
    sub_item_table = {
        {
            text_func = function()
                local back_to_exit = G_reader_settings:readSetting("back_to_exit") or "prompt"
                return T(_("Back to exit (%1)"),
                         back_to_exit_str[back_to_exit][2])
            end,
            checked_func = function()
                local back_in_filemanager = G_reader_settings:readSetting("back_in_filemanager")
                return back_in_filemanager == nil or back_in_filemanager == "default"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_in_filemanager", "default")
            end,
        },
        {
            text = _("Go to parent folder"),
            checked_func = function()
                return G_reader_settings:readSetting("back_in_filemanager")
                           == "parent_folder"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_in_filemanager", "parent_folder")
            end,
        },
    },
}
common_settings.enable_back_history = {
    text = _("Enable back history"),
    checked_func = function()
        return G_reader_settings:nilOrTrue("enable_back_history")
    end,
    callback = function()
        G_reader_settings:flipNilOrTrue("enable_back_history")
    end,
}
if Device:hasKeys() then
    common_settings.invert_page_turn_buttons = {
        text = _("Invert page turn buttons"),
        checked_func = function()
            return G_reader_settings:isTrue("input_invert_page_turn_keys")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("input_invert_page_turn_keys")
            Device:invertButtons()
        end,
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
        {
            text = _("Highlight action"),
            sub_item_table = {
                {
                    text = _("Ask with popup dialog"),
                    checked_func = function()
                        return G_reader_settings:nilOrFalse("default_highlight_action")
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("default_highlight_action", nil)
                    end,
                },
                {
                    text = _("Highlight"),
                    checked_func = function()
                        return G_reader_settings:readSetting("default_highlight_action") == "highlight"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("default_highlight_action", "highlight")
                    end,
                },
                {
                    text = _("Translate"),
                    checked_func = function()
                        return G_reader_settings:readSetting("default_highlight_action") == "translate"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("default_highlight_action", "translate")
                    end,
                },
                {
                    text = _("Wikipedia"),
                    checked_func = function()
                        return G_reader_settings:readSetting("default_highlight_action") == "wikipedia"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("default_highlight_action", "wikipedia")
                    end,
                },
            }
        },
    },
}
common_settings.language = Language:getLangMenuTable()

return common_settings
