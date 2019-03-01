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

    toc = _("Table of contents"),
    bookmarks = _("Bookmarks"),
    reading_progress = _("Reading progress"),

    history = _("History"),
    open_previous_document = _("Open previous document"),
    filemanager = _("File browser"),

    full_refresh = _("Full screen refresh"),
    night_mode = _("Night mode"),
    suspend = _("Suspend"),
    show_menu = _("Show menu"),
    show_config_menu = _("Show bottom menu"),
    show_frontlight_dialog = _("Show frontlight dialog"),
    toggle_frontlight = _("Toggle frontlight"),
    toggle_gsensor = _("Toggle accelerometer"),
    toggle_rotation = _("Toggle rotation"),
    toggle_reflow = _("Toggle reflow"),

    zoom_contentwidth = _("Zoom to fit content width"),
    zoom_contentheight = _("Zoom to fit content height"),
    zoom_pagewidth = _("Zoom to fit page width"),
    zoom_pageheight = _("Zoom to fit page height"),
    zoom_column = _("Zoom to fit column"),
    zoom_content = _("Zoom to fit content"),
    zoom_page = _("Zoom to fit page"),

    folder_up = _("Folder up"),
}

local custom_multiswipes_path = DataStorage:getSettingsDir().."/multiswipes.lua"
local custom_multiswipes = LuaData:open(custom_multiswipes_path, { name = "MultiSwipes" })
local custom_multiswipes_table = custom_multiswipes:readSetting("multiswipes")

local default_multiswipes = {
    "west east",
    "east west",
    "north south",
    "south north",
    "north west",
    "north east",
    "south west",
    "south east",
    "east north",
    "west north",
    "east south",
    "west south",
    "west east west",
    "east north west",
    "south east north",
    "east north west east",
    "south east north south",
    "east south west north",
}
local multiswipes = {}
local multiswipes_info_text = _([[
Multiswipes allow you to perform complex gestures built up out of multiple straight swipes.]])

function ReaderGesture:init()
    if not Device:isTouchDevice() then return end
    self.multiswipes_enabled = G_reader_settings:readSetting("multiswipes_enabled")
    self.is_docless = self.ui == nil or self.ui.document == nil
    self.ges_mode = self.is_docless and "gesture_fm" or "gesture_reader"
    self.default_gesture = {
        tap_right_bottom_corner = "nothing",
        tap_left_bottom_corner = Device:hasFrontlight() and "toggle_frontlight" or "nothing",
        short_diagonal_swipe = "full_refresh",
        multiswipe = "nothing", -- otherwise registerGesture() won't pick up on multiswipes
        multiswipe_west_east = "previous_location",
        multiswipe_east_west = "latest_bookmark",
        multiswipe_north_east = "toc",
        multiswipe_north_west = self.ges_mode == "gesture_fm" and "folder_up" or "bookmarks",
        multiswipe_east_north = "history",
        multiswipe_east_south = "go_to",
        multiswipe_south_north = "skim",
        multiswipe_south_east = "toggle_reflow",
        multiswipe_south_west = "show_frontlight_dialog",
        multiswipe_west_south = "back",
        multiswipe_west_east_west = "open_previous_document",
        multiswipe_east_north_west = "zoom_contentwidth",
        multiswipe_south_east_north = "zoom_contentheight",
        multiswipe_east_north_west_east = "zoom_pagewidth",
        multiswipe_south_east_north_south = "zoom_pageheight",
        multiswipe_east_south_west_north = "full_refresh",
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
                text = _("Tap bottom left corner"),
                sub_item_table = self:buildMenu("tap_left_bottom_corner", self.default_gesture["tap_left_bottom_corner"]),
            },
            {
                text = _("Tap bottom right corner"),
                sub_item_table = self:buildMenu("tap_right_bottom_corner", self.default_gesture["tap_right_bottom_corner"]),
            },
            {
                text = _("Short diagonal swipe"),
                sub_item_table = self:buildMenu("short_diagonal_swipe", self.default_gesture["short_diagonal_swipe"]),
            },
        },
    }
