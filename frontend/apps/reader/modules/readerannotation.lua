local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderAnnotation = WidgetContainer:extend{
    annotations = nil, -- array sorted by annotation position order, ascending
}

-- build, read, save

function ReaderAnnotation:buildAnnotation(bm, highlights, init)
    -- bm: associated single bookmark ; highlights: tables with all highlights
    local note = bm.text
    if note == "" then
        note = nil
    end
    local chapter = bm.chapter
    local hl, pageno = self:getHighlightByDatetime(highlights, bm.datetime)
    if init then
        if note and self.ui.bookmark:isBookmarkAutoText(bm) then
            note = nil
        end
        if chapter == nil then
            chapter = self.ui.toc:getTocTitleByPage(bm.page)
        end
        pageno = self.ui.paging and bm.page or self.document:getPageFromXPointer(bm.page)
    end
    if self.ui.paging and bm.pos0 and not bm.pos0.page then
        -- old single-page reflow highlights do not have page in position
        bm.pos0.page = bm.page
        bm.pos1.page = bm.page
    end
    if not hl then -- page bookmark or orphaned bookmark
        hl = {}
        if bm.highlighted then -- orphaned bookmark
            hl.drawer = self.view.highlight.saved_drawer
            hl.color = self.view.highlight.saved_color
            if self.ui.paging then
                if bm.pos0.page == bm.pos1.page then
                    hl.pboxes = self.document:getPageBoxesFromPositions(bm.page, bm.pos0, bm.pos1)
                else -- multi-page highlight, restore the first box only
                    hl.pboxes = self.document:getPageBoxesFromPositions(bm.page, bm.pos0, bm.pos0)
                end
            end
        end
    end
    return { -- annotation
        datetime    = bm.datetime, -- creation time, not changeable
        drawer      = hl.drawer,   -- highlight drawer
        color       = hl.color,    -- highlight color
        text        = bm.notes,    -- highlighted text, editable
        text_edited = hl.edited,   -- true if highlighted text has been edited
        note        = note,        -- user's note, editable
        chapter     = chapter,     -- book chapter title
        pageno      = pageno,      -- book page number
        page        = bm.page,     -- highlight location, xPointer or number (pdf)
        pos0        = bm.pos0,     -- highlight start position, xPointer (== page) or table (pdf)
        pos1        = bm.pos1,     -- highlight end position, xPointer or table (pdf)
        pboxes      = hl.pboxes,   -- pdf pboxes, used only and changeable by addMarkupAnnotation
        ext         = hl.ext,      -- pdf multi-page highlight
    }
end

function ReaderAnnotation:getHighlightByDatetime(highlights, datetime)
    for pageno, page_highlights in pairs(highlights) do
        for _, highlight in ipairs(page_highlights) do
            if highlight.datetime == datetime then
                return highlight, pageno
            end
        end
    end
end

function ReaderAnnotation:getAnnotationsFromBookmarksHighlights(bookmarks, highlights, init)
    local annotations = {}
    for i = #bookmarks, 1, -1 do
        table.insert(annotations, self:buildAnnotation(bookmarks[i], highlights, init))
    end
    if init then
        self:sortItems(annotations)
    end
    return annotations
end

function ReaderAnnotation:onReadSettings(config)
    local annotations = config:readSetting("annotations")
    if annotations then
        -- KOHighlights may set this key when it has merged annotations from different sources:
        -- we want to make sure they are updated and sorted
        local needs_update = config:isTrue("annotations_externally_modified")
        local needs_sort -- if incompatible annotations were built of old highlights/bookmarks
        -- Annotation formats in crengine and mupdf are incompatible.
        local has_annotations = #annotations > 0
        local annotations_type = has_annotations and type(annotations[1].page)
        if self.ui.rolling and annotations_type ~= "string" then -- incompatible format loaded, or empty
            if has_annotations then -- backup incompatible format if not empty
                config:saveSetting("annotations_paging", annotations)
            end
             -- load compatible format
            annotations = config:readSetting("annotations_rolling") or {}
            config:delSetting("annotations_rolling")
            needs_sort = true
        elseif self.ui.paging and annotations_type ~= "number" then
            if has_annotations then
                config:saveSetting("annotations_rolling", annotations)
            end
            annotations = config:readSetting("annotations_paging") or {}
            config:delSetting("annotations_paging")
            needs_sort = true
        end
        self.annotations = annotations
        if needs_update or needs_sort then
            if self.ui.rolling then
                self.ui:registerPostInitCallback(function()
                    self:updatedAnnotations(needs_update, needs_sort)
                end)
            else
                self:updatedAnnotations(needs_update, needs_sort)
            end
            config:delSetting("annotations_externally_modified")
        end
    else -- first run
        if self.ui.rolling then
            self.ui:registerPostInitCallback(function()
                self:migrateToAnnotations(config)
            end)
        else
            self:migrateToAnnotations(config)
        end
    end
