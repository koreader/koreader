local CreOptions = require("ui/data/creoptions")
local Device = require("device")
local Event = require("ui/event")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Dispatcher = {
    initialized = false,
}

--[[--
contains a list of a dispatchable settings
each setting contains:
    category: one of
       none: a direct event call
       arg: a event that expects a gesture object or an argument
       absolutenumber: event that sets a number
       incrementalnumber: event that increments a number & accepts a gesture object
       string: event with a list of arguments to chose from
    event: what to call.
    title: for use in ui.
    section: under which menu to display (currently: device, filemanager, rolling, paging)
and optionally
    min/max: for number
    default
    args: allowed values for string.
    toggle: display name for args
    separator: put a separator after in the menu list
--]]--
local settingsList = {
    -- Device settings
    show_frontlight_dialog = { category="none", event="ShowFlDialog", title=_("Show frontlight dialog"), device=true, condition=Device:hasFrontlight(),},
    toggle_frontlight = { category="none", event="ToggleFrontlight", title=_("Toggle frontlight"), device=true, condition=Device:hasFrontlight(),},
    set_frontlight = { category="absolutenumber", event="SetFlIntensity", min=0, max=Device:getPowerDevice().fl_max, title=_("Set frontlight brightness"), device=true, condition=Device:hasFrontlight(),},
    increase_frontlight = { category="incrementalnumber", event="IncreaseFlIntensity", min=1, max=Device:getPowerDevice().fl_max, title=_("Increase frontlight brightness"), device=true, condition=Device:hasFrontlight(),},
    decrease_frontlight = { category="incrementalnumber", event="DecreaseFlIntensity", min=1, max=Device:getPowerDevice().fl_max, title=_("Decrease frontlight brightness"), device=true, condition=Device:hasFrontlight(),},
    set_frontlight_warmth = { category="absolutenumber", event="SetFlWarmth", min=0, max=100, title=_("Set frontlight warmth"), device=true, condition=Device:hasNaturalLight(),},
    increase_frontlight_warmth = { category="incrementalnumber", event="IncreaseFlWarmth", min=1, max=Device:getPowerDevice().fl_warmth_max, title=_("Increase frontlight warmth"), device=true, condition=Device:hasNaturalLight(),},
    decrease_frontlight_warmth = { category="incrementalnumber", event="DecreaseFlWarmth", min=1, max=Device:getPowerDevice().fl_warmth_max, title=_("Decrease frontlight warmth"), device=true, condition=Device:hasNaturalLight(),},
    toggle_gsensor = { category="none", event="ToggleGSensor", title=_("Toggle accelerometer"), device=true, condition=Device:canToggleGSensor(),},
    wifi_on = { category="none", event="InfoWifiOn", title=_("Turn on Wi-Fi"), device=true, condition=Device:hasWifiToggle(),},
    wifi_off = { category="none", event="InfoWifiOff", title=_("Turn off Wi-Fi"), device=true, condition=Device:hasWifiToggle(),},
    toggle_wifi = { category="none", event="ToggleWifi", title=_("Toggle Wi-Fi"), device=true, condition=Device:hasWifiToggle(),},
    reading_progress = { category="none", event="ShowReaderProgress", title=_("Reading progress"), device=true,},
    stats_calendar_view = { category="none", event="ShowCalendarView", title=_("Statistics calendar view"), device=true,},
    history = { category="none", event="ShowHist", title=_("History"), device=true,},
    open_previous_document = { category="none", event="OpenLastDoc", title=_("Open previous document"), device=true,},
    filemanager = { category="none", event="Home", title=_("File browser"), device=true,},
    dictionary_lookup = { category="none", event="ShowDictionaryLookup", title=_("Dictionary lookup"), device=true,},
    wikipedia_lookup = { category="none", event="ShowWikipediaLookup", title=_("Wikipedia lookup"), device=true,},
    fulltext_search = { category="none", event="ShowFulltextSearchInput", title=_("Fulltext search"), device=true,},
    file_search = { category="none", event="ShowFileSearch", title=_("File search"), device=true,},
    full_refresh = { category="none", event="FullRefresh", title=_("Full screen refresh"), device=true,},
    night_mode = { category="none", event="ToggleNightMode", title=_("Toggle night mode"), device=true,},
    set_night_mode = { category="string", event="SetNightMode", title=_("Set night mode"), device=true, args={true, false}, toggle={_("On"), _("Off")},},
    suspend = { category="none", event="SuspendEvent", title=_("Suspend"), device=true,},
    exit = { category="none", event="Exit", title=_("Exit KOReader"), device=true,},
    restart = { category="none", event="Restart", title=_("Restart KOReader"), device=true, condition=Device:canRestart(),},
    reboot = { category="none", event="Reboot", title=_("Reboot the device"), device=true, condition=Device:canReboot(),},
    poweroff = { category="none", event="PowerOff", title=_("Power off"), device=true, condition=Device:canPowerOff(),},
    show_menu = { category="none", event="ShowMenu", title=_("Show menu"), device=true,},
    toggle_hold_corners = { category="none", event="IgnoreHoldCorners", title=_("Toggle hold corners"), device=true,},
    toggle_rotation = { category="none", event="ToggleRotation", title=_("Toggle rotation"), device=true,},
    wallabag_download = { category="none", event="SynchronizeWallabag", title=_("Wallabag retrieval"), device=true,},
    calibre_search = { category="none", event="CalibreSearch", title=_("Search in calibre metadata"), device=true,},
    calibre_browse_tags = { category="none", event="CalibreBrowseTags", title=_("Browse all calibre tags"), device=true,},
    calibre_browse_series = { category="none", event="CalibreBrowseSeries", title=_("Browse all calibre series"), device=true,},
    favorites = { category="arg", event="ShowColl", arg="favorites", title=_("Favorites"), device=true,},

    -- filemanager settings
    folder_up = { category="none", event="FolderUp", title=_("Folder up"), filemanager=true},
    show_plus_menu = { category="none", event="ShowPlusMenu", title=_("Show plus menu"), filemanager=true},
    folder_shortcuts = { category="none", event="ShowFolderShortcutsDialog", title=_("Folder shortcuts"), filemanager=true},

    -- reader settings
    prev_chapter = { category="none", event="GotoPrevChapter", title=_("Previous chapter"), rolling=true, paging=true,},
    next_chapter = { category="none", event="GotoNextChapter", title=_("Next chapter"), rolling=true, paging=true,},
    first_page = { category="none", event="GoToBeginning", title=_("First page"), rolling=true, paging=true,},
    last_page = { category="none", event="GoToEnd", title=_("Last page"), rolling=true, paging=true,},
    prev_bookmark = { category="none", event="GotoPreviousBookmarkFromPage", title=_("Previous bookmark"), rolling=true, paging=true,},
    next_bookmark = { category="none", event="GotoNextBookmarkFromPage", title=_("Next bookmark"), rolling=true, paging=true,},
    go_to = { category="none", event="ShowGotoDialog", title=_("Go to"), rolling=true, paging=true,},
    skim = { category="none", event="ShowSkimtoDialog", title=_("Skim"), rolling=true, paging=true,},
    back = { category="none", event="Back", title=_("Back"), rolling=true, paging=true,},
    previous_location = { category="arg", event="GoBackLink", arg=true, title=_("Back to previous location"), rolling=true, paging=true,},
    latest_bookmark = { category="none", event="GoToLatestBookmark", title=_("Go to latest bookmark"), rolling=true, paging=true,},
    follow_nearest_link = { category="arg", event="GoToPageLink", arg={pos={x=0,y=0}}, title=_("Follow nearest link"), rolling=true, paging=true,},
    follow_nearest_internal_link = { category="arg", event="GoToInternalPageLink", arg={pos={x=0,y=0}}, title=_("Follow nearest internal link"), rolling=true, paging=true,},
    clear_location_history = { category="arg", event="ClearLocationStack", arg=true, title=_("Clear location history"), rolling=true, paging=true,},
    toc = { category="none", event="ShowToc", title=_("Table of contents"), rolling=true, paging=true,},
    bookmarks = { category="none", event="ShowBookmark", title=_("Bookmarks"), rolling=true, paging=true,},
    book_statistics = { category="none", event="ShowBookStats", title=_("Book statistics"), rolling=true, paging=true,},
    book_status = { category="none", event="ShowBookStatus", title=_("Book status"), rolling=true, paging=true,},
    book_info = { category="none", event="ShowBookInfo", title=_("Book information"), rolling=true, paging=true,},
    book_description = { category="none", event="ShowBookDescription", title=_("Book description"), rolling=true, paging=true,},
    book_cover = { category="none", event="ShowBookCover", title=_("Book cover"), rolling=true, paging=true,},
    show_config_menu = { category="none", event="ShowConfigMenu", title=_("Show bottom menu"), rolling=true, paging=true,},
    toggle_bookmark = { category="none", event="ToggleBookmark", title=_("Toggle bookmark"), rolling=true, paging=true,},
    toggle_inverse_reading_order = { category="none", event="ToggleReadingOrder", title=_("Toggle page turn direction"), rolling=true, paging=true,},
    cycle_highlight_action = { category="none", event="CycleHighlightAction", title=_("Cycle highlight action"), rolling=true, paging=true,},
    cycle_highlight_style = { category="none", event="CycleHighlightStyle", title=_("Cycle highlight style"), rolling=true, paging=true,},
    kosync_push_progress = { category="none", event="KOSyncPushProgress", title=_("Push progress from this device"), rolling=true, paging=true,},
    kosync_pull_progress = { category="none", event="KOSyncPullProgress", title=_("Pull progress from other devices"), rolling=true, paging=true,},
    page_jmp = { category="absolutenumber", event="GotoViewRel", min=-100, max=100, title=_("Go X pages"), rolling=true, paging=true,},

    -- rolling reader settings
    increase_font = { category="incrementalnumber", event="IncreaseFontSize", min=1, max=255, title=_("Increase font size"), rolling=true,},
    decrease_font = { category="incrementalnumber", event="DecreaseFontSize", min=1, max=255, title=_("Decrease font size"), rolling=true,},

    -- paging reader settings
    toggle_page_flipping = { category="none", event="TogglePageFlipping", title=_("Toggle page flipping"), paging=true,},
    toggle_reflow = { category="none", event="ToggleReflow", title=_("Toggle reflow"), paging=true,},
    zoom = { category="string", event="SetZoomMode", title=_("Zoom to"), args={"contentwidth", "contentheight", "pagewidth", "pageheight", "column", "content", "page"}, toggle={"content width", "content height", "page width", "page height", "column", "content", "page"}, paging=true,},

    -- parsed from CreOptions
    -- the rest of the table elements are built from their counterparts in CreOptions
    rotation_mode = {category="string", device=true},
    visible_pages = {category="string", rolling=true},
    h_page_margins = {category="string", rolling=true},
    sync_t_b_page_margins = {category="string", rolling=true},
    t_page_margin = {category="absolutenumber", rolling=true},
    b_page_margin = {category="absolutenumber", rolling=true},
    view_mode = {category="string", rolling=true},
    block_rendering_mode = {category="string", rolling=true},
    render_dpi = {category="string", rolling=true},
    line_spacing = {category="absolutenumber", rolling=true},
    font_size = {category="absolutenumber", title="Font Size", rolling=true},
    font_weight = {category="string", rolling=true},
    --font_gamma = {category="string", rolling=true},
    font_hinting = {category="string", rolling=true},
    font_kerning = {category="string", rolling=true},
    status_line = {category="string", rolling=true},
    embedded_css = {category="string", rolling=true},
    embedded_fonts = {category="string", rolling=true},
    smooth_scaling = {category="string", rolling=true},
    nightmode_images = {category="string", rolling=true},
}

