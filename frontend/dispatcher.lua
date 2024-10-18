--[[--
This module is responsible for dispatching events.

To add a new action an entry must be added to `settingsList` & `dispatcher_menu_order`
This can also be done at runtime via @{registerAction}().

`settingsList` contains the list of dispatchable settings.

Each setting contains:

* category: one of:
    * none: a direct event call
    * arg: a event that expects a gesture object or an argument
    * absolutenumber: event that sets a number
    * incrementalnumber: event that increments a number & accepts a gesture object
    * string: event with a list of arguments to chose from
    * configurable: like string but instead of an event it updates the configurable (used by kopt)
* event: what to call.
* title: for use in ui.
* section: under which menu to display (currently: general, device, screen, filemanager, reader, rolling, paging)
    and optionally
* min/max: for number
* step: for number
* default
* args: allowed values for string.
* toggle: display name for args
* separator: put a separator after in the menu list
* configurable: can be parsed from cre/kopt and used to set `document.configurable`. Should not be set manually
--]]--

local CreOptions = require("ui/data/creoptions")
local KoptOptions = require("ui/data/koptoptions")
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local Notification = require("ui/widget/notification")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local NC_ = _.npgettext
local T = require("ffi/util").template

local Dispatcher = {
    initialized = false,
}

-- See above for description.
local settingsList = {
    -- General
    reading_progress = {category="none", event="ShowReaderProgress", title=_("Reading progress"), general=true},
    open_previous_document = {category="none", event="OpenLastDoc", title=_("Open previous document"), general=true},
    history = {category="none", event="ShowHist", title=_("History"), general=true},
    history_search = {category="none", event="SearchHistory", title=_("History search"), general=true},
    favorites = {category="none", event="ShowColl", title=_("Favorites"), general=true},
    collections = {category="none", event="ShowCollList", title=_("Collections"), general=true},
    filemanager = {category="none", event="Home", title=_("File browser"), general=true, separator=true},
    ----
    dictionary_lookup = {category="none", event="ShowDictionaryLookup", title=_("Dictionary lookup"), general=true},
    wikipedia_lookup = {category="none", event="ShowWikipediaLookup", title=_("Wikipedia lookup"), general=true, separator=true},
    ----
    show_menu = {category="none", event="ShowMenu", title=_("Show menu"), general=true},
    menu_search = {category="none", event="MenuSearch", title=_("Menu search"), general=true},
    screenshot = {category="none", event="Screenshot", title=_("Screenshot"), general=true, separator=true},
    ----

    -- Device
    exit_screensaver = {category="none", event="ExitScreensaver", title=_("Exit sleep screen"), device=true},
    start_usbms = {category="none", event="RequestUSBMS", title=_("Start USB storage"), device=true, condition=Device:canToggleMassStorage()},
    suspend = {category="none", event="RequestSuspend", title=_("Sleep"), device=true, condition=Device:canSuspend()},
    restart = {category="none", event="Restart", title=_("Restart KOReader"), device=true, condition=Device:canRestart()},
    reboot = {category="none", event="RequestReboot", title=_("Reboot the device"), device=true, condition=Device:canReboot()},
    poweroff = {category="none", event="RequestPowerOff", title=_("Power off"), device=true, condition=Device:canPowerOff()},
    exit = {category="none", event="Exit", title=_("Exit KOReader"), device=true, separator=true},
    ----
    toggle_hold_corners = {category="none", event="IgnoreHoldCorners", title=_("Toggle long-press on corners"), device=true, condition=Device:isTouchDevice()},
    touch_input_on = {category="none", event="IgnoreTouchInput", arg=false, title=_("Enable touch input"), device=true, condition=Device:isTouchDevice()},
    touch_input_off = {category="none", event="IgnoreTouchInput", arg=true, title=_("Disable touch input"), device=true, condition=Device:isTouchDevice()},
    toggle_touch_input = {category="none", event="IgnoreTouchInput", title=_("Toggle touch input"), device=true, separator=true, condition=Device:isTouchDevice()},
    ----
    swap_left_page_turn_buttons = {category="none", event="SwapPageTurnButtons", arg="left", title=_("Invert left-side page-turn buttons"), device=true, condition= Device:hasDPad() and Device:useDPadAsActionKeys()},
    swap_right_page_turn_buttons = {category="none", event="SwapPageTurnButtons", arg="right", title=_("Invert right-side page-turn buttons"), device=true, condition= Device:hasDPad() and Device:useDPadAsActionKeys()},
    swap_page_turn_buttons = {category="none", event="SwapPageTurnButtons", title=_("Invert page-turn buttons"), device=true, condition=Device:hasKeys(), separator=true},
    ----
    toggle_key_repeat = {category="none", event="ToggleKeyRepeat", title=_("Toggle key repeat"), device=true, condition=Device:hasKeys() and Device:canKeyRepeat(), separator=true},
    toggle_gsensor = {category="none", event="ToggleGSensor", title=_("Toggle accelerometer"), device=true, condition=Device:hasGSensor()},
    temp_gsensor_on = {category="none", event="TempGSensorOn", title=_("Enable accelerometer for 5 seconds"), device=true, condition=Device:hasGSensor()},
    lock_gsensor = {category="none", event="LockGSensor", title=_("Lock auto rotation to current orientation"), device=true, condition=Device:hasGSensor()},
    toggle_rotation = {category="none", event="SwapRotation", title=_("Toggle orientation"), device=true},
    invert_rotation = {category="none", event="InvertRotation", title=_("Invert rotation"), device=true},
    iterate_rotation = {category="none", event="IterateRotation", title=_("Rotate by 90° CW"), device=true},
    iterate_rotation_ccw = {category="none", event="IterateRotation", arg=true, title=_("Rotate by 90° CCW"), device=true, separator=true},
    ----
    wifi_on = {category="none", event="InfoWifiOn", title=_("Turn on Wi-Fi"), device=true, condition=Device:hasWifiToggle()},
    wifi_off = {category="none", event="InfoWifiOff", title=_("Turn off Wi-Fi"), device=true, condition=Device:hasWifiToggle()},
    toggle_wifi = {category="none", event="ToggleWifi", title=_("Toggle Wi-Fi"), device=true, condition=Device:hasWifiToggle()},
    toggle_fullscreen = {category="none", event="ToggleFullscreen", title=_("Toggle Fullscreen"), device=true, condition=not Device:isAlwaysFullscreen()},
    show_network_info = {category="none", event="ShowNetworkInfo", title=_("Show network info"), device=true, separator=true},
    ----

    -- Screen and lights
    show_frontlight_dialog = {category="none", event="ShowFlDialog", title=_("Show frontlight dialog"), screen=true, condition=Device:hasFrontlight()},
    toggle_frontlight = {category="none", event="ToggleFrontlight", title=_("Toggle frontlight"), screen=true, condition=Device:hasFrontlight()},
    set_frontlight = {category="absolutenumber", event="SetFlIntensity", min=0, max=Device:getPowerDevice().fl_max, title=_("Set frontlight brightness"), screen=true, condition=Device:hasFrontlight()},
    increase_frontlight = {category="incrementalnumber", event="IncreaseFlIntensity", min=1, max=Device:getPowerDevice().fl_max, title=_("Increase frontlight brightness"), screen=true, condition=Device:hasFrontlight()},
    decrease_frontlight = {category="incrementalnumber", event="DecreaseFlIntensity", min=1, max=Device:getPowerDevice().fl_max, title=_("Decrease frontlight brightness"), screen=true, condition=Device:hasFrontlight()},
    set_frontlight_warmth = {category="absolutenumber", event="SetFlWarmth", min=0, max=100, title=_("Set frontlight warmth"), screen=true, condition=Device:hasNaturalLight()},
    increase_frontlight_warmth = {category="incrementalnumber", event="IncreaseFlWarmth", min=1, max=Device:getPowerDevice().fl_warmth_max, title=_("Increase frontlight warmth"), screen=true, condition=Device:hasNaturalLight()},
    decrease_frontlight_warmth = {category="incrementalnumber", event="DecreaseFlWarmth", min=1, max=Device:getPowerDevice().fl_warmth_max, title=_("Decrease frontlight warmth"), screen=true, condition=Device:hasNaturalLight(), separator=true},
    night_mode = {category="none", event="ToggleNightMode", title=_("Toggle night mode"), screen=true},
    set_night_mode = {category="string", event="SetNightMode", title=_("Set night mode"), screen=true, args={true, false}, toggle={_("on"), _("off")}, separator=true},
    ----
    full_refresh = {category="none", event="FullRefresh", title=_("Full screen refresh"), screen=true},
    set_refresh_rate = {category="absolutenumber", event="SetBothRefreshRates", min=-1, max=200, title=_("Full refresh rate (always)"), screen=true, condition=Device:hasEinkScreen()},
    set_day_refresh_rate = {category="absolutenumber", event="SetDayRefreshRate", min=-1, max=200, title=_("Full refresh rate (not in night mode)"), screen=true, condition=Device:hasEinkScreen()},
    set_night_refresh_rate = {category="absolutenumber", event="SetNightRefreshRate", min=-1, max=200, title=_("Full refresh rate (in night mode)"), screen=true, condition=Device:hasEinkScreen()},
    set_flash_on_chapter_boundaries = {category="string", event="SetFlashOnChapterBoundaries", title=_("Always flash on chapter boundaries"), screen=true, condition=Device:hasEinkScreen(), args={true, false}, toggle={_("on"), _("off")}},
    toggle_flash_on_chapter_boundaries = {category="none", event="ToggleFlashOnChapterBoundaries", title=_("Toggle flashing on chapter boundaries"), screen=true, condition=Device:hasEinkScreen()},
    set_no_flash_on_second_chapter_page = {category="string", event="SetNoFlashOnSecondChapterPage", title=_("Never flash on chapter's 2nd page"), screen=true, condition=Device:hasEinkScreen(), args={true, false}, toggle={_("on"), _("off")}},
    toggle_no_flash_on_second_chapter_page = {category="none", event="ToggleNoFlashOnSecondChapterPage", title=_("Toggle flashing on chapter's 2nd page"), screen=true, condition=Device:hasEinkScreen()},
    set_flash_on_pages_with_images = {category="string", event="SetFlashOnPagesWithImages", title=_("Always flash on pages with images"), screen=true, condition=Device:hasEinkScreen(), args={true, false}, toggle={_("on"), _("off")}},
    toggle_flash_on_pages_with_images = {category="none", event="ToggleFlashOnPagesWithImages", title=_("Toggle flashing on pages with images"), screen=true, condition=Device:hasEinkScreen(), separator=true},
    ----

    -- File browser
    set_display_mode = {category="string", event="SetDisplayMode", title=_("Set display mode"), args_func=FileManager.getDisplayModeActions, filemanager=true},
    set_sort_by = {category="string", event="SetSortBy", title=_("Sort by"), args_func=FileManager.getSortByActions, filemanager=true},
    set_reverse_sorting = {category="string", event="SetReverseSorting", title=_("Reverse sorting"), args={true, false}, toggle={_("on"), _("off")}, filemanager=true},
    set_mixed_sorting = {category="string", event="SetMixedSorting", title=_("Folders and files mixed"), args={true, false}, toggle={_("on"), _("off")}, filemanager=true, separator=true},
    ----
    show_plus_menu = {category="none", event="ShowPlusMenu", title=_("Show plus menu"), filemanager=true},
    toggle_select_mode = {category="none", event="ToggleSelectMode", title=_("Toggle select mode"), filemanager=true},
    refresh_content = {category="none", event="RefreshContent", title=_("Refresh content"), filemanager=true},
    folder_shortcuts = {category="none", event="ShowFolderShortcutsDialog", title=_("Folder shortcuts"), filemanager=true},
    file_search = {category="none", event="ShowFileSearch", title=_("File search"), filemanager=true},
    file_search_results = {category="none", event="ShowSearchResults", title=_("Last file search results"), filemanager=true},
    ----
    folder_up = {category="none", event="FolderUp", title=_("Folder up"), filemanager=true},
    -- go_to
    -- back

    -- Reader
    open_next_document_in_folder = {category="none", event="OpenNextDocumentInFolder", title=_("Open next document in folder"), reader=true, separator=true},
    ----
    show_config_menu = {category="none", event="ShowConfigMenu", title=_("Show bottom menu"), reader=true},
    toggle_status_bar = {category="none", event="ToggleFooterMode", title=_("Toggle status bar"), reader=true},
    toggle_chapter_progress_bar = {category="none", event="ToggleChapterProgressBar", title=_("Toggle chapter progress bar"), reader=true, separator=true},
    ----
    prev_chapter = {category="none", event="GotoPrevChapter", title=_("Previous chapter"), reader=true},
    next_chapter = {category="none", event="GotoNextChapter", title=_("Next chapter"), reader=true},
    first_page = {category="none", event="GoToBeginning", title=_("First page"), reader=true},
    last_page = {category="none", event="GoToEnd", title=_("Last page"), reader=true},
    random_page = {category="none", event="GoToRandomPage", title=_("Random page"), reader=true},
    page_jmp = {category="absolutenumber", event="GotoViewRel", min=-100, max=100, title=_("Turn pages"), reader=true},
    go_to = {category="none", event="ShowGotoDialog", title=_("Go to page"), filemanager=true, reader=true},
    skim = {category="none", event="ShowSkimtoDialog", title=_("Skim document"), reader=true},
    prev_bookmark = {category="none", event="GotoPreviousBookmarkFromPage", title=_("Previous bookmark"), reader=true},
    next_bookmark = {category="none", event="GotoNextBookmarkFromPage", title=_("Next bookmark"), reader=true},
    first_bookmark = {category="none", event="GotoFirstBookmark", title=_("First bookmark"), reader=true},
    last_bookmark = {category="none", event="GotoLastBookmark", title=_("Last bookmark"), reader=true},
    latest_bookmark = {category="none", event="GoToLatestBookmark", title=_("Latest bookmark"), reader=true, separator=true},
    ----
    back = {category="none", event="Back", title=_("Back"), filemanager=true, reader=true},
    previous_location = {category="none", event="GoBackLink", arg=true, title=_("Back to previous location"), reader=true},
    next_location = {category="none", event="GoForwardLink", arg=true, title=_("Forward to next location"), reader=true},
    follow_nearest_link = {category="arg", event="GoToPageLink", arg={pos={x=0,y=0}}, title=_("Follow nearest link"), reader=true},
    follow_nearest_internal_link = {category="arg", event="GoToInternalPageLink", arg={pos={x=0,y=0}}, title=_("Follow nearest internal link"), reader=true},
    select_prev_page_link = { category="none", event = "SelectPrevPageLink", title=_("Select previous link in current page"), reader=true, condition=not Device:isTouchDevice()},
    select_next_page_link = { category="none", event = "SelectNextPageLink", title=_("Select next link in current page"), reader=true, condition=not Device:isTouchDevice()},
    add_location_to_history = {category="none", event="AddCurrentLocationToStack", arg=true, title=_("Add current location to history"), reader=true},
    clear_location_history = {category="none", event="ClearLocationStack", arg=true, title=_("Clear location history"), reader=true, separator=true},
    ----
    fulltext_search = {category="none", event="ShowFulltextSearchInput", title=_("Fulltext search"), reader=true},
    fulltext_search_findall_results = {category="none", event="ShowFindAllResults", title=_("Last fulltext search results"), reader=true},
    toc = {category="none", event="ShowToc", title=_("Table of contents"), reader=true},
    book_map = {category="none", event="ShowBookMap", title=_("Book map"), reader=true, condition=Device:isTouchDevice() or (Device:hasDPad() and Device:useDPadAsActionKeys())},
    book_map_overview = {category="none", event="ShowBookMap", arg=true, title=_("Book map (overview)"), reader=true, condition=Device:isTouchDevice() or (Device:hasDPad() and Device:useDPadAsActionKeys())},
    page_browser = {category="none", event="ShowPageBrowser", title=_("Page browser"), reader=true, condition=Device:isTouchDevice()},
    bookmarks = {category="none", event="ShowBookmark", title=_("Bookmarks"), reader=true},
    bookmark_search = {category="none", event="SearchBookmark", title=_("Bookmark search"), reader=true},
    toggle_bookmark = {category="none", event="ToggleBookmark", title=_("Toggle bookmark"), reader=true, separator=true},
    ----
    book_status = {category="none", event="ShowBookStatus", title=_("Book status"), reader=true},
    book_info = {category="none", event="ShowBookInfo", title=_("Book information"), reader=true},
    book_description = {category="none", event="ShowBookDescription", title=_("Book description"), reader=true},
    book_cover = {category="none", event="ShowBookCover", title=_("Book cover"), reader=true, separator=true},
    ----
    translate_page = {category="none", event="TranslateCurrentPage", title=_("Translate current page"), reader=true, separator=true},
    ----
    toggle_page_change_animation = {category="none", event="TogglePageChangeAnimation", title=_("Toggle page turn animations"), reader=true, condition=Device:canDoSwipeAnimation()},
    toggle_inverse_reading_order = {category="none", event="ToggleReadingOrder", title=_("Toggle page turn direction"), reader=true, condition=Device:isTouchDevice()},
    toggle_handmade_toc = {category="none", event="ToggleHandmadeToc", title=_("Toggle custom TOC"), reader=true, condition=Device:isTouchDevice()},
    toggle_handmade_flows = {category="none", event="ToggleHandmadeFlows", title=_("Toggle custom hidden flows"), reader=true, separator=true, condition=Device:isTouchDevice()},
    ----
    set_highlight_action = {category="string", event="SetHighlightAction", title=_("Set highlight action"), args_func=ReaderHighlight.getHighlightActions, reader=true},
    cycle_highlight_action = {category="none", event="CycleHighlightAction", title=_("Cycle highlight action"), reader=true},
    cycle_highlight_style = {category="none", event="CycleHighlightStyle", title=_("Cycle highlight style"), reader=true, separator=true},
    ----
    flush_settings = {category="none", event="FlushSettings", arg=true, title=_("Save book metadata"), reader=true, separator=true},
    ----

    -- Reflowable documents
    set_font = {category="string", event="SetFont", title=_("Font face"), rolling=true, args_func=require("fontlist").getFontArgFunc,},
    increase_font = {category="incrementalnumber", event="IncreaseFontSize", min=0.5, max=255, step=0.5, title=_("Increase font size"), rolling=true},
    decrease_font = {category="incrementalnumber", event="DecreaseFontSize", min=0.5, max=255, step=0.5, title=_("Decrease font size"), rolling=true},

    -- Fixed layout documents
    toggle_page_flipping = {category="none", event="TogglePageFlipping", title=_("Toggle page flipping"), paging=true},
    toggle_bookmark_flipping = {category="none", event="ToggleBookmarkFlipping", title=_("Toggle bookmark flipping"), paging=true},
    toggle_reflow = {category="none", event="ToggleReflow", title=_("Toggle reflow"), paging=true},
    zoom = {category="string", event="SetZoomMode", title=_("Zoom mode"), args_func=ReaderZooming.getZoomModeActions, paging=true},
    zoom_factor_change = {category="none", event="ZoomFactorChange", title=_("Change zoom factor"), paging=true, separator=true},
    ----
    panel_zoom_toggle = {category="none", event="TogglePanelZoomSetting", title=_("Toggle panel zoom"), paging=true, separator=true},
    ----

    -- parsed from CreOptions
    rotation_mode = {category="string", device=true},
    font_size = {category="absolutenumber", rolling=true, title=_("Font size"), step=0.5},
    word_spacing = {category="string", rolling=true},
    word_expansion = {category="string", rolling=true},
    font_gamma = {category="string", rolling=true},
    font_base_weight = {category="string", rolling=true},
    font_hinting = {category="string", rolling=true},
    font_kerning = {category="string", rolling=true, separator=true},
    ----
    visible_pages = {category="string", rolling=true, separator=true},
    ----
    h_page_margins = {category="string", rolling=true},
    sync_t_b_page_margins = {category="string", rolling=true},
    t_page_margin = {category="absolutenumber", rolling=true},
    b_page_margin = {category="absolutenumber", rolling=true, separator=true},
    ----
    view_mode = {category="string", rolling=true},
    block_rendering_mode = {category="string", rolling=true},
    render_dpi = {category="string", title=_("Zoom"), rolling=true},
    line_spacing = {category="absolutenumber", rolling=true, separator=true},
    ----
    status_line = {category="string", rolling=true},
    embedded_css = {category="string", rolling=true},
    embedded_fonts = {category="string", rolling=true},
    smooth_scaling = {category="string", rolling=true},
    nightmode_images = {category="string", rolling=true},

    -- parsed from KoptOptions
    kopt_trim_page = {category="string", paging=true},
    kopt_page_margin = {category="string", paging=true},
    kopt_zoom_overlap_h = {category="absolutenumber", paging=true},
    kopt_zoom_overlap_v = {category="absolutenumber", paging=true},
    kopt_zoom_mode_type = {category="string", paging=true},
    -- kopt_zoom_range_number = {category="string", paging=true},
    kopt_zoom_factor = {category="string", paging=true},
    kopt_zoom_mode_genus = {category="string", paging=true},
    kopt_zoom_direction = {category="string", paging=true},
    kopt_page_scroll = {category="string", paging=true},
    kopt_page_gap_height = {category="string", paging=true},
    kopt_full_screen = {category="string", paging=true},
    kopt_line_spacing = {category="configurable", paging=true},
    kopt_justification = {category="configurable", paging=true},
    kopt_font_size = {category="string", paging=true, title=_("Font Size")},
    kopt_font_fine_tune = {category="string", paging=true, title=_("Change font size")},
    kopt_word_spacing = {category="configurable", paging=true},
    kopt_text_wrap = {category="string", paging=true},
    kopt_contrast = {category="string", paging=true},
    kopt_page_opt = {category="configurable", paging=true},
    kopt_hw_dithering = {category="configurable", paging=true},
    kopt_sw_dithering = {category="configurable", paging=true},
    kopt_quality = {category="configurable", paging=true},
    kopt_doc_language = {category="string", paging=true},
    kopt_forced_ocr = {category="configurable", paging=true},
    kopt_writing_direction = {category="configurable", paging=true},
    kopt_defect_size = {category="string", paging=true},
    kopt_detect_indent = {category="configurable", paging=true},
    kopt_max_columns = {category="configurable", paging=true},
    kopt_auto_straighten = {category="absolutenumber", paging=true},

    settings = nil, -- reserved for per instance dispatcher settings
}

