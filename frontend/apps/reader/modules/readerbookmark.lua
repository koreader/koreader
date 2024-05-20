local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderBookmark = InputContainer:extend{
    bookmarks_items_per_page_default = 14,
    -- mark the type of a bookmark with a symbol + non-expandable space
    display_prefix = {
        highlight = "\u{2592}\u{2002}", -- "medium shade"
        note      = "\u{F040}\u{2002}", -- "pencil"
        bookmark  = "\u{F097}\u{2002}", -- "empty bookmark"
    },
    display_type = {
        highlight = _("highlights"),
        note      = _("notes"),
        bookmark  = _("page bookmarks"),
    },
}

function ReaderBookmark:init()
    self:registerKeyEvents()

    if G_reader_settings:hasNot("bookmarks_items_per_page") then
        -- The Bookmarks items per page and items' font size can now be
        -- configured. Previously, the ones set for the file browser
        -- were used. Initialize them from these ones.
        local items_per_page = G_reader_settings:readSetting("items_per_page")
                            or self.bookmarks_items_per_page_default
        G_reader_settings:saveSetting("bookmarks_items_per_page", items_per_page)
        local items_font_size = G_reader_settings:readSetting("items_font_size")
        if items_font_size and items_font_size ~= Menu.getItemFontSize(items_per_page) then
            -- Keep the user items font size if it's not the default for items_per_page
            G_reader_settings:saveSetting("bookmarks_items_font_size", items_font_size)
        end
    end
    self.items_text = G_reader_settings:readSetting("bookmarks_items_text_type", "note")

    self.ui.menu:registerToMainMenu(self)
    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderBookmark:onGesture() end

function ReaderBookmark:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowBookmark = { { "B" } }
    elseif Device:hasFiveWay() then
        self.key_events.ShowBookmark = { { "ScreenKB", "Left" } }
        self.key_events.ToggleBookmark = { { "ScreenKB", "Right" } }
    end
end

ReaderBookmark.onPhysicalKeyboardConnected = ReaderBookmark.registerKeyEvents

function ReaderBookmark:genItemTextMenuItem(type, get_string)
    local text_type = {
        text = _("highlighted text"),
        all  = _("highlighted text and note"),
        note = _("note, or highlighted text"),
    }
    if get_string then
        return text_type[type]
    end
    return {
        text = text_type[type],
        checked_func = function()
            return self.items_text == type
        end,
        callback = function()
            self.items_text = type
            G_reader_settings:saveSetting("bookmarks_items_text_type", type)
        end,
    }
end