-- array for item order in menu
local dispatcher_menu_order = {
    -- device
    "reading_progress",
    "history",
    "open_previous_document",
    "favorites",
    "filemanager",
    "stats_calendar_view",

    "dictionary_lookup",
    "wikipedia_lookup",
    "fulltext_search",
    "file_search",

    "full_refresh",
    "night_mode",
    "set_night_mode",
    "suspend",
    "exit",
    "restart",
    "reboot",
    "poweroff",

    "show_menu",
    "show_config_menu",
    "show_frontlight_dialog",
    "toggle_frontlight",
    "set_frontlight",
    "increase_frontlight",
    "decrease_frontlight",
    "set_frontlight_warmth",
    "increase_frontlight_warmth",
    "decrease_frontlight_warmth",

    "toggle_hold_corners",
    "toggle_gsensor",
    "toggle_rotation",

    "wifi_on",
    "wifi_off",
    "toggle_wifi",

    "wallabag_download",
    "calibre_search",
    "calibre_browse_tags",
    "calibre_browse_series",

    "rotation_mode",

    -- filemanager
    "folder_up",
    "show_plus_menu",
    "folder_shortcuts",

    -- reader
    "page_jmp",
    "prev_chapter",
    "next_chapter",
    "first_page",
    "last_page",
    "prev_bookmark",
    "next_bookmark",
    "go_to",
    "skim",
    "back",
    "previous_location",
    "latest_bookmark",
    "follow_nearest_link",
    "follow_nearest_internal_link",
    "clear_location_history",

    "toc",
    "bookmarks",
    "book_statistics",

    "book_status",
    "book_info",
    "book_description",
    "book_cover",

    "increase_font",
    "decrease_font",
    "font_size",
    --"font_gamma",
    "font_weight",
    "font_hinting",
    "font_kerning",

    "toggle_bookmark",
    "toggle_page_flipping",
    "toggle_reflow",
    "toggle_inverse_reading_order",
    "zoom",
    "cycle_highlight_action",
    "cycle_highlight_style",

    "kosync_push_progress",
    "kosync_pull_progress",

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
}

