local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
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
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderBookmark = InputContainer:extend{
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
        local items_per_page = G_reader_settings:readSetting("items_per_page") or Menu.items_per_page_default
        G_reader_settings:saveSetting("bookmarks_items_per_page", items_per_page)
        local items_font_size = G_reader_settings:readSetting("items_font_size")
        if items_font_size and items_font_size ~= Menu.getItemFontSize(items_per_page) then
            -- Keep the user items font size if it's not the default for items_per_page
            G_reader_settings:saveSetting("bookmarks_items_font_size", items_font_size)
        end
    end
    self.items_text = G_reader_settings:readSetting("bookmarks_items_text_type", "note")
    self.items_max_lines = G_reader_settings:readSetting("bookmarks_items_max_lines")

    self.ui.menu:registerToMainMenu(self)
    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderBookmark:onGesture() end

function ReaderBookmark:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowBookmark = { { "B" }, { "Shift", "Left" } }
        self.key_events.ToggleBookmark = { { "Shift", "Right" } }
    elseif Device:hasScreenKB() then
        self.key_events.ShowBookmark = { { "ScreenKB", "Left" } }
        self.key_events.ToggleBookmark = { { "ScreenKB", "Right" } }
    end
end

ReaderBookmark.onPhysicalKeyboardConnected = ReaderBookmark.registerKeyEvents

function ReaderBookmark:addToMainMenu(menu_items)
    menu_items.bookmarks = {
        text = _("Bookmarks"),
        callback = function()
            self:onShowBookmark()
        end,
    }
    if not Device:isTouchDevice() and not (Device:hasScreenKB() or Device:hasSymKey()) then
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
            check_callback_closes_menu = true,
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
                    return T(_("Max lines per bookmark: %1"), self.items_max_lines or _("disabled"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local default_value = 4
                    local spin_wodget = SpinWidget:new{
                        title_text = _("Max lines per bookmark"),
                        info_text = _("Set maximum number of lines to enable flexible item heights."),
                        value = self.items_max_lines or default_value,
                        value_min = 1,
                        value_max = 10,
                        default_value = default_value,
                        ok_always_enabled = true,
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_max_lines", spin.value)
                            self.items_max_lines = spin.value
                            touchmenu_instance:updateItems()
                        end,
                        extra_text = _("Disable"),
                        extra_callback = function()
                            G_reader_settings:delSetting("bookmarks_items_max_lines")
                            self.items_max_lines = nil
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(spin_wodget)
                end,
            },
            {
                text_func = function()
                    local curr_perpage = self.items_max_lines and _("flexible")
                        or G_reader_settings:readSetting("bookmarks_items_per_page")
                    return T(_("Bookmarks per page: %1"), curr_perpage)
                end,
                enabled_func = function()
                    return not self.items_max_lines
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local items = SpinWidget:new{
                        title_text = _("Bookmarks per page"),
                        value = curr_perpage,
                        value_min = 6,
                        value_max = 24,
                        default_value = Menu.items_per_page_default,
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_per_page", spin.value)
                            touchmenu_instance:updateItems()
                        end,
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
                        title_text = _("Bookmark font size"),
                        value = curr_font_size,
                        value_min = 10,
                        value_max = 72,
                        default_value = default_font_size,
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_font_size", spin.value)
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(items_font)
                end,
            },
            {
                text = _("Shrink bookmark font size to fit more text"),
                enabled_func = function()
                    return not self.items_max_lines
                end,
                checked_func = function()
                    return not self.items_max_lines and G_reader_settings:isTrue("bookmarks_items_multilines_show_more_text")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("bookmarks_items_multilines_show_more_text")
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Show in items: %1"), self:genShowInItemsMenuItems())
                end,
                sub_item_table = {
                    self:genShowInItemsMenuItems("text"),
                    self:genShowInItemsMenuItems("all"),
                    self:genShowInItemsMenuItems("note"),
                },
            },
            {
                text = _("Show separator between items"),
                checked_func = function()
                    return G_reader_settings:isTrue("bookmarks_items_show_separator")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("bookmarks_items_show_separator")
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Sort by: %1"), self:genSortByMenuItems())
                end,
                sub_item_table = {
                    self:genSortByMenuItems("page"),
                    self:genSortByMenuItems("date", true),
                    -- separator
                    {
                        text = _("Reverse sorting"),
                        checked_func = function()
                            return G_reader_settings:isTrue("bookmarks_items_reverse_sorting")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("bookmarks_items_reverse_sorting")
                        end,
                    },
                },
                separator = true,
            },
            {
                text = _("Export annotations on book closing"),
                checked_func = function()
                    return G_reader_settings:isTrue("annotations_export_on_closing")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("annotations_export_on_closing")
                end,
            },
            {
                text = _("Keep all annotations on import"),
                checked_func = function()
                    return G_reader_settings:isTrue("annotations_export_keep_all_on_import")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("annotations_export_keep_all_on_import")
                end,
            },
            {
                text_func = function()
                    return T(_("Export / import folder: %1"),
                        G_reader_settings:readSetting("annotations_export_folder") or _("book metadata folder"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local title_header = _("Current annotations export folder:")
                    local default_path = DocSettings:getSidecarDir(self.ui.document.file)
                    local current_path = G_reader_settings:readSetting("annotations_export_folder") or default_path
                    local caller_callback = function(path)
                        if path == default_path then
                            G_reader_settings:delSetting("annotations_export_folder")
                        else
                            G_reader_settings:saveSetting("annotations_export_folder", path)
                        end
                        touchmenu_instance:updateItems()
                    end
                    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
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

function ReaderBookmark:genShowInItemsMenuItems(value)
    local strings = {
        text = _("highlighted text"),
        all  = _("highlighted text and note"),
        note = _("note if set, otherwise highlighted text"),
    }
    if value == nil then
        value = G_reader_settings:readSetting("bookmarks_items_text_type", "note")
        return strings[value]
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.items_text == value
        end,
        radio = true,
        callback = function()
            self.items_text = value
            G_reader_settings:saveSetting("bookmarks_items_text_type", value)
        end,
    }
end

function ReaderBookmark:genSortByMenuItems(value, separator)
    local strings = {
        page = _("page number"),
        date = _("date"),
    }
    local strings_reverse = {
        page = _("page number, reverse"),
        date = _("date, reverse"),
    }
    if value == nil then
        local curr_value = G_reader_settings:readSetting("bookmarks_items_sorting") or "page"
        if G_reader_settings:isTrue("bookmarks_items_reverse_sorting") then
            return strings_reverse[curr_value]
        else
            return strings[curr_value]
        end
    end
    return {
        text = strings[value],
        checked_func = function()
            return value == (G_reader_settings:readSetting("bookmarks_items_sorting") or "page")
        end,
        radio = true,
        callback = function()
            G_reader_settings:saveSetting("bookmarks_items_sorting", value ~= "page" and value or nil)
        end,
        separator = separator,
    }
end

-- page bookmarks, dogear

function ReaderBookmark:onToggleBookmark()
    self:toggleBookmark()
    self.view.dogear:onSetDogearVisibility(not self.view.dogear_visible)
    -- Refresh the dogear first, because it might inherit ReaderUI refresh hints.
    UIManager:setDirty(self.view.dialog, function()
        return "ui",
        self.view.dogear:getRefreshRegion()
    end)
    -- And ask for a footer refresh, in case we have bookmark_count enabled.
    -- Assuming the footer is visible, it'll request a refresh regardless, but the EPDC should optimize it out if no content actually changed.
    self.view.footer:maybeUpdateFooter()
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
        index = -index
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
        index = self.ui.annotation:addItem(item)
    end
    self.ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = index }))
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

function ReaderBookmark:removeItem(item, item_idx)
    local index = item_idx or self:getBookmarkItemIndex(item)
    if item.drawer then
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
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = -1, index_modified = -index }))
    elseif item_type == "note" then
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_notes_added = -1, index_modified = -index }))
    end
    table.remove(self.ui.annotation.annotations, index)
    self.view.footer:maybeUpdateFooter()