-- array for item order in menu
local dispatcher_menu_order = {
    -- General
    "reading_progress",
    "open_previous_document",
    "history",
    "history_search",
    "favorites",
    "collections",
    "filemanager",
    ----
    "dictionary_lookup",
    "wikipedia_lookup",
    ----
    "show_menu",
    "menu_search",
    "screenshot",
    ----

    -- Device
    "exit_screensaver",
    "start_usbms",
    "suspend",
    "restart",
    "reboot",
    "poweroff",
    "exit",
    ----
    "toggle_hold_corners",
    "touch_input_on",
    "touch_input_off",
    "toggle_touch_input",
    ----
    "swap_page_turn_buttons",
    "swap_left_page_turn_buttons",
    "swap_right_page_turn_buttons",
    ----
    "toggle_key_repeat",
    "toggle_gsensor",
    "temp_gsensor_on",
    "lock_gsensor",
    "rotation_mode",
    "toggle_rotation",
    "invert_rotation",
    "iterate_rotation",
    "iterate_rotation_ccw",
    ----
    "wifi_on",
    "wifi_off",
    "toggle_wifi",
    "toggle_fullscreen",
    "show_network_info",
    ----

    -- Screen and lights
    "show_frontlight_dialog",
    "toggle_frontlight",
    "set_frontlight",
    "increase_frontlight",
    "decrease_frontlight",
    "set_frontlight_warmth",
    "increase_frontlight_warmth",
    "decrease_frontlight_warmth",
    "night_mode",
    "set_night_mode",
    ----
    "full_refresh",
    "set_refresh_rate",
    "set_day_refresh_rate",
    "set_night_refresh_rate",
    "set_flash_on_chapter_boundaries",
    "toggle_flash_on_chapter_boundaries",
    "set_no_flash_on_second_chapter_page",
    "toggle_no_flash_on_second_chapter_page",
    "set_flash_on_pages_with_images",
    "toggle_flash_on_pages_with_images",
    ----

    -- File browser
    "set_display_mode",
    "set_sort_by",
    "set_reverse_sorting",
    "set_mixed_sorting",
    ----
    "show_plus_menu",
    "toggle_select_mode",
    "refresh_content",
    "folder_shortcuts",
    "file_search",
    "file_search_results",
    ----
    "folder_up",
    -- "go_to"
    -- "back"

    -- Reader
    "open_next_document_in_folder",
    ----
    "show_config_menu",
    "toggle_status_bar",
    "toggle_chapter_progress_bar",
    ----
    "prev_chapter",
    "next_chapter",
    "first_page",
    "last_page",
    "random_page",
    "page_jmp",
    "go_to",
    "skim",
    "prev_bookmark",
    "next_bookmark",
    "first_bookmark",
    "last_bookmark",
    "latest_bookmark",
    ----
    "back",
    "previous_location",
    "next_location",
    "follow_nearest_link",
    "follow_nearest_internal_link",
    "select_prev_page_link",
    "select_next_page_link",
    "add_location_to_history",
    "clear_location_history",
    ----
    "fulltext_search",
    "fulltext_search_findall_results",
    "toc",
    "book_map",
    "book_map_overview",
    "page_browser",
    "bookmarks",
    "bookmark_search",
    "toggle_bookmark",
    ----
    "book_status",
    "book_info",
    "book_description",
    "book_cover",
    ----
    "translate_page",
    ----
    "toggle_page_change_animation",
    "toggle_inverse_reading_order",
    "toggle_handmade_toc",
    "toggle_handmade_flows",
    ----
    "set_highlight_action",
    "cycle_highlight_action",
    "cycle_highlight_style",
    ----
    "flush_settings",
    ----

    -- Reflowable documents
    "set_font",
    "increase_font",
    "decrease_font",
    "font_size",
    "word_spacing",
    "word_expansion",
    "font_gamma",
    "font_base_weight",
    "font_hinting",
    "font_kerning",
    ----
    "visible_pages",
    ----
    "h_page_margins",
    "sync_t_b_page_margins",
    "t_page_margin",
    "b_page_margin",
    ----
    "view_mode",
    "block_rendering_mode",
    "render_dpi",
    "line_spacing",
    ----
    "status_line",
    "embedded_css",
    "embedded_fonts",
    "smooth_scaling",
    "nightmode_images",

    -- Fixed layout documents
    "toggle_page_flipping",
    "toggle_bookmark_flipping",
    "toggle_reflow",
    "zoom",
    "zoom_factor_change",
    ----
    "panel_zoom_toggle",
    ----
    "kopt_trim_page",
    "kopt_page_margin",
    "kopt_zoom_overlap_h",
    "kopt_zoom_overlap_v",
    "kopt_zoom_mode_type",
    -- "kopt_zoom_range_number", -- can't figure out how this name text func works
    "kopt_zoom_factor",
    "kopt_zoom_mode_genus",
    "kopt_zoom_direction",
    "kopt_page_scroll",
    "kopt_page_gap_height",
    "kopt_full_screen",
    "kopt_line_spacing",
    "kopt_justification",
    "kopt_font_size",
    "kopt_font_fine_tune",
    "kopt_word_spacing",
    "kopt_text_wrap",
    "kopt_contrast",
    "kopt_page_opt",
    "kopt_hw_dithering",
    "kopt_sw_dithering",
    "kopt_quality",
    "kopt_doc_language",
    "kopt_forced_ocr",
    "kopt_writing_direction",
    "kopt_defect_size",
    "kopt_detect_indent",
    "kopt_max_columns",
    "kopt_auto_straighten",
}