function ReaderBookmark:addToMainMenu(menu_items)
    menu_items.bookmarks = {
        text = _("Bookmarks"),
        callback = function()
            self:onShowBookmark()
        end,
    }
    if not Device:isTouchDevice() then
        menu_items.toggle_bookmark = {
            text_func = function()
                return self:isPageBookmarked() and _("Remove bookmark for current page") or _("Bookmark current page")
            end,
            callback = function()
                self:onToggleBookmark()
            end,
       }
    end
    if self.ui.paging then
        menu_items.bookmark_browsing_mode = {
            text = _("Bookmark browsing mode"),
            checked_func = function()
                return self.ui.paging.bookmark_flipping_mode
            end,
            callback = function(touchmenu_instance)
                self.ui.paging:onToggleBookmarkFlipping()
                touchmenu_instance:closeMenu()
            end,
        }
    end
    menu_items.bookmarks_settings = {
        text = _("Bookmarks"),
        sub_item_table = {
            {
                text_func = function()
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    return T(_("Bookmarks per page: %1"), curr_perpage)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local items = SpinWidget:new{
                        value = curr_perpage,
                        value_min = 6,
                        value_max = 24,
                        default_value = self.bookmarks_items_per_page_default,
                        title_text = _("Bookmarks per page"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_per_page", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text_func = function()
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local default_font_size = Menu.getItemFontSize(curr_perpage)
                    local curr_font_size = G_reader_settings:readSetting("bookmarks_items_font_size", default_font_size)
                    return T(_("Bookmark font size: %1"), curr_font_size)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local default_font_size = Menu.getItemFontSize(curr_perpage)
                    local curr_font_size = G_reader_settings:readSetting("bookmarks_items_font_size", default_font_size)
                    local items_font = SpinWidget:new{
                        value = curr_font_size,
                        value_min = 10,
                        value_max = 72,
                        default_value = default_font_size,
                        title_text = _("Bookmark font size"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_font_size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items_font)
                end,
            },
            {
                text = _("Shrink bookmark font size to fit more text"),
                checked_func = function()
                    return G_reader_settings:isTrue("bookmarks_items_multilines_show_more_text")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("bookmarks_items_multilines_show_more_text")
                end,
                separator = true,
            },
            {
                text = _("Show separator between items"),
                checked_func = function()
                    return G_reader_settings:isTrue("bookmarks_items_show_separator")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("bookmarks_items_show_separator")
                end,
            },
            {
                text_func = function()
                    local curr_type = G_reader_settings:readSetting("bookmarks_items_text_type", "note")
                    return T(_("Show in items: %1"), self:genItemTextMenuItem(curr_type, true))
                end,
                sub_item_table = {
                    self:genItemTextMenuItem("text"),
                    self:genItemTextMenuItem("all"),
                    self:genItemTextMenuItem("note"),
                },
            },
            {
                text = _("Sort by largest page number"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("bookmarks_items_reverse_sorting")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("bookmarks_items_reverse_sorting")
                end,
            },
        },
    }
    menu_items.bookmark_search = {
        text = _("Bookmark search"),
        enabled_func = function()
            return self.ui.annotation:hasAnnotations()
        end,
        callback = function()
            self:onSearchBookmark()
        end,
    }
end

-- page bookmarks, dogear

function ReaderBookmark:onToggleBookmark()
    self:toggleBookmark()
    self.view.footer:onUpdateFooter(self.view.footer_visible)
    self.view.dogear:onSetDogearVisibility(not self.view.dogear_visible)
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

function ReaderBookmark:toggleBookmark(pageno)
    local pn_or_xp, item
    if pageno then
        if self.ui.rolling then
            pn_or_xp = self.ui.document:getPageXPointer(pageno)
        else
            pn_or_xp = pageno
        end
    else
        pn_or_xp = self:getCurrentPageNumber()
    end
    local index = self:getDogearBookmarkIndex(pn_or_xp)
    if index then
        item = table.remove(self.ui.annotation.annotations, index)
    else
        local text
        local chapter = self.ui.toc:getTocTitleByPage(pn_or_xp)
        if chapter == "" then
            chapter = nil
        else
            -- @translators In which chapter title (%1) a note is found.
            text = T(_("in %1"), chapter)
        end
        item = {
            page = pn_or_xp,
            text = text,
            chapter = chapter,
        }
        self.ui.annotation:addItem(item)
    end
    self.ui:handleEvent(Event:new("AnnotationsModified", { item }))
end

function ReaderBookmark:setDogearVisibility(pn_or_xp)
    local visible = self:isPageBookmarked(pn_or_xp)
    self.view.dogear:onSetDogearVisibility(visible)
end

function ReaderBookmark:isPageBookmarked(pn_or_xp)
    local page = pn_or_xp or self:getCurrentPageNumber()
    return self:getDogearBookmarkIndex(page) and true or false
end

function ReaderBookmark:isBookmarkInPageOrder(a, b)
    local a_page = self:getBookmarkPageNumber(a)
    local b_page = self:getBookmarkPageNumber(b)
    if a_page == b_page then -- have page bookmarks before highlights
        return not a.drawer
    end
    return a_page < b_page
end

function ReaderBookmark:getDogearBookmarkIndex(pn_or_xp)
    local doesMatch
    if self.ui.paging then
        doesMatch = function(p1, p2)
            return p1 == p2
        end
    else
        doesMatch = function(p1, p2)
            return self.ui.document:getPageFromXPointer(p1) == self.ui.document:getPageFromXPointer(p2)
        end
    end
    local _middle
    local _start, _end = 1, #self.ui.annotation.annotations
    while _start <= _end do
        _middle = bit.rshift(_start + _end, 1)
        local v = self.ui.annotation.annotations[_middle]
        if not v.drawer and doesMatch(v.page, pn_or_xp) then
            return _middle
        elseif self:isBookmarkInPageOrder({page = pn_or_xp}, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
end

-- remove, update bookmark

function ReaderBookmark:removeItem(item)
    local index = self.ui.annotation:getItemIndex(item)
    if item.pos0 then
        self.ui.highlight:deleteHighlight(index) -- will call ReaderBookmark:removeItemByIndex()
    else -- dogear bookmark, update it in case we removed a bookmark for current page
        self:removeItemByIndex(index)
        self:setDogearVisibility(self:getCurrentPageNumber())
    end
end

function ReaderBookmark:removeItemByIndex(index)
    local item = self.ui.annotation.annotations[index]
    local item_type = self.getBookmarkType(item)
    if item_type == "highlight" then
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = -1 }))
    elseif item_type == "note" then
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_notes_added = -1 }))
    end
    table.remove(self.ui.annotation.annotations, index)
    self.view.footer:onUpdateFooter(self.view.footer_visible)
