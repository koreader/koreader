local order = {
    ["KOMenu:menu_buttons"] = {
        "navi",
        "typeset",
        "setting",
        "tools",
        "search",
        "filemanager",
        "main",
    },
    navi = {
        "table_of_contents",
        "bookmarks",
        "bookmark_browsing_mode",
        "----------------------------",
        "go_to",
        "skim_to",
        "----------------------------",
        "go_to_previous_location",
        "follow_links",
    },
    typeset = {
        "page_overlap",
        "switch_zoom_mode",
        "set_render_style",
        "----------------------------",
        "highlight_options",
        "----------------------------",
        "floating_punctuation",
        "change_font",
        "hyphenation",
        "----------------------------",
        "speed_reading_module_perception_expander",
    },
    setting = {
        "read_from_right_to_left",
        -- common settings
        -- those that don't exist will simply be skipped during menu gen
        "frontlight", -- if Device:hasFrontlight()
        "night_mode",
        "----------------------------",
        "network",
        "screen",
        "screensaver",
        "save_document",
        "----------------------------",
        "language",
        "time",
        "----------------------------",
        "djvu_render_mode",
        "status_bar",
    },
    tools = {
        "read_timer",
        "calibre_wireless_connection",
        "evernote",
        "statistics",
        "progress_sync",
        "zsync",
        "news_downloader",
        "----------------------------",
        "more_plugins",
    },
    more_plugins = {
        "auto_frontlight",
        "frontlight_gesture_controller",
        "battery_statistics",
        "synchronize_time",
        "keep_alive",
        "terminal",
        "storage_stat",
    },
    search = {
        "dictionary_lookup",
        "dictionary_lookup_history",
        "dictionary_settings",
        "----------------------------",
        "wikipedia_lookup",
        "wikipedia_history",
        "wikipedia_settings",
        "----------------------------",
        "goodreads",
        "----------------------------",
        "fulltext_search",
    },
    filemanager = {},
    main = {
        "history",
        "book_status",
        "book_info",
        "----------------------------",
        "system_statistics",
        "----------------------------",
        "ota_update", --[[ if Device:isKindle() or Device:isKobo() or
                           Device:isPocketBook() or Device:isAndroid() ]]--
        "version",
        "help",
        "----------------------------",
        "exit_menu",
    },
    help = {
        "quickstart_guide",
        "----------------------------",
        "report_bug",
        "----------------------------",
        "about",
    },
    exit_menu = {
        "restart_koreader",
        "----------------------------",
        "sleep", -- if Device:isKindle() or Device:isKobo()
        "poweroff", -- if Device:isKobo()
        "reboot",   -- if Device:isKobo()
        "----------------------------",
        "exit",
    }
}

return order
