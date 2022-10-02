local DataStorage = require("datastorage")
local LuaData = require("luadata")

local Migration = {}

local custom_multiswipes_path = DataStorage:getSettingsDir().."/multiswipes.lua"
local custom_multiswipes = LuaData:open(custom_multiswipes_path, "MultiSwipes")
local custom_multiswipes_table = custom_multiswipes:readSetting("multiswipes")

function Migration:convertAction(location, ges, action)
    local result
    if action == "ignore" then
        result = nil
    elseif action == "nothing" then
        result = {}
    elseif action == "reading_progress" then
        result = {reading_progress = true,}
    elseif action == "book_statistics" then
        result = {book_statistics = true,}
    elseif action == "stats_calendar_view" then
        result = {stats_calendar_view = true,}
    elseif action == "toc" then
        result = {toc = true,}
    elseif action == "night_mode" then
        result = {night_mode = true,}
    elseif action == "full_refresh" then
        result = {full_refresh = true,}
    elseif action == "bookmarks" then
        result = {bookmarks = true,}
    elseif action == "history" then
        result = {history = true,}
    elseif action == "favorites" then
        result = {favorites = true,}
    elseif action == "book_info" then
        result = {book_info = true,}
    elseif action == "book_description" then
        result = {book_description = true,}
    elseif action == "book_cover" then
        result = {book_cover = true,}
    elseif action == "book_status" then
        result = {book_status = true}
    elseif action == "page_jmp_fwd_10" then
        result = {page_jmp = 10,}
    elseif action == "page_jmp_fwd_1" then
        result = {page_jmp = 1,}
    elseif action == "page_jmp_back_10" then
        result = {page_jmp = -10,}
    elseif action == "page_jmp_back_1" then
        result = {page_jmp = -1,}
    elseif action == "next_chapter" then
        result = {next_chapter = true,}
    elseif action == "first_page" then
        result = {first_page = true,}
    elseif action == "last_page" then
        result = {last_page = true,}
    elseif action == "prev_chapter" then
        result = {prev_chapter = true,}
    elseif action == "next_bookmark" then
        result = {next_bookmark = true,}
    elseif action == "prev_bookmark" then
        result = {prev_bookmark = true,}
    elseif action == "go_to" then
        result = {go_to = true,}
    elseif action == "skim" then
        result = {skim = true,}
    elseif action == "back" then
        result = { back = true,}
    elseif action == "previous_location" then
        result = {previous_location = true,}
    elseif action == "latest_bookmark" then
        result = {latest_bookmark = true,}
    elseif action == "follow_nearest_link" then
        result = {follow_nearest_link = true,}
    elseif action == "follow_nearest_internal_link" then
        result = {follow_nearest_internal_link = true,}
    elseif action == "clear_location_history" then
        result = {clear_location_history = true,}
    elseif action == "filemanager" then
        result = {filemanager = true,}
    elseif action == "file_search" then
        result = {file_search = true,}
    elseif action == "folder_up" then
        result = {folder_up = true,}
    elseif action == "show_plus_menu" then
        result = {show_plus_menu = true,}
    elseif action == "folder_shortcuts" then
        result = {folder_shortcuts = true,}
    elseif action == "open_previous_document" then
        result = {open_previous_document = true,}
    elseif action == "dictionary_lookup" then
        result = {dictionary_lookup = true,}
    elseif action == "wikipedia_lookup" then
        result = {wikipedia_lookup = true,}
    elseif action == "fulltext_search" then
        result = {fulltext_search = true,}
    elseif action == "show_menu" then
        result = {show_menu = true,}
    elseif action == "show_config_menu" then
        result = {show_config_menu = true,}
    elseif action == "show_frontlight_dialog" then
        result = {show_frontlight_dialog = true,}
    elseif action == "increase_frontlight" then
        result = {increase_frontlight = 0,}
    elseif action == "decrease_frontlight" then
        result = {decrease_frontlight = 0,}
    elseif action == "increase_frontlight_warmth" then
        result = {increase_frontlight_warmth = 0,}
    elseif action == "decrease_frontlight_warmth" then
        result = {decrease_frontlight_warmth = 0,}
    elseif action == "toggle_bookmark" then
        result = {toggle_bookmark = true,}
    elseif action == "toggle_inverse_reading_order" then
        result = {toggle_inverse_reading_order = true,}
    elseif action == "toggle_frontlight" then
        result = {toggle_frontlight = true,}
    elseif action == "toggle_hold_corners" then
        result = {toggle_hold_corners = true,}
    elseif action == "toggle_gsensor" then
        result = {toggle_gsensor = true,}
    elseif action == "toggle_page_flipping" then
        result = {toggle_page_flipping = true,}
    elseif action == "toggle_reflow" then
        result = {toggle_reflow = true,}
    elseif action == "toggle_rotation" then
        result = {toggle_rotation = true,}
    elseif action == "toggle_wifi" then
        result = {toggle_wifi = true,}
    elseif action == "wifi_off" then
        result = {wifi_off = true,}
    elseif action == "wifi_on" then
        result = {wifi_on = true,}
    elseif action == "increase_font" then
        result = {increase_font = 0,}
    elseif action == "decrease_font" then
        result = {decrease_font = 0,}
    elseif action == "suspend" then
        result = {suspend = true,}
    elseif action == "exit" then
        result = {exit = true,}
    elseif action == "restart" then
        result = {restart = true,}
    elseif action == "reboot" then
        result = {reboot = true,}
    elseif action == "poweroff" then
        result = {poweroff = true,}
    elseif action == "zoom_contentwidth" then
        result = {zoom = "contentwidth",}
    elseif action == "zoom_contentheight" then
        result = {zoom = "contentheight",}
    elseif action == "zoom_pagewidth" then
        result = {zoom = "pagewidth",}
    elseif action == "zoom_pageheight" then
        result = {zoom = "pageheight",}
    elseif action == "zoom_column" then
        result = {zoom = "column",}
    elseif action == "zoom_content" then
        result = {zoom = "content",}
    elseif action == "zoom_page" then
        result = {zoom = "page",}
    elseif action == "wallabag_download" then
        result = {wallabag_download = true,}
    elseif action == "cycle_highlight_action" then
        result = {cycle_highlight_action = true,}
    elseif action == "cycle_highlight_style" then
        result = {cycle_highlight_style = true,}
    elseif action == "kosync_push_progress" then
        result = {kosync_push_progress = true,}
    elseif action == "kosync_pull_progress" then
        result = {kosync_pull_progress = true,}
    elseif action == "calibre_search" then
        result = {calibre_search = true,}
    elseif action == "calibre_browse_tags" then
        result = {calibre_browse_tags = true,}
    elseif action == "calibre_browse_series" then
        result = {calibre_browse_series = true,}
    else return end
    location[ges] = result
end

function Migration:migrateGestures(caller)
    for _, ges_mode in ipairs({"gesture_fm", "gesture_reader"}) do
        local ges_mode_setting = G_reader_settings:readSetting(ges_mode)
        if ges_mode_setting then
            for k, v in pairs(ges_mode_setting) do
                Migration:convertAction(caller.settings_data.data[ges_mode], k, v)
            end
            caller.settings_data:flush()
            G_reader_settings:delSetting(ges_mode)
        end
    end
    -- custom multiswipes
    if custom_multiswipes_table then
        for k, v in pairs(custom_multiswipes_table) do
            local multiswipe = "multiswipe_" .. caller:safeMultiswipeName(v)
            caller.settings_data.data.custom_multiswipes[multiswipe] = true
        end
    end
    caller.settings_data:flush()
    G_reader_settings:makeTrue("gestures_migrated")
end

return Migration