--[[--
    add settings from CreOptions / KoptOptions
--]]--
function Dispatcher:init()
    if Dispatcher.initialized then return end
    local parseoptions = function(base, i, prefix)
        for y=1, #base[i].options do
            local option = base[i].options[y]
            local name = prefix and prefix .. option.name or option.name
            if settingsList[name] ~= nil then
                if option.name ~= nil and option.values ~= nil then
                    settingsList[name].configurable = {name = option.name, values = option.values}
                end
                if settingsList[name].event == nil then
                    settingsList[name].event = option.event
                end
                if settingsList[name].title == nil then
                    settingsList[name].title = option.name_text
                end
                if settingsList[name].condition == nil then
                    settingsList[name].condition = option.show
                end
                if settingsList[name].category == "string" or settingsList[name].category == "configurable" then
                    if settingsList[name].toggle == nil then
                        settingsList[name].toggle = option.toggle or option.labels
                        if settingsList[name].toggle == nil then
                            settingsList[name].toggle = {}
                            for z=1,#option.values do
                                if type(option.values[z]) == "table" then
                                    settingsList[name].toggle[z] = option.values[z][1]
                                else
                                    settingsList[name].toggle[z] = option.values[z]
                                end
                            end
                        end
                    end
                    if settingsList[name].args == nil then
                        settingsList[name].args = option.args or option.values
                    end
                elseif settingsList[name].category == "absolutenumber" then
                    if settingsList[name].min == nil then
                        settingsList[name].min =
                            (option.more_options_param and (option.more_options_param.value_min or option.more_options_param.left_min))
                            or (option.args and option.args[1]) or option.values[1]
                    end
                    if settingsList[name].max == nil then
                        settingsList[name].max =
                            (option.more_options_param and (option.more_options_param.value_max or option.more_options_param.left_max))
                            or (option.args and option.args[#option.args]) or option.values[#option.values]
                    end
                    if settingsList[name].default == nil then
                        settingsList[name].default = option.default_value
                    end
                end
                settingsList[name].unit = option.more_options_param and option.more_options_param.unit
            end
        end
    end
    for i=1,#CreOptions do
        parseoptions(CreOptions, i)
    end
    for i=1,#KoptOptions do
        parseoptions(KoptOptions, i, "kopt_")
    end
    UIManager:broadcastEvent(Event:new("DispatcherRegisterActions"))
    Dispatcher.initialized = true
end

--[[--
Adds settings at runtime.

@usage
    function Hello:onDispatcherRegisterActions()
        Dispatcher:registerAction("helloworld_action", {category="none", event="HelloWorld", title=_("Hello World"), general=true})
    end

    function Hello:init()
        self:onDispatcherRegisterActions()
    end


@param name the key to use in the table
@param value a table per settingsList above
--]]--
function Dispatcher:registerAction(name, value)
    if settingsList[name] == nil then
        settingsList[name] = value
        table.insert(dispatcher_menu_order, name)
    end
    return true
end

--[[--
Removes settings at runtime.

@param name the key to use in the table
--]]--
function Dispatcher:removeAction(name)
    local k = util.arrayContains(dispatcher_menu_order, name)
    if k then
        table.remove(dispatcher_menu_order, k)
        settingsList[name] = nil
    end
    return true
end

local function iter_func(settings)
    if settings and settings.settings and settings.settings.order then
        return ipairs(settings.settings.order)
    else
        return pairs(settings)
    end
end

-- Returns the number of items present in the settings table
function Dispatcher:_itemsCount(settings)
    if settings then
        local count = util.tableSize(settings)
        if count > 0 and settings.settings ~= nil then
            count = count - 1
        end
        return count
    end
end

-- Returns a display name for the item.
function Dispatcher:getNameFromItem(item, settings, dont_show_value)
    if settingsList[item] == nil then
        return _("Unknown item")
    end
    local value = settings and settings[item]
    local title = settingsList[item].title
    if dont_show_value or value == nil then
        return title
    end
    local display_value
    local category = settingsList[item].category
    if category == "string" or category == "configurable" then
        if type(value) == "table" then
            display_value = string.format("%d / %d", unpack(value))
        else
            if not settingsList[item].args and settingsList[item].args_func then
                settingsList[item].args, settingsList[item].toggle = settingsList[item].args_func()
            end
            local value_num = util.arrayContains(settingsList[item].args, value)
            display_value = settingsList[item].toggle[value_num] or string.format("%.1f", value)
        end
    elseif category == "absolutenumber" then
        display_value = tostring(value)
    elseif category == "incrementalnumber" then
        display_value = value == 0 and _("gesture distance") or tostring(value)
    end
    if display_value then
        if settingsList[item].unit and (type(value) == "table" or tonumber(display_value)) then
                -- do not show unit when the setting is "none" ^^
            display_value = display_value .. "\u{202F}" .. settingsList[item].unit
        end
        title = title .. ": " .. display_value
    end
    return title
end

-- Converts copt/kopt-options values to args.
function Dispatcher:getArgFromValue(item, value)
    local value_num = util.arrayContains(settingsList[item].configurable.values, value)
    return settingsList[item].args[value_num]
end

-- Add the item to the end of the execution order.
-- If item or the order is nil all items will be added.
function Dispatcher:_addToOrder(location, settings, item)
    if location[settings] then
        if not location[settings].settings then location[settings].settings = {} end
        if not location[settings].settings.order or item == nil then
            location[settings].settings.order = {}
            for k in pairs(location[settings]) do
                if settingsList[k] ~= nil then
                    table.insert(location[settings].settings.order, k)
                end
            end
        else
            if not util.arrayContains(location[settings].settings.order, item) then
                table.insert(location[settings].settings.order, item)
            end
        end
    end
end

-- Remove the item from the execution order.
-- If item is nil all items will be removed.
-- If the resulting order is empty it will be nilled
function Dispatcher:_removeFromOrder(location, settings, item)
    if location[settings] and location[settings].settings then
        if location[settings].settings.order then
            if item then
                local k = util.arrayContains(location[settings].settings.order, item)
                if k then table.remove(location[settings].settings.order, k) end
            else
                location[settings].settings.order = {}
            end
            if next(location[settings].settings.order) == nil then
                location[settings].settings.order = nil
                if next(location[settings].settings) == nil then
                    location[settings].settings = nil
                end
            end
        end
    end
end

-- Get a textual representation of the enabled actions to display in a menu item.
function Dispatcher:menuTextFunc(settings)
    if settings then
        local count = Dispatcher:_itemsCount(settings)
        if count == 0 then
            return _("Nothing")
        elseif count == 1 then
            local item = next(settings)
            if item == "settings" then item = next(settings, item) end
            return Dispatcher:getNameFromItem(item, settings)
        end
        return T(NC_("Dispatcher", "1 action", "%1 actions", count), count)
    end
    return _("Pass through")
end

-- Get a list of all enabled actions to display in a menu.
function Dispatcher:getDisplayList(settings)
    local item_table = {}
    if not settings then return item_table end
    for item, v in iter_func(settings) do
        if type(item) == "number" then item = v end
        if settingsList[item] ~= nil and (settingsList[item].condition == nil or settingsList[item].condition == true) then
            table.insert(item_table, {text = Dispatcher:getNameFromItem(item, settings), key = item})
        end
    end
    return item_table
end

-- Display a SortWidget to sort the enable actions execution order.
function Dispatcher:_sortActions(caller, location, settings, touchmenu_instance)
    local display_list = Dispatcher:getDisplayList(location[settings])
    local SortWidget = require("ui/widget/sortwidget")
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Arrange actions"),
        item_table = display_list,
        callback = function()
            if location[settings] and next(location[settings]) ~= nil then
                if  not location[settings].settings then
                    location[settings].settings = {}
                end
                location[settings].settings.order = {}
                for i, v in ipairs(sort_widget.item_table) do
                    location[settings].settings.order[i] = v.key
                end
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
            caller.updated = true
        end
    }
    UIManager:show(sort_widget)
end

function Dispatcher:_addItem(caller, menu, location, settings, section)
    local function setValue(k, value, touchmenu_instance)
        if value ~= nil then
            if location[settings] == nil then
                location[settings] = {}
            end
            location[settings][k] = value
            Dispatcher:_addToOrder(location, settings, k)
        else
            location[settings][k] = nil
            Dispatcher:_removeFromOrder(location, settings, k)
        end
        caller.updated = true
        if touchmenu_instance then
            touchmenu_instance:updateItems()
        end
    end
    for __, k in ipairs(dispatcher_menu_order) do
        if settingsList[k][section] == true and settingsList[k].condition ~= false then
            if settingsList[k].category == "none" or settingsList[k].category == "arg" then
                table.insert(menu, {
                    text = settingsList[k].title,
                    checked_func = function()
                        return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local value = (location[settings] == nil or location[settings][k] == nil) and true or nil
                        setValue(k, value, touchmenu_instance)
                    end,
                    separator = settingsList[k].separator,
                })
            elseif settingsList[k].category == "absolutenumber" then
                table.insert(menu, {
                    text_func = function()
                        return Dispatcher:getNameFromItem(k, location[settings])
                    end,
                    checked_func = function()
                        return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local precision
                        if settingsList[k].step and math.floor(settingsList[k].step) ~= settingsList[k].step then
                            precision = "%0.1f"
                        end
                        local items = SpinWidget:new{
                            value = location[settings] ~= nil and location[settings][k] or settingsList[k].default or settingsList[k].min,
                            value_min = settingsList[k].min,
                            value_step = settingsList[k].step,
                            precision = precision,
                            value_hold_step = 5,
                            value_max = settingsList[k].max,
                            title_text = Dispatcher:getNameFromItem(k, location[settings], true),
                            unit = settingsList[k].unit,
                            ok_always_enabled = true,
                            callback = function(spin)
                                setValue(k, spin.value, touchmenu_instance)
                            end,
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        if location[settings] ~= nil and location[settings][k] ~= nil then
                            setValue(k, nil, touchmenu_instance)
                        end
                    end,
                    separator = settingsList[k].separator,
                })
            elseif settingsList[k].category == "incrementalnumber" then
                table.insert(menu, {
                    text_func = function()
                        return Dispatcher:getNameFromItem(k, location[settings])
                    end,
                    checked_func = function()
                        return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local value = location[settings] and location[settings][k]
                        if value == nil or value < settingsList[k].min then
                            value = settingsList[k].min
                        end
                        local precision
                        if settingsList[k].step and math.floor(settingsList[k].step) ~= settingsList[k].step then
                            precision = "%0.1f"
                        end
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            value = value,
                            value_min = settingsList[k].min,
                            value_step = settingsList[k].step,
                            precision = precision,
                            value_hold_step = 5,
                            value_max = settingsList[k].max,
                            title_text = Dispatcher:getNameFromItem(k, location[settings], true),
                            ok_always_enabled = true,
                            callback = function(spin)
                                setValue(k, spin.value, touchmenu_instance)
                            end,
                            option_text = caller.profiles == nil and _("Use gesture distance"), -- Gesture manager only
                            option_callback = function()
                                setValue(k, 0, touchmenu_instance)
                            end,
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        if location[settings] ~= nil and location[settings][k] ~= nil then
                            setValue(k, nil, touchmenu_instance)
                        end
                    end,
                    separator = settingsList[k].separator,
                })
            elseif settingsList[k].category == "string" or settingsList[k].category == "configurable" then
                local sub_item_table = {}
                if not settingsList[k].args and settingsList[k].args_func then
                    settingsList[k].args, settingsList[k].toggle = settingsList[k].args_func()
                end
                for i=1,#settingsList[k].args do
                    table.insert(sub_item_table, {
                        text = tostring(settingsList[k].toggle[i]),
                        checked_func = function()
                            if location[settings] ~= nil and location[settings][k] ~= nil then
                                if type(location[settings][k]) == "table" then
                                    return location[settings][k][1] == settingsList[k].args[i][1]
                                else
                                    return location[settings][k] == settingsList[k].args[i]
                                end
                            end
                        end,
                        callback = function()
                            setValue(k, settingsList[k].args[i])
                        end,
                    })
                end
                table.insert(menu, {
                    text_func = function()
                        return Dispatcher:getNameFromItem(k, location[settings])
                    end,
                    checked_func = function()
                        return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    sub_item_table = sub_item_table,
                    keep_menu_open = true,
                    hold_callback = function(touchmenu_instance)
                        if location[settings] ~= nil and location[settings][k] ~= nil then
                            setValue(k, nil, touchmenu_instance)
                        end
                    end,
                    separator = settingsList[k].separator,
                })
            end
        end
    end
end

--[[--
Add a submenu to edit which items are dispatched
arguments are:
    1) the caller so dispatcher can set the updated flag
    2) the table representing the submenu (can be empty)
    3) the object (table) in which the settings table is found
    4) the name of the settings table