end

function ReaderAnnotation:migrateToAnnotations(config)
    local bookmarks = config:readSetting("bookmarks") or {}
    local highlights = config:readSetting("highlight") or {}

    if config:hasNot("highlights_imported") then
        -- before 2014, saved highlights were not added to bookmarks when they were created.
        for page, hls in pairs(highlights) do
            for _, hl in ipairs(hls) do
                local hl_page = self.ui.paging and page or hl.pos0
                -- highlights saved by some old versions don't have pos0 field
                -- we just ignore those highlights
                if hl_page then
                    local item = {
                        datetime    = hl.datetime,
                        highlighted = true,
                        notes       = hl.text,
                        page        = hl_page,
                        pos0        = hl.pos0,
                        pos1        = hl.pos1,
                    }
                    if self.ui.paging then
                        item.pos0.page = page
                        item.pos1.page = page
                    end
                    table.insert(bookmarks, item)
                end
            end
        end
    end

    -- Bookmarks/highlights formats in crengine and mupdf are incompatible.
    local has_bookmarks = #bookmarks > 0
    local bookmarks_type = has_bookmarks and type(bookmarks[1].page)
    if self.ui.rolling then
        if bookmarks_type == "string" then -- compatible format loaded, check for incompatible old backup
            if config:has("bookmarks_paging") then -- save incompatible old backup
                local bookmarks_paging = config:readSetting("bookmarks_paging")
                local highlights_paging = config:readSetting("highlight_paging")
                local annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks_paging, highlights_paging)
                config:saveSetting("annotations_paging", annotations)
                config:delSetting("bookmarks_paging")
                config:delSetting("highlight_paging")
            end
        else -- incompatible format loaded, or empty
            if has_bookmarks then -- save incompatible format if not empty
                local annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks, highlights)
                config:saveSetting("annotations_paging", annotations)
            end
            -- load compatible format
            bookmarks = config:readSetting("bookmarks_rolling") or {}
            highlights = config:readSetting("highlight_rolling") or {}
            config:delSetting("bookmarks_rolling")
            config:delSetting("highlight_rolling")
        end
    else -- self.ui.paging
        if bookmarks_type == "number" then
            if config:has("bookmarks_rolling") then
                local bookmarks_rolling = config:readSetting("bookmarks_rolling")
                local highlights_rolling = config:readSetting("highlight_rolling")
                local annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks_rolling, highlights_rolling)
                config:saveSetting("annotations_rolling", annotations)
                config:delSetting("bookmarks_rolling")
                config:delSetting("highlight_rolling")
            end
        else
            if has_bookmarks then
                local annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks, highlights)
                config:saveSetting("annotations_rolling", annotations)
            end
            bookmarks = config:readSetting("bookmarks_paging") or {}
            highlights = config:readSetting("highlight_paging") or {}
            config:delSetting("bookmarks_paging")
            config:delSetting("highlight_paging")
        end
    end

    self.annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks, highlights, true)
end

function ReaderAnnotation:onDocumentRerendered()
    self.needs_update = true
end

function ReaderAnnotation:onCloseDocument()
    self:updatePageNumbers()
end

function ReaderAnnotation:onSaveSettings()
    self:updatePageNumbers()
    self.ui.doc_settings:saveSetting("annotations", self.annotations)
end

-- items handling

function ReaderAnnotation:updatePageNumbers()
    if self.needs_update and self.ui.rolling then -- triggered by ReaderRolling on document layout change
        for _, item in ipairs(self.annotations) do
            item.pageno = self.document:getPageFromXPointer(item.page)
        end
    end
    self.needs_update = nil
end

function ReaderAnnotation:sortItems(items)
    if #items > 1 then
        local sort_func = self.ui.rolling and function(a, b) return self:isItemInPositionOrderRolling(a, b) end
                                           or function(a, b) return self:isItemInPositionOrderPaging(a, b) end
        table.sort(items, sort_func)
    end
end

function ReaderAnnotation:updatedAnnotations(needs_update, needs_sort)
    if needs_update then
        self.needs_update = true
        self:updatePageNumbers()
        needs_sort = true
    end
    if needs_sort then
        self:sortItems(self.annotations)
    end
end

function ReaderAnnotation:updateItemByXPointer(item)
    -- called by ReaderRolling:checkXPointersAndProposeDOMVersionUpgrade()
    local chapter = self.ui.toc:getTocTitleByPage(item.page)
    if chapter == "" then
        chapter = nil
    end
    if not item.drawer then -- page bookmark
        item.text = chapter and T(_("in %1"), chapter) or nil
    end
    item.chapter = chapter
    item.pageno = self.document:getPageFromXPointer(item.page)
end

