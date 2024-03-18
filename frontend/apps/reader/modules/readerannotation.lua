local WidgetContainer = require("ui/widget/container/widgetcontainer")

local ReaderAnnotation = WidgetContainer:extend{}

function ReaderAnnotation:buildAnnotation(bm, highlights, update_pageno)
    -- bm - corresponding bookmark, highlights - all highlights
    local hl, pageno = self:getHighlightByDatetime(highlights, bm.datetime)
    if update_pageno then -- cannot be done in onReadSettings()
        pageno = self.ui.paging and bm.page or self.document:getPageFromXPointer(bm.page)
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
        note        = bm.text,     -- user's note, editable
        chapter     = bm.chapter,  -- book chapter title
        pageno      = pageno,      -- book page number
        page        = bm.page,     -- highlight location, xPointer or number (pdf)
        pos0        = bm.pos0,     -- highlight start position, xPointer or table (pdf)
        pos1        = bm.pos1,     -- highlight end position, xPointer or table (pdf)
        pboxes      = hl.pboxes,   -- pdf pboxes, used only and changeable by addMarkupAnnotation
        ext         = hl.ext,      -- pdf multi-page highlight
    }
end

function ReaderAnnotation.buildBookmark(an)
    return {
        datetime    = an.datetime,
        highlighted = an.drawer and true or nil,
        notes       = an.text,
        text        = an.note,
        chapter     = an.chapter,
        page        = an.page,
        pos0        = an.pos0,
        pos1        = an.pos1,
    }
end

function ReaderAnnotation.buildHighlight(an)
    return {
        datetime    = an.datetime,
        drawer      = an.drawer,
        color       = an.color,
        text        = an.text,
        edited      = an.text_edited,
        chapter     = an.chapter,
        page        = an.page,
        pos0        = an.pos0,
        pos1        = an.pos1,
        pboxes      = an.pboxes,
        ext         = an.ext,
    }
end

function ReaderAnnotation:getHighlightByDatetime(highlights, datetime)
    for pageno, page_highlights in pairs(highlights) do
        for i, highlight in ipairs(page_highlights) do
            if highlight.datetime == datetime then
                return highlight, pageno
            end
        end
    end
end

function ReaderAnnotation:getAnnotationsFromBookmarksHighlights(bookmarks, highlights, update_pageno)
    local annotations = {}
    for i = #bookmarks, 1, -1 do
        table.insert(annotations, self:buildAnnotation(bookmarks[i], highlights, update_pageno))
    end
    return annotations
end

function ReaderAnnotation:getBookmarksHighlightsFromAnnotations(annotations)
    local bookmarks, highlights = {}, {}
    for i = #annotations, 1, -1 do
        local an = annotations[i]
        table.insert(bookmarks, self.buildBookmark(an))
        if an.drawer then
            if highlights[an.pageno] == nil then
                highlights[an.pageno] = {}
            end
            table.insert(highlights[an.pageno], self.buildHighlight(an))
        end
    end
    return bookmarks, highlights
end

function ReaderAnnotation:onReadSettings(config)
    local bookmarks, highlights
    local annotations = config:readSetting("annotations")
    if annotations then
        local has_annotations = #annotations > 0
        local annotations_type = has_annotations and type(annotations[1].page)
        -- Annotation formats in crengine and mupdf are incompatible.
        if self.ui.rolling and annotations_type ~= "string" then -- incompatible format loaded, or empty
            if has_annotations then -- backup incompatible format if not empty
                config:saveSetting("annotations_paging", annotations)
            end
             -- load compatible format
            annotations = config:readSetting("annotations_rolling") or {}
            config:delSetting("annotations_rolling")
        elseif self.ui.paging and annotations_type ~= "number" then
            if has_annotations then
                config:saveSetting("annotations_rolling", annotations)
            end
            annotations = config:readSetting("annotations_paging") or {}
            config:delSetting("annotations_paging")
        end
        bookmarks, highlights = self:getBookmarksHighlightsFromAnnotations(annotations)
    else -- old bookmarks/highlights
        bookmarks = config:readSetting("bookmarks") or {}
        highlights = config:readSetting("highlight") or {}
        local has_bookmarks = #bookmarks > 0
        local bookmarks_type = has_bookmarks and type(bookmarks[1].page)
        if self.ui.rolling then
            if bookmarks_type == "string" then -- compatible format loaded, check for incompatible old backup
                if config:has("bookmarks_paging") then -- backup incompatible old backup
                    local bookmarks_paging = config:readSetting("bookmarks_paging")
                    local highlights_paging = config:readSetting("highlight_paging")
                    local annotations_paging = self:getAnnotationsFromBookmarksHighlights(bookmarks_paging, highlights_paging)
                    config:saveSetting("annotations_paging", annotations_paging)
                    config:delSetting("bookmarks_paging")
                    config:delSetting("highlight_paging")
                end
            else -- incompatible format loaded, or empty
                if has_bookmarks then -- backup incompatible format if not empty
                    annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks, highlights)
                    config:saveSetting("annotations_paging", annotations)
                end
                -- load compatible format
                bookmarks = config:readSetting("bookmarks_rolling") or {}
                highlights = config:readSetting("highlight_rolling") or {}
                config:delSetting("bookmarks_rolling")
                config:delSetting("highlight_rolling")
            end
        else
            if bookmarks_type == "number" then
                if config:has("bookmarks_rolling") then
                    local bookmarks_rolling = config:readSetting("bookmarks_rolling")
                    local highlights_rolling = config:readSetting("highlight_rolling")
                    local annotations_rolling = self:getAnnotationsFromBookmarksHighlights(bookmarks_rolling, highlights_rolling)
                    config:saveSetting("annotations_rolling", annotations_rolling)
                    config:delSetting("bookmarks_rolling")
                    config:delSetting("highlight_rolling")
                end
            else
                if has_bookmarks then
                    annotations = self:getAnnotationsFromBookmarksHighlights(bookmarks, highlights)
                    config:saveSetting("annotations_rolling", annotations)
                end
                bookmarks = config:readSetting("bookmarks_paging") or {}
                highlights = config:readSetting("highlight_paging") or {}
                config:delSetting("bookmarks_paging")
                config:delSetting("highlight_paging")
            end
        end
    end
    self.ui.bookmark.bookmarks = bookmarks
    self.view.highlight.saved = highlights
end

function ReaderAnnotation:onCloseDocument()
    local annotations = self:getAnnotationsFromBookmarksHighlights(self.ui.bookmark.bookmarks, self.view.highlight.saved, true)
    self.ui.doc_settings:saveSetting("annotations", annotations)
    self.ui.doc_settings:saveSetting("bookmarks", self.ui.bookmark.bookmarks)
    self.ui.doc_settings:saveSetting("highlight", self.view.highlight.saved)
end

return ReaderAnnotation
