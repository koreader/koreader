local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaData = require("luadata")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")
local logger = require("logger")

local ReaderGesture = InputContainer:new{}

local action_strings = {
    nothing = _("Nothing"),
    ignore = _("Ignore"),

    page_jmp_back_10 = _("Back 10 pages"),
    page_jmp_back_1 = _("Previous page"),
    page_jmp_fwd_10 = _("Forward 10 pages"),
    page_jmp_fwd_1 = _("Next page"),
    prev_chapter = _("Previous chapter"),
    next_chapter = _("Next chapter"),
    go_to = _("Go to"),
    skim = _("Skim"),
    back = _("Back"),
    previous_location = _("Back to previous location"),
    latest_bookmark = _("Go to latest bookmark"),
    follow_nearest_link = _("Follow nearest link"),
    follow_nearest_internal_link = _("Follow nearest internal link"),
    clear_location_history = _("Clear location history"),

    toc = _("Table of contents"),
    bookmarks = _("Bookmarks"),
    reading_progress = _("Reading progress"),
    book_status = _("Book status"),
    book_info = _("Book information"),
    book_description = _("Book description"),
    book_cover = _("Book cover"),

    history = _("History"),
    open_previous_document = _("Open previous document"),
    filemanager = _("File browser"),

    dictionary_lookup = _("Dictionary lookup"),
    wikipedia_lookup = _("Wikipedia lookup"),
    fulltext_search = _("Fulltext search"),
    file_search = _("File search"),

    full_refresh = _("Full screen refresh"),
    night_mode = _("Night mode"),
    suspend = _("Suspend"),
    exit = _("Exit KOReader"),
    restart = _("Restart KOReader"),
    show_menu = _("Show menu"),
    show_config_menu = _("Show bottom menu"),
    show_frontlight_dialog = _("Show frontlight dialog"),
    toggle_frontlight = _("Toggle frontlight"),
    toggle_gsensor = _("Toggle accelerometer"),
    toggle_rotation = _("Toggle rotation"),

    wifi_on = _("Enable wifi"),
    wifi_off = _("Disable wifi"),
    toggle_wifi = _("Toggle wifi"),

    toggle_bookmark = _("Toggle bookmark"),
    toggle_page_flipping = _("Toggle page flipping"),
    toggle_reflow = _("Toggle reflow"),

    zoom_contentwidth = _("Zoom to fit content width"),
    zoom_contentheight = _("Zoom to fit content height"),
    zoom_pagewidth = _("Zoom to fit page width"),
    zoom_pageheight = _("Zoom to fit page height"),
    zoom_column = _("Zoom to fit column"),
    zoom_content = _("Zoom to fit content"),
    zoom_page = _("Zoom to fit page"),

    folder_up = _("Folder up"),
    show_plus_menu = _("Show plus menu"),
    folder_shortcuts = _("Folder shortcuts"),
    cycle_highlight_action = _("Cycle highlight action"),
    cycle_highlight_style = _("Cycle highlight style"),
    wallabag_download = _("Wallabag retrieval"),
}

local custom_multiswipes_path = DataStorage:getSettingsDir().."/multiswipes.lua"
local custom_multiswipes = LuaData:open(custom_multiswipes_path, { name = "MultiSwipes" })
local custom_multiswipes_table = custom_multiswipes:readSetting("multiswipes")

