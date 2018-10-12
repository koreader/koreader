local order = {
    ["KOMenu:menu_buttons"] = {
        "filemanager_settings",
        "setting",
        "tools",
        "search",
        "plus_menu",
        "main",
    },
    filemanager_settings = {
        "filemanager_display_mode",
        "show_hidden_files",
        "items_per_page",
        "----------------------------",
        "sort_by",
        "reverse_sorting",
        "----------------------------",
        "start_with",
    },
    setting = {
        -- common settings
        -- those that don't exist will simply be skipped during menu gen
        "frontlight", -- if Device:hasFrontlight()
        "night_mode",
        "----------------------------",
        "network",
        "screen",
        "screensaver",
        "document",
        "navigation",
        "----------------------------",
        "language",
        "device",
        -- end common settings
    },
    device = {
        "time",
        "battery",
        "gesture",
    },
    network = {
        "network_wifi",
        "network_proxy",
        "network_restore",
        "network_info",
        "network_before_wifi_action",
        "network_dismiss_scan",
        "----------------------------",
        "ssh",
    },
    tools = {
	"wallabag",
        "calibre_wireless_connection",
        "evernote",
        "statistics",
        "cloud_storage",
        "read_timer",
        "news_downloader",
        "send2ebook",
        "text_editor",
        "----------------------------",
        "more_plugins",
        "plugin_management",
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
        "ota_update", -- if Device:hasOTAUpdates()
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
    plus_menu = {},
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
