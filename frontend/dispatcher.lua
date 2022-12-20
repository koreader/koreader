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
local Notification = require("ui/widget/notification")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderZooming = require("apps/reader/modules/readerzooming")
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
    -- Screen & Lights
    show_frontlight_dialog = {category="none", event="ShowFlDialog", title=_("Show frontlight dialog"), screen=true, condition=Device:hasFrontlight()},
    toggle_frontlight = {category="none", event="ToggleFrontlight", title=_("Toggle frontlight"), screen=true, condition=Device:hasFrontlight()},
    set_frontlight = {category="absolutenumber", event="SetFlIntensity", min=0, max=Device:getPowerDevice().fl_max, title=_("Set frontlight brightness"), screen=true, condition=Device:hasFrontlight()},
    increase_frontlight = {category="incrementalnumber", event="IncreaseFlIntensity", min=1, max=Device:getPowerDevice().fl_max, title=_("Increase frontlight brightness"), screen=true, condition=Device:hasFrontlight()},
    decrease_frontlight = {category="incrementalnumber", event="DecreaseFlIntensity", min=1, max=Device:getPowerDevice().fl_max, title=_("Decrease frontlight brightness"), screen=true, condition=Device:hasFrontlight()},
    set_frontlight_warmth = {category="absolutenumber", event="SetFlWarmth", min=0, max=100, title=_("Set frontlight warmth"), screen=true, condition=Device:hasNaturalLight()},
    increase_frontlight_warmth = {category="incrementalnumber", event="IncreaseFlWarmth", min=1, max=Device:getPowerDevice().fl_warmth_max, title=_("Increase frontlight warmth"), screen=true, condition=Device:hasNaturalLight()},
    decrease_frontlight_warmth = {category="incrementalnumber", event="DecreaseFlWarmth", min=1, max=Device:getPowerDevice().fl_warmth_max, title=_("Decrease frontlight warmth"), screen=true, condition=Device:hasNaturalLight(), separator=true},
    full_refresh = {category="none", event="FullRefresh", title=_("Full screen refresh"), screen=true},
    night_mode = {category="none", event="ToggleNightMode", title=_("Toggle night mode"), screen=true},
    set_night_mode = {category="string", event="SetNightMode", title=_("Set night mode"), screen=true, args={true, false}, toggle={_("on"), _("off")}, separator=true},
    set_refresh_rate = {category="absolutenumber", event="SetBothRefreshRates", min=-1, max=200, title=_("Full refresh rate (always)"), screen=true, condition=Device:hasEinkScreen()},
    set_day_refresh_rate = {category="absolutenumber", event="SetDayRefreshRate", min=-1, max=200, title=_("Full refresh rate (not in night mode)"), screen=true, condition=Device:hasEinkScreen()},
    set_night_refresh_rate = {category="absolutenumber", event="SetNightRefreshRate", min=-1, max=200, title=_("Full refresh rate (in night mode)"), screen=true, condition=Device:hasEinkScreen()},
    set_flash_on_chapter_boundaries = {category="string", event="SetFlashOnChapterBoundaries", title=_("Always flash on chapter boundaries"), screen=true, condition=Device:hasEinkScreen(), args={true, false}, toggle={_("on"), _("off")}},
    toggle_flash_on_chapter_boundaries = {category="none", event="ToggleFlashOnChapterBoundaries", title=_("Toggle flashing on chapter boundaries"), screen=true, condition=Device:hasEinkScreen()},
    set_no_flash_on_second_chapter_page = {category="string", event="SetNoFlashOnSecondChapterPage", title=_("Never flash on chapter's 2nd page"), screen=true, condition=Device:hasEinkScreen(), args={true, false}, toggle={_("on"), _("off")}},
    toggle_no_flash_on_second_chapter_page = {category="none", event="ToggleNoFlashOnSecondChapterPage", title=_("Toggle flashing on chapter's 2nd page"), screen=true, condition=Device:hasEinkScreen(), separator=true},

    -- Device settings
    toggle_gsensor = {category="none", event="ToggleGSensor", title=_("Toggle accelerometer"), device=true, condition=Device:hasGSensor()},
    wifi_on = {category="none", event="InfoWifiOn", title=_("Turn on Wi-Fi"), device=true, condition=Device:hasWifiToggle()},
    wifi_off = {category="none", event="InfoWifiOff", title=_("Turn off Wi-Fi"), device=true, condition=Device:hasWifiToggle()},
    toggle_wifi = {category="none", event="ToggleWifi", title=_("Toggle Wi-Fi"), device=true, condition=Device:hasWifiToggle()},
    toggle_fullscreen = {category="none", event="ToggleFullscreen", title=_("Toggle Fullscreen"), device=true, condition=not Device:isAlwaysFullscreen()},
    show_network_info = {category="none", event="ShowNetworkInfo", title=_("Show network info"), device=true, separator=true},
    exit_screensaver = {category="none", event="ExitScreensaver", title=_("Exit screensaver"), device=true},
    restart = {category="none", event="Restart", title=_("Restart KOReader"), device=true, condition=Device:canRestart()},
    suspend = {category="none", event="RequestSuspend", title=_("Suspend"), device=true, condition=Device:canSuspend()},
    reboot = {category="none", event="RequestReboot", title=_("Reboot the device"), device=true, condition=Device:canReboot()},
    poweroff = {category="none", event="RequestPowerOff", title=_("Power off"), device=true, condition=Device:canPowerOff(), separator=true},
    exit = {category="none", event="Exit", title=_("Exit KOReader"), device=true},
    toggle_hold_corners = {category="none", event="IgnoreHoldCorners", title=_("Toggle hold corners"), device=true},
    toggle_touch_input = {category="none", event="IgnoreTouchInput", title=_("Toggle touch input"), device=true, separator=true},
    toggle_rotation = {category="none", event="SwapRotation", title=_("Toggle orientation"), device=true},
    invert_rotation = {category="none", event="InvertRotation", title=_("Invert rotation"), device=true},
    iterate_rotation = {category="none", event="IterateRotation", title=_("Rotate by 90° CW"), device=true},
    iterate_rotation_ccw = {category="none", event="IterateRotation", arg=true, title=_("Rotate by 90° CCW"), device=true, separator=true},

    -- General
    reading_progress = {category="none", event="ShowReaderProgress", title=_("Reading progress"), general=true},
    history = {category="none", event="ShowHist", title=_("History"), general=true},
    open_previous_document = {category="none", event="OpenLastDoc", title=_("Open previous document"), general=true},
    filemanager = {category="none", event="Home", title=_("File browser"), general=true, separator=true},
    dictionary_lookup = {category="none", event="ShowDictionaryLookup", title=_("Dictionary lookup"), general=true},
    wikipedia_lookup = {category="none", event="ShowWikipediaLookup", title=_("Wikipedia lookup"), general=true},
    fulltext_search = {category="none", event="ShowFulltextSearchInput", title=_("Fulltext search"), general=true},
    file_search = {category="none", event="ShowFileSearch", title=_("File search"), general=true, separator=true},
    show_menu = {category="none", event="ShowMenu", title=_("Show menu"), general=true},
    menu_search = {category="none", event="MenuSearch", title=_("Menu search"), general=true},
    favorites = {category="none", event="ShowColl", arg="favorites", title=_("Favorites"), general=true},
    screenshot = {category="none", event="Screenshot", title=_("Screenshot"), general=true, separator=true},

    -- filemanager settings
    folder_up = {category="none", event="FolderUp", title=_("Folder up"), filemanager=true},
    show_plus_menu = {category="none", event="ShowPlusMenu", title=_("Show plus menu"), filemanager=true},
    toggle_select_mode = {category="none", event="ToggleSelectMode", title=_("Toggle select mode"), filemanager=true},
    refresh_content = {category="none", event="RefreshContent", title=_("Refresh content"), filemanager=true},
    folder_shortcuts = {category="none", event="ShowFolderShortcutsDialog", title=_("Folder shortcuts"), filemanager=true, separator=true},

    -- reader settings
    open_next_document_in_folder = {category="none", event="OpenNextDocumentInFolder", title=_("Open next document in folder"), reader=true, separator=true},
    toggle_status_bar = {category="none", event="TapFooter", title=_("Toggle status bar"), reader=true, separator=true},
    prev_chapter = {category="none", event="GotoPrevChapter", title=_("Previous chapter"), reader=true},
    next_chapter = {category="none", event="GotoNextChapter", title=_("Next chapter"), reader=true},
    first_page = {category="none", event="GoToBeginning", title=_("First page"), reader=true},
    last_page = {category="none", event="GoToEnd", title=_("Last page"), reader=true},
    prev_bookmark = {category="none", event="GotoPreviousBookmarkFromPage", title=_("Previous bookmark"), reader=true},
    next_bookmark = {category="none", event="GotoNextBookmarkFromPage", title=_("Next bookmark"), reader=true},
    go_to = {category="none", event="ShowGotoDialog", title=_("Go to page"), filemanager=true, reader=true},
    skim = {category="none", event="ShowSkimtoDialog", title=_("Skim document"), reader=true},
    back = {category="none", event="Back", title=_("Back"), reader=true},
    previous_location = {category="none", event="GoBackLink", arg=true, title=_("Back to previous location"), reader=true},
    latest_bookmark = {category="none", event="GoToLatestBookmark", title=_("Go to latest bookmark"), reader=true},
    follow_nearest_link = {category="arg", event="GoToPageLink", arg={pos={x=0,y=0}}, title=_("Follow nearest link"), reader=true},
    follow_nearest_internal_link = {category="arg", event="GoToInternalPageLink", arg={pos={x=0,y=0}}, title=_("Follow nearest internal link"), reader=true},
    clear_location_history = {category="none", event="ClearLocationStack", arg=true, title=_("Clear location history"), reader=true, separator=true},
    toc = {category="none", event="ShowToc", title=_("Table of contents"), reader=true},
    book_map = {category="none", event="ShowBookMap", title=_("Book map"), reader=true, condition=Device:isTouchDevice()},
    page_browser = {category="none", event="ShowPageBrowser", title=_("Page browser"), reader=true, condition=Device:isTouchDevice()},
    bookmarks = {category="none", event="ShowBookmark", title=_("Bookmarks"), reader=true},
    bookmark_search = {category="none", event="SearchBookmark", title=_("Bookmark search"), reader=true},
    book_status = {category="none", event="ShowBookStatus", title=_("Book status"), reader=true},
    book_info = {category="none", event="ShowBookInfo", title=_("Book information"), reader=true},
    book_description = {category="none", event="ShowBookDescription", title=_("Book description"), reader=true},
    book_cover = {category="none", event="ShowBookCover", title=_("Book cover"), reader=true, separator=true},
    show_config_menu = {category="none", event="ShowConfigMenu", title=_("Show bottom menu"), reader=true},
    toggle_bookmark = {category="none", event="ToggleBookmark", title=_("Toggle bookmark"), reader=true},
    toggle_page_change_animation = {category="none", event="TogglePageChangeAnimation", title=_("Toggle page turn animations"), reader=true, condition=Device:canDoSwipeAnimation()},
    toggle_inverse_reading_order = {category="none", event="ToggleReadingOrder", title=_("Toggle page turn direction"), reader=true, separator=true},
    swap_page_turn_buttons = {category="none", event="SwapPageTurnButtons", title=_("Invert page turn buttons"), reader=true, condition=Device:hasKeys(), separator=true},
    set_highlight_action = {category="string", event="SetHighlightAction", title=_("Set highlight action"), args_func=ReaderHighlight.getHighlightActions, reader=true},
    cycle_highlight_action = {category="none", event="CycleHighlightAction", title=_("Cycle highlight action"), reader=true},
    cycle_highlight_style = {category="none", event="CycleHighlightStyle", title=_("Cycle highlight style"), reader=true},
    page_jmp = {category="absolutenumber", event="GotoViewRel", min=-100, max=100, title=_("Turn pages"), reader=true},
    panel_zoom_toggle = {category="none", event="TogglePanelZoomSetting", title=_("Toggle panel zoom"), paging=true, separator=true},

    -- rolling reader settings
    set_font = {category="string", event="SetFont", title=_("Set font"), rolling=true, args_func=require("fontlist").getFontArgFunc,},
    increase_font = {category="incrementalnumber", event="IncreaseFontSize", min=0.5, max=255, step=0.5, title=_("Increase font size"), rolling=true},
    decrease_font = {category="incrementalnumber", event="DecreaseFontSize", min=0.5, max=255, step=0.5, title=_("Decrease font size"), rolling=true},

    -- paging reader settings
    toggle_page_flipping = {category="none", event="TogglePageFlipping", title=_("Toggle page flipping"), paging=true},
    toggle_reflow = {category="none", event="ToggleReflow", title=_("Toggle reflow"), paging=true},
    zoom = {category="string", event="SetZoomMode", title=_("Zoom mode"), args=ReaderZooming.available_zoom_modes, toggle=ReaderZooming.available_zoom_modes, paging=true},
    zoom_factor_change = {category="none", event="ZoomFactorChange", title=_("Change zoom factor"), paging=true, separator=true},

    -- parsed from CreOptions
    -- the rest of the table elements are built from their counterparts in CreOptions
    rotation_mode = {category="string", device=true},
    visible_pages = {category="string", rolling=true, separator=true},
    h_page_margins = {category="string", rolling=true},
    sync_t_b_page_margins = {category="string", rolling=true},
    t_page_margin = {category="absolutenumber", rolling=true},
    b_page_margin = {category="absolutenumber", rolling=true, separator=true},
    view_mode = {category="string", rolling=true},
    block_rendering_mode = {category="string", rolling=true},
    render_dpi = {category="string", title=_("Zoom"), rolling=true},
    line_spacing = {category="absolutenumber", rolling=true, separator=true},
    font_size = {category="absolutenumber", title=_("Set font size"), rolling=true, step=0.5},
    font_base_weight = {category="string", rolling=true},
    font_gamma = {category="string", rolling=true},
    font_hinting = {category="string", rolling=true},
    font_kerning = {category="string", rolling=true, separator=true},
    status_line = {category="string", rolling=true},
    embedded_css = {category="string", rolling=true},
    embedded_fonts = {category="string", rolling=true},
    smooth_scaling = {category="string", rolling=true},
    nightmode_images = {category="string", rolling=true, separator=true},

    -- parsed from KoptOptions
    kopt_trim_page = {category="string", paging=true},
    kopt_page_margin = {category="string", paging=true},
    kopt_zoom_overlap_h = {category="absolutenumber", paging=true},
    kopt_zoom_overlap_v = {category="absolutenumber", paging=true},
    kopt_zoom_mode_type = {category="string", paging=true},
    kopt_zoom_range_number = {category="string", paging=true},
    kopt_zoom_factor = {category="string", paging=true},
    kopt_zoom_mode_genus = {category="string", paging=true},
    kopt_zoom_direction = {category="string", paging=true},
    kopt_page_scroll = {category="string", paging=true},
    kopt_page_gap_height = {category="string", paging=true},
    kopt_full_screen = {category="string", paging=true},
    kopt_line_spacing = {category="configurable", paging=true},
    kopt_justification = {category="configurable", paging=true},
    kopt_font_size = {category="string", paging=true, title=_("Font Size")},
    kopt_font_fine_tune = {category="string", paging=true},
    kopt_word_spacing = {category="configurable", paging=true},
    kopt_text_wrap = {category="string", paging=true},
    kopt_contrast = {category="absolutenumber", paging=true},
    kopt_page_opt = {category="configurable", paging=true},
    kopt_hw_dithering = {category="configurable", paging=true, condition=Device:hasEinkScreen() and Device:canHWDither()},
    kopt_sw_dithering = {category="configurable", paging=true, condition=Device:hasEinkScreen() and not Device:canHWDither() and Device.screen.fb_bpp == 8},
    kopt_quality = {category="configurable", paging=true},
    kopt_doc_language = {category="string", paging=true},
    kopt_forced_ocr = {category="configurable", paging=true},
    kopt_writing_direction = {category="configurable", paging=true},
    kopt_defect_size = {category="string", paging=true, condition=false},
    kopt_auto_straighten = {category="absolutenumber", paging=true},
    kopt_detect_indent = {category="configurable", paging=true, condition=false},
    kopt_max_columns = {category="configurable", paging=true},

    settings = nil, -- reserved for per instance dispatcher settings
}