local default_multiswipes = {
    "west east",
    "east west",
    "north south",
    "south north",
    true, -- separator
    "north west",
    "north east",
    "south west",
    "south east",
    "east north",
    "west north",
    "east south",
    "west south",
    true, -- separator
    "north south north",
    "south north south",
    "west east west",
    "east west east",
    true, -- separator
    "south west north",
    "north east south",
    "north west south",
    "west south east",
    "west north east",
    "east south west",
    "east north west",
    "south east north",
    true, -- separator
    "east north west east",
    "south east north south",
    true, -- separator
    "east south west north",
    "west south east north",
    "south east north west",
    "south west north east",
    true, -- separator
    "southeast northeast",
    "northeast southeast",
    -- "southwest northwest", -- visually ambiguous
    -- "northwest southwest", -- visually ambiguous
    "northwest southwest northwest",
    "southeast southwest northwest",
    "southeast northeast northwest",
}
local multiswipes = {}
local multiswipes_info_text = _([[
Multiswipes allow you to perform complex gestures built up out of multiple swipe directions, never losing touch with the screen.

These advanced gestures consist of either straight swipes or diagonal swipes. To ensure accuracy, they can't be mixed.]])

function ReaderGesture:init()
    if not Device:isTouchDevice() then return end
    self.multiswipes_enabled = G_reader_settings:readSetting("multiswipes_enabled")
    self.is_docless = self.ui == nil or self.ui.document == nil
    self.ges_mode = self.is_docless and "gesture_fm" or "gesture_reader"
    self.default_gesture = {
        tap_top_left_corner = self.ges_mode == "gesture_reader" and "toggle_page_flipping" or "ignore",
        tap_top_right_corner = self.ges_mode == "gesture_reader" and "toggle_bookmark" or "show_plus_menu",
        tap_right_bottom_corner = "ignore",
        tap_left_bottom_corner = Device:hasFrontlight() and "toggle_frontlight" or "ignore",
        hold_top_left_corner = "ignore",
        hold_top_right_corner = "ignore",
        hold_bottom_left_corner = "ignore",
        hold_bottom_right_corner = "ignore",
        two_finger_tap_top_left_corner = "ignore",
        two_finger_tap_top_right_corner = "ignore",
        two_finger_tap_bottom_left_corner = "ignore",
        two_finger_tap_bottom_right_corner = "ignore",
        short_diagonal_swipe = "full_refresh",
        multiswipe = "nothing", -- otherwise registerGesture() won't pick up on multiswipes
        multiswipe_west_east = self.ges_mode == "gesture_reader" and "previous_location" or "nothing",
        multiswipe_east_west = self.ges_mode == "gesture_reader" and "latest_bookmark" or "nothing",
        multiswipe_north_east = self.ges_mode == "gesture_reader" and "toc" or "nothing",
        multiswipe_north_west = self.ges_mode == "gesture_reader" and "bookmarks" or "folder_shortcuts",
        multiswipe_north_south = self.ges_mode == "gesture_reader" and "nothing" or "folder_up",
        multiswipe_east_north = "history",
        multiswipe_west_north = self.ges_mode == "gesture_reader" and "book_status" or "nothing",
        multiswipe_east_south = "go_to",
        multiswipe_south_north = self.ges_mode == "gesture_reader" and "skim" or "nothing",
        multiswipe_south_east = self.ges_mode == "gesture_reader" and "toggle_reflow" or "nothing",
        multiswipe_south_west = "show_frontlight_dialog",
        multiswipe_west_south = "back",
        multiswipe_north_south_north = self.ges_mode == "gesture_reader" and "prev_chapter" or "nothing",
        multiswipe_south_north_south = self.ges_mode == "gesture_reader" and "next_chapter" or "nothing",
        multiswipe_west_east_west = "open_previous_document",
        multiswipe_east_north_west = self.ges_mode == "gesture_reader" and "zoom_contentwidth" or "nothing",
        multiswipe_south_east_north = self.ges_mode == "gesture_reader" and "zoom_contentheight" or "nothing",
        multiswipe_east_north_west_east = self.ges_mode == "gesture_reader" and "zoom_pagewidth" or "nothing",
        multiswipe_south_east_north_south = self.ges_mode == "gesture_reader" and "zoom_pageheight" or "nothing",
        multiswipe_east_south_west_north = "full_refresh",
        multiswipe_southeast_northeast = self.ges_mode == "gesture_reader" and "follow_nearest_link" or "nothing",
        multiswipe_northwest_southwest_northwest = Device:hasWifiToggle() and "toggle_wifi" or "nothing",
        multiswipe_southeast_southwest_northwest = Device:hasWifiToggle() and "wifi_off" or "nothing",
        multiswipe_southeast_northeast_northwest = Device:hasWifiToggle() and "wifi_on" or "nothing",

        two_finger_swipe_east = self.ges_mode == "gesture_reader" and "toc" or "ignore",
        two_finger_swipe_west = self.ges_mode == "gesture_reader" and "bookmarks" or "folder_shortcuts",
        two_finger_swipe_northeast = "ignore",
        two_finger_swipe_northwest = "ignore",
        two_finger_swipe_southeast = "ignore",
        two_finger_swipe_southwest = "ignore",
    }
    local gm = G_reader_settings:readSetting(self.ges_mode)
    if gm == nil then G_reader_settings:saveSetting(self.ges_mode, {}) end
    self.ui.menu:registerToMainMenu(self)
    self:initGesture()
end

function ReaderGesture:initGesture()
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    for gesture, action in pairs(self.default_gesture) do
        if not gesture_manager[gesture] then
            gesture_manager[gesture] = action
        end
    end
    for gesture, action in pairs(gesture_manager) do
        self:setupGesture(gesture, action)
    end
    G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
end

function ReaderGesture:genMultiswipeSubmenu()
    return {
        text = _("Multiswipe"),
        sub_item_table = self:buildMultiswipeMenu(),
        enabled_func = function() return self.multiswipes_enabled end,
        separator = true,
    }
end

function ReaderGesture:addToMainMenu(menu_items)
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)

    local actionTextFunc = function(gesture, gesture_name)
        local action_name = gesture_manager[gesture] ~= "nothing" and action_strings[gesture_manager[gesture]] or _("Available")
        return T(_("%1   (%2)"), gesture_name, action_name)
    end
    local corner_hold_submenu = {
        text = _("Hold corner"),
        sub_item_table = {
            {
                text_func = function() return actionTextFunc("hold_top_left_corner", _("Top left")) end,
                enabled_func = function() return self.ges_mode == "gesture_reader" end,
                sub_item_table = self:buildMenu("hold_top_left_corner", self.default_gesture["hold_top_left_corner"]),
            },
            {
                text_func = function() return actionTextFunc("hold_top_right_corner", _("Top right")) end,
                sub_item_table = self:buildMenu("hold_top_right_corner", self.default_gesture["hold_top_right_corner"]),
            },
            {
                text_func = function() return actionTextFunc("hold_bottom_left_corner", _("Bottom left")) end,
                sub_item_table = self:buildMenu("hold_bottom_left_corner", self.default_gesture["hold_bottom_left_corner"]),
            },
            {
                text_func = function() return actionTextFunc("hold_bottom_right_corner", _("Bottom right")) end,
                sub_item_table = self:buildMenu("hold_bottom_right_corner", self.default_gesture["hold_bottom_right_corner"]),
            },
        },
    }
    menu_items.gesture_manager = {
        text = _("Gesture manager"),
        sub_item_table = {
            {
                text = _("Enable multiswipes"),
                checked_func = function() return self.multiswipes_enabled end,
                callback = function()
                    G_reader_settings:saveSetting("multiswipes_enabled", not self.multiswipes_enabled)
                    self.multiswipes_enabled = G_reader_settings:isTrue("multiswipes_enabled")
                end,
                help_text = multiswipes_info_text,
            },
            {
                text = _("Multiswipe recorder"),
                enabled_func = function() return self.multiswipes_enabled end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local multiswipe_recorder
                    multiswipe_recorder = InputDialog:new{
                        title = _("Multiswipe recorder"),
                        input_hint = _("Make a multiswipe gesture"),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(multiswipe_recorder)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        local recorded_multiswipe = multiswipe_recorder._raw_multiswipe
                                        if not recorded_multiswipe then return end
                                        logger.dbg("Multiswipe recorder detected:", recorded_multiswipe)

                                        for k, multiswipe in pairs(multiswipes) do
                                            if recorded_multiswipe == multiswipe then
                                                UIManager:show(InfoMessage:new{
                                                    text = _("Recorded multiswipe already exists."),
                                                    show_icon = false,
                                                    timeout = 5,
                                                })
                                                return
                                            end
                                        end

                                        custom_multiswipes:addTableItem("multiswipes", recorded_multiswipe)
                                        -- TODO implement some nicer method in TouchMenu than this ugly hack for updating the menu
                                        touchmenu_instance.item_table[3] = self:genMultiswipeSubmenu()
                                        touchmenu_instance:updateItems()
                                        UIManager:close(multiswipe_recorder)
                                    end,
                                },
                            }
                        },
                    }

                    multiswipe_recorder.ges_events.Multiswipe = {
                        GestureRange:new{
                            ges = "multiswipe",
                            range = Geom:new{
                                x = 0, y = 0,
                                w = Screen:getWidth(),
                                h = Screen:getHeight(),
                            },
                            doc = "Multiswipe in gesture creator"
                        }
                    }

                    function multiswipe_recorder:onMultiswipe(arg, ges)
                        multiswipe_recorder._raw_multiswipe = ges.multiswipe_directions
                        multiswipe_recorder:setInputText(ReaderGesture:friendlyMultiswipeName(multiswipe_recorder._raw_multiswipe))
                    end

                    UIManager:show(multiswipe_recorder)
                end,
                help_text = _("The number of possible multiswipe gestures is theoretically infinite. With the multiswipe recorder you can easily record your own."),
            },
            -- NB If this changes from position 3, also update the position of this menu in multigesture recorder callback
            self:genMultiswipeSubmenu(),
            {
                text = _("Tap top left corner"),
                enabled_func = function() return self.ges_mode == "gesture_reader" end,
                sub_item_table = self:buildMenu("tap_top_left_corner", self.default_gesture["tap_top_left_corner"]),
            },
            {
                text = _("Tap top right corner"),
                sub_item_table = self:buildMenu("tap_top_right_corner", self.default_gesture["tap_top_right_corner"]),
            },
            {
                text = _("Tap bottom left corner"),
                sub_item_table = self:buildMenu("tap_left_bottom_corner", self.default_gesture["tap_left_bottom_corner"]),
            },
            {
                text = _("Tap bottom right corner"),
                sub_item_table = self:buildMenu("tap_right_bottom_corner", self.default_gesture["tap_right_bottom_corner"]),
                separator = true,
            },
            corner_hold_submenu,
            {
                text = _("Short diagonal swipe"),
                sub_item_table = self:buildMenu("short_diagonal_swipe", self.default_gesture["short_diagonal_swipe"]),
            },
        },
    }

    local twoFingerSwipeTextFunc = function(gesture, friendly_name)
        local action_name = gesture_manager[gesture] ~= "nothing" and action_strings[gesture_manager[gesture]] or _("Available")
        return T(_("%1   (%2)"), friendly_name, action_name)
    end

    if Device:hasMultitouch() then
        local corner_two_finger_tap_submenu = {
            text = _("Two-finger tap corner"),
            sub_item_table = {
                {
                    text_func = function() return actionTextFunc("two_finger_tap_top_left_corner", _("Top left")) end,
                    sub_item_table = self:buildMenu("two_finger_tap_top_left_corner", self.default_gesture["two_finger_tap_top_left_corner"]),
                },
                {
                    text_func = function() return actionTextFunc("two_finger_tap_top_right_corner", _("Top right")) end,
                    sub_item_table = self:buildMenu("two_finger_tap_top_right_corner", self.default_gesture["two_finger_tap_top_right_corner"]),
                },
                {
                    text_func = function() return actionTextFunc("two_finger_tap_bottom_left_corner", _("Bottom left")) end,
                    sub_item_table = self:buildMenu("two_finger_tap_bottom_left_corner", self.default_gesture["two_finger_tap_bottom_left_corner"]),
                },
                {
                    text_func = function() return actionTextFunc("two_finger_tap_bottom_right_corner", _("Bottom right")) end,
                    sub_item_table = self:buildMenu("two_finger_tap_bottom_right_corner", self.default_gesture["two_finger_tap_bottom_right_corner"]),
                },
            },
        }
        table.insert(menu_items.gesture_manager.sub_item_table, corner_two_finger_tap_submenu)
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = _("Two-finger swipe"),
            sub_item_table = {
                {
                    text_func = function() return twoFingerSwipeTextFunc("two_finger_swipe_east", "➡") end,
                    sub_item_table = self:buildMenu("two_finger_swipe_east", self.default_gesture["two_finger_swipe_east"]),
                },
                {
                    text_func = function() return twoFingerSwipeTextFunc("two_finger_swipe_west", "⬅") end,
                    sub_item_table = self:buildMenu("two_finger_swipe_west", self.default_gesture["two_finger_swipe_west"]),
                },
                {
                    text_func = function() return twoFingerSwipeTextFunc("two_finger_swipe_northeast", "⬈") end,
                    sub_item_table = self:buildMenu("two_finger_swipe_northeast", self.default_gesture["two_finger_swipe_northeast"]),
                },
                {
                    text_func = function() return twoFingerSwipeTextFunc("two_finger_swipe_northwest", "⬉") end,
                    sub_item_table = self:buildMenu("two_finger_swipe_northwest", self.default_gesture["two_finger_swipe_northwest"]),
                },
                {
                    text_func = function() return twoFingerSwipeTextFunc("two_finger_swipe_southeast", "⬊") end,
                    sub_item_table = self:buildMenu("two_finger_swipe_southeast", self.default_gesture["two_finger_swipe_southeast"]),
                },
                {
                    text_func = function() return twoFingerSwipeTextFunc("two_finger_swipe_southwest", "⬋") end,
                    sub_item_table = self:buildMenu("two_finger_swipe_southwest", self.default_gesture["two_finger_swipe_southwest"]),
                },
            },
        })
    end
