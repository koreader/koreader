local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ReaderGesture = InputContainer:new{
}

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
    -- todo: add default gesture
    for gesture, action in pairs(gesture_manager) do
        self:subMenuAction(gesture, action)
    end
end

function ReaderGesture:addToMainMenu(menu_items)
    menu_items.gesture = {
        text = _("Gesture manager"),
        sub_item_table = {
            {
                text = _("Tap right bottom corner"),
                sub_item_table = self:tapMenu("tap_right_bottom_corner")
            },
            {
                text = _("Tap left bottom corner"),
                sub_item_table = self:tapMenu("tap_left_bottom_corner")
            },
            {
                text = _("Short diagonal swipe"),
                sub_item_table = self:tapMenu("short_diagonal_swipe")
            },
        },
    }
end

function ReaderGesture:tapMenu(ges)
    if self.is_docless then
        return {
            self:createSubMenu(_("Disable"), nil, ges),
            self:createSubMenu(_("Folder up"), "folder_up", ges),
            self:createSubMenu(_("Full screen refresh"), "full_refresh", ges),
            self:createSubMenu(_("Night mode"), "night_mode", ges),
            self:createSubMenu(_("Reading progress"), "reading_progress", ges),
        }
    else
        return {
            self:createSubMenu(_("Disable"), nil, ges),
            self:createSubMenu(_("Backward 10 pages"), "page_update_down10", ges),
            self:createSubMenu(_("Bookmarks"), "bookmarks", ges),
            self:createSubMenu(_("Forward 10 pages"), "page_update_up10", ges),
            self:createSubMenu(_("Full screen refresh"), "full_refresh", ges),
            self:createSubMenu(_("Night mode"), "night_mode", ges),
            self:createSubMenu(_("Reading progress"), "reading_progress", ges),
            self:createSubMenu(_("Table of context"), "toc", ges),
        }
    end
end

function ReaderGesture:createSubMenu(text, action, ges)
    local gesture_manager = G_reader_settings:readSetting(self.ges_mode)
    return {
        text = text,
        checked_func = function()
            return gesture_manager[ges] == action
        end,
        callback = function()
            gesture_manager[ges] = action
            G_reader_settings:saveSetting(self.ges_mode, gesture_manager)
            self:subMenuAction(ges, action)
        end,
    }
end

function ReaderGesture:subMenuAction(ges, action)
    local ges_type
    local zone = {}
    local overrides
    local direction, distance
    if ges == "tap_right_bottom_corner" then
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
        direction = {'northeast', 'northwest', 'southeast', 'southwest'}
        distance = "short"
        --todo: ovverrides short swipe (refresh)
        if self.is_docless then
            overrides = { 'filemanager_tap' }
        else
            overrides = { 'rolling_swipe', 'paging_swipe' }
        end

    else return
    end
    self:registerGesture(ges, action, ges_type, zone, overrides, direction, distance)
end

local function directionContain(direction, element)
    for _, k in pairs(direction) do
        if k == element then
            return true
        end
    end
    return false
end

function ReaderGesture:registerGesture(ges, action, ges_type, zone, overrides, direction, distance)
    if action == nil then
        self.ui:unRegisterTouchZones({
            {
                id = ges,
                overrides = overrides,
            }
        })
        return
    end

    if action then
        self.ui:registerTouchZones({
            {
                id = ges,
                ges = ges_type,
                screen_zone = zone,
                handler = function(gest)
                    if distance == "short" and gest.distance > Screen:scaleBySize(300) then return end
                    if direction and not directionContain(direction, gest.direction) then return end
                    return self:gestureAction(action)
                end,
                overrides = overrides,
            },
        })
    end
end

function ReaderGesture:gestureAction(action, return_value)
    if action == "reading_progress" then
        UIManager:show(ReaderGesture.getReaderProgress())
    elseif action == "toc" then
        self.ui:handleEvent(Event:new("ShowToc"))
    elseif action == "night_mode" then
        local Screen = Device.screen
        local night_mode = G_reader_settings:readSetting("night_mode") or false
        Screen:toggleNightMode()
        UIManager:setDirty(nil, "full")
        G_reader_settings:saveSetting("night_mode", not night_mode)
    elseif action == "full_refresh" then
        UIManager:setDirty(nil, "full")
    elseif action == "bookmarks" then
        self.ui:handleEvent(Event:new("ShowBookmark"))
    elseif action =="page_update_up10" then
        self:pageUpdate(10)
    elseif action =="page_update_down10" then
        self:pageUpdate(-10)
    elseif action =="folder_up" then
        local lfs = require("libs/libkoreader-lfs")
        local new_path = self.ui.file_chooser.path .. "/.."
        self.ui.file_chooser:changeToPath(new_path)
    end
    if return_value then
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        -- no implemented for now
        return return_value
    else
        return true
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

return ReaderGesture
