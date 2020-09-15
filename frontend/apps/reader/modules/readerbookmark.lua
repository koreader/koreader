local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
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
    search_value = "",
}

function ReaderBookmark:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ShowBookmark = {
                { "B" },
                doc = "show bookmarks" },
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
    if not Device:isTouchDevice() then
        menu_items.toggle_bookmark = {
            text_func = function() return self:isCurrentPageBookmarked() and _("Remove bookmark for current page") or _("Bookmark current page") end,
            callback = function()
                self:onToggleBookmark()
            end,
       }
    end
    if self.ui.document.info.has_pages then
        menu_items.bookmark_browsing_mode = {
            text = self.bbm_menu_title,
            checked_func = function() return self.ui.paging.bookmark_flipping_mode end,
            callback = function(touchmenu_instance)
                self:enableBookmarkBrowsingMode()
                touchmenu_instance:closeMenu()
            end,
        }
    end
end

function ReaderBookmark:search(query, bookmarks, current_bookmark, bm_menu, viewer_instance, direction, manual_search)
    -- handle empty queries:
    if query == "" then
        self.search_value = ""
        return
    end
    -- make sure query doesn't fail on special characters. Only applied for manually searched terms, not for searching previous or next hits with buttons:
    if manual_search then
        query = query:gsub("%.", "%."):gsub("%-", "%-"):gsub("%%", "%%")
    end
    self.search_value = query
    local content
    local found_index = 0
    local start
    local use_second_loop = true
    if direction == 1 then
        start = current_bookmark + 1
        if start > #bookmarks then
            start = 1
            use_second_loop = false
        end
        for i = start, #bookmarks do
            content = string.lower(bookmarks[i].notes)
            if content:match(query) then
                found_index = i
                break
            end
        end
        if use_second_loop and found_index == 0 then
            for i = 1, current_bookmark do
                content = string.lower(bookmarks[i].notes)
                if content:match(query) then
                    found_index = i
                    break
                end
            end
        end
    -- direction == -1:
    else
        start = current_bookmark - 1
        if start < 1 then
            start = #bookmarks
            use_second_loop = false
        end
        for i = start, 1, -1 do
            content = string.lower(bookmarks[i].notes)
            if content:match(query) then
                found_index = i
                break
            end
        end
        if use_second_loop and found_index == 0 then
            for i = #bookmarks, current_bookmark, -1 do
                content = string.lower(bookmarks[i].notes)
                if content:match(query) then
                    found_index = i
                    break
                end
            end
        end
    end

    if found_index > 0 then
        UIManager:close(viewer_instance)
        bm_menu:onMenuHold(bookmarks[found_index])
    else
        UIManager:show(InfoMessage:new { text = T(_('No bookmarks found with query "%1"'), query) })
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
        if a.page == b.page then -- have bookmarks before highlights
            return a.highlighted
        end
        return a.page > b.page
    else
        local a_page = self.ui.document:getPageFromXPointer(a.page)
        local b_page = self.ui.document:getPageFromXPointer(b.page)
        if a_page == b_page then -- have bookmarks before highlights
            return a.highlighted
        end
        return a_page > b_page
    end
end

function ReaderBookmark:isBookmarkInReversePageOrder(a, b)
    -- The way this is used (by getNextBookmarkedPage(), iterating bookmarks
    -- in reverse order), we want to skip highlights, but also the current
    -- page: so we do not do any "a.page == b.page" check (not even with
    -- a reverse logic than the one from above function).
    if self.ui.document.info.has_pages then
        return a.page < b.page
    else
        local a_page = self.ui.document:getPageFromXPointer(a.page)
        local b_page = self.ui.document:getPageFromXPointer(b.page)
        return a_page < b_page
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

function ReaderBookmark:isCurrentPageBookmarked()
    local pn_or_xp
    if self.ui.document.info.has_pages then
        pn_or_xp = self.view.state.page
    else
        pn_or_xp = self.ui.document:getXPointer()
    end
    return self:getDogearBookmarkIndex(pn_or_xp) and true or false
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

function ReaderBookmark:onPosUpdate()
    self:setDogearVisibility(self.ui.document:getXPointer())
end

function ReaderBookmark:gotoBookmark(pn_or_xp)
    if pn_or_xp then
        local event = self.ui.document.info.has_pages and "GotoPage" or "GotoXPointer"
        self.ui:handleEvent(Event:new(event, pn_or_xp))
    end
end

