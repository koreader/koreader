local order = {
    ["KOMenu:menu_buttons"] = {
        "setting",
        "tools",
        "search",
        "main",
    },
    setting = {
        "filemanager_display_mode",
        "show_hidden_files",
        "items_per_page",
        "----------------------------",
        "sort_by",
        "reverse_sorting",
        "----------------------------",
        "start_with",
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
        "time",
        -- end common settings
    },
    tools = {
        "calibre_wireless_connection",
        "evernote",
        "statistics",
        "storage_stat",
        "cloud_storage",
        "read_timer",
        "news_downloader",
        "----------------------------",
        "more_plugins",
        "----------------------------",
        "advanced_settings",
        "developer_options",
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