-- array for item order in menu
local dispatcher_menu_order = {
    -- device
    "reading_progress",
    "open_previous_document",
    "history",
    "favorites",
    "filemanager",

    "dictionary_lookup",
    "wikipedia_lookup",
    "fulltext_search",
    "file_search",

    "show_menu",
    "menu_search",
    "screenshot",

    "exit_screensaver",
    "suspend",
    "exit",
    "restart",
    "reboot",
    "poweroff",

    "toggle_hold_corners",
    "toggle_touch_input",
    "toggle_gsensor",
    "rotation_mode",
    "toggle_rotation",
    "invert_rotation",
    "iterate_rotation",
    "iterate_rotation_ccw",

    "wifi_on",
    "wifi_off",
    "toggle_wifi",
    "toggle_fullscreen",
    "show_network_info",

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

    "full_refresh",
    "set_refresh_rate",
    "set_day_refresh_rate",
    "set_night_refresh_rate",
    "set_flash_on_chapter_boundaries",
    "toggle_flash_on_chapter_boundaries",
    "set_no_flash_on_second_chapter_page",
    "toggle_no_flash_on_second_chapter_page",

    -- filemanager
    "folder_up",
    "show_plus_menu",
    "toggle_select_mode",
    "refresh_content",
    "folder_shortcuts",

    -- reader
    "open_next_document_in_folder",

    "show_config_menu",
    "toggle_status_bar",

    "prev_chapter",
    "next_chapter",
    "first_page",
    "last_page",
    "page_jmp",
    "go_to",
    "skim",
    "prev_bookmark",
    "next_bookmark",
    "latest_bookmark",
    "back",
    "previous_location",
    "follow_nearest_link",
    "follow_nearest_internal_link",
    "clear_location_history",

    "toc",
    "book_map",
    "page_browser",
    "bookmarks",
    "bookmark_search",

    "book_status",
    "book_info",
    "book_description",
    "book_cover",

    "set_font",
    "increase_font",
    "decrease_font",
    "font_size",
    "font_gamma",
    "font_base_weight",
    "font_hinting",
    "font_kerning",

    "toggle_bookmark",
    "toggle_page_change_animation",
    "toggle_page_flipping",
    "toggle_reflow",
    "toggle_inverse_reading_order",
    "swap_page_turn_buttons",
    "zoom",
    "zoom_factor_change",
    "set_highlight_action",
    "cycle_highlight_action",
    "cycle_highlight_style",
    "panel_zoom_toggle",

    "visible_pages",

    "h_page_margins",
    "sync_t_b_page_margins",
    "t_page_margin",
    "b_page_margin",

    "view_mode",
    "block_rendering_mode",
    "render_dpi",
    "line_spacing",

    "status_line",
    "embedded_css",
    "embedded_fonts",
    "smooth_scaling",
    "nightmode_images",

    "kopt_trim_page",
    "kopt_page_margin",

    "kopt_zoom_overlap_h",
    "kopt_zoom_overlap_v",
    "kopt_zoom_mode_type",
    --"kopt_zoom_range_number", -- can't figure out how this name text func works
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
    "kopt_auto_straighten",
    "kopt_detect_indent",
    "kopt_max_columns",
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
                        settingsList[name].min = option.args and option.args[1] or option.values[1]
                    end
                    if settingsList[name].max == nil then
                        settingsList[name].max = option.args and option.args[#option.args] or option.values[#option.values]
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
    local title, category = settingsList[item].title, settingsList[item].category
    local value = settings and settings[item]
    if dont_show_value or value == nil or (value == 0 and category == "incrementalnumber") then
        return title
    else
        local display_value
        if category == "string" or category == "configurable" then
            if type(value) == "table" then
                display_value = string.format("%d / %d", unpack(value))
            else
                local value_num = util.arrayContains(settingsList[item].args, value)
                display_value = settingsList[item].toggle[value_num]
            end
        elseif category == "absolutenumber" or category == "incrementalnumber" then
            display_value = tostring(value)
        end
        if display_value then
            if settingsList[item].unit then
                display_value = display_value .. " " .. settingsList[item].unit
            end
            title = title .. ": " .. display_value
        end
    end
    return title
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
    local action_name = _("Pass through")
    if settings then
        local count = Dispatcher:_itemsCount(settings)
        if count == 0 then return _("Nothing") end
        if count == 1 then
            local item = next(settings)
            if item == "settings" then item = next(settings, item) end
            action_name = Dispatcher:getNameFromItem(item, settings)
        else
            action_name = T(NC_("Dispatcher", "1 action", "%1 actions", count), count)
        end
    end
    return action_name
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
        title = _("Sort"),
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
            if touchmenu_instance then  touchmenu_instance:updateItems() end
            caller.updated = true
        end
    }
    UIManager:show(sort_widget)
end

function Dispatcher:_addItem(caller, menu, location, settings, section)
    for _, k in ipairs(dispatcher_menu_order) do
        if settingsList[k][section] == true and
            (settingsList[k].condition == nil or settingsList[k].condition)
        then
            if settingsList[k].category == "none" or settingsList[k].category == "arg" then
                table.insert(menu, {
                    text = settingsList[k].title,
                    checked_func = function()
                        return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        if location[settings] == nil then
                            location[settings] = {}
                        end
                        if location[settings][k] then
                            location[settings][k] = nil
                            Dispatcher:_removeFromOrder(location, settings, k)
                        else
                            location[settings][k] = true
                            Dispatcher:_addToOrder(location, settings, k)
                        end
                        caller.updated = true
                        if touchmenu_instance then touchmenu_instance:updateItems() end
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
                            value_step = settingsList[k].step or 1,
                            precision = precision,
                            value_hold_step = 5,
                            value_max = settingsList[k].max,
                            default_value = settingsList[k].default,
                            title_text = Dispatcher:getNameFromItem(k, location[settings], true),
                            ok_always_enabled = true,
                            callback = function(spin)
                                if location[settings] == nil then
                                    location[settings] = {}
                                end
                                location[settings][k] = spin.value
                                Dispatcher:_addToOrder(location, settings, k)
                                caller.updated = true
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        if location[settings] ~= nil and location[settings][k] ~= nil then
                            location[settings][k] = nil
                            Dispatcher:_removeFromOrder(location, settings, k)
                            caller.updated = true
                        end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
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
                        local _ = require("gettext")
                        local precision
                        if settingsList[k].step and math.floor(settingsList[k].step) ~= settingsList[k].step then
                            precision = "%0.1f"
                        end
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            value = location[settings] ~= nil and location[settings][k] or settingsList[k].min,
                            value_min = settingsList[k].min,
                            value_step = settingsList[k].step or 1,
                            precision = precision,
                            value_hold_step = 5,
                            value_max = settingsList[k].max,
                            title_text = Dispatcher:getNameFromItem(k, location[settings], true),
                            info_text = _([[If called by a gesture the amount of the gesture will be used]]),
                            ok_always_enabled = true,
                            callback = function(spin)
                                if location[settings] == nil then
                                    location[settings] = {}
                                end
                                location[settings][k] = spin.value
                                Dispatcher:_addToOrder(location, settings, k)
                                caller.updated = true
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        if location[settings] ~= nil and location[settings][k] ~= nil then
                            location[settings][k] = nil
                            Dispatcher:_removeFromOrder(location, settings, k)
                            caller.updated = true
                        end
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    separator = settingsList[k].separator,
                })
            elseif settingsList[k].category == "string" or settingsList[k].category == "configurable" then
                local sub_item_table = {}
                if settingsList[k].args_func then
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
                            if location[settings] == nil then
                                location[settings] = {}
                            end
                            location[settings][k] = settingsList[k].args[i]
                            Dispatcher:_addToOrder(location, settings, k)
                            caller.updated = true
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
                            location[settings][k] = nil
                            Dispatcher:_removeFromOrder(location, settings, k)
                            caller.updated = true
                        end
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    separator = settingsList[k].separator,
                    menu_item_id = k,
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
    menu[#menu].separator = true
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
        text = _("Sort"),
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
end

function Dispatcher:_showAsMenu(settings)
    local display_list = Dispatcher:getDisplayList(settings)
    local quickmenu
    local buttons = {}
    for _, v in ipairs(display_list) do
        table.insert(buttons, {{
            text = v.text,
            align = "left",
            font_face = "smallinfofont",
            font_size = 22,
            font_bold = false,
            callback = function()
                UIManager:close(quickmenu)
                Dispatcher:execute({[v.key] = settings[v.key]})
            end,
        }})
    end
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    quickmenu = ButtonDialogTitle:new{
        title = settings.settings.name or "Quick Menu",
        title_align = "center",
        width_factor = 0.8,
        use_info_style = false,
        buttons = buttons,
    }
    UIManager:show(quickmenu)
end

--[[--
Calls the events in a settings list
arguments are:
    1) the settings table
    2) optionally a `gestures` object
--]]--
function Dispatcher:execute(settings, gesture)
    if settings.settings ~= nil and settings.settings.show_as_quickmenu == true then
        return Dispatcher:_showAsMenu(settings)
    end
    local has_many = Dispatcher:_itemsCount(settings) > 1
    if has_many then
        UIManager:broadcastEvent(Event:new("BatchedUpdate"))
    end
    for k, v in iter_func(settings) do
        if type(k) == "number" then
            k = v
            v = settings[k]
        end
        if settingsList[k] ~= nil and (settingsList[k].condition == nil or settingsList[k].condition == true) then
            Notification:setNotifySource(Notification.SOURCE_DISPATCHER)
            if settingsList[k].configurable then
                local value = v
                if type(v) ~= "number" then
                    for i, r in ipairs(settingsList[k].args) do
                        if v == r then value = settingsList[k].configurable.values[i] break end
                    end
                end
                UIManager:sendEvent(Event:new("ConfigChange", settingsList[k].configurable.name, value))
            end
            if settingsList[k].category == "none" then
                if settingsList[k].arg ~= nil then
                    UIManager:sendEvent(Event:new(settingsList[k].event, settingsList[k].arg))
                else
                    UIManager:sendEvent(Event:new(settingsList[k].event))
                end
            end
            if settingsList[k].category == "absolutenumber"
                or settingsList[k].category == "string"
            then
                UIManager:sendEvent(Event:new(settingsList[k].event, v))
            end
            -- the event can accept a gesture object or an argument
            if settingsList[k].category == "arg" then
                local arg = gesture or settingsList[k].arg
                UIManager:sendEvent(Event:new(settingsList[k].event, arg))
            end
            -- the event can accept a gesture object or a number
            if settingsList[k].category == "incrementalnumber" then
                local arg = v ~= 0 and v or gesture or 0
                UIManager:sendEvent(Event:new(settingsList[k].event, arg))
            end
        end
        Notification:resetNotifySource()
    end
    if has_many then
        UIManager:broadcastEvent(Event:new("BatchedUpdateDone"))
    end
end

return Dispatcher
