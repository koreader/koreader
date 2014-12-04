local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Menu = require("ui/widget/menu")
local Device = require("device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderBookmark = InputContainer:new{
    bm_menu_title = _("Bookmarks"),
    bookmarks = nil,
}

function ReaderBookmark:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ShowBookmark = {
                { "B" },
                doc = "show bookmarks" },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            ShowBookmark = {
                GestureRange:new{
                    ges = "two_finger_swipe",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    },
                    direction = "west"
                }
            },
        }
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReaderBookmark:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.navi, {
        text = self.bm_menu_title,
        callback = function()
            self:onShowBookmark()
        end,
    })
end

function ReaderBookmark:isBookmarkInTimeOrder(a, b)
    return a.datetime > b.datetime
end

function ReaderBookmark:isBookmarkInPageOrder(a, b)
    if self.ui.document.info.has_pages then
        return a.page > b.page
    else
        return self.ui.document:getPageFromXPointer(a.page) >
                self.ui.document:getPageFromXPointer(b.page)
    end
end

function ReaderBookmark:isBookmarkInReversePageOrder(a, b)
    if self.ui.document.info.has_pages then
        return a.page < b.page
    else
        return self.ui.document:getPageFromXPointer(a.page) <
                self.ui.document:getPageFromXPointer(b.page)
    end
end

function ReaderBookmark:fixBookmarkSort(config)
    -- for backward compatibility, since previously bookmarks for credocuments
    -- are not well sorted. We need to do a whole sorting for at least once.
    if not config:readSetting("bookmarks_sorted") then
        table.sort(self.bookmarks, function(a, b)
            return self:isBookmarkInPageOrder(a, b)
        end)
    end
end

function ReaderBookmark:importSavedHighlight(config)
    local textmarks = config:readSetting("highlight") or {}
    -- import saved highlight once, because from now on highlight are added to
    -- bookmarks when they are created.
    if not config:readSetting("highlights_imported") then
        for page, marks in pairs(textmarks) do
            for _, mark in ipairs(marks) do
                local page = self.ui.document.info.has_pages and page or mark.pos0
                -- highlights saved by some old versions don't have pos0 field
                -- we just ignore those highlights
                if page then
                    self:addBookmark({
                        page = page,
                        datetime = mark.datetime,
                        notes = mark.text,
                        highlighted = true,
                    })
                end
            end
        end
    end
end

function ReaderBookmark:onReadSettings(config)
    self.bookmarks = config:readSetting("bookmarks") or {}
    -- need to do this after initialization because checking xpointer
    -- may cause segfaults before credocuments are inited.
    self.ui:registerPostInitCallback(function()
        self:fixBookmarkSort(config)
        self:importSavedHighlight(config)
    end)
end

function ReaderBookmark:onSaveSettings()
    self.ui.doc_settings:saveSetting("bookmarks", self.bookmarks)
    self.ui.doc_settings:saveSetting("bookmarks_sorted", true)
    self.ui.doc_settings:saveSetting("highlights_imported", true)
end

function ReaderBookmark:onToggleBookmark()
    local pn_or_xp = nil
    if self.ui.document.info.has_pages then
        pn_or_xp = self.view.state.page
    else
        pn_or_xp = self.ui.document:getXPointer()
    end
    self:toggleBookmark(pn_or_xp)
    self.view.dogear_visible = not self.view.dogear_visible
    UIManager:setDirty(self.view.dialog, "partial")
    return true
end

function ReaderBookmark:setDogearVisibility(pn_or_xp)
    if self:getDogearBookmarkIndex(pn_or_xp) then
        self.ui:handleEvent(Event:new("SetDogearVisibility", true))
    else
        self.ui:handleEvent(Event:new("SetDogearVisibility", false))
    end
end

function ReaderBookmark:onPageUpdate(pageno)
    if self.ui.document.info.has_pages then
        self:setDogearVisibility(pageno)
    else
        self:setDogearVisibility(self.ui.document:getXPointer())
    end
end

function ReaderBookmark:onPosUpdate(pos)
    self:setDogearVisibility(self.ui.document:getXPointer())
end

