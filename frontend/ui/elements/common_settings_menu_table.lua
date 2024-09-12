local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InfoMessage = require("ui/widget/infomessage")
local Language = require("ui/language")
local NetworkMgr = require("ui/network/manager")
local PowerD = Device:getPowerDevice()
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local N_ = _.ngettext
local C_ = _.pgettext
local Screen = Device.screen
local T = require("ffi/util").template

local common_settings = {}

if Device:isCervantes() then
    local util = require("util")
    if util.pathExists("/usr/bin/restart.sh") then
        common_settings.start_bq = {
            text = T(_("Start %1 reader app"), "BQ"),
            callback = function()
                UIManager:quit(87)
            end,
        }
    end
end

if Device:hasFrontlight() then
    common_settings.frontlight = {
        text = _("Frontlight"),
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowFlDialog"))
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
    common_settings.mass_storage_actions = MassStorage:getActionsMenuTable()
end

if Device:canToggleChargingLED() then
    -- Charging LED settings
    common_settings.charging_led = {
        text = _("Turn on the power LED when charging"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("enable_charging_led")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("enable_charging_led")
        end
    }
end

-- Associate OS level file extensions (must be off by default, because we're not associated initially)
if Device:canAssociateFileExtensions() then
    common_settings.file_ext_assoc = {
        text = _("Associate file extensions"),
        sub_item_table = require("ui/elements/file_ext_assoc"):getSettingsMenuTable()
    }
end

-- This affects the topmenu, we want to be able to access it even if !Device:setDateTime()
common_settings.time = {
    text = _("Time and date"),
    sub_item_table = {
        {
            text = _("12-hour clock"),
            keep_menu_open = true,
            checked_func = function()
                return G_reader_settings:isTrue("twelve_hour_clock")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("twelve_hour_clock")
                UIManager:broadcastEvent(Event:new("TimeFormatChanged"))
            end,
        },
        {
            text_func = function ()
                local duration_format = G_reader_settings:readSetting("duration_format", "classic")
                local text = C_("Time", "Classic")
                if duration_format == "modern" then
                    text = C_("Time", "Modern")
                elseif duration_format == "letters" then
                    text = C_("Time", "Letters")
                end
                return T(_("Duration format: %1"), text)
            end,
            sub_item_table = {
                {
                    text_func = function()
                        local datetime = require("datetime")
                        -- sample text shows 1:23:45
                        local duration_format_str = datetime.secondsToClockDuration("classic", 5025, false)
                        return T(C_("Time", "Classic (%1)"), duration_format_str)
                    end,
                    checked_func = function()
                        return G_reader_settings:readSetting("duration_format") == "classic"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("duration_format", "classic")
                        UIManager:broadcastEvent(Event:new("UpdateFooter", true, true))
                    end,
                },
                {
                    text_func = function()
                        local datetime = require("datetime")
                        -- sample text shows 1h23'45"
                        local duration_format_str = datetime.secondsToClockDuration("modern", 5025, false)
                        return T(C_("Time", "Modern (%1)"), duration_format_str)
                    end,
                    checked_func = function()
                        return G_reader_settings:readSetting("duration_format") == "modern"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("duration_format", "modern")
                        UIManager:broadcastEvent(Event:new("UpdateFooter", true, true))
                    end,
                },
                {
                    text_func = function()
                        local datetime = require("datetime")
                        -- sample text shows 1h 23m 45s
                        local duration_format_str = datetime.secondsToClockDuration("letters", 5025, false)
                        return T(C_("Time", "Letters (%1)"), duration_format_str)
                    end,
                    checked_func = function()
                        return G_reader_settings:readSetting("duration_format") == "letters"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("duration_format", "letters")
                        UIManager:broadcastEvent(Event:new("UpdateFooter", true, true))
                    end,
                },
            }
        }
    }
}
if Device:setDateTime() then
    table.insert(common_settings.time.sub_item_table, {
        text = _("Set time"),
        keep_menu_open = true,
        callback = function()
            local now_t = os.date("*t")
            local curr_hour = now_t.hour
            local curr_min = now_t.min
            local time_widget = DateTimeWidget:new{
                hour = curr_hour,
                min = curr_min,
                ok_text = _("Set time"),
                title_text = _("Set time"),
                info_text =_("Time is in hours and minutes."),
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
    })
    table.insert(common_settings.time.sub_item_table, {
        text = _("Set date"),
        keep_menu_open = true,
        callback = function()
            local now_t = os.date("*t")
            local curr_year = now_t.year
            local curr_month = now_t.month
            local curr_day = now_t.day
            local date_widget = DateTimeWidget:new{
                year = curr_year,
                month = curr_month,
                day = curr_day,
                ok_text = _("Set date"),
                title_text = _("Set date"),
                info_text = _("Date is in years, months and days."),
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
    })
end

if Device:isKobo() then
    common_settings.ignore_sleepcover = {
        text = _("Ignore all sleepcover events"),
        checked_func = function()
            return G_reader_settings:isTrue("ignore_power_sleepcover")
        end,
        callback = function()
            G_reader_settings:toggle("ignore_power_sleepcover")
            G_reader_settings:makeFalse("ignore_open_sleepcover")
            UIManager:askForRestart()
        end
    }

    common_settings.ignore_open_sleepcover = {
        text = _("Ignore sleepcover wakeup events"),
        checked_func = function()
            return G_reader_settings:isTrue("ignore_open_sleepcover")
        end,
        callback = function()
            G_reader_settings:toggle("ignore_open_sleepcover")
            G_reader_settings:makeFalse("ignore_power_sleepcover")
            UIManager:askForRestart()
        end
    }
end

if Device:isKindle() and PowerD:hasHallSensor() then
    common_settings.cover_events = {
        text = _("Disable Kindle cover events"),
        help_text = _([[Toggle the Hall effect sensor.
This is used to detect if the cover is closed, which will automatically sleep and wake the device. If there is no cover present the sensor may cause spurious wakeups when located next to a magnetic source.]]),
        keep_menu_open = true,
        checked_func = function() return not PowerD:isHallSensorEnabled() end,
        callback = function() PowerD:onToggleHallSensor() end,
    }
end

common_settings.night_mode = {
    text = _("Night mode"),
    checked_func = function() return G_reader_settings:isTrue("night_mode") end,
    callback = function()
        UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    end
}
common_settings.network = {
    text = _("Network"),
}
NetworkMgr:getMenuTable(common_settings)

common_settings.screen = {
    text = _("Screen"),
}
common_settings.screen_rotation = dofile("frontend/ui/elements/screen_rotation_menu_table.lua")
common_settings.screen_dpi = dofile("frontend/ui/elements/screen_dpi_menu_table.lua")
common_settings.screen_eink_opt = dofile("frontend/ui/elements/screen_eink_opt_menu_table.lua")
common_settings.screen_notification = dofile("frontend/ui/elements/screen_notification_menu_table.lua")

if Device:isTouchDevice() then
    common_settings.taps_and_gestures = {
        text = _("Taps and gestures"),
    }
    common_settings.ignore_hold_corners = {
        text = _("Ignore long-press on corners"),
        checked_func = function()
            return G_reader_settings:isTrue("ignore_hold_corners")
        end,
        callback = function()
            UIManager:broadcastEvent(Event:new("IgnoreHoldCorners"))
        end,
    }
    common_settings.screen_disable_double_tab = dofile("frontend/ui/elements/screen_disable_double_tap_table.lua")
    common_settings.menu_activate = dofile("frontend/ui/elements/menu_activate.lua")
end

-- NOTE: Allow disabling color if it's mistakenly enabled on a Grayscale screen (after a settings import?)
if Screen:isColorEnabled() or Screen:isColorScreen() then
    common_settings.color_rendering = dofile("frontend/ui/elements/screen_color_menu_table.lua")
end

-- fullscreen toggle for supported devices
if not Device:isAlwaysFullscreen() then
    common_settings.fullscreen = {
        text = _("Fullscreen"),
        checked_func = function()
            return Device.fullscreen or Device.isDefaultFullscreen()
        end,
        callback = function()
            Device:toggleFullscreen()
            -- for legacy android devices
            if Device:isAndroid() then
                local api = Device.firmware_rev
                local needs_restart = api < 19 and api >= 16
                if needs_restart then
                    UIManager:askForRestart()
                end
            end
        end,
    }
end

if Device:isAndroid() then
    -- android common settings
    local isAndroid, android = pcall(require, "android")
    if not isAndroid then return end

    -- screen timeout options, disabled if device needs wakelocks.
    common_settings.screen_timeout = require("ui/elements/timeout_android"):getTimeoutMenuTable()

    -- haptic feedback override
    common_settings.android_haptic_feedback = {
        text = _("Force haptic feedback"),
        checked_func = function() return G_reader_settings:isTrue("haptic_feedback_override") end,
        callback = function()
            G_reader_settings:flipNilOrFalse("haptic_feedback_override")
            android.setHapticOverride(G_reader_settings:isTrue("haptic_feedback_override"))
        end,
    }

    -- volume key events
    common_settings.android_volume_keys = {
        text = _("Volume key page turning"),
        checked_func = function() return not android.getVolumeKeysIgnored() end,
        callback = function()
            local is_ignored = android.getVolumeKeysIgnored()
            android.setVolumeKeysIgnored(not is_ignored)
            G_reader_settings:saveSetting("android_ignore_volume_keys", not is_ignored)
        end,
    }

    common_settings.android_back_button = {
        text = _("Ignore back button completely"),
        checked_func = function() return android.isBackButtonIgnored() end,
        callback = function()
            local is_ignored = android.isBackButtonIgnored()
            android.setBackButtonIgnored(not is_ignored)
            G_reader_settings:saveSetting("android_ignore_back_button", not is_ignored)
        end,
    }

    -- ignore battery optimization
    if Device.firmware_rev >= 23 then
        common_settings.ignore_battery_optimizations = {
            text = _("Battery optimizations"),
            checked_func = function() return not android.settings.hasPermission("battery") end,
            callback = function()
                local text = _([[
Go to Android battery optimization settings?

You will be prompted with a permission management screen.

Please don't change any settings unless you know what you're doing.]])

                android.settings.requestPermission("battery", text, _("OK"), _("Cancel"))
            end,
        }
    end
end

common_settings.navigation = {
    text = _("Navigation"),
}
local back_to_exit_str = {
    prompt = {_("Prompt"), _("prompt")},
    always = {_("Always"), _("always")},
    disable ={_("Disable"), _("disable")},
}
local function genGenericMenuEntry(title, setting, value, default, radiomark)
    return {
        text = title,
        checked_func = function()
            return G_reader_settings:readSetting(setting, default) == value
        end,
        radio = radiomark,
        callback = function()
            G_reader_settings:saveSetting(setting, value)
        end,
    }
end
common_settings.back_to_exit = {
    text_func = function()
        local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt") -- set "back_to_exit" to "prompt"
        return T(_("Back to exit: %1"), back_to_exit_str[back_to_exit][2])
    end,
    sub_item_table = {
        genGenericMenuEntry(back_to_exit_str.prompt[1], "back_to_exit", "prompt"),
        genGenericMenuEntry(back_to_exit_str.always[1], "back_to_exit", "always"),
        genGenericMenuEntry(back_to_exit_str.disable[1], "back_to_exit", "disable"),
    },
}
common_settings.back_in_filemanager = {
    text_func = function()
        local menu_info = ""
        local back_in_filemanager = G_reader_settings:readSetting("back_in_filemanager", "default") -- set "back_in_filemanager" to "default"
        if back_in_filemanager == "default" then
            menu_info = _("back to exit")
        elseif back_in_filemanager == "parent_folder" then
            menu_info = _("parent folder")
        end
        return T(_("Back in file browser: %1"), menu_info)
    end,
    sub_item_table = {
        {
            text_func = function()
                local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt")
                return T(_("Back to exit (%1)"), back_to_exit_str[back_to_exit][2])
            end,
            checked_func = function()
                return G_reader_settings:readSetting("back_in_filemanager", "default") == "default"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_in_filemanager", "default")
            end,
        },
        genGenericMenuEntry(_("Go to parent folder"), "back_in_filemanager", "parent_folder"),
    },
}
common_settings.back_in_reader = {
    -- All these options are managed by ReaderBack
    text_func = function()
        local menu_info = ""
        local back_in_reader = G_reader_settings:readSetting("back_in_reader", "previous_location") -- set "back_in_reader" to "previous_location"
        if back_in_reader == "default" then
            menu_info = _("back to exit")
        elseif back_in_reader == "filebrowser" then
            menu_info = _("file browser")
        elseif back_in_reader == "previous_location" then
            menu_info = _("previous location")
        elseif back_in_reader == "previous_read_page" then
            menu_info = _("previous read page")
        end
        return T(_("Back in reader: %1"), menu_info)
    end,
    sub_item_table = {
        {
            text_func = function()
                local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt")
                return T(_("Back to exit (%1)"), back_to_exit_str[back_to_exit][2])
            end,
            checked_func = function()
                return G_reader_settings:readSetting("back_in_reader") == "default"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_in_reader", "default")
            end,
        },
        genGenericMenuEntry(_("Go to file browser"), "back_in_reader", "filebrowser"),
        genGenericMenuEntry(_("Go to previous location"), "back_in_reader", "previous_location"),
        genGenericMenuEntry(_("Go to previous read page"), "back_in_reader", "previous_read_page"),
    },
}
-- Kindle keyboard does not have a 'Backspace' key
if Device:hasKeyboard() and not Device:hasSymKey() then
    common_settings.backspace_as_back = {
        text = _("Backspace works as back button"),
        checked_func = function()
            return G_reader_settings:isTrue("backspace_as_back")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("backspace_as_back")
            UIManager:askForRestart()
        end,
    }
end

common_settings.opening_page_location_stack = {
    text = _("Add opening page to location history"),
    checked_func = function()
        return G_reader_settings:isTrue("opening_page_location_stack")
    end,
    callback = function()
        G_reader_settings:flipNilOrFalse("opening_page_location_stack")
    end,
}

local skim_dialog_position_string = {
    top    = _("Top"),
    center = _("Center"),
    bottom = _("Bottom"),
}
common_settings.skim_dialog_position = {
    text_func = function()
        local position = G_reader_settings:readSetting("skim_dialog_position") or "center"
        return T(_"Skim dialog position: %1", skim_dialog_position_string[position]:lower())
    end,
    sub_item_table = {
        genGenericMenuEntry(skim_dialog_position_string["top"],    "skim_dialog_position", "top"),
        genGenericMenuEntry(skim_dialog_position_string["center"], "skim_dialog_position", nil), -- default
        genGenericMenuEntry(skim_dialog_position_string["bottom"], "skim_dialog_position", "bottom"),
    },
}

-- Auto-save settings: default value, info text and warning, and menu items
if G_reader_settings:hasNot("auto_save_settings_interval_minutes") then
    -- Default to auto save every 15 mn
    G_reader_settings:saveSetting("auto_save_settings_interval_minutes", 15)
end

local auto_save_help_text = _([[
This sets how often to rewrite to disk global settings and book metadata, including your current position and any highlights and bookmarks made, when you're reading a document.

The normal behavior is to save those only when the document is closed, or your device suspended, or when exiting KOReader.

Setting it to some interval may help prevent losing new settings/sidecar data after a software crash, but will cause more I/O writes the lower the interval is, and may slowly wear out your storage media in the long run.]])

-- Some devices with FAT32 storage may not like having settings rewritten too often,
-- so let that be known. See https://github.com/koreader/koreader/pull/3625
local warn_about_auto_save = Device:isKobo() or Device:isKindle() or Device:isCervantes() or Device:isPocketBook() or Device:isSonyPRSTUX()
if warn_about_auto_save then
    local auto_save_help_warning = _([[Please be warned that on this device, setting a low interval may exacerbate the potential for filesystem corruption and complete data loss after a hardware crash.]])
    auto_save_help_text = auto_save_help_text .. "\n\n" .. auto_save_help_warning
end

local function genAutoSaveMenuItem(value)
    local setting_name = "auto_save_settings_interval_minutes"
    local text
    if not value then
        text = _("Only on close and suspend")
    else
        text = T(N_("Every minute", "Every %1 minutes", value), value)
    end
    return {
        text = text,
        help_text = auto_save_help_text,
        checked_func = function()
            return G_reader_settings:readSetting(setting_name) == value
        end,
        callback = function()
            G_reader_settings:saveSetting(setting_name, value)
        end,
    }
end

common_settings.document = {
    text = _("Document"),
    -- submenus are filled by menu_order
}

local metadata_folder_str = {
    ["doc"]  = _("book folder"),
    ["dir"]  = DocSettings.getSidecarStorage("dir"),
    ["hash"] = DocSettings.getSidecarStorage("hash"),
}

local metadata_folder_help_table = {
      _("Book view settings, reading progress, highlights, bookmarks and notes (collectively known as metadata) are stored in a separate folder named <book-filename>.sdr (\".sdr\" meaning \"sidecar\")."),
        "",
      _("You can decide between three locations/methods where these will be saved:"),
      _(" - alongside the book file itself (the long time default): sdr folders will be visible when you browse your library directories with another file browser or from your computer, which may clutter your vision of your library. But this allows you to move them along when you reorganize your library, and also survives any renaming of parent directories. Also, if you perform directory synchronization or backups, your settings will be part of them."),
    T(_(" - all in %1: sdr folders will only be visible and used by KOReader, and won't clutter your vision of your library directories with another file browser or from your computer. But any reorganisation of your library (directories or filename moves and renamings) may result in KOReader not finding your previous settings for these books. These settings won't be part of any synchronization or backups of your library."), metadata_folder_str.dir),
    T(_(" - all inside %1 as hashes: sdr folders are identified not by filepath/filename but by partial MD5 hash, allowing you to rename, move, and copy documents outside of KOReader without sdr folder clutter while keeping them linked to their metadata. However, any file modifications such as writing highlights into PDFs or downloading from calibre may change the hash, and thus lose their linked metadata. Calculating file hashes may also slow down file browser navigation. This option may suit users with multiple copies of documents across different devices and directories."), metadata_folder_str.hash),
}
local metadata_folder_help_text = table.concat(metadata_folder_help_table, "\n")

local hash_filemod_warn = T(_("%1 requires calculating partial file hashes of documents which may slow down file browser navigation. Any file modifications (such as embedding annotations into PDF files or downloading from calibre) may change the partial hash, thereby losing track of any highlights, bookmarks, and progress data. Embedding PDF annotations can be set at menu Typeset → Highlights → Write highlights into PDF."), metadata_folder_str.hash)
local leaving_hash_sdr_warn = _("Warning: You currently have documents with hash-based metadata. Until this metadata is moved by opening those documents, or deleted, file browser navigation may remain slower.")

local function genMetadataFolderMenuItem(value)
    return {
        text = metadata_folder_str[value],
        checked_func = function()
            return G_reader_settings:readSetting("document_metadata_folder") == value
        end,
        callback = function()
            local old_value = G_reader_settings:readSetting("document_metadata_folder")
            if value ~= old_value then
                G_reader_settings:saveSetting("document_metadata_folder", value)
                if value == "hash" then
                    DocSettings.setIsHashLocationEnabled(true)
                    UIManager:show(InfoMessage:new{ text = hash_filemod_warn, icon = "notice-warning" })
                else
                    DocSettings.setIsHashLocationEnabled(nil) -- reset
                    if DocSettings.isHashLocationEnabled() then
                        UIManager:show(InfoMessage:new{ text = leaving_hash_sdr_warn, icon = "notice-warning" })
                    end
                end
            end
        end,
        radio = true,
        separator = value == "hash",
    }
end

common_settings.document_metadata_location = {
    text_func = function()
        local value = G_reader_settings:readSetting("document_metadata_folder", "doc")
        return T(_("Book metadata location: %1"), metadata_folder_str[value])
    end,
    help_text = metadata_folder_help_text,
    sub_item_table = {
        {
            text = _("About book metadata location"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{ text = metadata_folder_help_text, })
            end,
            separator = true,
        },
        genMetadataFolderMenuItem("doc"),
        genMetadataFolderMenuItem("dir"),
        genMetadataFolderMenuItem("hash"),
        {
            text_func = function()
                local hash_text = _("Show documents with hash-based metadata")
                local no_hash_text = _("No documents with hash-based metadata")
                if DocSettings.isHashLocationEnabled() then
                    if G_reader_settings:readSetting("document_metadata_folder") ~= "hash" then
                        return  "⚠ " .. hash_text
                    end
                    return  hash_text
                end
                return no_hash_text
            end,
            keep_menu_open = true,
            enabled_func = function()
                return DocSettings.isHashLocationEnabled()
            end,
            callback = function()
                FileManagerBookInfo.showBooksWithHashBasedMetadata()
            end,
        },
    },
}

common_settings.document_auto_save = {
    text_func = function()
        local interval = G_reader_settings:readSetting("auto_save_settings_interval_minutes")
        local s_interval
        if interval == false then
            s_interval = _("only on close and suspend")
        else
            s_interval = T(N_("every 1 m", "every %1 m", interval), interval)
        end
        return T(_("Save book metadata: %1"), s_interval)
    end,
    help_text = auto_save_help_text,
    sub_item_table = {
        genAutoSaveMenuItem(false),
        genAutoSaveMenuItem(5),
        genAutoSaveMenuItem(15),
        genAutoSaveMenuItem(30),
        genAutoSaveMenuItem(60),
        warn_about_auto_save and {
            text = _("Important info about this auto-save option"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{ text = auto_save_help_text, })
            end,
        } or nil,
    },
    separator = true,
}

common_settings.document_end_action = {
    text = _("End of document action"),
    sub_item_table = {
        {
            text = _("Always mark as finished"),
            checked_func = function()
                return G_reader_settings:isTrue("end_document_auto_mark")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("end_document_auto_mark")
            end,
            separator = true,
        },
        genGenericMenuEntry(_("Ask with popup dialog"), "end_document_action", "pop-up", "pop-up", true),
        genGenericMenuEntry(_("Do nothing"), "end_document_action", "nothing", nil, true),
        genGenericMenuEntry(_("Book status"), "end_document_action", "book_status", nil, true),
        genGenericMenuEntry(_("Delete file"), "end_document_action", "delete_file", nil, true),
        {
            text = _("Open next file"),
            enabled_func = function()
                return G_reader_settings:readSetting("collate") ~= "access"
            end,
            checked_func = function()
                return G_reader_settings:readSetting("end_document_action") == "next_file"
            end,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting("end_document_action", "next_file")
            end,
        },
        genGenericMenuEntry(_("Go to beginning"), "end_document_action", "goto_beginning", nil, true),
        genGenericMenuEntry(_("Return to file browser"), "end_document_action", "file_browser", nil, true),
        genGenericMenuEntry(_("Mark book as finished"), "end_document_action", "mark_read", nil, true),
        genGenericMenuEntry(_("Book status and return to file browser"), "end_document_action", "book_status_file_browser", nil, true),
    }
}

common_settings.language = Language:getLangMenuTable()

common_settings.device = {
    text = _("Device"),
}

common_settings.keyboard_layout = {
    text = _("Keyboard"),
    sub_item_table = dofile("frontend/ui/elements/menu_keyboard_layout.lua"),
}

common_settings.font_ui_fallbacks = dofile("frontend/ui/elements/font_ui_fallbacks.lua")

common_settings.units = {
    text_func = function()
        local unit = G_reader_settings:readSetting("dimension_units", "mm")
        return T(_("Dimension units: %1"), unit)
    end,
    sub_item_table = {
        {
            text = _("Also show values in pixels"),
            checked_func = function()
                return G_reader_settings:isTrue("dimension_units_append_px")
            end,
            enabled_func = function()
                return G_reader_settings:readSetting("dimension_units") ~= "px"
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dimension_units_append_px")
            end,
            separator = true,
        },
        genGenericMenuEntry(_("Metric system"),   "dimension_units", "mm", nil, true),
        genGenericMenuEntry(_("Imperial system"), "dimension_units", "in", nil, true),
        genGenericMenuEntry(_("Pixels"),          "dimension_units", "px", nil, true),
    }
}

common_settings.screenshot = {
    text = _("Screenshot folder"),
    callback = function()
        local Screenshoter = require("ui/widget/screenshoter")
        Screenshoter:chooseFolder()
    end,
    keep_menu_open = true,
}

return common_settings