-- This function adds "chapter" property to highlights already saved in the document
function ReaderBookmark:updateHighlightsIfNeeded()
    local version = self.ui.doc_settings:readSetting("bookmarks_version") or 0
    if version >= 20200615 then
        return
    end

    for page, highlights in pairs(self.view.highlight.saved) do
        for _, highlight in pairs(highlights) do
            local pg_or_xp = self.ui.document.info.has_pages and
                    page or highlight.pos0
            local chapter_name = self.ui.toc:getTocTitleByPage(pg_or_xp)
            highlight.chapter = chapter_name
        end
    end

    for _, bookmark in ipairs(self.bookmarks) do
        if bookmark.pos0 then
            local pg_or_xp = self.ui.document.info.has_pages and
                    bookmark.page or bookmark.pos0
                local chapter_name = self.ui.toc:getTocTitleByPage(pg_or_xp)
            bookmark.chapter = chapter_name
        elseif bookmark.page then -- dogear bookmark
            local chapter_name = self.ui.toc:getTocTitleByPage(bookmark.page)
            bookmark.chapter = chapter_name
        end
    end
    self.ui.doc_settings:saveSetting("bookmarks_version", 20200615)
end

local function split(str, pat)
    local t = {}  -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t, cap)
        end
        last_end = e + 1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end
    return t
end

local function substrCount(subject, needle)
    return select(2, subject:gsub(needle, ""))
end

-- put uppercase strings (authors etc.) at start of line, and always a linebreak between them and the following text:
local function uppercaseWordsAtStartOfLine(itext)
    itext = string.gsub(itext, "\n[ ]+([A-Z][A-Z]+)", "\n%1")
    itext = string.gsub(itext, "([A-Z]+)\n[ ]+", "%1\n\n")
    itext = string.gsub(itext, "([A-Z]+)\n\n[ ]+", "%1\n\n")
    itext = string.gsub(itext, "([A-Z]+)\n([A-Z])", "%1\n\n%2")
    itext = string.gsub(itext, "\n\n\n", "\n\n")
    return itext
end

local function isPoem(itext)
    local line_endings_count = substrCount(itext, "\n")
    local requisition1 = line_endings_count > 3

    -- check whether lines are not too long:
    local lines = split(itext, "\n")
    local requisition2 = true
    for _, line in ipairs(lines) do
        if string.len(line) > 52 then
            requisition2 = false
            break
        end
    end
    return (requisition1 == true and requisition2 == true)
end

local function indent(itext)
    -- only for non poetic text indent para's:
    if not isPoem(itext) then
        local paras = split(itext, "\n")
        local skip_next_para = false
        for nr, para in ipairs(paras) do
            if nr > 1 and para:match("[A-Za-z]") then
                if not skip_next_para then
                    paras[nr] = "     " .. para
                else
                    skip_next_para = false
                end
            elseif nr > 1 then
                skip_next_para = true
            end
        end
        itext = table.concat(paras, "\n")
    end
    return uppercaseWordsAtStartOfLine(itext)
end