function ReaderBookmark:gotoBookmark(pn_or_xp)
    local event = self.ui.document.info.has_pages and "GotoPage" or "GotoXPointer"
    self.ui:handleEvent(Event:new(event, pn_or_xp))
end

function ReaderBookmark:onShowBookmark()
    -- build up item_table
    for k, v in ipairs(self.bookmarks) do
        local page = v.page
        -- for CREngine, bookmark page is xpointer
        if not self.ui.document.info.has_pages then
            page = self.ui.document:getPageFromXPointer(page)
        end
        v.text = _("Page") .. " " .. page .. " " .. v.notes .. " @ " .. v.datetime
    end

    local bm_menu = Menu:new{
        title = _("Bookmarks"),
        item_table = self.bookmarks,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("cfont", 20),
        on_close_ges = {
            GestureRange:new{
                ges = "two_finger_swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                direction = "east"
            }
        }
    }

    self.bookmark_menu = CenterContainer:new{
        dimen = Screen:getSize(),
        bm_menu,
    }

    -- buid up menu widget method as closure
    local bookmark = self
    function bm_menu:onMenuChoice(item)
        bookmark:gotoBookmark(item.page)
    end

    bm_menu.close_callback = function()
        UIManager:close(self.bookmark_menu)
    end

    bm_menu.show_parent = self.bookmark_menu

    UIManager:show(self.bookmark_menu)
    return true
end

function ReaderBookmark:isBookmarkMatch(item, pn_or_xp)
    if self.ui.document.info.has_pages then
        return item.page == pn_or_xp
    else
        return self.ui.document:isXPointerInCurrentPage(item.page)
    end
end

function ReaderBookmark:getDogearBookmarkIndex(pn_or_xp)
    local _start, _middle, _end = 1, 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        local v = self.bookmarks[_middle]
        if self:isBookmarkMatch(v, pn_or_xp) then
            if v.highlighted then
                return
            else
                return _middle
            end
        elseif self:isBookmarkInPageOrder({page = pn_or_xp}, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
end

-- binary insert of sorted bookmarks
function ReaderBookmark:addBookmark(item)
    local _start, _middle, _end, direction = 1, 1, #self.bookmarks, 0
    while _start <= _end do
        local v = self.bookmarks[_middle]
        _middle = math.floor((_start + _end)/2)
        if self:isBookmarkInPageOrder(item, self.bookmarks[_middle]) then
            _end, direction = _middle - 1, 0
        else
            _start, direction = _middle + 1, 1
        end
    end
    table.insert(self.bookmarks, _middle + direction, item)
end

-- binary search to remove bookmark
function ReaderBookmark:removeBookmark(item)
    local _start, _middle, _end = 1, 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        local v = self.bookmarks[_middle]
        if item.datetime == v.datetime and item.page == v.page then
            return table.remove(self.bookmarks, _middle)
        elseif self:isBookmarkInPageOrder(item, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
end

function ReaderBookmark:toggleBookmark(pn_or_xp)
    local index = self:getDogearBookmarkIndex(pn_or_xp)
    if index then
        table.remove(self.bookmarks, index)
    else
        -- build notes from TOC
        local notes = self.ui.toc:getTocTitleByPage(pn_or_xp)
        if notes ~= "" then
            notes = "in "..notes
        end
        self:addBookmark({
            page = pn_or_xp,
            datetime = os.date("%Y-%m-%d %H:%M:%S"),
            notes = notes,
        })
    end
end

function ReaderBookmark:getPreviousBookmarkedPage(pn_or_xp)
    DEBUG("go to next bookmark from", pn_or_xp)
    for i = 1, #self.bookmarks do
        if self:isBookmarkInPageOrder({page = pn_or_xp}, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getNextBookmarkedPage(pn_or_xp)
    DEBUG("go to next bookmark from", pn_or_xp)
    for i = #self.bookmarks, 1, -1 do
        if self:isBookmarkInReversePageOrder({page = pn_or_xp}, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:onGotoPreviousBookmark(pn_or_xp)
    self:gotoBookmark(self:getPreviousBookmarkedPage(pn_or_xp))
    return true
end

function ReaderBookmark:onGotoNextBookmark(pn_or_xp)
    self:gotoBookmark(self:getNextBookmarkedPage(pn_or_xp))
    return true
end

return ReaderBookmark