example usage:
    Dispatcher:addSubMenu(self, sub_items, self.data, "profile1")
--]]--
function Dispatcher:addSubMenu(caller, menu, location, settings)
    Dispatcher:init()
    menu.ignored_by_menu_search = true -- all those would be duplicated
    table.insert(menu, {
        text = _("Nothing"),
        separator = true,
        checked_func = function()
            return location[settings] ~= nil and Dispatcher:_itemsCount(location[settings]) == 0
        end,
        callback = function(touchmenu_instance)
            local name = location[settings] and location[settings].settings and location[settings].settings.name
            location[settings] = {}
            if name then
                location[settings].settings = { name = name }
            end
            caller.updated = true
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    local section_list = {
        {"general", _("General")},
        {"device", _("Device")},
        {"screen", _("Screen and lights")},
        {"filemanager", _("File browser")},
        {"reader", _("Reader")},
        {"rolling", _("Reflowable documents (epub, fb2, txt…)")},
        {"paging", _("Fixed layout documents (pdf, djvu, pics…)")},
    }
    for _, section in ipairs(section_list) do
        local submenu = {}
        Dispatcher:_addItem(caller, submenu, location, settings, section[1])
        table.insert(menu, {
            text = section[2],
            checked_func = function()
                if location[settings] ~= nil then
                    for k, _ in pairs(location[settings]) do
                        if settingsList[k] ~= nil and settingsList[k][section[1]] == true and
                            (settingsList[k].condition == nil or settingsList[k].condition)
                        then return true end
                    end
                end
            end,
            hold_callback = function(touchmenu_instance)
                if location[settings] ~= nil then
                    for k, _ in pairs(location[settings]) do
                        if settingsList[k] ~= nil and settingsList[k][section[1]] == true then
                            location[settings][k] = nil
                            Dispatcher:_removeFromOrder(location, settings, k)
                            caller.updated = true
                        end
                    end
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            end,
            sub_item_table = submenu,
        })
    end
    menu.max_per_page = #menu -- next items in page 2
    table.insert(menu, {
        text = _("Arrange actions"),
        checked_func = function()
            return location[settings] ~= nil
            and location[settings].settings ~= nil
            and location[settings].settings.order ~= nil
        end,
        callback = function(touchmenu_instance)
            Dispatcher:_sortActions(caller, location, settings, touchmenu_instance)
        end,
        hold_callback = function(touchmenu_instance)
            if location[settings]
            and location[settings].settings
            and location[settings].settings.order then
                Dispatcher:_removeFromOrder(location, settings)
                caller.updated = true
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end
        end,
    })
    table.insert(menu, {
        text = _("Show as QuickMenu"),
        checked_func = function()
            return location[settings] ~= nil
            and location[settings].settings ~= nil
            and location[settings].settings.show_as_quickmenu
        end,
        callback = function()
            if location[settings] then
                if location[settings].settings then
                    if location[settings].settings.show_as_quickmenu then
                        location[settings].settings.show_as_quickmenu = nil
                        if next(location[settings].settings) == nil then
                            location[settings].settings = nil
                        end
                    else
                        location[settings].settings.show_as_quickmenu = true
                    end
                else
                    location[settings].settings = {["show_as_quickmenu"] = true}
                end
                caller.updated = true
            end
        end,
    })
    table.insert(menu, {
        text = _("Keep QuickMenu open"),
        checked_func = function()
            return location[settings] ~= nil
            and location[settings].settings ~= nil
            and location[settings].settings.keep_open_on_apply
        end,
        callback = function()
            if location[settings] then
                if location[settings].settings then
                    if location[settings].settings.keep_open_on_apply then
                        location[settings].settings.keep_open_on_apply = nil
                        if next(location[settings].settings) == nil then
                            location[settings].settings = nil
                        end
                    else
                        location[settings].settings.keep_open_on_apply = true
                    end
                else
                    location[settings].settings = {["keep_open_on_apply"] = true}
                end
                caller.updated = true
            end
        end,
    })
end

function Dispatcher:isActionEnabled(action)
    local disabled = true
    if action and (action.condition == nil or action.condition == true) then
        local ui = require("apps/reader/readerui").instance
        local context = ui and (ui.paging and "paging" or "rolling")
        if context == "paging" then
            disabled = action["rolling"]
        elseif context == "rolling" then
            disabled = action["paging"]
        else -- FM
            disabled = (action["reader"] or action["rolling"] or action["paging"]) and not action["filemanager"]
        end
    end
    return not disabled
end

function Dispatcher:_showAsMenu(settings, exec_props)
    local title = settings.settings.name or _("QuickMenu")
    local keep_open_on_apply = settings.settings.keep_open_on_apply
    local display_list = Dispatcher:getDisplayList(settings)
    local quickmenu
    local buttons = {}
    if exec_props and exec_props.qm_show then
        table.insert(buttons, {{
            text = _("Execute all"),
            align = "left",
            font_face = "smallinfofont",
            font_size = 22,
            callback = function()
                UIManager:close(quickmenu)
                Dispatcher:execute(settings, { qm_show = false })
            end,
        }})
    end
    for _, v in ipairs(display_list) do
        table.insert(buttons, {{
            text = v.text,
            enabled = Dispatcher:isActionEnabled(settingsList[v.key]),
            align = "left",
            font_face = "smallinfofont",
            font_size = 22,
            font_bold = false,
            callback = function()
                UIManager:close(quickmenu)
                Dispatcher:execute({[v.key] = settings[v.key]})
                if keep_open_on_apply and not util.stringStartsWith(v.key, "touch_input") then
                    quickmenu:setTitle(title)
                    UIManager:show(quickmenu)
                end
            end,
            hold_callback = function()
                if v.key:sub(1, 13) == "profile_exec_" then
                    UIManager:close(quickmenu)
                    UIManager:sendEvent(Event:new(settingsList[v.key].event, settingsList[v.key].arg, { qm_show = true }))
                end
            end,
        }})
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    quickmenu = ButtonDialog:new{
        title = title,
        title_align = "center",
        shrink_unneeded_width = true,
        shrink_min_width = math.floor(0.6 * Screen:getWidth()),
        use_info_style = false,
        buttons = buttons,
        anchor = exec_props and exec_props.qm_anchor,
    }
    UIManager:show(quickmenu)
end

--[[--
Calls the events in a settings list
arguments are:
    1) the settings table
    2) execution management table: { qm_show = true|false} - forcibly show QM / run
                                   { qm_anchor = ges.pos } - anchor position
                                   { gesture = ges } - a `gestures` object
--]]--
function Dispatcher:execute(settings, exec_props)
    if ((exec_props == nil or exec_props.qm_show == nil) and settings.settings and settings.settings.show_as_quickmenu)
            or (exec_props and exec_props.qm_show) then
        return Dispatcher:_showAsMenu(settings, exec_props)
    end
    local has_many = Dispatcher:_itemsCount(settings) > 1
    if has_many then
        UIManager:broadcastEvent(Event:new("BatchedUpdate"))
    end
    local gesture = exec_props and exec_props.gesture
    for k, v in iter_func(settings) do
        if type(k) == "number" then
            k = v
            v = settings[k]
        end
        if Dispatcher:isActionEnabled(settingsList[k]) then
            Notification:setNotifySource(Notification.SOURCE_DISPATCHER)
            if settings.settings and settings.settings.notify then
                Notification:notify(T(_("Executing profile: %1"), settings.settings.name))
            end
            if settingsList[k].configurable then
                local value = v
                if type(v) ~= "number" then
                    for i, r in ipairs(settingsList[k].args) do
                        if v == r then value = settingsList[k].configurable.values[i] break end
                    end
                end
                UIManager:sendEvent(Event:new("ConfigChange", settingsList[k].configurable.name, value))
            end

            local category = settingsList[k].category
            local event = settingsList[k].event
            if category == "none" then
                if settingsList[k].arg ~= nil then
                    UIManager:sendEvent(Event:new(event, settingsList[k].arg, exec_props))
                else
                    UIManager:sendEvent(Event:new(event))
                end
            elseif category == "absolutenumber" or category == "string" then
                UIManager:sendEvent(Event:new(event, v))
            elseif category == "arg" then
                -- the event can accept a gesture object or an argument
                local arg = gesture or settingsList[k].arg
                UIManager:sendEvent(Event:new(event, arg))
            elseif category == "incrementalnumber" then
                -- the event can accept a gesture object or a number
                local arg = v ~= 0 and v or gesture or 0
                UIManager:sendEvent(Event:new(event, arg))
            end
        end
        Notification:resetNotifySource()
    end
    if has_many then
        UIManager:broadcastEvent(Event:new("BatchedUpdateDone"))
    end
end

return Dispatcher