--[[--
    add settings from CreOptions / KoptOptions
--]]--
function Dispatcher:init()
    local parseoptions = function(base, i)
        for y=1,#base[i].options do
            local option = base[i].options[y]
            if settingsList[option.name] ~= nil then
                if settingsList[option.name].event == nil then
                    settingsList[option.name].event = option.event
                end
                if settingsList[option.name].title == nil then
                    settingsList[option.name].title = option.name_text
                end
                if settingsList[option.name].category == "string" then
                    if settingsList[option.name].toggle == nil then
                        settingsList[option.name].toggle = option.toggle or option.labels
                        if settingsList[option.name].toggle == nil then
                        settingsList[option.name].toggle = {}
                            for z=1,#option.values do
                                if type(option.values[z]) == "table" then
                                    settingsList[option.name].toggle[z] = option.values[z][1]
                                end
                            end
                        end
                    end
                    if settingsList[option.name].args == nil then
                        settingsList[option.name].args = option.args or option.values
                    end
                elseif settingsList[option.name].category == "absolutenumber" then
                    if settingsList[option.name].min == nil then
                        settingsList[option.name].min = option.args[1]
                    end
                    if settingsList[option.name].max == nil then
                        settingsList[option.name].max = option.args[#option.args]
                    end
                    if settingsList[option.name].default == nil then
                        settingsList[option.name].default = option.default_value
                    end
                end
            end
        end
    end
    for i=1,#CreOptions do
        parseoptions(CreOptions, i)
    end
    Dispatcher.initialized = true
end

function Dispatcher:addItem(menu, location, settings, section)
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
                        if location[settings] ~= nil
                            and location[settings][k]
                        then
                            location[settings][k] = nil
                        else
                            location[settings][k] = true
                        end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                   end,
                   separator = settingsList[k].separator,
               })
            elseif settingsList[k].category == "absolutenumber" then
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, location[settings][k] or "")
                    end,
                    checked_func = function()
                    return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            width = Screen:getWidth() * 0.6,
                            value = location[settings][k] or settingsList[k].default or 0,
                            value_min = settingsList[k].min,
                            value_step = 1,
                            value_hold_step = 2,
                            value_max = settingsList[k].max,
                            default_value = 0,
                            title_text = T(settingsList[k].title, location[settings][k] or ""),
                            callback = function(spin)
                                location[settings][k] = spin.value
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        location[settings][k] = nil
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    separator = settingsList[k].separator,
                })
            elseif settingsList[k].category == "incrementalnumber" then
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, location[settings][k] or "")
                    end,
                    checked_func = function()
                    return location[settings] ~= nil and location[settings][k] ~= nil
                    end,
                    callback = function(touchmenu_instance)
                        local _ = require("gettext")
                        local SpinWidget = require("ui/widget/spinwidget")
                        local items = SpinWidget:new{
                            width = Screen:getWidth() * 0.6,
                            value = location[settings][k] or 0,
                            value_min = settingsList[k].min,
                            value_step = 1,
                            value_hold_step = 2,
                            value_max = settingsList[k].max,
                            default_value = 0,
                            title_text = T(settingsList[k].title, location[settings][k] or ""),
                            info_text = _([[If called by a gesture the amount of the gesture will be used]]),
                            callback = function(spin)
                                location[settings][k] = spin.value
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end
                        }
                        UIManager:show(items)
                    end,
                    hold_callback = function(touchmenu_instance)
                        location[settings][k] = nil
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    separator = settingsList[k].separator,
                })
            elseif settingsList[k].category == "string" then
                local sub_item_table = {}
                for i=1,#settingsList[k].args do
                    table.insert(sub_item_table, {
                        text = tostring(settingsList[k].toggle[i]),
                        checked_func = function()
                            return location[settings] ~= nil
                                and location[settings][k] ~= nil
                                and location[settings][k] == settingsList[k].args[i]
                        end,
                        callback = function()
                            location[settings][k] = settingsList[k].args[i]
                        end,
                    })
                end
                table.insert(menu, {
                    text_func = function()
                        return T(settingsList[k].title, location[settings][k])
                    end,
                    checked_func = function()
                        return location[settings] ~= nil
                            and location[settings][k] ~= nil
                    end,
                    sub_item_table = sub_item_table,
                    keep_menu_open = true,
                    hold_callback = function(touchmenu_instance)
                        location[settings][k] = nil
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
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
    1) the table representing the submenu (can be empty)
    2) the object (table) in which the settings table is found
    3) the name of the settings table