-- make bookmark navigator available for gesture through open_navigator (if set, then open navigator):
function ReaderBookmark:onShowBookmark(open_navigator)
    self:updateHighlightsIfNeeded()
    -- build up item_table
    for k, v in ipairs(self.bookmarks) do
        local page = v.page
        -- for CREngine, bookmark page is xpointer
        if not self.ui.document.info.has_pages then
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                page = self.ui.pagemap:getXPointerPageLabel(page, true)
            else
                page = self.ui.document:getPageFromXPointer(page)
            end
        end
        if v.text == nil or v.text == "" then
            v.text = T(_("Page %1 %2 @ %3"), page, v.notes, v.datetime)
        end
    end

    local bm_menu = Menu:new{
        title = T(_("Bookmarks (%1)"), #self.bookmarks),
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
                direction = BD.flipDirectionIfMirroredUILayout("east")
            }
        }
    }

    self.bookmark_menu = CenterContainer:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        bm_menu,
    }

    -- build up menu widget method as closure
    local bookmark = self
    function bm_menu:onMenuChoice(item)
        bookmark.ui.link:addCurrentLocationToStack()
        bookmark:gotoBookmark(item.page)
    end

    function bm_menu:onMenuHold(item)
        -- reverse the bookmarks (because KOReader bookmarks are sorted in reverse of natural page order):
        -- not sure whether this is always the case?
        local bookmarks = {}
        for i = #bookmark.bookmarks, 1, -1 do
            local temp = bookmark.bookmarks[i]
            -- we need this reference to the unreversed, original bookmarks for deleting or renaming them:
            temp.index = i
            table.insert(bookmarks, temp)
        end
        local current_bookmark = 1
        local page = ""
        for nr, bmk in ipairs(bookmarks) do
            if item.index == bmk.index then
                current_bookmark = nr
                break
            end
        end
        local title = T(_("Bookmark details  -  %1/%2"), tostring(current_bookmark), tostring(#bookmarks))
        -- show page of bookmark in title:
        local ipage = item.page
        if not bookmark.ui.document.info.has_pages then
            page = bookmark.ui.document:getPageFromXPointer(ipage)
        end
        if page ~= "" then
            title = title .. "  -  " .. _("page") .. " " .. page
        end
        -- show search term in title:
        if bookmark.search_value and bookmark.search_value ~= "" then
            title = title .. '  -  "' .. bookmark.search_value .. '"'
        end
        local from_start_text = "▕◁"
        local backward_text = "◁"
        local forward_text = "▷"
        local from_end_text = "▷▏"
        if BD.mirroredUILayout() then
            backward_text, forward_text = forward_text, backward_text
            -- Keep the LTR order of |< and >|:
            from_start_text, from_end_text = BD.ltr(from_end_text), BD.ltr(from_start_text)
        end
        local first_button_row = {
            {
                text = _("Remove"),
                callback = function()
                    UIManager:show(ConfirmBox:new {
                        text = _("Do you want remove this bookmark?"),
                        cancel_text = _("Cancel"),
                        cancel_callback = function()
                            return
                        end,
                        ok_text = _("Remove"),
                        ok_callback = function()
                            local org_item = bookmark.bookmarks[item.index]
                            bookmark:removeHighlight(org_item)
                            UIManager:close(self.textviewer)
                            if #bookmark.bookmarks > 1 then
                                bm_menu:switchItemTable(nil, bookmark.bookmarks, -1)
                                -- if no bookmarks left after removal, return to reader:
                            else
                                return false
                            end
                        end,
                    })
                end,
            },
            {
                text = _("Rename"),
                callback = function()
                    local org_item = bookmark.bookmarks[item.index]
                    bookmark:renameBookmark(org_item)
                    UIManager:close(self.textviewer)
                end,
            },
            {
                text = backward_text,
                enabled = bookmark.search_value ~= "",
                callback = function()
                    bookmark:search(bookmark.search_value, bookmarks, current_bookmark, bm_menu, self.textviewer, -1)
                end,
            },
            {
                text = _("Search"),
                callback = function()
                    bookmark:prompt({
                        title = _("Bookmark search"),
                        value = bookmark.search_value:gsub("%%", ""),
                        hint = _("Needle"),
                        callback = function(query)
                            bookmark:search(string.lower(query), bookmarks, current_bookmark, bm_menu, self.textviewer, 1, true)
                        end,
                        save_button_text = _("Search")
                    })
                end,
            },
            {
                text = forward_text,
                enabled = bookmark.search_value ~= "",
                callback = function()
                    bookmark:search(bookmark.search_value, bookmarks, current_bookmark, bm_menu, self.textviewer, 1)
                end,
            },
            {
                text = _("Go to"),
                callback = function()
                    UIManager:close(self.textviewer)
                    UIManager:close(bookmark.bookmark_menu)
                    bookmark.ui.link:addCurrentLocationToStack()
                    bookmark:gotoBookmark(item.page)
                end,
            },
        }
        local second_button_row = {
            {
                text = from_start_text,
                enabled = #bookmark.bookmarks > 1,
                callback = function()
                    UIManager:close(self.textviewer)
                    bm_menu:onMenuHold(bookmarks[1])
                end,
            },
            {
                text = backward_text,
                enabled = #bookmark.bookmarks > 1,
                callback = function()
                    UIManager:close(self.textviewer)
                    local prev = current_bookmark - 1
                    if prev < 1 then
                        prev = #bookmarks
                    end
                    bm_menu:onMenuHold(bookmarks[prev])
                end,
            },
            {
                text = _("Close"),
                is_enter_default = true,
                callback = function()
                    UIManager:close(self.textviewer)
                    -- Also close list of bookmarks, for quick return to document. To only close the textviewer, use the close button in the upper right corner:
                    UIManager:close(bookmark.bookmark_menu)
                end,
            },
            {
                text = forward_text,
                enabled = #bookmark.bookmarks > 1,
                callback = function()
                    UIManager:close(self.textviewer)
                    local next = current_bookmark + 1
                    if next > #bookmarks then
                        next = 1
                    end
                    bm_menu:onMenuHold(bookmarks[next])
                end,
            },
            {
                text = from_end_text,
                enabled = #bookmark.bookmarks > 1,
                callback = function()
                    UIManager:close(self.textviewer)
                    bm_menu:onMenuHold(bookmarks[#bookmarks])
                end,
            },
        }
        local text = item.notes
        if not item.highlighted then
            text = T(_("Page %1 %2 @ %3"), ipage, item.notes, item.datetime)
        end

        local font_size = G_reader_settings:readSetting("dict_font_size") or 20
        self.textviewer = TextViewer:new{
            title = title,
            -- add indentation for better readability:
            text = indent(text),
            -- make text easier to read:
            justified = false,
            text_face = Font:getFace("cfont", font_size),
            width = self.textviewer_width,
            height = self.textviewer_height,
            buttons_table = {
                first_button_row,
                second_button_row,
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
    if open_navigator then
        if #self.bookmarks > 0 then
            -- open first bookmark in page order:
            bm_menu:onMenuHold(self.bookmarks[#self.bookmarks])
        else
            UIManager:show(InfoMessage:new { text = _('Bookmarks navigator: no bookmarks defined yet') })
        end
    end
    return true
end

-- argument is a table, containing: value, hint, callback, cancel_callback
function ReaderBookmark:prompt(args)
    local value = args.value
    local description = args.description
    local callback = args.callback
    local cancel_callback = args.cancel_callback
    local title = args.title or _("Edit")
    local save_button_text = args.save_button_text or _("Save")
    local prompt_dialog
    prompt_dialog = InputDialog:new {
        title = title,
        input = value,
        input_type = "text",
        description = description,
        fullscreen = false,
        condensed = true,
        allow_newline = false,
        cursor_at_end = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(prompt_dialog)
                        if cancel_callback then
                            cancel_callback()
                        end
                    end,
                },
                {
                    text = save_button_text,
                    is_enter_default = true,
                    callback = function()
                        local newval = prompt_dialog:getInputText()
                        UIManager:close(prompt_dialog)
                        callback(newval)
                    end,
                },
            }
        },
    }
    UIManager:show(prompt_dialog)
    prompt_dialog:onShowKeyboard()
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
    if self.ui.document.info.has_pages then
        return item1.pos0 and item1.pos1 and item2.pos0 and item2.pos1
        and item1.pos0.page == item2.pos0.page
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
        -- Update dogear in case we removed a bookmark for current page
        if self.ui.document.info.has_pages then
            self:setDogearVisibility(self.view.state.page)
        else
            self:setDogearVisibility(self.ui.document:getXPointer())
        end
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

function ReaderBookmark:updateBookmark(item)
    for i=1, #self.bookmarks do
        if item.datetime == self.bookmarks[i].datetime and item.page == self.bookmarks[i].page then
            local page = self.ui.document:getPageFromXPointer(item.updated_highlight.pos0)
            local new_text = item.updated_highlight.text
            self.bookmarks[i].page = item.updated_highlight.pos0
            self.bookmarks[i].pos0 = item.updated_highlight.pos0
            self.bookmarks[i].pos1 = item.updated_highlight.pos1
            self.bookmarks[i].notes = item.updated_highlight.text
            self.bookmarks[i].text = T(_("Page %1 %2 @ %3"), page,
                                        new_text,
                                        item.updated_highlight.datetime)
            self.bookmarks[i].datetime = item.updated_highlight.datetime
            self.bookmarks[i].chapter = item.updated_highlight.chapter
            self:onSaveSettings()
        end
    end
end

function ReaderBookmark:renameBookmark(item, from_highlight)
    if from_highlight then
        -- Called by ReaderHighlight:editHighlight, we need to find the bookmark
        for i=1, #self.bookmarks do
            if item.datetime == self.bookmarks[i].datetime and item.page == self.bookmarks[i].page then
                item = self.bookmarks[i]
                if item.text == nil or item.text == "" or not item.highlighted then
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
        allow_newline = true,
        cursor_at_end = true,
        add_scroll_buttons = true,
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
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

function ReaderBookmark:toggleBookmark(pn_or_xp)
    local index = self:getDogearBookmarkIndex(pn_or_xp)
    if index then
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
            chapter = chapter_name
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

function ReaderBookmark:getLatestBookmark()
    local latest_bookmark
    local latest_bookmark_datetime = "0"
    for i = 1, #self.bookmarks do
        if self.bookmarks[i].datetime > latest_bookmark_datetime then
            latest_bookmark_datetime = self.bookmarks[i].datetime
            latest_bookmark = self.bookmarks[i]
        end
    end
    return latest_bookmark
end

function ReaderBookmark:hasBookmarks()
    return self.bookmarks and #self.bookmarks > 0
end

function ReaderBookmark:getNumberOfHighlightsAndNotes()
    local highlights = 0
    local notes = 0
    for i = 1, #self.bookmarks do
        if self.bookmarks[i].highlighted then
            highlights = highlights + 1
            -- No real way currently to know which highlights
            -- have been edited and became "notes". Editing them
            -- adds this 'text' field, but just showing bookmarks
            -- do that as well...
            if self.bookmarks[i].text then
                notes = notes + 1
            end
        end
    end
    return highlights, notes
end

return ReaderBookmark
