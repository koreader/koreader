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
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderBookmark = InputContainer:extend{
    bookmarks_items_per_page_default = 14,
    bookmarks = nil,
    -- mark the type of a bookmark with a symbol + non-expandable space
    display_prefix = {
        highlight = "\u{2592}\u{2002}", -- "medium shade"
        note = "\u{F040}\u{2002}", -- "pencil"
        bookmark = "\u{F097}\u{2002}", -- "empty bookmark"
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

    self.ui.menu:registerToMainMenu(self)
    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderBookmark:onGesture() end

function ReaderBookmark:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowBookmark = { { "B" } }
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
                self:toggleBookmarkBrowsingMode()
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
                text = _("Sort by largest page number"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("bookmarks_items_reverse_sorting")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("bookmarks_items_reverse_sorting")
                end,
            },
            {
                text = _("Add page number / timestamp to bookmark"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("bookmarks_items_auto_text")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("bookmarks_items_auto_text")
                end,
            },
        },
    }
    menu_items.bookmark_search = {
        text = _("Bookmark search"),
        enabled_func = function()
            return self:hasBookmarks()
        end,
        callback = function()
            self:onSearchBookmark()
        end,
    }
end

function ReaderBookmark:toggleBookmarkBrowsingMode()
    self.ui:handleEvent(Event:new("ToggleBookmarkFlipping"))
end

function ReaderBookmark:isBookmarkInPositionOrder(a, b)
    if self.ui.paging then
        if a.page == b.page then -- both bookmarks in the same page
            if a.highlighted and b.highlighted then -- both are highlights, compare positions
                local is_reflow = self.ui.document.configurable.text_wrap -- save reflow mode
                -- reflow mode didn't set page in positions (in older bookmarks)
                if not a.pos0.page then
                    a.pos0.page = a.page
                    a.pos1.page = a.page
                end
                if not b.pos0.page then
                    b.pos0.page = b.page
                    b.pos1.page = b.page
                end
                self.ui.document.configurable.text_wrap = 0 -- native positions
                -- sort start and end positions of each highlight
                local compare_pos, a_start, a_end, b_start, b_end, result
                compare_pos = self.ui.document:comparePositions(a.pos0, a.pos1) > 0
                a_start = compare_pos and a.pos0 or a.pos1
                a_end = compare_pos and a.pos1 or a.pos0
                compare_pos = self.ui.document:comparePositions(b.pos0, b.pos1) > 0
                b_start = compare_pos and b.pos0 or b.pos1
                b_end = compare_pos and b.pos1 or b.pos0
                -- compare start positions
                compare_pos = self.ui.document:comparePositions(a_start, b_start)
                if compare_pos == 0 then -- both highlights with the same start, compare ends
                    result = self.ui.document:comparePositions(a_end, b_end) < 0
                else
                    result = compare_pos < 0
                end
                self.ui.document.configurable.text_wrap = is_reflow -- restore reflow mode
                return result
            end
            return a.highlighted -- have page bookmarks before highlights
        end
        return a.page > b.page
    else
        local a_page = self.ui.document:getPageFromXPointer(a.page)
        local b_page = self.ui.document:getPageFromXPointer(b.page)
        if a_page == b_page then -- both bookmarks in the same page
            local compare_xp = self.ui.document:compareXPointers(a.page, b.page)
            if compare_xp then
                if compare_xp == 0 then -- both bookmarks with the same start
                    if a.highlighted and b.highlighted then -- both are highlights, compare ends
                        compare_xp = self.ui.document:compareXPointers(a.pos1, b.pos1)
                        if compare_xp then
                            return compare_xp < 0
                        end
                        logger.warn("Invalid xpointer in highlight:", a.pos1, b.pos1)
                        return
                    end
                    return a.highlighted -- have page bookmarks before highlights
                end
                return compare_xp < 0
            end
            -- if compare_xp is nil, some xpointer is invalid and will be sorted first to page 1
            logger.warn("Invalid xpointer in highlight:", a.page, b.page)
        end
        return a_page > b_page
    end
end

function ReaderBookmark:isBookmarkInPageOrder(a, b)
    local a_page = self:getBookmarkPageNumber(a)
    local b_page = self:getBookmarkPageNumber(b)
    if a_page == b_page then -- have bookmarks before highlights
        return a.highlighted
    end
    return a_page > b_page
end

function ReaderBookmark:isBookmarkInReversePageOrder(a, b)
    -- The way this is used (by getNextBookmarkedPage(), iterating bookmarks
    -- in reverse order), we want to skip highlights, but also the current
    -- page: so we do not do any "a.page == b.page" check (not even with
    -- a reverse logic than the one from above function).
    return self:getBookmarkPageNumber(a) < self:getBookmarkPageNumber(b)
end

function ReaderBookmark:isBookmarkPageInPageOrder(a, b)
    return a > self:getBookmarkPageNumber(b)
end

function ReaderBookmark:isBookmarkPageInReversePageOrder(a, b)
    return a < self:getBookmarkPageNumber(b)
end

function ReaderBookmark:fixBookmarkSort(config)
    -- for backward compatibility, since previously bookmarks for credocuments
    -- are not well sorted. We need to do a whole sorting for at least once.
    -- 20220106: accurate sorting with isBookmarkInPositionOrder
    if config:hasNot("bookmarks_sorted_20220106") then
        table.sort(self.bookmarks, function(a, b)
            return self:isBookmarkInPositionOrder(a, b)
        end)
    end
end

function ReaderBookmark:importSavedHighlight(config)
    local textmarks = config:readSetting("highlight") or {}
    -- import saved highlight once, because from now on highlight are added to
    -- bookmarks when they are created.
    if config:hasNot("highlights_imported") then
        for page, marks in pairs(textmarks) do
            for _, mark in ipairs(marks) do
                local mark_page = self.ui.paging and page or mark.pos0
                -- highlights saved by some old versions don't have pos0 field
                -- we just ignore those highlights
                if mark_page then
                    self:addBookmark({
                        page = mark_page,
                        datetime = mark.datetime,
                        notes = mark.text,
                        highlighted = true,
                    })
                end
            end
        end
    end
end

function ReaderBookmark:updateHighlightsIfNeeded(config)
    -- adds "chapter" property to highlights and bookmarks already saved in the document
    local version = config:readSetting("bookmarks_version") or 0
    if version >= 20200615 then
        return
    end
    for page, highlights in pairs(self.view.highlight.saved) do
        for _, highlight in ipairs(highlights) do
            local pn_or_xp = self.ui.paging and page or highlight.pos0
            highlight.chapter = self.ui.toc:getTocTitleByPage(pn_or_xp)
        end
    end
    for _, bookmark in ipairs(self.bookmarks) do
        local pn_or_xp = (self.ui.rolling and bookmark.pos0) and bookmark.pos0 or bookmark.page
        bookmark.chapter = self.ui.toc:getTocTitleByPage(pn_or_xp)
    end
end

function ReaderBookmark:onReadSettings(config)
    self.bookmarks = config:readSetting("bookmarks", {})
    -- Bookmark formats in crengine and mupdf are incompatible.
    -- Backup bookmarks when the document is opened with incompatible engine.
    if #self.bookmarks > 0 then
        local bookmarks_type = type(self.bookmarks[1].page)
        if self.ui.rolling and bookmarks_type == "number" then
            config:saveSetting("bookmarks_paging", self.bookmarks)
            self.bookmarks = config:readSetting("bookmarks_rolling", {})
            config:saveSetting("bookmarks", self.bookmarks)
            config:delSetting("bookmarks_rolling")
        elseif self.ui.paging and bookmarks_type == "string" then
            config:saveSetting("bookmarks_rolling", self.bookmarks)
            self.bookmarks = config:readSetting("bookmarks_paging", {})
            config:saveSetting("bookmarks", self.bookmarks)
            config:delSetting("bookmarks_paging")
        end
    else
        if self.ui.rolling and config:has("bookmarks_rolling") then
            self.bookmarks = config:readSetting("bookmarks_rolling")
            config:delSetting("bookmarks_rolling")
        elseif self.ui.paging and config:has("bookmarks_paging") then
            self.bookmarks = config:readSetting("bookmarks_paging")
            config:delSetting("bookmarks_paging")
        end
    end
    -- need to do this after initialization because checking xpointer
    -- may cause segfaults before credocuments are inited.
    self.ui:registerPostInitCallback(function()
        self:fixBookmarkSort(config)
        self:importSavedHighlight(config)
        self:updateHighlightsIfNeeded(config)
    end)
end

function ReaderBookmark:onSaveSettings()
    self.ui.doc_settings:saveSetting("bookmarks", self.bookmarks)
    self.ui.doc_settings:saveSetting("bookmarks_version", 20200615)
    self.ui.doc_settings:makeTrue("bookmarks_sorted_20220106")
    self.ui.doc_settings:makeTrue("highlights_imported")
end

function ReaderBookmark:onToggleBookmark()
    self:toggleBookmark()
    self.view.footer:onUpdateFooter(self.view.footer_visible)
    self.view.dogear:onSetDogearVisibility(not self.view.dogear_visible)
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

function ReaderBookmark:isPageBookmarked(pn_or_xp)
    local page = pn_or_xp or self:getCurrentPageNumber()
    return self:getDogearBookmarkIndex(page) and true or false
end

function ReaderBookmark:setDogearVisibility(pn_or_xp)
    self.view.dogear:onSetDogearVisibility(self:isPageBookmarked(pn_or_xp))
end

function ReaderBookmark:onPageUpdate(pageno)
    local pn_or_xp = self.ui.paging and pageno or self.ui.document:getXPointer()
    self:setDogearVisibility(pn_or_xp)
end

function ReaderBookmark:onPosUpdate(pos)
    self:setDogearVisibility(self.ui.document:getXPointer())
end

function ReaderBookmark:gotoBookmark(pn_or_xp, marker_xp)
    if pn_or_xp then
        local event = self.ui.paging and "GotoPage" or "GotoXPointer"
        self.ui:handleEvent(Event:new(event, pn_or_xp, marker_xp))
    end
end

function ReaderBookmark:onShowBookmark(match_table)
    self.show_edited_only = nil
    self.select_mode = false
    self.filtered_mode = match_table and true or false
    -- build up item_table
    local item_table = {}
    local is_reverse_sorting = G_reader_settings:nilOrTrue("bookmarks_items_reverse_sorting")
    local curr_page_num = self:getCurrentPageNumber()
    local curr_page_string = self:getBookmarkPageString(curr_page_num)
    local curr_page_index = self:getBookmarkInsertionIndexBinary({page = curr_page_num}) - 1
    local num = #self.bookmarks + 1
    curr_page_index = is_reverse_sorting and curr_page_index or num - curr_page_index
    local curr_page_index_filtered = curr_page_index
    for i = 1, #self.bookmarks do
        -- bookmarks are internally sorted by descending page numbers
        local v = self.bookmarks[is_reverse_sorting and i or num - i]
        if v.text == nil or v.text == "" then
            v.text = self:getBookmarkAutoText(v)
        end
        local item = util.tableDeepCopy(v)
        item.type = self:getBookmarkType(item)
        if not match_table or self:doesBookmarkMatchTable(item, match_table) then
            item.text_orig = item.text or item.notes
            item.text = self.display_prefix[item.type] .. item.text_orig
            item.mandatory = self:getBookmarkPageString(item.page)
            if (not is_reverse_sorting and i >= curr_page_index) or (is_reverse_sorting and i <= curr_page_index) then
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
        title = self.filtered_mode and _("Bookmarks (search results)") or _("Bookmarks"),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
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
            bm_menu:updateItems()
        else
            bookmark.ui.link:addCurrentLocationToStack()
            bookmark:gotoBookmark(item.page, item.pos0)
            bm_menu.close_callback()
        end
    end

    function bm_menu:onMenuHold(item)
        local bm_view = bookmark._getDialogHeader(item) .. "\n\n"
        if item.type == "bookmark" then
            bm_view = bm_view .. item.text
        else
            bm_view = bm_view .. bookmark.display_prefix["highlight"] .. item.notes
            if item.type == "note" then
                bm_view = bm_view .. "\n\n" .. item.text
            end
        end
        local not_select_mode = not self.select_mode and not bookmark.ui.highlight.select_mode
        local textviewer
        textviewer = TextViewer:new{
            title = _("Bookmark details"),
            text = bm_view,
            text_type = "bookmark",
            buttons_table = {
                {
                    {
                        text = _("Reset text"),
                        enabled = item.highlighted and not_select_mode and item.edited or false,
                        callback = function()
                            UIManager:close(textviewer)
                            bookmark:setHighlightedText(item)
                            if bookmark.show_edited_only then
                                table.remove(item_table, item.idx)
                            end
                            bookmark.refresh()
                        end,
                    },
                    {
                        text = _("Edit text"),
                        enabled = item.highlighted and not_select_mode or false,
                        callback = function()
                            UIManager:close(textviewer)
                            bookmark:editHighlightedText(item)
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
                                    bookmark:removeHighlight(item)
                                    table.remove(item_table, item.idx)
                                    bm_menu:switchItemTable(nil, item_table, -1)
                                    UIManager:close(textviewer)
                                end,
                            })
                        end,
                    },
                    {
                        text = bookmark:getBookmarkNote(item) and _("Edit note") or _("Add note"),
                        enabled = not self.select_mode,
                        callback = function()
                            bookmark:setBookmarkNote(item)
                            UIManager:close(textviewer)
                        end,
                    },
                },
                {
                    {
                        text = _("Close"),
                        is_enter_default = true,
                        callback = function()
                            UIManager:close(textviewer)
                        end,
                    },
                    {
                        text = _("Go to bookmark"),
                        enabled = not self.select_mode,
                        callback = function()
                            UIManager:close(textviewer)
                            bookmark.ui.link:addCurrentLocationToStack()
                            bookmark:gotoBookmark(item.page, item.pos0)
                            bm_menu.close_callback()
                        end,
                    },
                },
            }
        }
        UIManager:show(textviewer)
        return true
    end

    function bm_menu:toggleSelectMode()
        self.select_mode = not self.select_mode
        if self.select_mode then
            self.select_count = 0
            bm_menu:setTitleBarLeftIcon("check")
        else
            for _, v in ipairs(item_table) do
                v.dim = nil
                if v.after_curr_page then
                    v.mandatory_dim = true
                end
            end
            bm_menu:switchItemTable(nil, item_table, curr_page_index_filtered)
            bm_menu:setTitleBarLeftIcon("appbar.menu")
        end
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
                        bm_menu:updateItems()
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
                        bm_menu:updateItems()
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
                        bm_menu:updateItems()
                    end,
                },
                {
                    text = _("Reset"),
                    enabled = G_reader_settings:isFalse("bookmarks_items_auto_text")
                        and actions_enabled and not bookmark.ui.highlight.select_mode,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Reset page number / timestamp?"),
                            ok_text = _("Reset"),
                            ok_callback = function()
                                UIManager:close(bm_dialog)
                                for _, v in ipairs(item_table) do
                                    if v.dim then
                                        bookmark:removeBookmark(v, true) -- reset_auto_text_only=true
                                    end
                                end
                                bm_menu:onClose()
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
                        bm_menu:toggleSelectMode()
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
                                        bookmark:removeHighlight(item_table[i])
                                        table.remove(item_table, i)
                                    end
                                end
                                self.select_mode = false
                                bm_menu:switchItemTable(nil, item_table, -1)
                                bm_menu:setTitleBarLeftIcon("appbar.menu")
                            end,
                        })
                    end,
                },
            })
        else
            dialog_title = _("Filter by bookmark type")
            local actions_enabled = #item_table > 0
            local hl_count = 0
            local nt_count = 0
            local bm_count = 0
            for i, v in ipairs(item_table) do
                if v.type == "highlight" then
                    hl_count = hl_count + 1
                elseif v.type == "note" then
                    nt_count = nt_count + 1
                elseif v.type == "bookmark" then
                    bm_count = bm_count + 1
                end
            end
            table.insert(buttons, {
                {
                    text = _("All (reset filters)"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bm_menu:onClose()
                        bookmark:onShowBookmark()
                    end,
                },
                {
                    text = bookmark.display_prefix["highlight"] .. T(_("%1 (%2)"), _("highlights"), hl_count),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bm_menu:onClose()
                        bookmark:onShowBookmark({highlight = true})
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = bookmark.display_prefix["bookmark"] .. T(_("%1 (%2)"), _("page bookmarks"), bm_count),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bm_menu:onClose()
                        bookmark:onShowBookmark({bookmark = true})
                    end,
                },
                {
                    text = bookmark.display_prefix["note"] .. T(_("%1 (%2)"), _("notes"), nt_count),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bm_menu:onClose()
                        bookmark:onShowBookmark({note = true})
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Filter by highlight style"),
                    callback = function()
                        bookmark:filterByHighlightStyle(bm_dialog, bm_menu)
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Filter by edited highlighted text"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark:filterByEditedText(bm_menu)
                    end,
                },
            })
            table.insert(buttons, {})
            table.insert(buttons, {
                {
                    text = _("Current page"),
                    callback = function()
                        UIManager:close(bm_dialog)
                        bm_menu:switchItemTable(nil, item_table, curr_page_index_filtered)
                    end,
                },
                {
                    text = _("Latest bookmark"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        local _, idx = bookmark:getLatestBookmark()
                        idx = is_reverse_sorting and idx or #item_table - idx + 1
                        bm_menu:switchItemTable(nil, item_table, idx)
                        bm_menu:onMenuHold(item_table[idx])
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Select bookmarks"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        bm_menu:toggleSelectMode()
                    end,
                },
                {
                    text = _("Search bookmarks"),
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(bm_dialog)
                        bookmark:onSearchBookmark(bm_menu)
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
        bm_menu:toggleSelectMode()
        return true
    end

    bm_menu.close_callback = function()
        UIManager:close(self.bookmark_menu)
    end

    self.refresh = function()
        bm_menu:updateItems()
        self:onSaveSettings()
    end

    bm_menu:switchItemTable(nil, item_table, curr_page_index_filtered)
    UIManager:show(self.bookmark_menu)
    return true
end

function ReaderBookmark:isBookmarkMatch(item, pn_or_xp)
    if self.ui.paging then
        return item.page == pn_or_xp
    else
        return self.ui.document:getPageFromXPointer(item.page) == self.ui.document:getPageFromXPointer(pn_or_xp)
    end
end

function ReaderBookmark:getDogearBookmarkIndex(pn_or_xp)
    local _middle
    local _start, _end = 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        local v = self.bookmarks[_middle]
        if not v.highlighted and self:isBookmarkMatch(v, pn_or_xp) then
            return _middle
        elseif self:isBookmarkInPageOrder({page = pn_or_xp}, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
end

function ReaderBookmark:isBookmarkSame(item1, item2)
    if item1.notes ~= item2.notes then return false end
    if self.ui.paging then
        return item1.pos0 and item1.pos1 and item2.pos0 and item2.pos1
        and item1.pos0.page == item2.pos0.page
        and item1.pos0.x == item2.pos0.x and item1.pos0.y == item2.pos0.y
        and item1.pos1.x == item2.pos1.x and item1.pos1.y == item2.pos1.y
    else
        return item1.page == item2.page
        and item1.pos0 == item2.pos0 and item1.pos1 == item2.pos1
    end
end

function ReaderBookmark:getBookmarkIndexFullScan(item)
    for i, v in ipairs(self.bookmarks) do
        if item.datetime == v.datetime then
            return i
        end
    end
end

function ReaderBookmark:getBookmarkIndexBinarySearch(item)
    local _start, _end, _middle = 1, #self.bookmarks
    while _start <= _end do
        _middle = bit.rshift(_start + _end, 1)
        local v = self.bookmarks[_middle]
        if item.datetime == v.datetime and item.page == v.page then
            return _middle
        elseif self:isBookmarkInPositionOrder(item, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
end

function ReaderBookmark:getBookmarkInsertionIndexBinary(item)
    local _start, _end, _middle, direction = 1, #self.bookmarks, 1, 0
    while _start <= _end do
        _middle = bit.rshift(_start + _end, 1)
        if self:isBookmarkInPositionOrder(item, self.bookmarks[_middle]) then
            _end, direction = _middle - 1, 0
        else
            _start, direction = _middle + 1, 1
        end
    end
    return _middle + direction
end

function ReaderBookmark:addBookmark(item)
    local index = self:getBookmarkInsertionIndexBinary(item)
    table.insert(self.bookmarks, index, item)
    self.ui:handleEvent(Event:new("BookmarkAdded", item))
    self.view.footer:onUpdateFooter(self.view.footer_visible)
end

function ReaderBookmark:isBookmarkAdded(item)
    -- binary search of sorted bookmarks (without check of datetime, for dictquicklookup)
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
    else -- dogear bookmark, update it in case we removed a bookmark for current page
        self:removeBookmark(item)
        self:setDogearVisibility(self:getCurrentPageNumber())
    end
end

function ReaderBookmark:removeBookmark(item, reset_auto_text_only)
    -- If we haven't found item in binary search, it may be because there are multiple
    -- bookmarks on the same page, and the above binary search decided to
    -- not search on one side of one it found on page, where item could be.
    -- Fallback to do a full scan.
    local index = self:getBookmarkIndexBinarySearch(item) or self:getBookmarkIndexFullScan(item)
    local bookmark = self.bookmarks[index]
    if reset_auto_text_only then
        if self:isBookmarkAutoText(bookmark) then
            bookmark.text = nil
        end
    else
        local bookmark_type = item.type or self:getBookmarkType(bookmark)
        if bookmark_type == "highlight" then
            self.ui:handleEvent(Event:new("DelHighlight"))
        elseif bookmark_type == "note" then
            self.ui:handleEvent(Event:new("DelNote"))
        end
        self.ui:handleEvent(Event:new("BookmarkRemoved", bookmark))
        table.remove(self.bookmarks, index)
        self.view.footer:onUpdateFooter(self.view.footer_visible)
    end
end

function ReaderBookmark:updateBookmark(item)
    -- Called from Highlights when changing highlight boundaries (positions).
    -- Binary search cannot be used.
    local index = self:getBookmarkIndexFullScan(item)
    local v = self.bookmarks[index]
    local bookmark_before = util.tableDeepCopy(v)
    local is_auto_text_before = self:isBookmarkAutoText(v)
    v.page = item.updated_highlight.pos0
    v.pos0 = item.updated_highlight.pos0
    v.pos1 = item.updated_highlight.pos1
    v.notes = item.updated_highlight.text
    v.datetime = item.updated_highlight.datetime
    v.chapter = item.updated_highlight.chapter
    if is_auto_text_before then
        v.text = self:getBookmarkAutoText(v)
    end
    self.ui:handleEvent(Event:new("BookmarkUpdated", v, bookmark_before))
    self:onSaveSettings()
end

function ReaderBookmark._getDialogHeader(bookmark)
    return T(_("Page: %1"), bookmark.mandatory) .. "     " .. T(_("Time: %1"), bookmark.datetime)
end

function ReaderBookmark:setBookmarkNote(item, from_highlight, is_new_note, new_text)
    local bookmark
    if from_highlight then
        local bm = self.bookmarks[self:getBookmarkIndexFullScan(item)]
        if bm.text == nil or bm.text == "" then
            bm.text = self:getBookmarkAutoText(bm)
        end
        bookmark = util.tableDeepCopy(bm)
        bookmark.type = self:getBookmarkType(bookmark)
        bookmark.text_orig = bm.text or bm.notes
        bookmark.mandatory = self:getBookmarkPageString(bm.page)
    else
        bookmark = item
    end
    local input_text = self:getBookmarkNote(bookmark) and bookmark.text_orig or nil
    if new_text then
        if input_text then
            input_text = input_text .. "\n\n" .. new_text
        else
            input_text = new_text
        end
    end
    self.input = InputDialog:new{
        title = _("Edit note"),
        description = "   " .. self._getDialogHeader(bookmark),
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
                        UIManager:close(self.input)
                        if is_new_note then -- "Add note" cancelled, remove saved highlight
                            local index = self:getBookmarkIndexBinarySearch(bookmark) or self:getBookmarkIndexFullScan(bookmark)
                            self:removeHighlight(self.bookmarks[index])
                        end
                    end,
                },
                {
                    text = _("Paste"), -- insert highlighted text (auto-text)
                    callback = function()
                        self.input._input_widget:addChars(bookmark.text_orig)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value = self.input:getInputText()
                        if value == "" then -- blank input resets the 'text' field to auto-text
                            value = self:getBookmarkAutoText(bookmark)
                        end
                        bookmark.text = value or bookmark.notes
                        local bookmark_type = bookmark.type
                        bookmark.type = self:getBookmarkType(bookmark)
                        if bookmark_type ~= bookmark.type then
                            if bookmark_type == "highlight" then
                                self.ui:handleEvent(Event:new("DelHighlight"))
                                self.ui:handleEvent(Event:new("AddNote"))
                            else
                                self.ui:handleEvent(Event:new("AddHighlight"))
                                self.ui:handleEvent(Event:new("DelNote"))
                            end
                        end
                        local index = self:getBookmarkIndexBinarySearch(bookmark) or self:getBookmarkIndexFullScan(bookmark)
                        local bm = self.bookmarks[index]
                        bm.text = value
                        self.ui:handleEvent(Event:new("BookmarkEdited", bm))
                        if bookmark.highlighted then
                            self.ui.highlight:writePdfAnnotation("content", bookmark.page, bookmark, bookmark.text)
                        end
                        UIManager:close(self.input)
                        if from_highlight then
                            if self.view.highlight.note_mark then
                                UIManager:setDirty(self.dialog, "ui") -- refresh note marker
                            end
                        else
                            bookmark.text_orig = bookmark.text
                            bookmark.text = self.display_prefix[bookmark.type] .. bookmark.text
                            self.refresh()
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

function ReaderBookmark:editHighlightedText(item)
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Edit highlighted text"),
        description = "   " .. self._getDialogHeader(item),
        input = item.notes,
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
                        self:setHighlightedText(item, input_dialog:getInputText())
                        UIManager:close(input_dialog)
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:setHighlightedText(item, text)
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
    -- highlight
    local hl = self.ui.highlight:getHighlightByDatetime(item.datetime)
    hl.text = text
    hl.edited = edited
    -- bookmark
    local index = self:getBookmarkIndexBinarySearch(item) or self:getBookmarkIndexFullScan(item)
    local bm = self.bookmarks[index]
    local is_auto_text_before = self:isBookmarkAutoText(bm)
    bm.notes = text
    if is_auto_text_before then
        bm.text = self:getBookmarkAutoText(bm)
    end
    bm.edited = edited
    -- item table
    item.notes = text
    item.text_orig = bm.text or text
    item.text = self.display_prefix[item.type] .. item.text_orig
    item.edited = edited
    if edited then
        self.refresh()
    end
end

function ReaderBookmark:onSearchBookmark(bm_menu)
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
                        local match_table = {
                            search_str = search_str,
                            bookmark = check_button_bookmark.checked,
                            highlight = check_button_highlight.checked,
                            note = check_button_note.checked,
                            case_sensitive = check_button_case.checked,
                        }
                        UIManager:close(input_dialog)
                        if bm_menu then -- from bookmark list
                            for i = #bm_menu.item_table, 1, -1 do
                                if not self:doesBookmarkMatchTable(bm_menu.item_table[i], match_table) then
                                    table.remove(bm_menu.item_table, i)
                                end
                            end
                            bm_menu:switchItemTable(_("Bookmarks (search results)"), bm_menu.item_table)
                            self.filtered_mode = true
                        else -- from main menu
                            self:onShowBookmark(match_table)
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
        text = " " .. self.display_prefix["highlight"] .. _("highlights"),
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_highlight)
    check_button_note = CheckButton:new{
        text = " " .. self.display_prefix["note"] .. _("notes"),
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_note)
    check_button_bookmark = CheckButton:new{
        text = " " .. self.display_prefix["bookmark"] .. _("page bookmarks"),
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_bookmark)

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:filterByEditedText(bm_menu)
    self.show_edited_only = true
    for i = #bm_menu.item_table, 1, -1 do
        if not bm_menu.item_table[i].edited then
            table.remove(bm_menu.item_table, i)
        end
    end
    bm_menu:switchItemTable(_("Bookmarks (edited)"), bm_menu.item_table)
end

function ReaderBookmark:filterByHighlightStyle(bm_dialog, bm_menu)
    local filter_by_drawer = function(drawer)
        UIManager:close(bm_dialog)
        for i = #bm_menu.item_table, 1, -1 do
            if not self:doesBookmarkMatchTable(bm_menu.item_table[i], {drawer = drawer}) then
                table.remove(bm_menu.item_table, i)
            end
        end
        bm_menu:switchItemTable(_("Bookmarks (filtered)"), bm_menu.item_table)
    end
    self.ui.highlight:showHighlightStyleDialog(filter_by_drawer)
end

function ReaderBookmark:doesBookmarkMatchTable(item, match_table)
    if match_table.drawer then -- filter by highlight style
        return item.highlighted
            and match_table.drawer == self.ui.highlight:getHighlightByDatetime(item.datetime).drawer
    end
    if match_table[item.type] then
        if match_table.search_str then
            local text = item.notes
            if item.text then -- search in the highlighted text and in the note
                text = text .. "\u{FFFF}" .. item.text
            end
            if not match_table.case_sensitive then
                text = Utf8Proc.lowercase(util.fixUtf8(text, "?"))
            end
            return text:find(match_table.search_str)
        end
        return true
    end
end

function ReaderBookmark:toggleBookmark(pageno)
    local pn_or_xp
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
        self.ui:handleEvent(Event:new("BookmarkRemoved", self.bookmarks[index]))
        table.remove(self.bookmarks, index)
    else
        -- build notes from TOC
        local notes = self.ui.toc:getTocTitleByPage(pn_or_xp)
        local chapter_name = notes
        if notes ~= "" then
            -- @translators In which chapter title (%1) a note is found.
            notes = T(_("in %1"), notes)
        end
        self:addBookmark({
            page = pn_or_xp,
            datetime = os.date("%Y-%m-%d %H:%M:%S"),
            notes = notes,
            chapter = chapter_name,
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

function ReaderBookmark:getFirstBookmarkedPageFromPage(pn_or_xp)
    if #self.bookmarks > 0 then
        local first = #self.bookmarks
        if self:isBookmarkPageInPageOrder(pn_or_xp, self.bookmarks[first]) then
            return self.bookmarks[first].page
        end
    end
end

function ReaderBookmark:getLastBookmarkedPageFromPage(pn_or_xp)
    if #self.bookmarks > 0 then
        local last = 1
        if self:isBookmarkPageInReversePageOrder(pn_or_xp, self.bookmarks[last]) then
            return self.bookmarks[last].page
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

function ReaderBookmark:onGotoNextBookmarkFromPage(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    self:gotoBookmark(self:getNextBookmarkedPageFromPage(self.ui:getCurrentPage()))
    return true
end

function ReaderBookmark:onGotoPreviousBookmarkFromPage(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    self:gotoBookmark(self:getPreviousBookmarkedPageFromPage(self.ui:getCurrentPage()))
    return true
end

function ReaderBookmark:onGotoFirstBookmark(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    self:gotoBookmark(self:getFirstBookmarkedPageFromPage(self.ui:getCurrentPage()))
    return true
end

function ReaderBookmark:onGotoLastBookmark(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    self:gotoBookmark(self:getLastBookmarkedPageFromPage(self.ui:getCurrentPage()))
    return true
end

function ReaderBookmark:getLatestBookmark()
    local latest_bookmark, latest_bookmark_idx
    local latest_bookmark_datetime = "0"
    for i, v in ipairs(self.bookmarks) do
        if v.datetime > latest_bookmark_datetime then
            latest_bookmark_datetime = v.datetime
            latest_bookmark = v
            latest_bookmark_idx = i
        end
    end
    return latest_bookmark, latest_bookmark_idx
end

function ReaderBookmark:hasBookmarks()
    return self.bookmarks and #self.bookmarks > 0
end

function ReaderBookmark:getNumberOfBookmarks()
    return self.bookmarks and #self.bookmarks or 0
end

function ReaderBookmark:getNumberOfHighlightsAndNotes() -- for Statistics plugin
    local highlights = 0
    local notes = 0
    for _, v in ipairs(self.bookmarks) do
        local bm_type = self:getBookmarkType(v)
        if bm_type == "highlight" then
            highlights = highlights + 1
        elseif bm_type == "note" then
            notes = notes + 1
        end
    end
    return highlights, notes
end

function ReaderBookmark:getCurrentPageNumber()
    return self.ui.paging and self.view.state.page or self.ui.document:getXPointer()
end

function ReaderBookmark:getBookmarkPageNumber(bookmark)
    return self.ui.paging and bookmark.page or self.ui.document:getPageFromXPointer(bookmark.page)
end

function ReaderBookmark:getBookmarkType(bookmark)
    if bookmark.highlighted then
        if self:isBookmarkAutoText(bookmark) then
            return "highlight"
        else
            return "note"
        end
    else
        return "bookmark"
    end
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

function ReaderBookmark:getBookmarkedPages()
    local pages = {}
    for _, bm in ipairs(self.bookmarks) do
        local page = self:getBookmarkPageNumber(bm)
        local btype = self:getBookmarkType(bm)
        if not pages[page] then
            pages[page] = {}
        end
        if not pages[page][btype] then
            pages[page][btype] = true
        end
    end
    return pages
end

function ReaderBookmark:getBookmarkAutoText(bookmark, force_auto_text)
    if G_reader_settings:nilOrTrue("bookmarks_items_auto_text") or force_auto_text then
        local page = self:getBookmarkPageString(bookmark.page)
        return T(_("Page %1 %2 @ %3"), page, bookmark.notes, bookmark.datetime)
    else
        -- When not auto_text, and 'text' would be identical to 'notes', leave 'text' be nil
        return nil
    end
end

--- Check if the 'text' field has not been edited manually
function ReaderBookmark:isBookmarkAutoText(bookmark)
    return (bookmark.text == nil) or (bookmark.text == "") or (bookmark.text == bookmark.notes)
        or (bookmark.text == self:getBookmarkAutoText(bookmark, true))
end

function ReaderBookmark:getBookmarkNote(item)
    for _, bm in ipairs(self.bookmarks) do
        if item.datetime == bm.datetime then
            return not self:isBookmarkAutoText(bm) and bm.text
        end
    end
end

function ReaderBookmark:getBookmarkForHighlight(item)
    return self.bookmarks[self:getBookmarkIndexFullScan(item)]
end

return ReaderBookmark