example usage:
    Dispatcher.addSubMenu(sub_items, self.data, "profile1")
--]]--
function Dispatcher:addSubMenu(menu, location, settings)
    if not Dispatcher.initialized then Dispatcher:init() end
    table.insert(menu, {
        text = _("None"),
        separator = true,
        checked_func = function()
            return next(location[settings]) == nil
        end,
        callback = function(touchmenu_instance)
            location[settings] = {}
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    local section_list = {
        {"device", _("Device")},
        {"filemanager", _("File browser")},
        {"rolling", _("Reflowable documents (epub, fb2, txt…)")},
        {"paging", _("Fixed layout documents (pdf, djvu, pics…)")},
    }
    for _, section in ipairs(section_list) do
        local submenu = {}
        -- pass caller's context
        Dispatcher:addItem(submenu, location, settings, section[1])
        table.insert(menu, {
            text = section[2],
            sub_item_table = submenu,
        })
    end
end

--[[--
Calls the events in a settings list
arguments are:
    1) a reference to the uimanager
    2) the settings table
    3) optionally a `gestures`object
--]]--
function Dispatcher:execute(ui, settings, gesture)
    for k, v in pairs(settings) do
        if settingsList[k].conditions == nil or settingsList[k].conditions == true then
            if settingsList[k].category == "none" then
                ui:handleEvent(Event:new(settingsList[k].event))
            end
            if settingsList[k].category == "absolutenumber"
                or settingsList[k].category == "string"
            then
                ui:handleEvent(Event:new(settingsList[k].event, v))
            end
            -- the event can accept a gesture object or an argument
            if settingsList[k].category == "arg" then
                local arg = gesture or settingsList[k].arg
                ui:handleEvent(Event:new(settingsList[k].event, arg))
            end
            -- the event can accept a gesture object or a number
            if settingsList[k].category == "incrementalnumber" then
                local arg = gesture or v
                ui:handleEvent(Event:new(settingsList[k].event, arg))
            end
        end
    end
end

return Dispatcher