end

function ReaderGesture:buildMenu(ges, default)
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    local menu = {
        {"nothing", true },
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
        {"latest_bookmark", not self.is_docless, true},

        {"folder_up", self.is_docless, true},

        { "toc", not self.is_docless},
        {"bookmarks", not self.is_docless},
        {"reading_progress", ReaderGesture.getReaderProgress ~= nil, true},

        {"history", true},
        {"open_previous_document", true, true},
        {"filemanager", not self.is_docless, true},

        {"full_refresh", true},
        {"night_mode", true},
        {"suspend", true},
        {"show_menu", true},
        {"show_config_menu", not self.is_docless},
        {"show_frontlight_dialog", Device:hasFrontlight()},
        {"toggle_frontlight", Device:hasFrontlight()},
        {"toggle_gsensor", Device:canToggleGSensor()},
        {"toggle_rotation", not self.is_docless, true},
        {"toggle_reflow", not self.is_docless, true},

        {"zoom_contentwidth", not self.is_docless},
        {"zoom_contentheight", not self.is_docless},
        {"zoom_pagewidth", not self.is_docless},
        {"zoom_pageheight", not self.is_docless},
        {"zoom_column", not self.is_docless},
        {"zoom_content", not self.is_docless},
        {"zoom_page", not self.is_docless},
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

    for k, v in pairs(default_multiswipes) do
        table.insert(multiswipes, v)
    end

    if custom_multiswipes_table then
        for k, v in pairs(custom_multiswipes_table) do
            table.insert(multiswipes, v)
        end
    end

    for i=1, #multiswipes do
        local multiswipe = multiswipes[i]
        local friendly_multiswipe_name = self:friendlyMultiswipeName(multiswipe)
        local safe_multiswipe_name = "multiswipe_"..self:safeMultiswipeName(multiswipe)
        local default_action = self.default_gesture[safe_multiswipe_name] and self.default_gesture[safe_multiswipe_name] or "nothing"
        table.insert(menu, {
            text_func = function()
                local action_name = gesture_manager[safe_multiswipe_name] ~= "nothing" and action_strings[gesture_manager[safe_multiswipe_name]] or _("Available")
                return T(_("%1   (%2)"), friendly_multiswipe_name, action_name)
            end,
            sub_item_table = self:buildMenu(safe_multiswipe_name, default_action),
            hold_callback = function(touchmenu_instance)
                if i > #default_multiswipes then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Remove custom multiswipe %1?"), friendly_multiswipe_name),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            -- multiswipes are a combined table, first defaults, then custom
                            -- so the right index is minus #defalt_multiswipes
                            custom_multiswipes:removeTableItem("multiswipes", i-#default_multiswipes)
                            touchmenu_instance.item_table = self:buildMultiswipeMenu()
                            touchmenu_instance:updateItems()
                        end,
                    })
                end
            end,
        })
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
    east = "↦",
    west = "↤",
    north = "↥",
    south = "↧",
}
function ReaderGesture:friendlyMultiswipeName(multiswipe)
    for k, v in pairs(multiswipe_to_arrow) do
        multiswipe = multiswipe:gsub(k, v)
    end
    return multiswipe
end

function ReaderGesture:safeMultiswipeName(multiswipe)
    return multiswipe:gsub(" ", "_")
end