end

function ReaderBookmark:deleteItemNote(item)
    local index = self:getBookmarkItemIndex(item)
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
            return self.ui.pagemap:getXPointerPageLabel(page, true)
        end
        page = self.ui.document:getPageFromXPointer(page)
    end
    if self.ui.document:hasHiddenFlows() then
        local flow = self.ui.document:getPageFlow(page)
        page = self.ui.document:getPageNumberInFlow(page)
        if flow > 0 then
            page = T("[%1]%2", page, flow)
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
    self.sorting_mode = G_reader_settings:readSetting("bookmarks_items_sorting") or "page"
    self.is_reverse_sorting = G_reader_settings:isTrue("bookmarks_items_reverse_sorting")

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
    local curr_page_datetime
    if self.sorting_mode == "date" and #item_table > 0 then
        local idx = math.max(1, math.min(curr_page_index_filtered, #item_table))
        curr_page_datetime = item_table[idx].datetime
        local sort_func = self.is_reverse_sorting and function(a, b) return a.datetime > b.datetime end
                                                   or function(a, b) return a.datetime < b.datetime end
        table.sort(item_table, sort_func)
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
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        items_per_page = items_per_page,
        items_font_size = items_font_size,
        items_max_lines = self.items_max_lines,
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
        if self.select_count then
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
        if self.select_count then
            self.select_count = nil
            for _, v in ipairs(item_table) do
                v.dim = nil
                if v.after_curr_page then
                    v.mandatory_dim = true
                end
            end
            self:setTitleBarLeftIcon("appbar.menu")
        else
            self.select_count = 0
            self:setTitleBarLeftIcon("check")
        end
        bookmark:updateBookmarkList(nil, -1)
    end

    function bm_menu:onLeftButtonTap()
        local bm_dialog, dialog_title
        local buttons = {}
        if self.select_count then
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
                                self.select_count = nil
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
                    text = _("Export annotations"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark.ui.annotation:onExportAnnotations()
                    end,
                },
            })
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                {
                    text = _("Current page"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        local idx
                        if bookmark.sorting_mode == "date" then
                            for i, v in ipairs(item_table) do
                                if v.datetime == curr_page_datetime then
                                    idx = i
                                    break
                                end
                            end
                        else -- "page"
                            idx = curr_page_index_filtered
                        end
                        bookmark:updateBookmarkList(nil, idx)
                    end,
                },
                {
                    text = _("Latest bookmark"),
                    enabled = actions_enabled
                        and not (bookmark.match_table or bookmark.show_edited_only or bookmark.show_drawer_only),
                    callback = function()
                        UIManager:close(bm_dialog)
                        local idx
                        if bookmark.sorting_mode == "date" then
                            idx = bookmark.is_reverse_sorting and 1 or #item_table
                        else -- "page"
                            idx = select(2, bookmark:getLatestBookmark())
                            idx = bookmark.is_reverse_sorting and #item_table - idx + 1 or idx
                        end
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

    local idx
    if bookmark.sorting_mode == "date" then -- show the most recent bookmark
        idx = bookmark.is_reverse_sorting and 1 or #item_table
    else -- "page", show bookmark in the current book page
        idx = curr_page_index_filtered
    end
    self:updateBookmarkList(nil, idx)
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
    if bm_menu.select_count then
        subtitle = T(_("Selected: %1"), bm_menu.select_count)
    else
        if self.show_edited_only then
            subtitle = _("Filter: edited highlighted text")
        elseif self.show_drawer_only then
            subtitle = _("Highlight style:") .. " " .. self.ui.highlight:getHighlightStyleString(self.show_drawer_only):lower()
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
                subtitle = #types > 0 and _("Bookmark type:") .. " " .. table.concat(types, ", ")
            end
        else
            subtitle = ""
        end
    end

    bm_menu:switchItemTable(title, item_table, item_number, nil, subtitle)
end

function ReaderBookmark:getBookmarkItemIndex(item)
    if not item.idx or self.match_table or self.show_edited_only or self.show_drawer_only -- filtered
            or self.sorting_mode ~= "page" then -- or item_table order does not match with annotations
        return self.ui.annotation:getItemIndex(item)
    end
    if self.is_reverse_sorting then
        return #self.ui.annotation.annotations - item.idx + 1
    end
    return item.idx
end

function ReaderBookmark:getBookmarkItemText(item)
    local text
    if item.type == "highlight" or self.items_text == "text" then
        text = self.display_prefix[item.type] .. item.text_orig
    else
        if item.type == "note" and self.items_text == "note" then
            text = self.display_prefix["note"] .. item.note
        else
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
        end
    end
    if self.sorting_mode == "date" then
        text = item.datetime .. "\u{2002}" .. text
    end
    return text
end

function ReaderBookmark:_getDialogHeader(bookmark)
    local page_str = bookmark.mandatory or self:getBookmarkPageString(bookmark.page)
    return T(_("Page: %1"), page_str) .. "     " .. T(_("Time: %1"), bookmark.datetime)
end

function ReaderBookmark:showBookmarkDetails(item_or_index)
    local item_table, item, item_idx, item_type
    local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
    if bm_menu then -- called from Bookmark list, got item
        item_table = bm_menu.item_table
        item = item_or_index
        item_idx = item.idx
        item_type = item.type
    else -- called from Reader, got index
        item_table = self.ui.annotation.annotations
        item_idx = item_or_index
        item = item_table[item_idx]
        item_type = self.getBookmarkType(item)
    end
    local items_nb = #item_table
    local text = self:_getDialogHeader(item) .. "\n\n"
    local prefix = item_type == "bookmark" and self.display_prefix["bookmark"] or self.display_prefix["highlight"]
    text = text .. prefix .. (item.text_orig or item.text)
    if item.note then
        text = text .. "\n\n" .. self.display_prefix["note"] .. item.note
    end
    local not_select_mode = not (bm_menu and bm_menu.select_count) and not self.ui.highlight.select_mode

    local textviewer
    local function _goToBookmark()
        UIManager:close(textviewer)
        self.ui.link:addCurrentLocationToStack()
        self:gotoBookmark(item.page, item.pos0)
    end
    local function _showBookmarkDetails(idx)
        UIManager:close(textviewer)
        if bm_menu then
            self:updateBookmarkList(nil, idx)
            self:showBookmarkDetails(item_table[idx])
        else
            self:showBookmarkDetails(idx)
        end
    end
    local function edit_details_callback()
        self.details_updated = true
        UIManager:close(textviewer)
        self:showBookmarkDetails(item_or_index)
    end
    local function close_callback()
        if self.details_updated then
            self.details_updated = nil
            if bm_menu then
                if self.show_edited_only then
                    for i = items_nb, 1, -1 do
                        if not item_table[i].text_edited then
                            table.remove(item_table, i)
                        end
                    end
                end
                self:updateBookmarkList(item_table, -1)
            else
                if self.view.highlight.note_mark then -- refresh note marker
                    UIManager:setDirty(self.dialog, "ui")
                end
            end
        end
    end

    local buttons_table = {
        {
            {
                text = "▕◁",
                enabled = item_idx > 1,
                callback = function()
                    _showBookmarkDetails(1)
                end,
            },
            {
                text = "◁",
                enabled = item_idx > 1,
                callback = function()
                    _showBookmarkDetails(item_idx - 1)
                end,
            },
            {
                text = "▷",
                enabled = item_idx < items_nb,
                callback = function()
                    _showBookmarkDetails(item_idx + 1)
                end,
            },
            {
                text = "▷▏",
                enabled = item_idx < items_nb,
                callback = function()
                    _showBookmarkDetails(items_nb)
                end,
            },
        },
        {
            {
                text = _("Reset text"),
                enabled = item.text_edited and not_select_mode or false,
                callback = function()
                    self:setHighlightedText(item_or_index, nil, edit_details_callback)
                end,
            },
            {
                text = _("Edit text"),
                enabled = item.drawer and not_select_mode or false,
                callback = function()
                    self:editHighlightedText(item_or_index, edit_details_callback)
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
                            UIManager:close(textviewer)
                            self:removeItem(item, not bm_menu and item_idx)
                            if bm_menu then
                                table.remove(item_table, item_idx)
                                self:updateBookmarkList(item_table, -1)
                            end
                        end,
                    })
                end,
            },
            {
                text = item.note and _("Edit note") or _("Add note"),
                enabled = not_select_mode,
                callback = function()
                    self:setBookmarkNote(item_or_index, nil, nil, edit_details_callback)
                end,
            },
        },
        {
            {
                text = _("Go to bookmark"),
                enabled = not (bm_menu and bm_menu.select_count),
                callback = function()
                    _goToBookmark()
                    if bm_menu then
                        bm_menu.close_callback()
                    end
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    textviewer:onClose()
                end,
            },
        },
    }

    textviewer = TextViewer:new{
        title = T(_("Bookmark details (%1/%2)"), item_idx, items_nb),
        text = text,
        text_type = "bookmark",
        buttons_table = buttons_table,
        close_callback = close_callback,
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
                        -- NOTE: We'll want a full refresh on close, as the CRe highlight may extend past our own dimensions,
                        --       especially if we're closed separately from our VirtualKeyboard.
                        UIManager:close(input_dialog, "flashui")
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
                        self.ui.highlight:writePdfAnnotation("content", annotation, value)
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

function ReaderBookmark:editHighlightedText(item_or_index, caller_callback)
    local item
    if self.bookmark_menu then
        item = item_or_index -- in item_table
    else -- from Highlight
        item = self.ui.annotation.annotations[item_or_index]
    end
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Edit highlighted text"),
        description = "   " .. self:_getDialogHeader(item),
        input = item.text_orig or item.text,
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
                        self:setHighlightedText(item_or_index, input_dialog:getInputText(), caller_callback)
                        UIManager:close(input_dialog)
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:setHighlightedText(item_or_index, text, caller_callback)
    local item, index
    if self.bookmark_menu then
        item = item_or_index -- in item_table
        index = self:getBookmarkItemIndex(item)
    else -- from Highlight
        index = item_or_index
    end
    local annotation = self.ui.annotation.annotations[index]
    local edited
    if text then
        edited = true
    else -- reset to selected text
        if self.ui.rolling then
            text = self.ui.document:getTextFromXPointers(annotation.pos0, annotation.pos1)
        else
            text = self.ui.document:getTextFromPositions(annotation.pos0, annotation.pos1).text
        end
    end
    annotation.text = text
    annotation.text_edited = edited
    if item then
        item.text_orig = text
        item.text = self:getBookmarkItemText(item)
        item.text_edited = edited
    end
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
    return true
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
