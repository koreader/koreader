local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderBookmark = InputContainer:new{
    bm_menu_title = _("Bookmarks"),
    bbm_menu_title = _("Bookmark browsing mode"),
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

function ReaderBookmark:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.bookmarks = {
        text = self.bm_menu_title,
        callback = function()
            self:onShowBookmark()
        end,
    }
    if self.ui.document.info.has_pages then
        menu_items.bookmark_browsing_mode = {
            text = self.bbm_menu_title,
            checked_func = function() return self.view.flipping_visible end,
            callback = function(touchmenu_instance)
                self:enableBookmarkBrowsingMode()
                touchmenu_instance:closeMenu()
            end,
        }
    end
end

function ReaderBookmark:enableBookmarkBrowsingMode()
    self.ui:handleEvent(Event:new("ToggleBookmarkFlipping"))
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

function ReaderBookmark:isBookmarkPageInPageOrder(a, b)
    if self.ui.document.info.has_pages then
        return a > b.page
    else
        return a > self.ui.document:getPageFromXPointer(b.page)
    end
end

function ReaderBookmark:isBookmarkPageInReversePageOrder(a, b)
    if self.ui.document.info.has_pages then
        return a < b.page
    else
        return a < self.ui.document:getPageFromXPointer(b.page)
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
                page = self.ui.document.info.has_pages and page or mark.pos0
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
    local pn_or_xp
    if self.ui.document.info.has_pages then
        pn_or_xp = self.view.state.page
    else
        pn_or_xp = self.ui.document:getXPointer()
    end
    self:toggleBookmark(pn_or_xp)
    self.ui:handleEvent(Event:new("SetDogearVisibility",
                                  not self.view.dogear_visible))
    UIManager:setDirty(self.view.dialog, "ui")
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
        if v.text == nil or v.text == "" then
            v.text = T(_("Page %1 %2 @ %3"), page, v.notes, v.datetime)
        end
    end

    local bm_menu = Menu:new{
        title = _("Bookmarks"),
        item_table = self.bookmarks,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("x_smallinfofont"),
        perpage = G_reader_settings:readSetting("items_per_page") or 14,
        line_color = require("ffi/blitbuffer").COLOR_WHITE,
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

    function bm_menu:onMenuHold(item)
        self.textviewer = TextViewer:new{
            title = _("Bookmark details"),
            text = item.notes,
            width = self.textviewer_width,
            height = self.textviewer_height,
            buttons_table = {
                {
                    {
                        text = _("Rename this bookmark"),
                        callback = function()
                            bookmark:renameBookmark(item)
                            UIManager:close(self.textviewer)
                        end,
                    },
                    {
                        text = _("Remove this bookmark"),
                        callback = function()
                            UIManager:show(ConfirmBox:new{
                                text = _("Do you want remove this bookmark?"),
                                cancel_text = _("Cancel"),
                                cancel_callback = function()
                                    return
                                end,
                                ok_text = _("Remove"),
                                ok_callback = function()
                                    bookmark:removeHighlight(item)
                                    bm_menu:switchItemTable(nil, bookmark.bookmarks, -1)
                                    UIManager:close(self.textviewer)
                                end,
                            })
                        end,
                    },
                },
                {
                    {
                        text = _("Close"),
                        is_enter_default = true,
                        callback = function()
                            UIManager:close(self.textviewer)
                        end,
                    },
                }
            }
        }
        UIManager:show(self.textviewer)
        return true
    end

    bm_menu.close_callback = function()
        UIManager:close(self.bookmark_menu)
    end

    bm_menu.show_parent = self.bookmark_menu
    self.refresh = function()
        bm_menu:updateItems()
        self:onSaveSettings()
    end

    UIManager:show(self.bookmark_menu)
    return true
end

function ReaderBookmark:isBookmarkMatch(item, pn_or_xp)
    -- this is not correct, but previous commit temporarily
    -- reverted, see #2395 & #2394
    if self.ui.document.info.has_pages then
        return item.page == pn_or_xp
    else
        return self.ui.document:isXPointerInCurrentPage(item.page)
    end
end

function ReaderBookmark:getDogearBookmarkIndex(pn_or_xp)
    local _middle
    local _start, _end = 1, #self.bookmarks
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

function ReaderBookmark:isBookmarkSame(item1, item2)
    if item1.notes ~= item2.notes then return false end
    if self.ui.document.info.has_pages then
        return item2.pos0 and item2.pos1 and item1.pos0.page == item2.pos0.page
        and item1.pos0.x == item2.pos0.x and item1.pos0.y == item2.pos0.y
        and item1.pos1.x == item2.pos1.x and item1.pos1.y == item2.pos1.y
    else
        return item1.page == item2.page
        and item1.pos0 == item2.pos0 and item1.pos1 == item2.pos1
    end
end

-- binary insert of sorted bookmarks
function ReaderBookmark:addBookmark(item)
    local _start, _middle, _end, direction = 1, 1, #self.bookmarks, 0
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        -- won't add duplicated bookmarks
        if self:isBookmarkSame(item, self.bookmarks[_middle]) then
            logger.warn("skip adding duplicated bookmark")
            return
        end
        if self:isBookmarkInPageOrder(item, self.bookmarks[_middle]) then
            _end, direction = _middle - 1, 0
        else
            _start, direction = _middle + 1, 1
        end
    end
    table.insert(self.bookmarks, _middle + direction, item)
end

-- binary search of sorted bookmarks
function ReaderBookmark:isBookmarkAdded(item)
    local _middle
    local _start, _end = 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        if self:isBookmarkSame(item, self.bookmarks[_middle]) then
            return true
        end
        if self:isBookmarkInPageOrder(item, self.bookmarks[_middle]) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
    return false
end

function ReaderBookmark:removeHighlight(item)
    if item.pos0 then
        self.ui:handleEvent(Event:new("Unhighlight", item))
    else
        self:removeBookmark(item)
    end
end

-- binary search to remove bookmark
function ReaderBookmark:removeBookmark(item)
    local _middle
    local _start, _end = 1, #self.bookmarks
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
    -- If we haven't found item, it may be because there are multiple
    -- bookmarks on the same page, and the above binary search decided to
    -- not search on one side of one it found on page, where item could be.
    -- Fallback to do a full scan.
    logger.dbg("removeBookmark: binary search didn't find bookmark, doing full scan")
    for i=1, #self.bookmarks do
        local v = self.bookmarks[i]
        if item.datetime == v.datetime and item.page == v.page then
            return table.remove(self.bookmarks, i)
        end
    end
    logger.warn("removeBookmark: full scan search didn't find bookmark")
end

function ReaderBookmark:renameBookmark(item, from_highlight)
    if from_highlight then
        -- Called by ReaderHighlight:editHighlight, we need to find the bookmark
        for i=1, #self.bookmarks do
            if item.datetime == self.bookmarks[i].datetime and item.page == self.bookmarks[i].page then
                item = self.bookmarks[i]
                if item.text == nil or item.text == "" then
                    -- Make up bookmark text as done in onShowBookmark
                    local page = item.page
                    if not self.ui.document.info.has_pages then
                        page = self.ui.document:getPageFromXPointer(page)
                    end
                    item.text = T(_("Page %1 %2 @ %3"), page, item.notes, item.datetime)
                end
                break
            end
        end
        if item.text == nil then -- bookmark not found
            return
        end
    end
    self.input = InputDialog:new{
        title = _("Rename bookmark"),
        input = item.text,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(self.input)
                    end,
                },
                {
                    text = _("Rename"),
                    callback = function()
                        local value = self.input:getInputValue()
                        if value ~= "" then
                            for i=1, #self.bookmarks do
                                if item.text == self.bookmarks[i].text and  item.pos0 == self.bookmarks[i].pos0 and
                                    item.pos1 == self.bookmarks[i].pos1 and item.page == self.bookmarks[i].page then
                                    self.bookmarks[i].text = value
                                    UIManager:close(self.input)
                                    if not from_highlight then
                                        self.refresh()
                                    end
                                    break
                                end
                            end
                        end
                        UIManager:close(self.input)
                    end,
                },
            }
        },
    }
    self.input:onShowKeyboard()
    UIManager:show(self.input)
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
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = 1, #self.bookmarks do
        if self:isBookmarkInPageOrder({page = pn_or_xp}, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getNextBookmarkedPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = #self.bookmarks, 1, -1 do
        if self:isBookmarkInReversePageOrder({page = pn_or_xp}, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getPreviousBookmarkedPageFromPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = 1, #self.bookmarks do
        if self:isBookmarkPageInPageOrder(pn_or_xp, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getNextBookmarkedPageFromPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = #self.bookmarks, 1, -1 do
        if self:isBookmarkPageInReversePageOrder(pn_or_xp, self.bookmarks[i]) then
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

function ReaderBookmark:getLatestBookmark()
    local latest_bookmark = nil
    local latest_bookmark_datetime = "0"
    for i = 1, #self.bookmarks do
        if self.bookmarks[i].datetime > latest_bookmark_datetime then
            latest_bookmark_datetime = self.bookmarks[i].datetime
            latest_bookmark = self.bookmarks[i]
        end
    end
    return latest_bookmark
end

return ReaderBookmark
