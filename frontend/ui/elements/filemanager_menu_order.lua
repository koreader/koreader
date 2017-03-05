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
        "----------------------------",
        "show_advanced_options",
        -- end common settings
    },
    tools = {
        "calibre_wireless_connection",
        "evernote",
        "goodreads",
        "keep_alive",
        "statistics",
        "storage_stat",
        "cloud_storage",
        "----------------------------",
        "advanced_settings",
        "developer_options",
    },
    search = {
        "dictionary_lookup",
        "find_book_in_calibre_catalog",
        "find_file",
        "----------------------------",
        "opds_catalog",
    },
    main = {
        "history",
        "open_last_document",
        "----------------------------",
        "ota_update", -- if Device:isKindle() or Device:isKobo() or Device:isPocketBook() or Device:isAndroid()
        "version",
        "help",
        "----------------------------",
        "exit",
    },
}

return order