end

function ReaderGesture:buildMenu(ges, default)
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    local menu = {
        {"nothing", true },
        {"ignore", true, true },
        {"page_jmp_back_10", not self.is_docless},
        {"page_jmp_back_1", not self.is_docless},
        {"page_jmp_fwd_10", not self.is_docless},
        {"page_jmp_fwd_1", not self.is_docless},
        {"prev_chapter", not self.is_docless},
        {"next_chapter", not self.is_docless},
        {"go_to", true},
        {"skim", not self.is_docless},
        {"back", true},
        {"previous_location", not self.is_docless},
        {"latest_bookmark", not self.is_docless},
        {"follow_nearest_link", not self.is_docless},
        {"follow_nearest_internal_link", not self.is_docless},
        {"clear_location_history", not self.is_docless, true},

        {"folder_up", self.is_docless},
        {"show_plus_menu", self.is_docless},
        {"folder_shortcuts", true, true},

        { "toc", not self.is_docless},
        {"bookmarks", not self.is_docless},
        {"reading_progress", ReaderGesture.getReaderProgress ~= nil},
        {"book_status", not self.is_docless},
        {"book_info", not self.is_docless},
        {"book_description", not self.is_docless},
        {"book_cover", not self.is_docless, true},

        {"history", true},
        {"open_previous_document", true, true},
        {"filemanager", not self.is_docless, true},

        {"dictionary_lookup", true},
        {"wikipedia_lookup", true, true},
        {"fulltext_search", not self.is_docless},
        {"file_search", true, true},

        {"full_refresh", true},
        {"night_mode", true},
        {"suspend", true},
        {"exit", true},
        {"restart", not Device:isAndroid()},

        {"show_menu", true},
        {"show_config_menu", not self.is_docless, true},
        {"show_frontlight_dialog", Device:hasFrontlight()},
        {"toggle_frontlight", Device:hasFrontlight(), true},
        {"toggle_gsensor", Device:canToggleGSensor()},
        {"toggle_rotation", not self.is_docless, true},

        {"wifi_on", Device:hasWifiToggle()},
        {"wifi_off", Device:hasWifiToggle()},
        {"toggle_wifi", Device:hasWifiToggle(), true},

        {"toggle_bookmark", not self.is_docless, true},
        {"toggle_page_flipping", not self.is_docless, true},
        {"toggle_reflow", not self.is_docless, true},
        {"zoom_contentwidth", not self.is_docless},
        {"zoom_contentheight", not self.is_docless},
        {"zoom_pagewidth", not self.is_docless},
        {"zoom_pageheight", not self.is_docless},
        {"zoom_column", not self.is_docless},
        {"zoom_content", not self.is_docless},
        {"zoom_page", not self.is_docless, true},
        {"cycle_highlight_action", not self.is_docless},
        {"cycle_highlight_style", not self.is_docless},
        {"wallabag_download", self.ui.wallabag ~= nil},
    }
    local return_menu = {}
    -- add default action to the top of the submenu
    for __, entry in pairs(menu) do
        if entry[1] == default then
            local menu_entry_default = T(_("%1 (default)"), action_strings[entry[1]])
            table.insert(return_menu, self:createSubMenu(menu_entry_default, entry[1], ges, true))

            if not gesture_manager[ges] then
                gesture_manager[ges] = default
                G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
            end
            break
        end
    end
    -- another elements
    for _, entry in pairs(menu) do
        if not entry[2] and gesture_manager[ges] == entry[1] then
            gesture_manager[ges] = "nothing"
            G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
        end
        if entry[1] ~= default and entry[2] then
            local sep = entry[1] == "nothing" or entry[3] == true
            table.insert(return_menu, self:createSubMenu(action_strings[entry[1]], entry[1], ges, sep))
        end
    end
    return return_menu