end

function ReaderBookmark:deleteItemNote(item)
    local index = self.ui.annotation:getItemIndex(item)
    self.ui.annotation.annotations[index].note = nil
    self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = 1, nb_notes_added = -1 }))
end

-- navigation

function ReaderBookmark:onPageUpdate(pageno)
    local pn_or_xp = self.ui.paging and pageno or self.ui.document:getXPointer()
    self:setDogearVisibility(pn_or_xp)
end

function ReaderBookmark:onPosUpdate(pos)
    local pn_or_xp = self.ui.document:getXPointer()
    self:setDogearVisibility(pn_or_xp)
end

function ReaderBookmark:gotoBookmark(pn_or_xp, marker_xp)
    if pn_or_xp then
        local event = self.ui.paging and "GotoPage" or "GotoXPointer"
        self.ui:handleEvent(Event:new(event, pn_or_xp, marker_xp))
    end
end

function ReaderBookmark:getNextBookmarkedPage(pn_or_xp, page_bookmark_only)
    local pageno = self:getBookmarkPageNumber({page = pn_or_xp})
    for i = 1, #self.ui.annotation.annotations do
        local item = self.ui.annotation.annotations[i]
        if (not page_bookmark_only or not item.drawer) and pageno < self:getBookmarkPageNumber(item) then
            return item.page
        end
    end
end

function ReaderBookmark:getPreviousBookmarkedPage(pn_or_xp, page_bookmark_only)
    local pageno = self:getBookmarkPageNumber({page = pn_or_xp})
    for i = #self.ui.annotation.annotations, 1, -1 do
        local item = self.ui.annotation.annotations[i]
        if (not page_bookmark_only or not item.drawer) and pageno > self:getBookmarkPageNumber(item) then
            return item.page
        end
    end
end

function ReaderBookmark:getFirstBookmarkedPage(pn_or_xp)
    if #self.ui.annotation.annotations > 0 then
        local pageno = self:getBookmarkPageNumber({page = pn_or_xp})
        local item = self.ui.annotation.annotations[1]
        if pageno > self:getBookmarkPageNumber(item) then
            return item.page
        end
    end
end

