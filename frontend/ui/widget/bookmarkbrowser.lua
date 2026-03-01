local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local PathChooser = require("ui/widget/pathchooser")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local T = ffiUtil.template

local BookmarkBrowser = WidgetContainer:extend{
    display_prefix = ReaderBookmark.display_prefix,
    display_type = ReaderBookmark.display_type,
    separator = " • ",
    checkmark = "\u{2713}",
}

function BookmarkBrowser:show(files, ui)
    self.ui = ui or self.ui

    self.items_per_page = G_reader_settings:readSetting("bookmarks_items_per_page")
        or G_reader_settings:readSetting("items_per_page") or Menu.items_per_page_default
    self.items_font_size = G_reader_settings:readSetting("bookmarks_items_font_size")
        or G_reader_settings:readSetting("items_font_size") or Menu.getItemFontSize(self.items_per_page)
    self.items_max_lines = G_reader_settings:readSetting("bookmarks_items_max_lines")
    self.multilines_show_more_text = G_reader_settings:isTrue("bookmarks_items_multilines_show_more_text")
    self.line_color = G_reader_settings:isTrue("bookmarks_items_show_separator")
        and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_WHITE
    self.items_text = G_reader_settings:readSetting("bookmarks_items_text_type") or "note"
    self.sorting_mode = G_reader_settings:readSetting("bookmarks_items_sorting") or "page"
    self.is_reverse_sorting = G_reader_settings:isTrue("bookmarks_items_reverse_sorting")
    self.highlight_color_default = G_reader_settings:readSetting("highlight_color")
        or (Screen:isColorEnabled() and "yellow" or "gray")
    self.bookmarks_items_show_color = G_reader_settings:isTrue("bookmarks_items_show_color")
    self.bookmarks_items_color_default = G_reader_settings:isTrue("bookmarks_items_show_color_default")
        and ReaderHighlight:getHighlightColor(self.highlight_color_default) or nil

    self.books = self:getBookList(files)
    self.filter_table = { enabled_books_nb = #self.books }
    self.bm_list = Menu:new{
        subtitle = "",
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        items_per_page = self.items_per_page,
        items_font_size = self.items_font_size,
        items_max_lines = self.items_max_lines,
        multilines_show_more_text = self.multilines_show_more_text,
        line_color = self.line_color,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:showBookmarkListMenu()
        end,
        onMenuSelect = function(self_menu, item)
            if item.file then
                self:showBookDialog(item)
            else
                self:showBookmarkDetails(item)
            end
        end,
        search_callback = function(search_string)
            self:showSearchDialog(search_string)
        end,
        close_callback = function()
            self.books = nil
            self.filter_table = nil
            self.bm_list = nil
            UIManager:scheduleIn(0.5, function()
                collectgarbage()
                collectgarbage()
            end)
        end,
    }
    self:updateBookmarkList()
    UIManager:show(self.bm_list)
end

function BookmarkBrowser:updateBookmarkList(item_number)
    local item_table, title, subtitle
    if item_number == nil then
        item_table = self:getItemTable()
        title = T(_("Books: %1"), self.visible_books_nb) .. self.separator ..
                T(_("Bookmarks: %1"), #item_table - self.visible_books_nb)
        if self.filters_nb > 0 then
            if self.filters_nb > 1 then
                subtitle = T(_("Filters: %1"), self.filters_nb)
            else -- single filter
                if self.filter_table.enabled_books_nb < #self.books then
                    subtitle = _("Filtered by book")
                elseif self.filter_table.search_string then
                    subtitle = T(_("Query: %1"), self.filter_table.search_string)
                elseif self.filter_table.type then
                    subtitle = T(_("Type: %1"), self.display_type[self.filter_table.type])
                elseif self.filter_table.style then
                    subtitle = T(_("Style: %1"), ReaderHighlight:getHighlightStyleString(self.filter_table.style))
                elseif self.filter_table.color then
                    subtitle = T(_("Color: %1"), ReaderHighlight:getHighlightColorString(self.filter_table.color))
                end
            end
        else
            subtitle = ""
        end
    end
    self.bm_list:switchItemTable(title, item_table, item_number, nil, subtitle)
end

function BookmarkBrowser:getBookList(files)
    -- builds list of books that have been opened, have doc_props, have annotations
    -- sorted by combined title "Authors • Title"
    local current_file = self.ui.document and self.ui.document.file
    local books = {}
    for file in pairs(files) do
        local is_current_file = file == current_file or nil
        local doc_settings, doc_props, annotations
        if is_current_file then
            doc_settings = self.ui.doc_settings
            doc_props = self.ui.doc_props
            annotations = self.ui.annotation.annotations
        else
            doc_settings = BookList.hasBookBeenOpened(file) and BookList.getDocSettings(file)
            if doc_settings then
                doc_props = doc_settings:readSetting("doc_props")
                annotations = doc_settings:readSetting("annotations")
            end
        end
        if annotations and #annotations > 0 then
            if not is_current_file then
                doc_props = self.ui.bookinfo.extendProps(doc_props, file)
            end
            doc_props.has_cover = true -- enable "Book cover" button in the book dialog
            local authors = doc_props.authors and doc_props.authors:gsub("\n.*", " et al.") or _("Unknown author")
            table.insert(books, {
                enabled = true, -- start with showing all books from the source
                file = file,
                is_current_file = is_current_file,
                doc_settings = doc_settings,
                doc_props = doc_props,
                annotations = annotations,
                authors = authors,
                sort_string = util.stringLower(authors .. doc_props.display_title),
                -- will be filled when building item table
                item_table_idx = nil,
                bookmarks_nb = nil,
            })
        end
    end
    if #books > 1 then
        table.sort(books, function(a, b) return ffiUtil.strcoll(a.sort_string, b.sort_string) end)
    end
    return books
end

function BookmarkBrowser:getFiltersNumber()
    return (self.filter_table.enabled_books_nb < #self.books and 1 or 0)
         + (self.filter_table.search_string and 1 or 0)
         + (self.filter_table.type and 1 or 0)
         + (self.filter_table.style and 1 or 0)
         + (self.filter_table.color and 1 or 0)
end

function BookmarkBrowser:getItemTable()
    local date_sort_func
    if self.sorting_mode == "date" then
        date_sort_func = self.is_reverse_sorting and function(a, b) return a.datetime > b.datetime end
                                                  or function(a, b) return a.datetime < b.datetime end
    end
    self.filters_nb = self:getFiltersNumber()
    local no_filter = self.filters_nb == 0
    self.visible_books_nb = 0 -- may differ from the enabled books number due to bookmarks filtering
    local item_table = {}
    for __, book in ipairs(self.books) do
        if book.enabled then
            local book_item_table_idx = #item_table + 1
            local bookmark_idx = 0
            local annotations_nb = #book.annotations
            local num = annotations_nb + 1
            local book_item_table = {}
            for i = 1, annotations_nb do
                local a = book.annotations[self.is_reverse_sorting and num - i or i]
                local a_type = ReaderBookmark.getBookmarkType(a)
                if no_filter or self:doesBookmarkMatch(a, a_type) then
                    bookmark_idx = bookmark_idx + 1
                    local text_bgcolor
                    if self.bookmarks_items_show_color and a.drawer then
                        if a.color == nil or a.color == self.highlight_color_default then
                            text_bgcolor = self.bookmarks_items_color_default
                        else
                            text_bgcolor = ReaderHighlight:getHighlightColor(a.color)
                        end
                    end
                    local item = { -- boookmark entry
                        datetime     = a.datetime,
                        drawer       = a.drawer,
                        color        = a.color,
                        text_edited  = a.edited,
                        note         = a.note,
                        chapter      = a.chapter,
                        page         = a.page,
                        pos0         = a.pos0,
                        text_orig    = a.text or "",
                        type         = a_type,
                        mandatory    = a.pageref or a.pageno,
                        text_bgcolor = text_bgcolor,
                        bookmark_idx = bookmark_idx,
                        book_idx     = book_item_table_idx,
                    }
                    item.text = ReaderBookmark.getBookmarkItemText(self, item)
                    table.insert(book_item_table, item)
                end
            end
            annotations_nb = #book_item_table
            book.bookmarks_nb = annotations_nb
            if annotations_nb > 0 then
                book.item_table_idx = book_item_table_idx
                self.visible_books_nb = self.visible_books_nb + 1
                table.insert(item_table, { -- book entry
                    text = T(_("%1 • %2"), book.authors, book.doc_props.display_title),
                    bold = true,
                    mandatory = "(" .. annotations_nb .. ")",
                    file = book.file,
                    is_current_file = book.is_current_file,
                    doc_props = book.doc_props,
                    doc_settings = book.doc_settings,
                    authors = book.authors,
                    bookmarks_nb = annotations_nb,
                })
                if date_sort_func and annotations_nb > 1 then
                    table.sort(book_item_table, date_sort_func)
                end
                table.move(book_item_table, 1, annotations_nb, #item_table + 1, item_table)
            end
        end
    end
    return item_table
end

function BookmarkBrowser:doesBookmarkMatch(a, a_type)
    if self.filter_table.type and self.filter_table.type ~= a_type then return end
    if self.filter_table.style and self.filter_table.style ~= a.drawer then return end
    if self.filter_table.color and self.filter_table.color ~= a.color then return end
    if self.filter_table.search_string then
        local text = a.text or ""
        if a.note then
            text = text .. "\u{FFFF}" .. a.note
        end
        if util.stringSearch(text, self.filter_table.search_string, self.filter_table.search_case_sensitive) == 0 then
            return
        end
    end
    return true
end

function BookmarkBrowser:showBookDialog(item)
    local file = item.file
    local book_dialog
    local function close_dialog_callback()
        UIManager:close(book_dialog)
    end
    local buttons = {
        {
            {
                text = _("Open"),
                callback = function()
                    UIManager:close(book_dialog)
                    self.bm_list:onClose()
                    if self.ui.document then
                        if not item.is_current_file then
                            self.ui:switchDocument(file)
                        end
                    else
                        self.ui:openFile(file)
                    end
                end,
            },
            filemanagerutil.genBookInformationButton(item.doc_settings, item.doc_props, close_dialog_callback),
        },
        {
            filemanagerutil.genBookCoverButton(file, item.doc_props, close_dialog_callback),
            filemanagerutil.genBookDescriptionButton(file, item.doc_props, close_dialog_callback),
        },
        {}, -- separator
        {
            self:genShowBookListButton(close_dialog_callback),
        },
    }
    book_dialog = ButtonDialog:new{
        title = item.authors .. "\n" .. item.doc_props.display_title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(book_dialog)
end

function BookmarkBrowser:showBookmarkDetails(item)
    local item_table = self.bm_list.item_table
    local items_nb = #item_table
    local book = item_table[item.book_idx]

    local bm_info = {
        BD.ltr(item.datetime),
        T(_("Page %1"), item.mandatory),
        item.drawer and ReaderHighlight:getHighlightStyleString(item.drawer),
        item.color and ReaderHighlight:getHighlightColorString(item.color),
    }
    local bm_text_prefix = item.type == "bookmark" and self.display_prefix["bookmark"] or self.display_prefix["highlight"]
    local text = {
        T(_("%1: %2"), TextBoxWidget.PTF_BOLD_START.._("Title")..TextBoxWidget.PTF_BOLD_END, book.doc_props.display_title),
        T(_("%1: %2"), TextBoxWidget.PTF_BOLD_START.._("Author(s)")..TextBoxWidget.PTF_BOLD_END, book.authors),
        T(_("%1: %2"), TextBoxWidget.PTF_BOLD_START.._("Chapter")..TextBoxWidget.PTF_BOLD_END, item.chapter or ""),
        "",
        table.concat(bm_info, self.separator),
        "",
        bm_text_prefix .. (item.text_orig or item.text),
        "",
        item.note and self.display_prefix["note"] .. item.note,
    }

    local textviewer
    local function _showBookmarkDetails(idx)
        UIManager:close(textviewer)
        self:updateBookmarkList(idx)
        self:showBookmarkDetails(item_table[idx])
    end

    local label_first, label_last = "▕◁", "▷▏"
    local label_prev, label_next = "◁", "▷"
    if BD.mirroredUILayout() then
        label_first, label_last = BD.ltr(label_last), BD.ltr(label_first)
        label_prev, label_next = label_next, label_prev
    end
    local buttons_table = {
        {
            {
                text = label_first,
                enabled = item.idx > 2,
                callback = function()
                    _showBookmarkDetails(2)
                end,
            },
            {
                text = label_prev,
                enabled = item.idx > 2,
                callback = function()
                    local idx = item.idx - 1
                    if item_table[idx].file then -- book
                        idx = idx - 1
                    end
                    _showBookmarkDetails(idx)
                end,
            },
            {
                text = label_next,
                enabled = item.idx < items_nb,
                callback = function()
                    local idx = item.idx + 1
                    if item_table[idx].file then -- book
                        idx = idx + 1
                    end
                    _showBookmarkDetails(idx)
                end,
            },
            {
                text = label_last,
                enabled = item.idx < items_nb,
                callback = function()
                    _showBookmarkDetails(items_nb)
                end,
            },
        },
        {
            {
                text = _("View in book"),
                callback = function()
                    textviewer:onClose()
                    self.bm_list:onClose()
                    local after_open_callback = function(ui)
                        ui.link:addCurrentLocationToStack()
                        ui.bookmark:gotoBookmark(item.page, item.pos0)
                    end
                    if self.ui.document then
                        if book.is_current_file then
                            after_open_callback(self.ui)
                        else
                            self.ui:switchDocument(book.file, nil, after_open_callback)
                        end
                    else
                        self.ui:openFile(book.file, nil, nil, nil, after_open_callback)
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
        title = T(_("%1 / %2"), item.bookmark_idx, book.bookmarks_nb),
        text = TextBoxWidget.PTF_HEADER .. table.concat(text, "\n"),
        text_type = "bookmark",
        buttons_table = buttons_table,
    }
    UIManager:show(textviewer)
end

function BookmarkBrowser:showBookmarkListMenu()
    local are_disabled_books = self.filter_table.enabled_books_nb < #self.books
    local bm_list_menu
    local function close_dialog_callback()
        UIManager:close(bm_list_menu)
    end
    local buttons = {
        {
            {
                text = are_disabled_books
                    and T(_("Books: %1 / %2"), self.filter_table.enabled_books_nb, #self.books) or _("Books"),
                enabled = #self.books > 1,
                callback = function()
                    UIManager:close(bm_list_menu)
                    self:showBookList(true)
                end,
                hold_callback = function()
                    if are_disabled_books then
                        UIManager:close(bm_list_menu)
                        for _, book in ipairs(self.books) do
                            book.enabled = true
                        end
                        self.filter_table.enabled_books_nb = #self.books
                        self:updateBookmarkList()
                    end
                end,
            },
            {
                text = self.filter_table.style
                    and T(_("Style: %1"), ReaderHighlight:getHighlightStyleString(self.filter_table.style)) or _("Style"),
                callback = function()
                    UIManager:close(bm_list_menu)
                    local caller_callback = function(style)
                        self.filter_table.style = style
                        self:updateBookmarkList()
                    end
                    ReaderHighlight:showHighlightStyleDialog(caller_callback, self.filter_table.style)
                end,
                hold_callback = function()
                    if self.filter_table.style then
                        UIManager:close(bm_list_menu)
                        self.filter_table.style = nil
                        self:updateBookmarkList()
                    end
                end,
            },
        },
        {
            {
                text = self.filter_table.type
                    and T(_("Type: %1"), self.display_type[self.filter_table.type]) or _("Type"),
                callback = function()
                    UIManager:close(bm_list_menu)
                    local caller_callback = function(bm_type)
                        self.filter_table.type = bm_type
                        self:updateBookmarkList()
                    end
                    self:showBookmarkTypeDialog(caller_callback, self.filter_table.type)
                end,
                hold_callback = function()
                    if self.filter_table.type then
                        UIManager:close(bm_list_menu)
                        self.filter_table.type = nil
                        self:updateBookmarkList()
                    end
                end,
            },
            {
                text = self.filter_table.color
                    and T(_("Color: %1"), ReaderHighlight:getHighlightColorString(self.filter_table.color)) or _("Color"),
                callback = function()
                    UIManager:close(bm_list_menu)
                    local caller_callback = function(color)
                        self.filter_table.color = color
                        self:updateBookmarkList()
                    end
                    ReaderHighlight:showHighlightColorDialog(caller_callback, self.filter_table.color)
                end,
                hold_callback = function()
                    if self.filter_table.color then
                        UIManager:close(bm_list_menu)
                        self.filter_table.color = nil
                        self:updateBookmarkList()
                    end
                end,
            },
        },
        {
            {
                text = self.filter_table.search_string
                    and T(_("Search: %1"), self.filter_table.search_string) or _("Search"),
                callback = function()
                    UIManager:close(bm_list_menu)
                    self:showSearchDialog()
                end,
                hold_callback = function()
                    if self.filter_table.search_string then
                        UIManager:close(bm_list_menu)
                        self.filter_table.search_string = nil
                        self.filter_table.search_case_sensitive = nil
                        self:updateBookmarkList()
                    end
                end,
            },
        },
        {
            {
                text = _("Reset all filters"),
                enabled = self.filters_nb > 0,
                callback = function()
                    UIManager:close(bm_list_menu)
                    if are_disabled_books then
                        for _, book in ipairs(self.books) do
                            book.enabled = true
                        end
                    end
                    self.filter_table = { enabled_books_nb = #self.books }
                    self:updateBookmarkList()
                end,
            },
        },
        {}, -- separator
        {
            self:genShowBookListButton(close_dialog_callback),
        },
    }
    bm_list_menu = ButtonDialog:new{
        title = _("Filters"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(bm_list_menu)
end

function BookmarkBrowser:showBookmarkTypeDialog(caller_callback, curr_type)
    local types = { "highlight", "note", "bookmark" }
    local type_dialog
    local buttons = {}
    for i, bm_type in ipairs(types) do
        local type_name = self.display_type[bm_type]
        buttons[i] = {{
            text = bm_type ~= curr_type and type_name or type_name .. "  " .. self.checkmark,
            menu_style = true,
            callback = function()
                if bm_type ~= curr_type then
                    caller_callback(bm_type)
                end
                UIManager:close(type_dialog)
            end,
        }}
    end
    type_dialog = ButtonDialog:new{
        width_factor = 0.4,
        buttons = buttons,
    }
    UIManager:show(type_dialog)
end

function BookmarkBrowser:showBookList(multi_choice)
    local book_list, subtitle, onMenuSelect, title_bar_left_icon, onLeftButtonTap
    local getSubTitle = function(books_nb)
        return T(_("Enabled books: %1"), books_nb)
    end
    local updateBookList = function(books_nb)
        book_list.title_bar:setSubTitle(getSubTitle(books_nb), true)
        book_list:updateItems(1, true)
    end
    local item_table = {}
    if multi_choice then
        subtitle = getSubTitle(self.filter_table.enabled_books_nb)
        local books_enabled = { books_nb = self.filter_table.enabled_books_nb }
        for i, book in ipairs(self.books) do
            books_enabled[i] = book.enabled
            item_table[i] = {
                text = T(_("%1 • %2"), book.authors, book.doc_props.display_title),
                bold = book.is_current_file,
                mandatory = book.enabled and self.checkmark,
            }
        end
        onMenuSelect = function(self_menu, item) -- toggle book selection
            local idx = item.idx
            books_enabled[idx] = not books_enabled[idx] or nil
            books_enabled.books_nb = books_enabled.books_nb + (books_enabled[idx] and 1 or -1)
            item_table[idx].mandatory = books_enabled[idx] and self.checkmark
            updateBookList(books_enabled.books_nb)
        end
        title_bar_left_icon = "check"
        onLeftButtonTap = function()
            self:showBookListMenu(book_list, books_enabled)
        end
    else
        for _, book in ipairs(self.books) do
            if book.enabled and book.bookmarks_nb > 0 then
                local item = self.bm_list.item_table[book.item_table_idx]
                table.insert(item_table, {
                    text = item.text,
                    bold = book.is_current_file,
                    mandatory = item.mandatory,
                    item_table_idx = book.item_table_idx,
                })
            end
        end
        onMenuSelect = function(self_menu, item) -- jump to the book in the bookmark list
            UIManager:close(book_list)
            self:updateBookmarkList(item.item_table_idx)
        end
    end

    book_list = BookList:new{
        title = T(_("Books: %1"), #item_table),
        subtitle = subtitle,
        item_table = item_table,
        items_per_page = self.items_per_page,
        items_font_size = self.items_font_size,
        multilines_show_more_text = self.multilines_show_more_text,
        line_color = self.line_color,
        title_bar_left_icon = title_bar_left_icon,
        onLeftButtonTap = onLeftButtonTap,
        onMenuSelect = onMenuSelect,
        updateBookList = updateBookList,
    }
    UIManager:show(book_list)
end

function BookmarkBrowser:showBookListMenu(book_list, books_enabled)
    local empty_prop = "\u{0000}" .. _("N/A") -- sorted first
    local book_list_menu
    local function deselectAll()
        for i, item in ipairs(book_list.item_table) do
            books_enabled[i] = nil
            books_enabled.books_nb = 0
            item.mandatory = nil
        end
    end
    local function selectBooksByProp(item_idxs)
        deselectAll()
        for _, idx in ipairs(item_idxs) do
            books_enabled[idx] = true
            book_list.item_table[idx].mandatory = self.checkmark
        end
        books_enabled.books_nb = #item_idxs
        book_list.updateBookList(books_enabled.books_nb)
    end
    local function genMetadataButton(button_text, button_prop)
        return {
            text = button_text,
            callback = function()
                UIManager:close(book_list_menu)
                local prop_values = {}
                for idx, book in ipairs(self.books) do
                    local doc_prop = book.doc_props[button_prop]
                    if doc_prop == nil then
                        doc_prop = { empty_prop }
                    elseif button_prop == "series" then
                        doc_prop = { doc_prop }
                    elseif button_prop == "language" then
                        doc_prop = { doc_prop:lower() }
                    else -- "authors", "keywords"
                        doc_prop = util.splitToArray(doc_prop, "\n")
                    end
                    for _, prop in ipairs(doc_prop) do
                        prop_values[prop] = prop_values[prop] or {}
                        table.insert(prop_values[prop], idx)
                    end
                end
                self:showPropValueList(button_prop, prop_values, selectBooksByProp)
            end,
        }
    end

    local buttons = {
        {
            genMetadataButton(_("Author(s)"), "authors"),
            genMetadataButton(_("Series"), "series"),
        },
        {
            genMetadataButton(_("Language"), "language"),
            genMetadataButton(_("Keywords"), "keywords"),
        },
        {}, -- separator
        {
            {
                text = _("Deselect all"),
                callback = function()
                    UIManager:close(book_list_menu)
                    deselectAll()
                    book_list.updateBookList(0)
                end,
            },
            {
                text = _("Select all"),
                callback = function()
                    UIManager:close(book_list_menu)
                    for i, item in ipairs(book_list.item_table) do
                        books_enabled[i] = true
                        item.mandatory = self.checkmark
                    end
                    books_enabled.books_nb = #self.books
                    book_list.updateBookList(books_enabled.books_nb)
                end,
            },
        },
        {}, -- separator
        {
            {
                text = _("Apply"),
                callback = function()
                    UIManager:close(book_list_menu)
                    UIManager:close(book_list)
                    local do_update
                    for i, book in ipairs(self.books) do
                        if book.enabled ~= books_enabled[i] then
                            book.enabled = books_enabled[i]
                            do_update = true
                        end
                    end
                    if do_update then
                        self.filter_table.enabled_books_nb = books_enabled.books_nb
                        self:updateBookmarkList()
                    end
                end,
            },
        },
    }
    book_list_menu = ButtonDialog:new{
        title = _("Filters"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(book_list_menu)
end

function BookmarkBrowser:showPropValueList(prop, prop_values, caller_callback)
    local prop_list
    local prop_item_table = {}
    for value, item_idxs in pairs(prop_values) do
        table.insert(prop_item_table, {
            text = value,
            mandatory = #item_idxs,
            callback = function()
                UIManager:close(prop_list)
                caller_callback(item_idxs)
            end,
        })
    end
    if #prop_item_table > 1 then
        table.sort(prop_item_table, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
    end
    prop_list = BookList:new{
        title = T(_("%1: %2"), self.ui.bookinfo.prop_text[prop]:sub(1, -2), #prop_item_table),
        item_table = prop_item_table,
    }
    UIManager:show(prop_list)
end

function BookmarkBrowser:genShowBookListButton(caller_callback)
    return {
        text = _("Book list"),
        enabled = self.visible_books_nb > 1,
        callback = function()
            caller_callback()
            self:showBookList()
        end,
    }
end

function BookmarkBrowser:showSearchDialog(search_string)
    local search_dialog, check_button_case
    search_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        input = search_string or self.filter_table.search_string,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    callback = function()
                        local str = search_dialog:getInputText()
                        if str ~= "" then
                            UIManager:close(search_dialog)
                            self.filter_table.search_string = str
                            self.filter_table.search_case_sensitive = check_button_case.checked
                            self:updateBookmarkList()
                        end
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.filter_table.search_case_sensitive,
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_case)
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
end

function BookmarkBrowser:showSourceDialog(ui)
    self.ui = ui
    local home_dir = G_reader_settings:readSetting("home_dir")
    local source_dialog
    local function fetch_and_show_bookmarks(fetch_func_or_folder, subfolders)
        UIManager:close(source_dialog)
        UIManager:show(InfoMessage:new{
            text = _("Fetching bookmarks…"),
            timeout = 0.1,
        })
        UIManager:nextTick(function()
            local books = {}
            if type(fetch_func_or_folder) == "function" then
                fetch_func_or_folder(books)
            else
                util.findFiles(fetch_func_or_folder, function(file)
                    books[file] = DocumentRegistry:hasProvider(file) or nil
                end, subfolders)
            end
            self:show(books)
        end)
    end
    local buttons = {
        {{
            text = _("History"),
            callback = function()
                fetch_and_show_bookmarks(function(books)
                    for _, v in ipairs(require("readhistory").hist) do
                        books[v.file] = v.select_enabled or nil
                    end
                end)
            end,
        }},
        {{
            text = _("Collections"),
            callback = function()
                local caller_callback = function(selected_collections)
                    fetch_and_show_bookmarks(function(books)
                        for coll_name in pairs(selected_collections) do
                            for file in pairs(require("readcollection").coll[coll_name]) do
                                books[file] = true
                            end
                        end
                    end)
                end
                self.ui.collections:onShowCollList({}, caller_callback, true)
            end,
        }},
        {{
            text = _("Selected files"),
            enabled = ui.selected_files ~= nil,
            callback = function()
                fetch_and_show_bookmarks(function(books)
                    for file in pairs(ui.selected_files) do
                        books[file] = true
                    end
                end)
            end,
        }},
        {{
            text = _("Home folder"),
            enabled = home_dir ~= nil,
            callback = function()
                fetch_and_show_bookmarks(home_dir, false)
            end,
        }},
        {{
            text = _("Home folder with subfolders"),
            enabled = home_dir ~= nil,
            callback = function()
                fetch_and_show_bookmarks(home_dir, true)
            end,
        }},
        {{
            text = _("Folder"),
            callback = function()
                UIManager:show(PathChooser:new{
                    select_file = false,
                    path = home_dir,
                    onConfirm = function(path)
                        fetch_and_show_bookmarks(path, false)
                    end,
                })
            end,
        }},
        {{
            text = _("Folder with subfolders"),
            callback = function()
                UIManager:show(PathChooser:new{
                    select_file = false,
                    path = home_dir,
                    onConfirm = function(path)
                        fetch_and_show_bookmarks(path, true)
                    end,
                })
            end,
        }},
    }
    source_dialog = ButtonDialog:new{
        title = _("Book source"),
        title_align = "center",
        width_factor = 0.8,
        buttons = buttons,
    }
    UIManager:show(source_dialog)
end

return BookmarkBrowser