end

function ReaderGesture:buildMultiswipeMenu()
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    local menu = {}
    multiswipes = {}

    -- Build a list of gestures in settings, so we can show those
    -- that don't appear anymore in default or custom lists, and
    -- allow removing them (as they will still work)
    local settings_gestures = {}
    for k, v in pairs(gesture_manager) do
        if k:sub(1, 11) == "multiswipe_" then
            k = k:sub(12):gsub("_", " ")
            settings_gestures[k] = v
        end
    end

    for k, v in pairs(default_multiswipes) do
        table.insert(multiswipes, v)
        settings_gestures[v] = nil -- remove from settings list
    end

    if custom_multiswipes_table and #custom_multiswipes_table > 0 then
        table.insert(multiswipes, true) -- add separator
        for k, v in pairs(custom_multiswipes_table) do
            table.insert(multiswipes, v)
            settings_gestures[v] = nil -- remove from settings list
        end
    end

    if next(settings_gestures) then -- there are old gestures in settings
        table.insert(multiswipes, true) -- add separator
        for k, v in pairs(settings_gestures) do
            table.insert(multiswipes, k)
        end
    end

    for i=1, #multiswipes do
        local separator = false
        if i < #multiswipes and multiswipes[i+1] == true then
            separator = true
        end
        if type(multiswipes[i]) == "string" then -- skip separators (true)
            local multiswipe = multiswipes[i]
            local friendly_multiswipe_name = self:friendlyMultiswipeName(multiswipe)
            -- friendly_multiswipe_name = friendly_multiswipe_name .. os.time() -- for debugging menu updates
            local safe_multiswipe_name = "multiswipe_"..self:safeMultiswipeName(multiswipe)
            local default_action = self.default_gesture[safe_multiswipe_name] and self.default_gesture[safe_multiswipe_name] or "nothing"
            table.insert(menu, {
                text_func = function()
                    local action_name = gesture_manager[safe_multiswipe_name] ~= "nothing" and action_strings[gesture_manager[safe_multiswipe_name]] or _("Available")
                    return T(_("%1   (%2)"), friendly_multiswipe_name, action_name)
                end,
                sub_item_table = self:buildMenu(safe_multiswipe_name, default_action),
                hold_callback = function(touchmenu_instance)
                    if i > #default_multiswipes + 1 then -- +1 for added separator (true)
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Remove custom multiswipe %1?"), friendly_multiswipe_name),
                            ok_text = _("Remove"),
                            ok_callback = function()
                                -- Remove associated action from settings
                                gesture_manager[safe_multiswipe_name] = nil
                                -- multiswipes are a combined table, first defaults, then custom
                                -- so the right index is minus #defalt_multiswipes minus 1 added separator
                                custom_multiswipes:removeTableItem("multiswipes", i-#default_multiswipes-1)
                                -- touchmenu_instance.item_table = self:buildMultiswipeMenu()
                                -- We need to update touchmenu_instance.item_table in-place for the upper
                                -- menu to have it updated too
                                local item_table = touchmenu_instance.item_table
                                while #item_table > 0 do
                                    table.remove(item_table, #item_table)
                                end
                                for __, v in ipairs(self:buildMultiswipeMenu()) do
                                    table.insert(item_table, v)
                                end
                                touchmenu_instance:updateItems()
                            end,
                        })
                    end
                end,
                separator = separator,
            })
        end
    end

    return menu
