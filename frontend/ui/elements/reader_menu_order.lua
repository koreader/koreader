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
        "go_to",
        "skim_to",
        "follow_links",
    },
    typeset = {
        "page_overlap",
        "switch_zoom_mode",
        "set_render_style",
        "floating_punctuation",
        "highlight_options",
        "change_font",
        "hyphenation",
        "read_timer",
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
        "----------------------------",
        "djvu_render_mode",
        "status_bar",
    },
    tools = {
        "calibre_wireless_connection",
        "evernote",
        "goodreads",
        "keep_alive",
        "frontlight_gesture_controller",
        "statistics",
        "battery_statistics",
        "storage_stat",
        "speed_reading_module_perception_expander",
        "synchronize_time",
        "progress_sync",
        "zsync",
        "terminal",
    },
    search = {
        "dictionary_lookup",
        "wikipedia_lookup",
        "fulltext_search",
    },
    filemanager = {},
    main = {
        "history",
        "book_status",
        "----------------------------",
        "ota_update", -- if Device:isKindle() or Device:isKobo() or Device:isPocketBook() or Device:isAndroid()
        "version",
        "help",
        "system_statistics",
        "----------------------------",
        "exit",
    },
}

return order