function ReaderGesture:setupGesture(ges, action)
    local ges_type
    local zone
    local overrides
    local direction, distance
    if ges == "multiswipe" then
        ges_type = "multiswipe"
        zone = {
            ratio_x = 0.0, ratio_y = 0,
            ratio_w = 1, ratio_h = 1,
        }
        direction = {
            northeast = true, northwest = true,
            southeast = true, southwest = true,
            east = true, west = true,
            north = true, south = true,
        }
    elseif ges == "tap_right_bottom_corner" then
        ges_type = "tap"
        zone = {
            ratio_x = 0.9, ratio_y = 0.9,
            ratio_w = 0.1, ratio_h = 0.1,
        }
        if self.is_docless then
            overrides = { 'filemanager_tap' }
        else
            overrides = { 'readerfooter_tap', }
        end
    elseif ges == "tap_left_bottom_corner" then
        ges_type = "tap"
        zone = {
            ratio_x = 0.0, ratio_y = 0.9,
            ratio_w = 0.1, ratio_h = 0.1,
        }
        if self.is_docless then
            overrides = { 'filemanager_tap' }
        else
            overrides = { 'readerfooter_tap', 'filemanager_tap' }
        end
    elseif ges == "short_diagonal_swipe" then
        ges_type = "swipe"
        zone = {
            ratio_x = 0.0, ratio_y = 0,
            ratio_w = 1, ratio_h = 1,
        }
        direction = {northeast = true, northwest = true, southeast = true, southwest = true}
        distance = "short"
        if self.is_docless then
            overrides = { 'filemanager_tap' }
        else
            overrides = { 'rolling_swipe', 'paging_swipe' }
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
                        return self:multiswipeAction(gest.multiswipe_directions)
                    end
                end

                return self:gestureAction(action)
            end,
            overrides = overrides,
        },
    })
end

function ReaderGesture:gestureAction(action)
    if action == "reading_progress" and ReaderGesture.getReaderProgress then
        UIManager:show(ReaderGesture.getReaderProgress())
    elseif action == "toc" then
        self.ui:handleEvent(Event:new("ShowToc"))
    elseif action == "night_mode" then
        local night_mode = G_reader_settings:readSetting("night_mode") or false
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
    elseif action == "page_jmp_fwd_10" then
        self:pageUpdate(10)
    elseif action == "page_jmp_fwd_1" then
        self.ui:handleEvent(Event:new("TapForward"))
    elseif action == "page_jmp_back_10" then
        self:pageUpdate(-10)
    elseif action == "page_jmp_back_1" then
        self:pageUpdate(-1)
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
        self.ui:handleEvent(Event:new("GoBackLink"))
    elseif action == "latest_bookmark" then
        self.ui.link:onGoToLatestBookmark()
    elseif action == "filemanager" then
        self.ui:onClose()
        self.ui:showFileManager()
    elseif action == "folder_up" then
        self.ui.file_chooser:changeToPath(string.format("%s/..", self.ui.file_chooser.path))
    elseif action == "open_previous_document" then
        -- FileManager
        if self.ui.menu.openLastDoc and G_reader_settings:readSetting("lastfile") ~= nil then
            self.ui.menu:openLastDoc()
        -- ReaderUI
        elseif self.ui.switchDocument and self.ui.menu then
            self.ui:switchDocument(self.ui.menu:getPreviousFile())
        end
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
    elseif action == "toggle_frontlight" then
        Device:getPowerDevice():toggleFrontlight()
        self:onShowFLOnOff()
    elseif action == "toggle_gsensor" then
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor()
        self:onGSensorToggle()
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
        if Screen:getScreenMode() == "portrait" then
            self.ui:handleEvent(Event:new("SetScreenMode", "landscape"))
        else
            self.ui:handleEvent(Event:new("SetScreenMode", "portrait"))
        end
    elseif action == "suspend" then
        UIManager:suspend()
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
    end
    return true
end

function ReaderGesture:multiswipeAction(multiswipe_directions)
    if not self.multiswipes_enabled then return end
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    local multiswipe_gesture_name = "multiswipe_"..self:safeMultiswipeName(multiswipe_directions)
    for gesture, action in pairs(gesture_manager) do
        if gesture == multiswipe_gesture_name then
            return self:gestureAction(action)
        end
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