end

function ReaderGesture:createSubMenu(text, action, ges, separator)
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    return {
        text = text,
        checked_func = function()
            return gesture_manager[ges] == action
        end,
        callback = function()
            gesture_manager[ges] = action
            G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
            self:setupGesture(ges, action)
        end,
        separator = separator or false,
    }
end

local multiswipe_to_arrow = {
    east = "➡",
    west = "⬅",
    north = "⬆",
    south = "⬇",
    northeast = "⬈",
    northwest = "⬉",
    southeast = "⬊",
    southwest = "⬋",
}
function ReaderGesture:friendlyMultiswipeName(multiswipe)
    return multiswipe:gsub("%S+", multiswipe_to_arrow)
end

function ReaderGesture:safeMultiswipeName(multiswipe)
    return multiswipe:gsub(" ", "_")
end

function ReaderGesture:setupGesture(ges, action)
    local ges_type
    local zone
    local overrides
    local direction, distance

    local zone_fullscreen = {
        ratio_x = 0.0, ratio_y = 0,
        ratio_w = 1, ratio_h = 1,
    }

    -- legacy global variable DTAP_ZONE_FLIPPING may still be defined in default.persistent.lua
    local dtap_zone_top_left = DTAP_ZONE_FLIPPING and DTAP_ZONE_FLIPPING or DTAP_ZONE_TOP_LEFT
    local zone_top_left_corner = {
        ratio_x = dtap_zone_top_left.x,
        ratio_y = dtap_zone_top_left.y,
        ratio_w = dtap_zone_top_left.w,
        ratio_h = dtap_zone_top_left.h,
    }
    -- legacy global variable DTAP_ZONE_BOOKMARK may still be defined in default.persistent.lua
    local dtap_zone_top_right = DTAP_ZONE_BOOKMARK and DTAP_ZONE_BOOKMARK or DTAP_ZONE_TOP_RIGHT
    local zone_top_right_corner = {
        ratio_x = dtap_zone_top_right.x,
        ratio_y = dtap_zone_top_right.y,
        ratio_w = dtap_zone_top_right.w,
        ratio_h = dtap_zone_top_right.h,
    }
    local zone_bottom_left_corner = {
        ratio_x = DTAP_ZONE_BOTTOM_LEFT.x,
        ratio_y = DTAP_ZONE_BOTTOM_LEFT.y,
        ratio_w = DTAP_ZONE_BOTTOM_LEFT.w,
        ratio_h = DTAP_ZONE_BOTTOM_LEFT.h,
    }
    local zone_bottom_right_corner = {
        ratio_x = DTAP_ZONE_BOTTOM_RIGHT.x,
        ratio_y = DTAP_ZONE_BOTTOM_RIGHT.y,
        ratio_w = DTAP_ZONE_BOTTOM_RIGHT.w,
        ratio_h = DTAP_ZONE_BOTTOM_RIGHT.h,
    }

    local overrides_tap_corner
    local overrides_hold_corner
    if self.is_docless then
        overrides_tap_corner = {
            "filemanager_tap",
        }
    else
        overrides_tap_corner = {
            "tap_backward",
            "tap_forward",
            "readermenu_tap",
            "readerconfigmenu_tap",
            "readerfooter_tap",
        }
        overrides_hold_corner = {
            "readerfooter_hold",
        }
    end

    if ges == "multiswipe" then
        ges_type = "multiswipe"
        zone = zone_fullscreen
        direction = {
            northeast = true, northwest = true,
            southeast = true, southwest = true,
            east = true, west = true,
            north = true, south = true,
        }
    elseif ges == "tap_top_left_corner" then
        ges_type = "tap"
        zone = zone_top_left_corner
        overrides = overrides_tap_corner
    elseif ges == "tap_top_right_corner" then
        ges_type = "tap"
        zone = zone_top_right_corner
        overrides = overrides_tap_corner
    elseif ges == "tap_right_bottom_corner" then
        ges_type = "tap"
        zone = zone_bottom_right_corner
        overrides = overrides_tap_corner
    elseif ges == "tap_left_bottom_corner" then
        ges_type = "tap"
        zone = zone_bottom_left_corner
        overrides = overrides_tap_corner
    elseif ges == "hold_top_left_corner" then
        ges_type = "hold"
        zone = zone_top_left_corner
        overrides = overrides_hold_corner
    elseif ges == "hold_top_right_corner" then
        ges_type = "hold"
        zone = zone_top_right_corner
        overrides = overrides_hold_corner
    elseif ges == "hold_bottom_right_corner" then
        ges_type = "hold"
        zone = zone_bottom_right_corner
        overrides = overrides_hold_corner
    elseif ges == "hold_bottom_left_corner" then
        ges_type = "hold"
        zone = zone_bottom_left_corner
        overrides = overrides_hold_corner
    elseif ges == "two_finger_tap_top_left_corner" then
        ges_type = "two_finger_tap"
        zone = zone_top_left_corner
    elseif ges == "two_finger_tap_top_right_corner" then
        ges_type = "two_finger_tap"
        zone = zone_top_right_corner
    elseif ges == "two_finger_tap_bottom_right_corner" then
        ges_type = "two_finger_tap"
        zone = zone_bottom_right_corner
    elseif ges == "two_finger_tap_bottom_left_corner" then
        ges_type = "two_finger_tap"
        zone = zone_bottom_left_corner
    elseif ges == "two_finger_swipe_west" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {west = true}
    elseif ges == "two_finger_swipe_east" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {east = true}
    elseif ges == "two_finger_swipe_northwest" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {northwest = true}
    elseif ges == "two_finger_swipe_northeast" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {northeast = true}
    elseif ges == "two_finger_swipe_southwest" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {southwest = true}
    elseif ges == "two_finger_swipe_southeast" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {southeast = true}
    elseif ges == "short_diagonal_swipe" then
        ges_type = "swipe"
        zone = {
            ratio_x = 0.0, ratio_y = 0,
            ratio_w = 1, ratio_h = 1,
        }
        direction = {northeast = true, northwest = true, southeast = true, southwest = true}
        distance = "short"
        if self.is_docless then
            overrides = {
                "filemanager_tap",
            }
        else
            overrides = {
                "rolling_swipe",
                "paging_swipe",
            }
        end

    else return
    end
    self:registerGesture(ges, action, ges_type, zone, overrides, direction, distance)