function ReaderAnnotation:isItemInPositionOrderRolling(a, b)
    local a_page = self.document:getPageFromXPointer(a.page)
    local b_page = self.document:getPageFromXPointer(b.page)
    if a_page == b_page then -- both items in the same page
        if a.drawer and b.drawer then -- both items are highlights, compare positions
            local compare_xp = self.document:compareXPointers(a.page, b.page)
            if compare_xp then
                if compare_xp == 0 then -- both highlights with the same start, compare ends
                    compare_xp = self.document:compareXPointers(a.pos1, b.pos1)
                    if compare_xp then
                        return compare_xp > 0
                    end
                    logger.warn("Invalid xpointer in highlight:", a.pos1, b.pos1)
                    return true
                end
                return compare_xp > 0
            end
            -- if compare_xp is nil, some xpointer is invalid and "a" will be sorted first to page 1
            logger.warn("Invalid xpointer in highlight:", a.page, b.page)
            return true
        end
        return not a.drawer -- have page bookmarks before highlights
    end
    return a_page < b_page
end

function ReaderAnnotation:isItemInPositionOrderPaging(a, b)
    if a.page == b.page then -- both items in the same page
        if a.drawer and b.drawer then -- both items are highlights, compare positions
            local is_reflow = self.document.configurable.text_wrap -- save reflow mode
            self.document.configurable.text_wrap = 0 -- native positions
            -- sort start and end positions of each highlight
            local a_start, a_end, b_start, b_end, result
            if self.document:comparePositions(a.pos0, a.pos1) > 0 then
                a_start, a_end = a.pos0, a.pos1
            else
                a_start, a_end = a.pos1, a.pos0
            end
            if self.document:comparePositions(b.pos0, b.pos1) > 0 then
                b_start, b_end = b.pos0, b.pos1
            else
                b_start, b_end = b.pos1, b.pos0
            end
            -- compare start positions
            local compare_pos = self.document:comparePositions(a_start, b_start)
            if compare_pos == 0 then -- both highlights with the same start, compare ends
                result = self.document:comparePositions(a_end, b_end) > 0
            else
                result = compare_pos > 0
            end
            self.document.configurable.text_wrap = is_reflow -- restore reflow mode
            return result
        end
        return not a.drawer -- have page bookmarks before highlights
    end
    return a.page < b.page
end

function ReaderAnnotation:getItemIndex(item, no_binary)
    local doesMatch
    if item.datetime then
        doesMatch = function(a, b)
            return a.datetime == b.datetime
        end
    else
        if self.ui.rolling then
            doesMatch = function(a, b)
                if a.text ~= b.text or a.pos0 ~= b.pos0 or a.pos1 ~= b.pos1 then
                    return false
                end
                return true
            end
        else
            doesMatch = function(a, b)
                if a.text ~= b.text or a.pos0.page ~= b.pos0.page
                                    or a.pos0.x ~= b.pos0.x or a.pos1.x ~= b.pos1.x
                                    or a.pos0.y ~= b.pos0.y or a.pos1.y ~= b.pos1.y then
                    return false
                end
                return true
            end
        end
    end

    if not no_binary then
        local isInOrder = self.ui.rolling and self.isItemInPositionOrderRolling or self.isItemInPositionOrderPaging
        local _start, _end, _middle = 1, #self.annotations
        while _start <= _end do
            _middle = bit.rshift(_start + _end, 1)
            local v = self.annotations[_middle]
            if doesMatch(item, v) then
                return _middle
            elseif isInOrder(self, item, v) then
                _end = _middle - 1
            else
                _start = _middle + 1
            end
        end
    end

    for i, v in ipairs(self.annotations) do
        if doesMatch(item, v) then
            return i
        end
    end
end

function ReaderAnnotation:getInsertionIndex(item)
    local isInOrder = self.ui.rolling and self.isItemInPositionOrderRolling or self.isItemInPositionOrderPaging
    local _start, _end, _middle, direction = 1, #self.annotations, 1, 0
    while _start <= _end do
        _middle = bit.rshift(_start + _end, 1)
        if isInOrder(self, item, self.annotations[_middle]) then
            _end, direction = _middle - 1, 0
        else
            _start, direction = _middle + 1, 1
        end
    end
    return _middle + direction
end

function ReaderAnnotation:addItem(item)
    item.datetime = os.date("%Y-%m-%d %H:%M:%S")
    item.pageno = self.ui.paging and item.page or self.document:getPageFromXPointer(item.page)
    local index = self:getInsertionIndex(item)
    table.insert(self.annotations, index, item)
    return index
end

-- info

function ReaderAnnotation:hasAnnotations()
    return #self.annotations > 0
end

function ReaderAnnotation:getNumberOfAnnotations()
    return #self.annotations
end

function ReaderAnnotation:getNumberOfHighlightsAndNotes() -- for Statistics plugin
    local highlights = 0
    local notes = 0
    for _, item in ipairs(self.annotations) do
        if item.drawer then
            if item.note then
                notes = notes + 1
            else
                highlights = highlights + 1
            end
        end
    end
    return highlights, notes
end

return ReaderAnnotation