function ReaderBookmark:getLastBookmarkedPage(pn_or_xp)
    if #self.ui.annotation.annotations > 0 then
        local pageno = self:getBookmarkPageNumber({page = pn_or_xp})
        local item = self.ui.annotation.annotations[#self.ui.annotation.annotations]
        if pageno < self:getBookmarkPageNumber(item) then
            return item.page
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

function ReaderBookmark:onGotoPreviousBookmarkFromPage(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    local pn_or_xp = self:getCurrentPageNumber()
    self:gotoBookmark(self:getPreviousBookmarkedPage(pn_or_xp))
    return true
end

function ReaderBookmark:onGotoNextBookmarkFromPage(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    local pn_or_xp = self:getCurrentPageNumber()
    self:gotoBookmark(self:getNextBookmarkedPage(pn_or_xp))
    return true
end

function ReaderBookmark:onGotoFirstBookmark(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    local pn_or_xp = self:getCurrentPageNumber()
    self:gotoBookmark(self:getFirstBookmarkedPage(pn_or_xp))
    return true
end

function ReaderBookmark:onGotoLastBookmark(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    local pn_or_xp = self:getCurrentPageNumber()
    self:gotoBookmark(self:getLastBookmarkedPage(pn_or_xp))
    return true
end

-- bookmarks misc info, helpers

function ReaderBookmark:getCurrentPageNumber()
    return self.ui.paging and self.view.state.page or self.ui.document:getXPointer()
end

function ReaderBookmark:getBookmarkPageNumber(bookmark)
    return self.ui.paging and bookmark.page or self.ui.document:getPageFromXPointer(bookmark.page)
end

function ReaderBookmark.getBookmarkType(bookmark)
    if bookmark.drawer then
        if bookmark.note then
            return "note"
        end
        return "highlight"
    end
    return "bookmark"
end

function ReaderBookmark:getLatestBookmark()
    local latest_bookmark, latest_bookmark_idx
    local latest_bookmark_datetime = "0"
    for i, v in ipairs(self.ui.annotation.annotations) do
        if v.datetime > latest_bookmark_datetime then
            latest_bookmark_datetime = v.datetime
            latest_bookmark = v
            latest_bookmark_idx = i
        end
    end
    return latest_bookmark, latest_bookmark_idx
end

function ReaderBookmark:getBookmarkedPages()
    local pages = {}
    for _, bm in ipairs(self.ui.annotation.annotations) do
        local page = self:getBookmarkPageNumber(bm)
        local btype = self.getBookmarkType(bm)
        if not pages[page] then
            pages[page] = {}
        end
        if not pages[page][btype] then
            pages[page][btype] = true
        end
    end
    return pages
end

function ReaderBookmark:getBookmarkPageString(page)
    if self.ui.rolling then
        if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
            page = self.ui.pagemap:getXPointerPageLabel(page, true)
        else
            page = self.ui.document:getPageFromXPointer(page)
            if self.ui.document:hasHiddenFlows() then
                local flow = self.ui.document:getPageFlow(page)
                page = self.ui.document:getPageNumberInFlow(page)
                if flow > 0 then
                    page = T("[%1]%2", page, flow)
                end
            end
        end
    end
    return tostring(page)
end

function ReaderBookmark:isBookmarkAutoText(bookmark)
    -- old bookmarks only
    if bookmark.text == "" or bookmark.text == bookmark.notes then
        return true
    end
    local page = self:getBookmarkPageString(bookmark.page)
    local auto_text = T(_("Page %1 %2 @ %3"), page, bookmark.notes, bookmark.datetime)
    return bookmark.text == auto_text
end

-- bookmark list, dialogs

function ReaderBookmark:onShowBookmark()
    self.is_reverse_sorting = G_reader_settings:nilOrTrue("bookmarks_items_reverse_sorting") -- page numbers descending

    -- build up item_table
    local item_table = {}
    local curr_page_num = self:getCurrentPageNumber()
    local curr_page_string = self:getBookmarkPageString(curr_page_num)
    local curr_page_index = self.ui.annotation:getInsertionIndex({page = curr_page_num})
    local num = #self.ui.annotation.annotations + 1
    curr_page_index = self.is_reverse_sorting and num - curr_page_index or curr_page_index
    local curr_page_index_filtered = curr_page_index
    for i = 1, #self.ui.annotation.annotations do
        local v = self.ui.annotation.annotations[self.is_reverse_sorting and num - i or i]
        local item = util.tableDeepCopy(v)
        item.text_orig = item.text or ""
        item.type = self.getBookmarkType(item)
        if not self.match_table or self:doesBookmarkMatchTable(item) then
            item.text = self:getBookmarkItemText(item)
            item.mandatory = self:getBookmarkPageString(item.page)
            if (not self.is_reverse_sorting and i >= curr_page_index) or (self.is_reverse_sorting and i <= curr_page_index) then
                item.after_curr_page = true
                item.mandatory_dim = true
            end
            if item.mandatory == curr_page_string then
                item.bold = true
                item.after_curr_page = nil
                item.mandatory_dim = nil
            end
            table.insert(item_table, item)
        else
            curr_page_index_filtered = curr_page_index_filtered - 1
        end
    end

    local items_per_page = G_reader_settings:readSetting("bookmarks_items_per_page")
    local items_font_size = G_reader_settings:readSetting("bookmarks_items_font_size", Menu.getItemFontSize(items_per_page))
    local multilines_show_more_text = G_reader_settings:isTrue("bookmarks_items_multilines_show_more_text")
    local show_separator = G_reader_settings:isTrue("bookmarks_items_show_separator")

    self.bookmark_menu = CenterContainer:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
    }
    local bm_menu = Menu:new{
        title = T(_("Bookmarks (%1)"), #item_table),
        subtitle = "",
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        items_per_page = items_per_page,
        items_font_size = items_font_size,
        multilines_show_more_text = multilines_show_more_text,
        line_color = show_separator and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_WHITE,
        title_bar_left_icon = "appbar.menu",
        on_close_ges = {
            GestureRange:new{
                ges = "two_finger_swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                direction = BD.flipDirectionIfMirroredUILayout("east")
            }
        },
        show_parent = self.bookmark_menu,
    }
    table.insert(self.bookmark_menu, bm_menu)

    local bookmark = self

    function bm_menu:onMenuSelect(item)
        if self.select_mode then
            if item.dim then
                item.dim = nil
                if item.after_curr_page then
                    item.mandatory_dim = true
                end
                self.select_count = self.select_count - 1
            else
                item.dim = true
                self.select_count = self.select_count + 1
            end
            bookmark:updateBookmarkList(nil, -1)
        else
            bookmark.ui.link:addCurrentLocationToStack()
            bookmark:gotoBookmark(item.page, item.pos0)
            self.close_callback()
        end
    end

    function bm_menu:onMenuHold(item)
        bookmark:showBookmarkDetails(item)
        return true
    end

    function bm_menu:toggleSelectMode()
        self.select_mode = not self.select_mode
        if self.select_mode then
            self.select_count = 0
            self:setTitleBarLeftIcon("check")
        else
            for _, v in ipairs(item_table) do
                v.dim = nil
                if v.after_curr_page then
                    v.mandatory_dim = true
                end
            end
            self:setTitleBarLeftIcon("appbar.menu")
        end
        bookmark:updateBookmarkList(nil, -1)
    end

    function bm_menu:onLeftButtonTap()
        local bm_dialog, dialog_title
        local buttons = {}
        if self.select_mode then
            local actions_enabled = self.select_count > 0
            local more_selections_enabled = self.select_count < #item_table
            if actions_enabled then
                dialog_title = T(N_("1 bookmark selected", "%1 bookmarks selected", self.select_count), self.select_count)
            else
                dialog_title = _("No bookmarks selected")
            end
            table.insert(buttons, {
                {
                    text = _("Select all"),
                    enabled = more_selections_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        for _, v in ipairs(item_table) do
                            v.dim = true
                        end
                        self.select_count = #item_table
                        bookmark:updateBookmarkList(nil, -1)
                    end,
                },
                {
                    text = _("Select page"),
                    enabled = more_selections_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        local item_first = (bm_menu.page - 1) * bm_menu.perpage + 1
                        local item_last = math.min(item_first + bm_menu.perpage - 1, #item_table)
                        for i = item_first, item_last do
                            local v = item_table[i]
                            if v.dim == nil then
                                v.dim = true
                                self.select_count = self.select_count + 1
                            end
                        end
                        bookmark:updateBookmarkList(nil, -1)
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Deselect all"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        for _, v in ipairs(item_table) do
                            v.dim = nil
                            if v.after_curr_page then
                                v.mandatory_dim = true
                            end
                        end
                        self.select_count = 0
                        bookmark:updateBookmarkList(nil, -1)
                    end,
                },
                {
                    text = _("Delete note"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Delete bookmark notes?"),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                UIManager:close(bm_dialog)
                                for _, v in ipairs(item_table) do
                                    if v.dim then
                                        bookmark:deleteItemNote(v)
                                    end
                                end
                                self:onClose()
                                bookmark:onShowBookmark()
                            end,
                        })
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Exit select mode"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        self:toggleSelectMode()
                    end,
                },
                {
                    text = _("Remove"),
                    enabled = actions_enabled and not bookmark.ui.highlight.select_mode,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Remove selected bookmarks?"),
                            ok_text = _("Remove"),
                            ok_callback = function()
                                UIManager:close(bm_dialog)
                                for i = #item_table, 1, -1 do
                                    if item_table[i].dim then
                                        bookmark:removeItem(item_table[i])
                                        table.remove(item_table, i)
                                    end
                                end
                                self.select_mode = false
                                self:setTitleBarLeftIcon("appbar.menu")
                                bookmark:updateBookmarkList(item_table, -1)
                            end,
                        })
                    end,
                },
            })
        else -- select mode off
            dialog_title = _("Filter by bookmark type")
            local actions_enabled = #item_table > 0
            local type_count = { highlight = 0, note = 0, bookmark = 0 }
            for _, item in ipairs(bookmark.ui.annotation.annotations) do
                local item_type = bookmark.getBookmarkType(item)
                type_count[item_type] = type_count[item_type] + 1
            end
            local genBookmarkTypeButton = function(item_type)
                return {
                    text = bookmark.display_prefix[item_type] ..
                        T(_("%1 (%2)"), bookmark.display_type[item_type], type_count[item_type]),
                    callback = function()
                        UIManager:close(bm_dialog)
                        self:onClose()
                        bookmark.match_table = { [item_type] = true }
                        bookmark:onShowBookmark()
                    end,
                }
            end
            table.insert(buttons, {
                {
                    text = _("All (reset filters)"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        self:onClose()
                        bookmark:onShowBookmark()
                    end,
                },
                genBookmarkTypeButton("highlight"),
            })
            table.insert(buttons, {
                genBookmarkTypeButton("bookmark"),
                genBookmarkTypeButton("note"),
            })
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                {
                    text = _("Filter by edited highlighted text"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark:filterByEditedText()
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Filter by highlight style"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark:filterByHighlightStyle()
                    end,
                },
            })
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                {
                    text = _("Current page"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark:updateBookmarkList(nil, curr_page_index_filtered)
                    end,
                },
                {
                    text = _("Latest bookmark"),
                    enabled = actions_enabled
                        and not (bookmark.match_table or bookmark.show_edited_only or bookmark.show_drawer_only),
                    callback = function()
                        UIManager:close(bm_dialog)
                        local _, idx = bookmark:getLatestBookmark()
                        idx = self.is_reverse_sorting and #item_table - idx + 1 or idx
                        bookmark:updateBookmarkList(nil, idx)
                        bookmark:showBookmarkDetails(item_table[idx])
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Select bookmarks"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        self:toggleSelectMode()
                    end,
                },
                {
                    text = _("Search bookmarks"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark:onSearchBookmark()
                    end,
                },
            })
        end
        bm_dialog = ButtonDialog:new{
            title = dialog_title,
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(bm_dialog)
    end

    function bm_menu:onLeftButtonHold()
        self:toggleSelectMode()
        return true
    end

    bm_menu.close_callback = function()
        UIManager:close(self.bookmark_menu)
        self.bookmark_menu = nil
        self.match_table = nil
        self.show_edited_only = nil
        self.show_drawer_only = nil
    end

    self:updateBookmarkList(nil, curr_page_index_filtered)
    UIManager:show(self.bookmark_menu)
    return true
end

function ReaderBookmark:updateBookmarkList(item_table, item_number)
    local bm_menu = self.bookmark_menu[1]

    local title
    if item_table then
        title = T(_("Bookmarks (%1)"), #item_table)
    end

    local subtitle
    if bm_menu.select_mode then
        subtitle = T(_("Selected: %1"), bm_menu.select_count)
    else
        if self.show_edited_only then
            subtitle = _("Filter: edited highlighted text")
        elseif self.show_drawer_only then
            subtitle = _("Highlight style: ") .. self.ui.highlight:getHighlightStyleString(self.show_drawer_only):lower()
        elseif self.match_table then
            if self.match_table.search_str then
                subtitle = T(_("Query: %1"), self.match_table.search_str)
            else
                local types = {}
                for type, type_string in pairs(self.display_type) do
                    if self.match_table[type] then
                        table.insert(types, type_string)
                    end
                end
                table.sort(types)
                subtitle = #types > 0 and _("Bookmark type: ") .. table.concat(types, ", ")
            end
        else
            subtitle = ""
        end
    end

    bm_menu:switchItemTable(title, item_table, item_number, nil, subtitle)
end

function ReaderBookmark:getBookmarkItemIndex(item)
    return (self.match_table or self.show_edited_only or self.show_drawer_only)
        and self.ui.annotation:getItemIndex(item) -- item table is filtered, cannot use item.idx
        or (self.is_reverse_sorting and #self.ui.annotation.annotations - item.idx + 1 or item.idx)
end

function ReaderBookmark:getBookmarkItemText(item)
    if item.type == "highlight" or self.items_text == "text" then
        return self.display_prefix[item.type] .. item.text_orig
    end
    if item.type == "note" and self.items_text == "note" then
        return self.display_prefix["note"] .. item.note
    end
    local text
    if item.type == "bookmark" then
        text = self.display_prefix["bookmark"]
    else -- it is a note, but we show the "highlight" prefix before the highlighted text
        text = self.display_prefix["highlight"]
    end
    if self.items_text == "all" or self.items_text == "note" then
        text = text .. item.text_orig
    end
    if item.note then
        text = text .. "\u{2002}" .. self.display_prefix["note"] .. item.note
    end
    return text
end

function ReaderBookmark:_getDialogHeader(bookmark)
    local page_str = bookmark.mandatory or self:getBookmarkPageString(bookmark.page)
    return T(_("Page: %1"), page_str) .. "     " .. T(_("Time: %1"), bookmark.datetime)
end

function ReaderBookmark:showBookmarkDetails(item)
    local bm_menu = self.bookmark_menu[1]
    local item_table = bm_menu.item_table
    local text = self:_getDialogHeader(item) .. "\n\n"
    local prefix = item.type == "bookmark" and self.display_prefix["bookmark"] or self.display_prefix["highlight"]
    text = text .. prefix .. item.text_orig
    if item.note then
        text = text .. "\n\n" .. self.display_prefix["note"] .. item.note
    end
    local not_select_mode = not bm_menu.select_mode and not self.ui.highlight.select_mode

    local textviewer
    local edit_details_callback = function()
        self.details_updated = true
        UIManager:close(textviewer)
        self:showBookmarkDetails(item_table[item.idx])
    end
    local _showBookmarkDetails = function(idx)
        UIManager:close(textviewer)
        self:updateBookmarkList(nil, idx)
        self:showBookmarkDetails(item_table[idx])
    end

    textviewer = TextViewer:new{
        title = T(_("Bookmark details (%1/%2)"), item.idx, #item_table),
        text = text,
        text_type = "bookmark",
        buttons_table = {
            {
                {
                    text = _("Reset text"),
                    enabled = item.drawer and not_select_mode and item.text_edited or false,
                    callback = function()
                        self:setHighlightedText(item, nil, edit_details_callback)
                    end,
                },
                {
                    text = _("Edit text"),
                    enabled = item.drawer and not_select_mode or false,
                    callback = function()
                        self:editHighlightedText(item, edit_details_callback)
                    end,
                },
            },
            {
                {
                    text = _("Remove bookmark"),
                    enabled = not_select_mode,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Remove this bookmark?"),
                            ok_text = _("Remove"),
                            ok_callback = function()
                                self:removeItem(item)
                                table.remove(item_table, item.idx)
                                self:updateBookmarkList(item_table, -1)
                                UIManager:close(textviewer)
                            end,
                        })
                    end,
                },
                {
                    text = item.note and _("Edit note") or _("Add note"),
                    enabled = not bm_menu.select_mode,
                    callback = function()
                        self:setBookmarkNote(item, nil, nil, edit_details_callback)
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        if self.details_updated then
                            self.details_updated = nil
                            if self.show_edited_only then
                                for i = #item_table, 1, -1 do
                                    if not item_table[i].text_edited then
                                        table.remove(item_table, i)
                                    end
                                end
                            end
                            self:updateBookmarkList(item_table, -1)
                        end
                        UIManager:close(textviewer)
                    end,
                },
                {
                    text = _("Go to bookmark"),
                    enabled = not bm_menu.select_mode,
                    callback = function()
                        UIManager:close(textviewer)
                        self.ui.link:addCurrentLocationToStack()
                        self:gotoBookmark(item.page, item.pos0)
                        bm_menu.close_callback()
                    end,
                },
            },
            {
                {
                    text = "▕◁",
                    enabled = item.idx > 1,
                    callback = function()
                        _showBookmarkDetails(1)
                    end,
                },
                {
                    text = "◁",
                    enabled = item.idx > 1,
                    callback = function()
                        _showBookmarkDetails(item.idx - 1)
                    end,
                },
                {
                    text = "▷",
                    enabled = item.idx < #item_table,
                    callback = function()
                        _showBookmarkDetails(item.idx + 1)
                    end,
                },
                {
                    text = "▷▏",
                    enabled = item.idx < #item_table,
                    callback = function()
                        _showBookmarkDetails(#item_table)
                    end,
                },
            },
        }
    }
    UIManager:show(textviewer)
    return true
end

function ReaderBookmark:setBookmarkNote(item_or_index, is_new_note, new_note, caller_callback)
    local item, index
    if self.bookmark_menu then
        item = item_or_index -- in item_table
        index = self:getBookmarkItemIndex(item)
    else -- from Highlight
        index = item_or_index
    end
    local annotation = self.ui.annotation.annotations[index]
    local type_before = item and item.type or self.getBookmarkType(annotation)
    local input_text = annotation.note
    if new_note then
        if input_text then
            input_text = input_text .. "\n\n" .. new_note
        else
            input_text = new_note
        end
    end
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Edit note"),
        description = "   " .. self:_getDialogHeader(annotation),
        input = input_text,
        allow_newline = true,
        add_scroll_buttons = true,
        use_available_height = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                        if is_new_note then -- "Add note" called from highlight dialog and cancelled, remove saved highlight
                            self:removeItemByIndex(index)
                        end
                    end,
                },
                {
                    text = _("Paste"), -- insert highlighted text
                    callback = function()
                        input_dialog:addTextToInput(annotation.text)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value = input_dialog:getInputText()
                        if value == "" then -- blank input deletes note
                            value = nil
                        end
                        annotation.note = value
                        local type_after = self.getBookmarkType(annotation)
                        if type_before ~= type_after then
                            if type_before == "highlight" then
                                self.ui:handleEvent(Event:new("AnnotationsModified",
                                    { annotation, nb_highlights_added = -1, nb_notes_added = 1 }))
                            else
                                self.ui:handleEvent(Event:new("AnnotationsModified",
                                    { annotation, nb_highlights_added = 1, nb_notes_added = -1 }))
                            end
                        end
                        UIManager:close(input_dialog)
                        if item then
                            item.note = value
                            item.type = type_after
                            item.text = self:getBookmarkItemText(item)
                        end
                        caller_callback()
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:editHighlightedText(item, caller_callback)
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Edit highlighted text"),
        description = "   " .. self:_getDialogHeader(item),
        input = item.text_orig,
        allow_newline = true,
        add_scroll_buttons = true,
        use_available_height = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        self:setHighlightedText(item, input_dialog:getInputText(), caller_callback)
                        UIManager:close(input_dialog)
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:setHighlightedText(item, text, caller_callback)
    local edited
    if text then
        edited = true
    else -- reset to selected text
        if self.ui.rolling then
            text = self.ui.document:getTextFromXPointers(item.pos0, item.pos1)
        else
            text = self.ui.document:getTextFromPositions(item.pos0, item.pos1).text
        end
    end
    local index = self:getBookmarkItemIndex(item)
    self.ui.annotation.annotations[index].text = text
    self.ui.annotation.annotations[index].text_edited = edited
    item.text_orig = text
    item.text = self:getBookmarkItemText(item)
    item.text_edited = edited
    caller_callback()
end

function ReaderBookmark:onSearchBookmark()
    local input_dialog
    local check_button_case, separator, check_button_bookmark, check_button_highlight, check_button_note
    input_dialog = InputDialog:new{
        title = _("Search bookmarks"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local search_str = input_dialog:getInputText()
                        if search_str == "" then
                            search_str = nil
                        else
                            if not check_button_case.checked then
                                search_str = Utf8Proc.lowercase(util.fixUtf8(search_str, "?"))
                            end
                        end
                        self.match_table = {
                            search_str = search_str,
                            bookmark = check_button_bookmark.checked,
                            highlight = check_button_highlight.checked,
                            note = check_button_note.checked,
                            case_sensitive = check_button_case.checked,
                        }
                        UIManager:close(input_dialog)
                        if self.bookmark_menu then -- from bookmark list
                            local bm_menu = self.bookmark_menu[1]
                            local item_table = bm_menu.item_table
                            for i = #item_table, 1, -1 do
                                if not self:doesBookmarkMatchTable(item_table[i]) then
                                    table.remove(item_table, i)
                                end
                            end
                            self:updateBookmarkList(item_table)
                        else -- from main menu
                            self:onShowBookmark()
                        end
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = " " .. _("Case sensitive"),
        checked = false,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_case)
    local separator_width = input_dialog:getAddedWidgetAvailableWidth()
    separator = CenterContainer:new{
        dimen = Geom:new{
            w = separator_width,
            h = 2 * Size.span.vertical_large,
        },
        LineWidget:new{
            background = Blitbuffer.COLOR_DARK_GRAY,
            dimen = Geom:new{
                w = separator_width,
                h = Size.line.medium,
            }
        },
    }
    input_dialog:addWidget(separator)
    check_button_highlight = CheckButton:new{
        text = " " .. self.display_prefix["highlight"] .. self.display_type["highlight"],
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_highlight)
    check_button_note = CheckButton:new{
        text = " " .. self.display_prefix["note"] .. self.display_type["note"],
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_note)
    check_button_bookmark = CheckButton:new{
        text = " " .. self.display_prefix["bookmark"] .. self.display_type["bookmark"],
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_bookmark)

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:filterByEditedText()
    local bm_menu = self.bookmark_menu[1]
    local item_table = bm_menu.item_table
    for i = #item_table, 1, -1 do
        if not item_table[i].text_edited then
            table.remove(item_table, i)
        end
    end
    self.show_edited_only = true
    self:updateBookmarkList(item_table)
end

function ReaderBookmark:filterByHighlightStyle()
    local filter_by_drawer_callback = function(drawer)
        local bm_menu = self.bookmark_menu[1]
        local item_table = bm_menu.item_table
        for i = #item_table, 1, -1 do
            if item_table[i].drawer ~= drawer then
                table.remove(item_table, i)
            end
        end
        self.show_drawer_only = drawer
        self:updateBookmarkList(item_table)
    end
    self.ui.highlight:showHighlightStyleDialog(filter_by_drawer_callback)
end

function ReaderBookmark:doesBookmarkMatchTable(item)
    if self.match_table[item.type] then
        if self.match_table.search_str then
            local text = item.text_orig
            if item.note then -- search in the highlighted text and in the note
                text = text .. "\u{FFFF}" .. item.note
            end
            if not self.match_table.case_sensitive then
                text = Utf8Proc.lowercase(util.fixUtf8(text, "?"))
            end
            return text:find(self.match_table.search_str)
        end
        return true
    end
end

return ReaderBookmark