end

function ReaderGesture:registerGesture(ges, action, ges_type, zone, overrides, direction, distance)
    self.ui:registerTouchZones({
        {
            id = ges,
            ges = ges_type,
            screen_zone = zone,
            handler = function(gest)
                if distance == "short" and gest.distance > Screen:scaleBySize(300) then return end
                if direction and not direction[gest.direction] then return end

                if ges == "multiswipe" then
                    if self.multiswipes_enabled == nil then
                        UIManager:show(ConfirmBox:new{
                            text = _("You have just performed a multiswipe gesture for the first time.") .."\n\n".. multiswipes_info_text,
                            ok_text = _("Enable"),
                            ok_callback = function()
                                G_reader_settings:saveSetting("multiswipes_enabled", true)
                                self.multiswipes_enabled = true
                            end,
                            cancel_text = _("Disable"),
                            cancel_callback = function()
                                G_reader_settings:saveSetting("multiswipes_enabled", false)
                                self.multiswipes_enabled = false
                            end,
                        })
                    else
                        return self:multiswipeAction(gest.multiswipe_directions, gest)
                    end
                end

                return self:gestureAction(action, gest)
            end,
            overrides = overrides,
        },
    })
end

function ReaderGesture:gestureAction(action, ges)
    if action == "ignore" then
        return
    elseif action == "reading_progress" and ReaderGesture.getReaderProgress then
        UIManager:show(ReaderGesture.getReaderProgress())
    elseif action == "toc" then
        self.ui:handleEvent(Event:new("ShowToc"))
    elseif action == "night_mode" then
        local night_mode = G_reader_settings:isTrue("night_mode")
        Screen:toggleNightMode()
        UIManager:setDirty("all", "full")
        G_reader_settings:saveSetting("night_mode", not night_mode)
    elseif action == "full_refresh" then
        if self.view then
            -- update footer (time & battery)
            self.view.footer:updateFooter()
        end
        UIManager:setDirty("all", "full")
    elseif action == "bookmarks" then
        self.ui:handleEvent(Event:new("ShowBookmark"))
    elseif action == "history" then
        self.ui:handleEvent(Event:new("ShowHist"))
    elseif action == "book_info" then
        self.ui:handleEvent(Event:new("ShowBookInfo"))
    elseif action == "book_description" then
        self.ui:handleEvent(Event:new("ShowBookDescription"))
    elseif action == "book_cover" then
        self.ui:handleEvent(Event:new("ShowBookCover"))
    elseif action == "book_status" then
        self.ui:handleEvent(Event:new("ShowBookStatus"))
    elseif action == "page_jmp_fwd_10" then
        self:pageUpdate(10)
    elseif action == "page_jmp_fwd_1" then
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
    elseif action == "page_jmp_back_10" then
        self:pageUpdate(-10)
    elseif action == "page_jmp_back_1" then
        self.ui:handleEvent(Event:new("GotoViewRel", -1))
    elseif action == "next_chapter" then
        self.ui:handleEvent(Event:new("GotoNextChapter"))
    elseif action == "prev_chapter" then
        self.ui:handleEvent(Event:new("GotoPrevChapter"))
    elseif action == "go_to" then
        self.ui:handleEvent(Event:new("ShowGotoDialog"))
    elseif action == "skim" then
        self.ui:handleEvent(Event:new("ShowSkimtoDialog"))
    elseif action == "back" then
        self.ui:handleEvent(Event:new("Back"))
    elseif action == "previous_location" then
        self.ui:handleEvent(Event:new("GoBackLink", true)) -- show_notification_if_empty
    elseif action == "latest_bookmark" then
        self.ui:handleEvent(Event:new("GoToLatestBookmark"))
    elseif action == "follow_nearest_link" then
        self.ui:handleEvent(Event:new("GoToPageLink", ges, false, G_reader_settings:isTrue("footnote_link_in_popup")))
    elseif action == "follow_nearest_internal_link" then
        self.ui:handleEvent(Event:new("GoToPageLink", ges, true, G_reader_settings:isTrue("footnote_link_in_popup")))
    elseif action == "clear_location_history" then
        self.ui:handleEvent(Event:new("ClearLocationStack", true)) -- show_notification
    elseif action == "filemanager" then
        self.ui:onClose()
        self.ui:showFileManager()
    elseif action == "file_search" then
        if self.ges_mode == "gesture_fm" then
            self.ui:handleEvent(Event:new("ShowFileSearch", self.ui.file_chooser.path))
        else
            local last_dir = self.ui:getLastDirFile()
            self.ui:handleEvent(Event:new("ShowFileSearch", last_dir))
        end
    elseif action == "folder_up" then
        self.ui.file_chooser:changeToPath(string.format("%s/..", self.ui.file_chooser.path))
    elseif action == "show_plus_menu" then
        self.ui:handleEvent(Event:new("ShowPlusMenu"))
    elseif action == "folder_shortcuts" then
        self.ui:handleEvent(Event:new("ShowFolderShortcutsDialog"))
    elseif action == "open_previous_document" then
        -- FileManager
        if self.ui.menu.openLastDoc and G_reader_settings:readSetting("lastfile") ~= nil then
            self.ui.menu:openLastDoc()
        -- ReaderUI
        elseif self.ui.switchDocument and self.ui.menu then
            self.ui:switchDocument(self.ui.menu:getPreviousFile())
        end
    elseif action == "dictionary_lookup" then
        self.ui:handleEvent(Event:new("ShowDictionaryLookup"))
    elseif action == "wikipedia_lookup" then
        self.ui:handleEvent(Event:new("ShowWikipediaLookup"))
    elseif action == "fulltext_search" then
        self.ui:handleEvent(Event:new("ShowFulltextSearchInput"))
    elseif action == "show_menu" then
        if self.ges_mode == "gesture_fm" then
            self.ui:handleEvent(Event:new("ShowMenu"))
        else
            self.ui:handleEvent(Event:new("ShowReaderMenu"))
        end
    elseif action == "show_config_menu" then
        self.ui:handleEvent(Event:new("ShowConfigMenu"))
    elseif action == "show_frontlight_dialog" then
        if self.ges_mode == "gesture_fm" then
            local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")
            ReaderFrontLight:onShowFlDialog()
        else
            self.ui:handleEvent(Event:new("ShowFlDialog"))
        end
    elseif action == "toggle_bookmark" then
        self.ui:handleEvent(Event:new("ToggleBookmark"))
    elseif action == "toggle_frontlight" then
        Device:getPowerDevice():toggleFrontlight()
        self:onShowFLOnOff()
    elseif action == "toggle_gsensor" then
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor()
        self:onGSensorToggle()
    elseif action == "toggle_page_flipping" then
        if not self.ui.document.info.has_pages then
            -- ReaderRolling has no support (yet) for onTogglePageFlipping,
            -- so don't make that top left tap area unusable (and allow
            -- taping on links there)
            return false
        end
        self.ui:handleEvent(Event:new("TogglePageFlipping"))
    elseif action == "toggle_reflow" then
        if not self.document.info.has_pages then return end
        if self.document.configurable.text_wrap == 1 then
            self.document.configurable.text_wrap = 0
        else
            self.document.configurable.text_wrap = 1
        end
        self.ui:handleEvent(Event:new("RedrawCurrentPage"))
        self.ui:handleEvent(Event:new("RestoreZoomMode"))
        self.ui:handleEvent(Event:new("InitScrollPageStates"))
    elseif action == "toggle_rotation" then
        local event_name = self.document.info.has_pages and "SwapScreenMode" or "ChangeScreenMode"
        local arg = Screen:getScreenMode() == "portrait" and "landscape" or "portrait"
        self.ui:handleEvent(Event:new(event_name, arg))
    elseif action == "toggle_wifi" then
        local NetworkMgr = require("ui/network/manager")

        if not NetworkMgr:isOnline() then
            UIManager:show(InfoMessage:new{
                text = _("Enabling wifi…"),
                timeout = 1,
            })

            -- NB Normal widgets should use NetworkMgr:promptWifiOn()
            -- This is specifically the toggle wifi action, so consent is implied.
            NetworkMgr:turnOnWifi()
        else
            NetworkMgr:turnOffWifi()

            UIManager:show(InfoMessage:new{
                text = _("Wifi disabled."),
                timeout = 1,
            })
        end
    elseif action == "wifi_off" then
        local NetworkMgr = require("ui/network/manager")
        -- can't hurt
        NetworkMgr:turnOffWifi()

        UIManager:show(InfoMessage:new{
            text = _("Wifi disabled."),
            timeout = 1,
        })
    elseif action == "wifi_on" then
        local NetworkMgr = require("ui/network/manager")

        if not NetworkMgr:isOnline() then
            UIManager:show(InfoMessage:new{
                text = _("Enabling wifi…"),
                timeout = 1,
            })

            -- NB Normal widgets should use NetworkMgr:promptWifiOn()
            -- This is specifically the toggle wifi action, so consent is implied.
            NetworkMgr:turnOnWifi()
        else
            local info_text
            local current_network = NetworkMgr:getCurrentNetwork()
            -- this method is only available for some implementations
            if current_network then
                info_text = T(_("Already connected to network %1."), NetworkMgr:getCurrentNetwork())
            else
                info_text = _("Already connected.")
            end
            UIManager:show(InfoMessage:new{
                text = info_text,
                timeout = 1,
            })
        end
    elseif action == "suspend" then
        UIManager:suspend()
    elseif action == "exit" then
        self.ui.menu:exitOrRestart()
    elseif action == "restart" then
        self.ui.menu:exitOrRestart(function() UIManager:restartKOReader() end)
    elseif action == "zoom_contentwidth" then
        self.ui:handleEvent(Event:new("SetZoomMode", "contentwidth"))
    elseif action == "zoom_contentheight" then
        self.ui:handleEvent(Event:new("SetZoomMode", "contentheight"))
    elseif action == "zoom_pagewidth" then
        self.ui:handleEvent(Event:new("SetZoomMode", "pagewidth"))
    elseif action == "zoom_pageheight" then
        self.ui:handleEvent(Event:new("SetZoomMode", "pageheight"))
    elseif action == "zoom_column" then
        self.ui:handleEvent(Event:new("SetZoomMode", "column"))
    elseif action == "zoom_content" then
        self.ui:handleEvent(Event:new("SetZoomMode", "content"))
    elseif action == "zoom_page" then
        self.ui:handleEvent(Event:new("SetZoomMode", "page"))
    elseif action == "wallabag_download" then
        self.ui:handleEvent(Event:new("SynchronizeWallabag"))
    elseif action == "cycle_highlight_action" then
        self.ui:handleEvent(Event:new("CycleHighlightAction"))
    elseif action == "cycle_highlight_style" then
        self.ui:handleEvent(Event:new("CycleHighlightStyle"))
    end
    return true
