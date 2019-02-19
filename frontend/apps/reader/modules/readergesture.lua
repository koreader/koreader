local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")
local util = require("util")

local default_gesture = {
    tap_right_bottom_corner = "nothing",
    tap_left_bottom_corner = Device:hasFrontlight() and "toggle_frontlight" or "nothing",
    short_diagonal_swipe = "full_refresh",
    multiswipe_west_south = "previous_location",
}

local ReaderGesture = InputContainer:new{
    multiswipes_enabled = G_reader_settings:readSetting("multiswipes_enabled"),
}

local multiswipes_info_text = _([[
Multiswipes allow you to perform complex gestures built up out of multiple straight swipes.]])

function ReaderGesture:init()
    if not Device:isTouchDevice() then return end
    self.is_docless = self.ui == nil or self.ui.document == nil
    self.ges_mode = self.is_docless and "gesture_fm" or "gesture_reader"
    local gm = G_reader_settings:readSetting(self.ges_mode)
    if gm == nil then G_reader_settings:saveSetting(self.ges_mode, {}) end
    self.ui.menu:registerToMainMenu(self)
    self:initGesture()
end

function ReaderGesture:initGesture()
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    for gesture, action in pairs(default_gesture) do
        if not gesture_manager[gesture] then
            gesture_manager[gesture] = action
        end
    end
    for gesture, action in pairs(gesture_manager) do
        self:setupGesture(gesture, action)
    end
    G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
end

function ReaderGesture:addToMainMenu(menu_items)
    menu_items.gesture = {
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
                text = _("Multiswipe"),
                sub_item_table = self:buildMultiswipeMenu(),
                enabled_func = function() return self.multiswipes_enabled end,
                separator = true,
            },
            {
                text = _("Tap bottom left corner"),
                sub_item_table = self:buildMenu("tap_left_bottom_corner", default_gesture["tap_left_bottom_corner"]),
            },
            {
                text = _("Tap bottom right corner"),
                sub_item_table = self:buildMenu("tap_right_bottom_corner", default_gesture["tap_right_bottom_corner"]),
            },
            {
                text = _("Short diagonal swipe"),
                sub_item_table = self:buildMenu("short_diagonal_swipe", default_gesture["short_diagonal_swipe"]),
            },
        },
    }
end

function ReaderGesture:buildMenu(ges, default)
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    local menu = {
        {_("Nothing"), "nothing", true },
        {_("Back 10 pages"), "page_jmp_back_10", not self.is_docless},
        {_("Previous page"), "page_jmp_back_1", not self.is_docless},
        {_("Forward 10 pages"), "page_jmp_fwd_10", not self.is_docless},
        {_("Next page"), "page_jmp_fwd_1", not self.is_docless},
        {_("Back to previous location"), "previous_location", not self.is_docless},
        {_("Folder up"), "folder_up", self.is_docless},
        {_("Bookmarks"), "bookmarks", not self.is_docless},
        {_("History"), "history", true},
        {_("Table of contents"), "toc", not self.is_docless},
        {_("Reading progress"), "reading_progress", ReaderGesture.getReaderProgress ~= nil},
        {_("Full screen refresh"), "full_refresh", true},
        {_("Night mode"), "night_mode", true},
        {_("Suspend"), "suspend", true},
        {_("Toggle frontlight"), "toggle_frontlight", Device:hasFrontlight()},
        {_("Toggle accelerometer"), "toggle_gsensor", Device:canToggleGSensor()},
        {_("Toggle rotation"), "toggle_rotation", not self.is_docless},
    }
    local return_menu = {}
    -- add default action to the top of the submenu
    for __, entry in pairs(menu) do
        if entry[2] == default then
            local menu_entry_default = T(_("%1 (default)"), entry[1])
            table.insert(return_menu, self:createSubMenu(menu_entry_default, entry[2], ges, true))

            if not gesture_manager[ges] then
                gesture_manager[ges] = default
                G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
            end
            break
        end
    end
    -- another elements
    for _, entry in pairs(menu) do
        if not entry[3] and gesture_manager[ges] == entry[2] then
            gesture_manager[ges] = "nothing"
            G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
        end
        if entry[2] ~= default and entry[3] then
            table.insert(return_menu, self:createSubMenu(entry[1], entry[2], ges, entry[2] == "nothing"))
        end
    end
    return return_menu
end

local multiswipes = {
    "west east",
    "east west",
    "north south",
    "south north",
    "south west",
    "south east",
    "east south",
    "west south",
}
local custom_multiswipes_path = DataStorage:getSettingsDir().."/multiswipes"
if util.pathExists(custom_multiswipes_path..".lua") then
    for k, v in pairs(require(custom_multiswipes_path)) do
        table.insert(multiswipes, v)
    end
end

function ReaderGesture:buildMultiswipeMenu()
    local menu = {}

    for i=1, #multiswipes do
        local multiswipe = multiswipes[i]
        local friendly_multiswipe_name = self:friendlyMultiswipeName(multiswipe)
        local safe_multiswipe_name = "multiswipe_"..self:safeMultiswipeName(multiswipe)
        local default_gesture = default_gesture[safe_multiswipe_name] and default_gesture[safe_multiswipe_name] or "nothing"
        table.insert(menu, {
            text = friendly_multiswipe_name,
            sub_item_table = self:buildMenu(safe_multiswipe_name, default_gesture),
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
        self:pageUpdate(1)
    elseif action == "page_jmp_back_10" then
        self:pageUpdate(-10)
    elseif action == "page_jmp_back_1" then
        self:pageUpdate(-1)
    elseif action == "previous_location" then
        self.ui:handleEvent(Event:new("GoBackLink"))
    elseif action == "folder_up" then
        self.ui.file_chooser:changeToPath(string.format("%s/..", self.ui.file_chooser.path))
    elseif action == "toggle_frontlight" then
        Device:getPowerDevice():toggleFrontlight()
        self:onShowFLOnOff()
    elseif action == "toggle_gsensor" then
        G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
        Device:toggleGSensor()
        self:onGSensorToggle()
    elseif action == "toggle_rotation" then
        if Screen:getScreenMode() == "portrait" then
            self.ui:handleEvent(Event:new("SetScreenMode", "landscape"))
        else
            self.ui:handleEvent(Event:new("SetScreenMode", "portrait"))
        end
    elseif action == "suspend" then
        UIManager:suspend()
    end
    return true
end

function ReaderGesture:multiswipeAction(multiswipe_directions)
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
