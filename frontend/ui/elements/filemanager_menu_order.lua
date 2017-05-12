local order = {
    ["KOMenu:menu_buttons"] = {
        "setting",
        "tools",
        "search",
        "main",
    },
    setting = {
        "show_hidden_files",
        "----------------------------",
        "sort_by",
        "reverse_sorting",
        "----------------------------",
        "start_with_last_opened_file",
        "screensaver",
        "----------------------------",
        -- common settings
        -- those that don't exist will simply be skipped during menu gen
        "frontlight", -- if Device:hasFrontlight()
        "night_mode",
        "----------------------------",
        "network",
        "screen",
        "save_document",
        "----------------------------",
        "language",
        -- end common settings
    },
    tools = {
        "calibre_wireless_connection",
        "evernote",
        "keep_alive",
        "frontlight_gesture_controller",
        "statistics",
        "battery_statistics",
        "storage_stat",
        "cloud_storage",
        "read_timer",
        "news_downloader",
        "synchronize_time",
        "terminal",
        "----------------------------",
        "advanced_settings",
        "developer_options",
    },
    search = {
        "dictionary_lookup",
        "wikipedia_lookup",
        "----------------------------",
        "find_book_in_calibre_catalog",
        "find_file",
        "----------------------------",
        "goodreads",
        "opds_catalog",
    },
    main = {
        "history",
        "open_last_document",
        "----------------------------",
        "ota_update", -- if Device:isKindle() or Device:isKobo() or Device:isPocketBook() or Device:isAndroid()
        "version",
        "help",
        "system_statistics",
        "----------------------------",
        "exit",
    },
    help = {
        "quickstart_guide",
        "----------------------------",
        "report_bug",
        "----------------------------",
        "about",
    },
}

return order