end

function ReaderGesture:multiswipeAction(multiswipe_directions, ges)
    if not self.multiswipes_enabled then return end
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    local multiswipe_gesture_name = "multiswipe_"..self:safeMultiswipeName(multiswipe_directions)
    local action = gesture_manager[multiswipe_gesture_name]
    if action and action ~= "nothing" then
        return self:gestureAction(action, ges)
    end
end

function ReaderGesture:pageUpdate(page)
    local curr_page
    if self.document.info.has_pages then
        curr_page = self.ui.paging.current_page
    else
        curr_page = self.document:getCurrentPage()
    end
    if curr_page and page then
        curr_page = curr_page + page
        self.ui:handleEvent(Event:new("GotoPage", curr_page))
    end

end

function ReaderGesture:onShowFLOnOff()
    local Notification = require("ui/widget/notification")
    local powerd = Device:getPowerDevice()
    local new_text
    if powerd.is_fl_on then
        new_text = _("Frontlight is on.")
    else
        new_text = _("Frontlight is off.")
    end
    UIManager:show(Notification:new{
        text = new_text,
        timeout = 1.0,
    })
    return true
end

function ReaderGesture:onGSensorToggle()
    local Notification = require("ui/widget/notification")
    local new_text
    if G_reader_settings:isTrue("input_ignore_gsensor") then
        new_text = _("Accelerometer rotation events will now be ignored.")
    else
        new_text = _("Accelerometer rotation events will now be honored.")
    end
    UIManager:show(Notification:new{
        text = new_text,
        timeout = 1.0,
    })
    return true
end

return ReaderGesture
