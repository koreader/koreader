local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderToc = InputContainer:extend{
    toc = nil,
    toc_depth = nil,
    ticks = nil,
    ticks_flattened = nil,
    ticks_flattened_filtered = nil,
    collapsed_toc = nil, -- table
    collapse_depth = 2,
    expanded_nodes = nil, -- table
    toc_items_per_page_default = 14,
    alt_toc_symbol = "\u{E298}" -- two-folders in circle (custom toc uses a pen in square symbol)
}

function ReaderToc:init()
    self:registerKeyEvents()

    if G_reader_settings:hasNot("toc_items_per_page") then
        -- The TOC items per page and items' font size can now be
        -- configured. Previously, the ones set for the file browser
        -- were used. Initialize them from these ones.
        local items_per_page = G_reader_settings:readSetting("items_per_page")
                            or self.toc_items_per_page_default
        G_reader_settings:saveSetting("toc_items_per_page", items_per_page)
        local items_font_size = G_reader_settings:readSetting("items_font_size")
        if items_font_size and items_font_size ~= Menu.getItemFontSize(items_per_page) then
            -- Keep the user items font size if it's not the default for items_per_page
            G_reader_settings:saveSetting("toc_items_font_size", items_font_size)
        end
    end

    self:resetToc()
    self.ui.menu:registerToMainMenu(self)

    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderToc:onGesture() end

function ReaderToc:registerKeyEvents()
    if Device:hasScreenKB() then
        self.key_events.ShowToc = { { "ScreenKB", "Up" } }
    elseif Device:hasKeyboard() then
        self.key_events.ShowToc = { { "T" }, { "Shift", "Up" } }
    end
end

function ReaderToc:getTitle()
    local title = _("Table of contents")
    -- Handmade ToC has precedence over alternative ToC
    if self.ui.handmade:isHandmadeTocEnabled() then
        title = title .. " " .. self.ui.handmade.custom_toc_symbol
    elseif self.ui.document:isTocAlternativeToc() then
        title = title .. " " .. self.alt_toc_symbol
    end
    return title
end

ReaderToc.onPhysicalKeyboardConnected = ReaderToc.registerKeyEvents

function ReaderToc:onReadSettings(config)
    self.toc_ticks_ignored_levels = config:readSetting("toc_ticks_ignored_levels") or {}
    self.toc_chapter_navigation_bind_to_ticks = config:readSetting("toc_chapter_navigation_bind_to_ticks")
    self.toc_chapter_title_bind_to_ticks = config:readSetting("toc_chapter_title_bind_to_ticks")
end

function ReaderToc:onSaveSettings()
    self.ui.doc_settings:saveSetting("toc_ticks_ignored_levels", self.toc_ticks_ignored_levels)
    self.ui.doc_settings:saveSetting("toc_chapter_navigation_bind_to_ticks", self.toc_chapter_navigation_bind_to_ticks)
    self.ui.doc_settings:saveSetting("toc_chapter_title_bind_to_ticks", self.toc_chapter_title_bind_to_ticks)
end

function ReaderToc:cleanUpTocTitle(title, replace_empty)
    title = title:gsub("\13", "")
    if replace_empty and title:match("^%s*$") then
        title = "\u{2013}" -- En-Dash
    end
    return title
end

function ReaderToc:onSetDimensions(dimen)
    self.dimen = dimen
end

function ReaderToc:resetToc()
    self.toc = nil
    self.toc_menu_items_built = false
    self.toc_depth = nil
    self.ticks = nil
    self.ticks_flattened = nil
    self.ticks_flattened_filtered = nil
    self.collapsed_toc = {}
    self.collapse_depth = 2
    self.expanded_nodes = {}
end

ReaderToc.onUsePageLabelsUpdated = ReaderToc.resetToc

function ReaderToc:onUpdateToc()
    self:resetToc()
    self.ui:handleEvent(Event:new("TocReset"))
    return true
end

-- Be sure to update the ToC after a CRE rerendering
function ReaderToc:onDocumentRerendered()
    self:onUpdateToc()
end

function ReaderToc:onPageUpdate(pageno)
    if UIManager.FULL_REFRESH_COUNT == -1 or G_reader_settings:isTrue("refresh_on_chapter_boundaries") then
        local flash_on_second = G_reader_settings:nilOrFalse("no_refresh_on_second_chapter_page")
        local paging_forward, paging_backward
        if flash_on_second then
            if self.pageno then
                if pageno > self.pageno then
                    paging_forward = true
                elseif pageno < self.pageno then
                    paging_backward = true
                end
            end
        end

        if paging_backward and self:isChapterEnd(pageno) then
            UIManager:setDirty(nil, "full")
        elseif self:isChapterStart(pageno) then
            UIManager:setDirty(nil, "full")
        elseif paging_forward and self:isChapterSecondPage(pageno) then
            UIManager:setDirty(nil, "full")
        end
    end

    self.pageno = pageno
end

function ReaderToc:onPosUpdate(pos, pageno)
    if pageno then
        self.pageno = pageno
    end
end

function ReaderToc:fillToc()
    if self.toc then return end
    if self.ui.document:canHaveAlternativeToc() then
        if self.ui.doc_settings:isTrue("alternative_toc") then
            -- (if the document has a cache, the previously built alternative
            -- TOC was saved and has been reloaded, and this will be avoided)
            if not self.ui.document:isTocAlternativeToc() then
                self:resetToc()
                self.ui.document:buildAlternativeToc()
            end
        end
    end
    self.toc = self.ui.document:getToc()
    self:validateAndFixToc()
end

function ReaderToc:validateAndFixToc()
    -- Our code expects (rightfully) the TOC items to be ordered and to have
    -- increasing page numbers, but we may occasionally not get that from the
    -- engines (usually, because of bugs or duplicated IDs in the document).
    local toc = self.toc
    local first = 1
    local last = #toc

    -- For testing: shuffle a bit a valid TOC and make it randomly invalid
    -- for i = first, last do
    --     toc[i].page = toc[i].page + math.random(10) - 5
    -- end

    -- Do a cheap quick scan first
    logger.dbg("validateAndFixToc(): quick scan")
    local has_bogus
    local cur_page = 0
    local max_depth = 0
    local cur_seq_by_level = {}
    for i = first, last do
        local item = toc[i]
        local page = item.page
        if page < cur_page then
            has_bogus = true
            break
        end
        cur_page = page
        -- Use this loop to compute max_depth here (if has_bogus,
        -- we will recompute it in the loop below)
        local depth = item.depth
        if depth > max_depth then
            max_depth = depth
        end
        -- Also use this loop to compute seq_in_level for each
        -- item, needed by BookMap with alternative theme
        local seq = (cur_seq_by_level[depth] or 0) + 1
        item.seq_in_level = seq
        cur_seq_by_level[depth] = seq
    end
    if not has_bogus then -- no TOC items, or all are valid
        logger.dbg("validateAndFixToc(): TOC is fine")
        self.toc_depth = max_depth
        return
    end
    logger.dbg("validateAndFixToc(): TOC needs fixing")

    -- Bad ordering previously noticed: try to fix the wrong items' page
    -- by setting it to the previous or next good item page.
    max_depth = 0 -- recompute this
    cur_seq_by_level = {}
    local nb_bogus = 0
    local nb_fixed_pages = 0
    -- We fix only one bogus item per loop, taking the option that
    -- changes the least nb of items.
    -- Sample cases, *N* being the page noticed as bogus:
    --   1 4 57 *6*  9 13 24         best to reset 57 to 4 (or 6, or 5)
    --   1 4 57 *6* 79 84 96         best to reset 6 to 57 (or 79 or 68)
    --   1 4 55 56 57 *6*  7 8 9 10  best to reset 55,56,57 to 4
    --   1 4 55 56 57 *6*  7 60 62   best to reset 6,7 to 57
    -- (These cases are met in the following code with cur_page=57 and page=6)
    cur_page = 0
    for i = first, last do
        local item = toc[i]
        -- Recompute max_depth and item's seq_in_level
        local depth = item.depth
        if depth > max_depth then
            max_depth = depth
        end
        local seq = (cur_seq_by_level[depth] or 0) + 1
        item.seq_in_level = seq
        cur_seq_by_level[depth] = seq
        -- Look for bogus page
        local page = item.fixed_page or item.page
        if page >= cur_page then
            cur_page = page
        else
            -- Bogus page (or bogus previous page)
            nb_bogus = nb_bogus + 1
            -- See how many pages we'd need fixing on either side
            local nb_prev = 0
            local nb_prev_main = 0
            for j = i-1, first, -1 do
                local ppage = toc[j].fixed_page or toc[j].page
                if ppage <= page then
                    break
                else
                    nb_prev = nb_prev + 1
                    if self.ui.document:getPageFlow(ppage) == 0 then
                        nb_prev_main = nb_prev_main + 1
                    end
                end
            end
            local nb_next = 0
            local nb_next_main = 0
            for j = i, last do
                local npage = toc[j].fixed_page or toc[j].page
                if npage >= cur_page then
                    break
                else
                    nb_next = nb_next + 1
                    if self.ui.document:getPageFlow(npage) == 0 then
                        nb_next_main = nb_next_main + 1
                    end
                end
            end
            logger.dbg("BOGUS TOC:", i, page, "<", i-1, cur_page, "-", nb_prev, nb_next)
            -- Note: by comparing only the entries that belong to the main (linear) flow
            -- we give priority to moving non-linear bogus entries
            if nb_prev_main <= nb_next_main then -- less changes when fixing previous pages
                local fixed_page
                if i-nb_prev-1 >= 1 then
                    fixed_page = toc[i-nb_prev-1].fixed_page or toc[i-nb_prev-1].page
                else
                    fixed_page = 1
                end
                for j = i-1, i-nb_prev, -1 do
                    toc[j].fixed_page = fixed_page
                    logger.dbg("  fix prev", j, toc[j].page, "=>", fixed_page)
                end
            else
                local fixed_page = cur_page -- (might be better to use next one, but not safer)
                for j = i, i+nb_next-1 do
                    toc[j].fixed_page = fixed_page
                    logger.dbg("  fix next", j, toc[j].page, "=>", fixed_page)
                end
            end
            cur_page = item.fixed_page or item.page
        end
    end
    if nb_bogus > 0 then
        for i = first, last do
            if toc[i].fixed_page and toc[i].fixed_page ~= toc[i].page then
                toc[i].orig_page = toc[i].page -- keep the original one, for display only
                toc[i].page = toc[i].fixed_page
                nb_fixed_pages = nb_fixed_pages + 1
            end
        end
    end
    logger.info(string.format("TOC had %d bogus page numbers: fixed %d items to keep them ordered.", nb_bogus, nb_fixed_pages))
    self.toc_depth = max_depth
end

function ReaderToc:completeTocWithChapterLengths()
    local toc = self.toc
    local first = 1
    local last = #toc
    if last == 0 then
        return
    end
    local prev_item_by_level = {}
    for i = first, last do
        local item = toc[i]
        local page = item.page
        local depth = item.depth
        for j=#prev_item_by_level, depth, -1 do
            local prev_item = prev_item_by_level[j]
            if prev_item then
                prev_item.chapter_length = page - prev_item.page
            end
            prev_item_by_level[j] = nil
        end
        prev_item_by_level[depth] = item
    end
    -- Set the length of the last ones
    local page = self.ui.document:getPageCount() + 1
    for j=#prev_item_by_level, 0, -1 do
        local prev_item = prev_item_by_level[j]
        if prev_item then
            prev_item.chapter_length = page - prev_item.page
        end
    end
end

function ReaderToc:completeTocWithChapterLengthsFromPagemap()
    local toc = self.toc
    local first = 1
    local last = #toc
    if last == 0 then
        return
    end
    local prev_item_by_level = {}
    for i = first, last do
        local item = toc[i]
        local page, chapter_starts_new_ref_page = self:getPagePagemapIndex(item.page)
        local extra_page = chapter_starts_new_ref_page and 0 or 1
        local depth = item.depth
        for j=#prev_item_by_level, depth, -1 do
            local prev_item = prev_item_by_level[j]
            if prev_item then
                local prev_page = self:getPagePagemapIndex(prev_item.page)
                prev_item.chapter_length = page and prev_page and (page - prev_page + extra_page) or "\u{2013}"
            end
            prev_item_by_level[j] = nil
        end
        prev_item_by_level[depth] = item
    end
    -- Set the length of the last ones
    local page = self.ui.pagemap:getPageLabelProps() -- last label index
    for j=#prev_item_by_level, 0, -1 do
        local prev_item = prev_item_by_level[j]
        if prev_item then
            local prev_page = self:getPagePagemapIndex(prev_item.page)
            prev_item.chapter_length = page and prev_page and (page - prev_page + 1) or "\u{2013}"
        end
    end
end

function ReaderToc:getTocIndexByPage(pn_or_xp, skip_ignored_ticks)
    self:fillToc()
    if #self.toc == 0 then return end
    local pageno = pn_or_xp
    if type(pn_or_xp) == "string" then
        return self:getAccurateTocIndexByXPointer(pn_or_xp, skip_ignored_ticks)
    end
    local prev_index = 0
    for _k,_v in ipairs(self.toc) do
        if not skip_ignored_ticks or not self.toc_ticks_ignored_levels[_v.depth] then
            if _v.page == pageno then
                -- Return the first chapter seen on the current page
                prev_index = _k
                break
            end
            if _v.page > pageno then
                -- Return last chapter seen on a previous page
                break
            end
            prev_index = _k
        end
    end
    return prev_index > 0 and prev_index or nil
end

function ReaderToc:getAccurateTocIndexByXPointer(xptr, skip_ignored_ticks)
    local pageno = self.ui.document:getPageFromXPointer(xptr)
    -- get toc entry(index) on for the current page
    -- we don't get infinite loop, because the this call is not
    -- with xpointer, but with page
    local index = self:getTocIndexByPage(pageno, skip_ignored_ticks)
    if not index or not self.toc[index] then return end
    local initial_comparison = self.ui.document:compareXPointers(self.toc[index].xpointer, xptr)
    if initial_comparison and initial_comparison < 0 then
        local i = index - 1
        while self.toc[i] do
            if not skip_ignored_ticks or not self.toc_ticks_ignored_levels[self.toc[i].depth] then
                local toc_xptr = self.toc[i].xpointer
                local cmp = self.ui.document:compareXPointers(toc_xptr, xptr)
                if cmp and cmp >= 0 then -- toc_xptr is before xptr(xptr >= toc_xptr)
                    return i
                end
            end
            i = i - 1
        end
    else
        local prev_index = index
        local i = index + 1
        while self.toc[i] do
            if not skip_ignored_ticks or not self.toc_ticks_ignored_levels[self.toc[i].depth] then
                local toc_xptr = self.toc[i].xpointer
                local cmp = self.ui.document:compareXPointers(toc_xptr, xptr)
                if cmp and cmp < 0 then -- toc_xptr is after xptr(xptr < toc_xptr)
                    return prev_index
                end
                prev_index = i
            end
            i = i + 1
        end
    end
    return index
end

function ReaderToc:getTocTitleByPage(pn_or_xp)
    local index = self:getTocIndexByPage(pn_or_xp, self.toc_chapter_title_bind_to_ticks)
    if index then
        return self:cleanUpTocTitle(self.toc[index].title)
    else
        return ""
    end
end

function ReaderToc:getFullTocTitleByPage(pn_or_xp)
    local chapters = {}
    local toc_ticks_ignored_levels_orig = {}
    local toc_chapter_title_bind_to_ticks_orig = self.toc_chapter_title_bind_to_ticks -- backup the flag
    self.toc_chapter_title_bind_to_ticks = true -- honor self.toc_ticks_ignored_levels
    local max_depth = self:getMaxDepth()
    for depth = max_depth, 1, -1 do
        toc_ticks_ignored_levels_orig[depth] = self.toc_ticks_ignored_levels[depth] -- backup the level
        -- ignore the level if it should be ignored due to original settings
        self.toc_ticks_ignored_levels[depth] = self.toc_ticks_ignored_levels[depth] and toc_chapter_title_bind_to_ticks_orig
        local chapter = self:getTocTitleByPage(pn_or_xp)
        if chapter ~= "" and chapter ~= chapters[1] then
            table.insert(chapters, 1, chapter)
        end
        self.toc_ticks_ignored_levels[depth] = true -- ignore the level on next iterations
    end
    self.toc_chapter_title_bind_to_ticks = toc_chapter_title_bind_to_ticks_orig -- restore the flag
    table.move(toc_ticks_ignored_levels_orig, 1, max_depth, 1, self.toc_ticks_ignored_levels) -- restore all levels
    return chapters
end

function ReaderToc:getTocTitleOfCurrentPage()
    if self.pageno then
        return self:getTocTitleByPage(self.pageno)
    end
end

function ReaderToc:getMaxDepth()
    if self.toc_depth then return self.toc_depth end

    -- Not cached yet, compute it
    self:fillToc()
    local max_depth = 0
    for _, v in ipairs(self.toc) do
        if v.depth > max_depth then
            max_depth = v.depth
        end
    end
    self.toc_depth = max_depth
    return self.toc_depth
end

--[[
The ToC ticks is a list of page numbers in ascending order of ToC nodes at a particular depth level.
A positive level returns nodes at that depth level (top-level is 1, depth always matches level. Higher values mean deeper nesting.)
A negative level does the same, but computes the depth level in reverse (i.e., -1 is the most deeply nested one).
Omitting the level argument returns the full hierarchical table.
--]]
function ReaderToc:getTocTicks(level)
    -- Handle negative levels
    if level and level < 0 then
        level = self:getMaxDepth() + level + 1
    end

    if level then
        if self.ticks and self.ticks[level] then
            return self.ticks[level]
        end
    else
        if self.ticks then
            return self.ticks
        end
    end

    -- Build ToC ticks if not found
    self:fillToc()
    self.ticks = {}

    if #self.toc > 0 then
        -- Start by building a simple hierarchical ToC tick table
        for _, v in ipairs(self.toc) do
            if not self.ticks[v.depth] then
                self.ticks[v.depth] = {}
            end
            table.insert(self.ticks[v.depth], v.page)
        end

        -- Normally the ticks are already sorted, but in rare cases,
        -- ToC nodes may be not in ascending order
        for k, _ in ipairs(self.ticks) do
            table.sort(self.ticks[k])
        end
    end

    if level then
        return self.ticks[level]
    else
        return self.ticks
    end
end

--[[
Returns a flattened list of ToC ticks, without duplicates
]]
function ReaderToc:getTocTicksFlattened(for_chapter_navigation)
    local wants_filtered_ticks = true
    if not next(self.toc_ticks_ignored_levels) then
        -- No ignored level: no need to keep an additional list of filtered ticks
        wants_filtered_ticks = false
    elseif for_chapter_navigation then
        if not self.toc_chapter_navigation_bind_to_ticks then
            wants_filtered_ticks = false
        end
    end
    if wants_filtered_ticks then
        if self.ticks_flattened_filtered then
            return self.ticks_flattened_filtered
        end
    else
        if self.ticks_flattened then
            return self.ticks_flattened
        end
    end

    -- It hasn't been cached yet, compute it.
    local ticks = self:getTocTicks()
    local ticks_flattened = {}

    -- Keep track of what we add to avoid duplicates (c.f., https://stackoverflow.com/a/20067270)
    local hash = {}
    for depth, v in ipairs(ticks) do
        if not wants_filtered_ticks or not self.toc_ticks_ignored_levels[depth] then
            for _, page in ipairs(v) do
                if not hash[page] then
                    table.insert(ticks_flattened, page)
                    hash[page] = true
                end
            end
        end
    end

    -- And finally, sort it again
    table.sort(ticks_flattened)

    -- Store it in the relevant slot
    if wants_filtered_ticks then
        self.ticks_flattened_filtered = ticks_flattened
    else
        self.ticks_flattened = ticks_flattened
    end
    return ticks_flattened
end

function ReaderToc:getNextChapter(cur_pageno)
    local ticks = self:getTocTicksFlattened(true)
    local next_chapter = nil
    for _, page in ipairs(ticks) do
        if page > cur_pageno then
            next_chapter = page
            break
        end
    end
    return next_chapter
end

function ReaderToc:getPreviousChapter(cur_pageno)
    local ticks = self:getTocTicksFlattened(true)
    local previous_chapter = nil
    for _, page in ipairs(ticks) do
        if page >= cur_pageno then
            break
        end
        previous_chapter = page
    end
    return previous_chapter
end

function ReaderToc:isChapterStart(cur_pageno)
    local ticks = self:getTocTicksFlattened(true)
    local _start = false
    for _, page in ipairs(ticks) do
        if page == cur_pageno then
            _start = true
            break
        end
    end
    return _start
end

function ReaderToc:isChapterSecondPage(cur_pageno)
    local ticks = self:getTocTicksFlattened(true)
    local _second = false
    for _, page in ipairs(ticks) do
        if page + 1 == cur_pageno then
            _second = true
            break
        end
    end
    return _second
end

function ReaderToc:isChapterEnd(cur_pageno)
    local ticks = self:getTocTicksFlattened(true)
    local _end = false
    for _, page in ipairs(ticks) do
        if page - 1 == cur_pageno then
            _end = true
            break
        end
    end
    return _end
end

function ReaderToc:getPagePagemapIndex(pageno)
    -- for chapters, pageno is a rendered page number where the chapter title is displayed
    if pageno then
        local xp = self.ui.document:getPageXPointer(pageno)
        if xp then
            -- reference page (label) of the top of the displayed page
            -- (the label itself may be displayed in one of the previous pages)
            local label = self.ui.pagemap:getXPointerPageLabel(xp, true)
            -- label_pn - rendered page number where the label is displayed
            local index, label_pn = self.ui.pagemap:getPageLabelProps(label)
            if index then
                return index, label_pn == pageno -- true if chapter starts at new ref page
            end
        end
    end
end

function ReaderToc:getPreviousChapterPagemapIndex(pageno)
    local chapter_pn = self:isChapterStart(pageno) and pageno or self:getPreviousChapter(pageno)
    return self:getPagePagemapIndex(chapter_pn) or 1
end

function ReaderToc:getNextChapterPagemapIndex(pageno)
    local chapter_pn = self:getNextChapter(pageno)
    if chapter_pn then
        return self:getPagePagemapIndex(chapter_pn) -- chapter_idx, chapter_starts_new_ref_page
    else -- last chapter
        return self.ui.pagemap:getPageLabelProps() -- last index
    end
end

function ReaderToc:getChapterPageCount(pageno)
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        local prev_chapter_idx = self:getPreviousChapterPagemapIndex(pageno)
        if prev_chapter_idx then
            local next_chapter_idx, chapter_starts_new_ref_page = self:getNextChapterPagemapIndex(pageno)
            if next_chapter_idx then
                return next_chapter_idx - prev_chapter_idx + (chapter_starts_new_ref_page and 0 or 1)
            end
        end
    end

    local next_chapter = self:getNextChapter(pageno) or self.ui.document:getPageCount() + 1
    local previous_chapter = self:isChapterStart(pageno) and pageno or self:getPreviousChapter(pageno) or 1
    local page_count = next_chapter - previous_chapter
    if self.ui.document:hasHiddenFlows() and self.ui.document:getPageFlow(pageno) == 0 then
        -- If current page in a hidden flow, return the full amount of pages in this chapter.
        -- Otherwise, count only pages in the main flow
        for page = previous_chapter, next_chapter - 1 do
            if self.ui.document:getPageFlow(page) ~= 0 then
                page_count = page_count - 1
            end
        end
    end
    return page_count
end

function ReaderToc:getChapterPagesLeft(pageno)
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        local page_idx = self:getPagePagemapIndex(pageno)
        if page_idx then
            local next_chapter_idx, chapter_starts_new_ref_page = self:getNextChapterPagemapIndex(pageno)
            if next_chapter_idx then
                return next_chapter_idx - page_idx - (chapter_starts_new_ref_page and 1 or 0)
            end
        end
    end

    local next_chapter = self:getNextChapter(pageno)
    if not next_chapter then
        -- (ReaderFooter deals itself with nil and pageno in last chapter)
        return
    end
    local pages_left = next_chapter - pageno - 1
    if self.ui.document:hasHiddenFlows() and self.ui.document:getPageFlow(pageno) == 0 then
        for page = pageno, next_chapter - 1 do
            if self.ui.document:getPageFlow(page) ~= 0 then
                pages_left = pages_left - 1
            end
        end
    end
    return pages_left
end

function ReaderToc:getChapterPagesDone(pageno)
    if self:isChapterStart(pageno) then return 0 end

    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        local page_idx = self:getPagePagemapIndex(pageno)
        if page_idx then
            local prev_chapter_idx = self:getPreviousChapterPagemapIndex(pageno)
            if prev_chapter_idx then
                return page_idx - prev_chapter_idx
            end
        end
    end

    local previous_chapter = self:getPreviousChapter(pageno)
    if not previous_chapter then
        -- (ReaderFooter deals itself with nil and pageno not yet in first chapter)
        return
    end
    local pages_done = pageno - previous_chapter
    if self.ui.document:hasHiddenFlows() and self.ui.document:getPageFlow(pageno) == 0 then
        for page = previous_chapter, pageno - 1 do
            if self.ui.document:getPageFlow(page) ~= 0 then
                pages_done = pages_done - 1
            end
        end
    end
    return pages_done
end

function ReaderToc:updateCurrentNode()
    if self.search_string ~= nil and self.search_string ~= "*" then return end
    if #self.collapsed_toc > 0 and self.pageno then
        for i, v in ipairs(self.collapsed_toc) do
            if v.page >= self.pageno then
                if v.page == self.pageno then
                    -- Use first TOC item on current page (which may have others)
                    self.collapsed_toc.current = i
                else
                    -- Use previous TOC item (if any), which is on a previous page
                    self.collapsed_toc.current = i > 1 and i - 1 or 1
                end
                return
            end
        end
        self.collapsed_toc.current = #self.collapsed_toc
    end
end

function ReaderToc:expandParentNode(index)
    if index then
        local nodes_to_expand = {}
        local depth = self.filtered_toc[index].depth
        for i = index - 1, 1, -1 do
            if depth > self.filtered_toc[i].depth then
                depth = self.filtered_toc[i].depth
                table.insert(nodes_to_expand, i)
            end
            if depth == 1 then break end
        end
        for i = #nodes_to_expand, 1, -1 do
            self:expandToc(nodes_to_expand[i])
        end
    end
end

function ReaderToc:onShowToc()
    if self.view:shouldInvertBiDiLayoutMirroring() then
        BD.invert()
    end

    local items_per_page = G_reader_settings:readSetting("toc_items_per_page") or self.toc_items_per_page_default
    local items_font_size = G_reader_settings:readSetting("toc_items_font_size") or Menu.getItemFontSize(items_per_page)
    local items_show_chapter_length = G_reader_settings:isTrue("toc_items_show_chapter_length")
    local items_with_dots = G_reader_settings:nilOrTrue("toc_items_with_dots")

    self:fillToc()
    -- build menu items
    if #self.toc > 0 and not self.toc_menu_items_built then
        self.toc_menu_items_built = true
        if items_show_chapter_length then
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                self:completeTocWithChapterLengthsFromPagemap()
            else
                self:completeTocWithChapterLengths()
            end
        end
        -- Have the width of 4 spaces be the unit of indentation
        local tmp = TextWidget:new{
            text = "    ",
            face = Font:getFace("smallinfofont", items_font_size),
            }
        local toc_indent = tmp:getSize().w
        tmp:free()

        local has_hidden_flows = self.ui.document:hasHiddenFlows()
        for k, v in ipairs(self.toc) do
            v.index = k
            v.indent = toc_indent * (v.depth-1)
            v.text = self:cleanUpTocTitle(v.title, true)
            if items_show_chapter_length then
                v.post_text = T("(%1)", v.chapter_length)
            else
                v.post_text = nil
            end
            v.bidi_wrap_func = BD.auto
            v.mandatory = v.page
            if has_hidden_flows then
                local flow = self.ui.document:getPageFlow(v.page)
                if v.orig_page then -- bogus page fixed: show original page number
                    -- This is an ugly piece of code, which can result in an ugly TOC,
                    -- but it shouldn't be needed very often, only when bogus page numbers
                    -- are fixed, and then showing everything gets complicated
                    local orig_flow = self.ui.document:getPageFlow(v.orig_page)
                    if flow == 0 and orig_flow == flow then
                        v.mandatory = T("(%1) %2", self.ui.document:getPageNumberInFlow(v.orig_page), self.ui.document:getPageNumberInFlow(v.page))
                    elseif flow == 0 and orig_flow ~= flow then
                        v.mandatory = T("[%1]%2", self.ui.document:getPageNumberInFlow(v.orig_page), self.ui.document:getPageFlow(v.orig_page))
                    elseif flow > 0 and orig_flow == flow then
                        v.mandatory = T("[(%1) %2]%3", self.ui.document:getPageNumberInFlow(v.orig_page),
                                                       self.ui.document:getPageNumberInFlow(v.page), self.ui.document:getPageFlow(v.page))
                    else
                        v.mandatory = T("([%1]%2) [%3]%4", self.ui.document:getPageNumberInFlow(v.orig_page), self.ui.document:getPageFlow(v.orig_page),
                                                           self.ui.document:getPageNumberInFlow(v.page), self.ui.document:getPageFlow(v.page))
                    end
                else
                    -- Plain numbers for the linear entries,
                    -- for non-linear entries we use the same syntax as in the Go to dialog
                    if flow == 0 then
                        v.mandatory = self.ui.document:getPageNumberInFlow(v.page)
                    else
                        v.mandatory = T("[%1]%2", self.ui.document:getPageNumberInFlow(v.page), self.ui.document:getPageFlow(v.page))
                    end
                end
            elseif v.orig_page then -- bogus page fixed: show original page number
                v.mandatory = T("(%1) %2", v.orig_page, v.page)
            end
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                v.mandatory = self.ui.pagemap:getXPointerPageLabel(v.xpointer)
            end
        end
    end

    -- Estimate expand/collapse icon size
    -- *2/5 to account for Menu top title and bottom icons, and add some space between consecutive icons
    local icon_size = math.floor(Screen:getHeight() / items_per_page * 2/5)
    local button_width = icon_size * 2
    self.expand_button = Button:new{
        icon = "control.expand",
        icon_rotation_angle = BD.mirroredUILayout() and 180 or 0,
        width = button_width,
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        show_parent = self,
        callback = function(index) self:expandToc(index) end,
        onTapSelectButton = function() end, -- pass through taps to onMenuSelect
    }

    self.collapse_button = Button:new{
        icon = "control.collapse",
        width = button_width,
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        show_parent = self,
        callback = function(index) self:collapseToc(index) end,
        onTapSelectButton = function() end, -- pass through taps to onMenuSelect
    }

    -- update collapsible state
    if #self.toc > 0 and #self.collapsed_toc == 0 then
        local depth = 0
        for i = #self.toc, 1, -1 do
            local v = self.toc[i]
            -- node v has child node(s)
            if v.depth < depth then
                v.state = self.expand_button:new{}
            end
            if v.depth < self.collapse_depth then
                table.insert(self.collapsed_toc, 1, v)
            end
            depth = v.depth
        end
        self.filtered_toc = self.toc
    end
    local can_collapse = self:getMaxDepth() > 1

    -- NOTE: If the ToC actually has multiple depth levels, we request smaller padding between items,
    --       because we inflate the state Button's width on the left, mainly to give it a larger tap zone.
    --       This yields *slightly* better alignment between state & mandatory (in terms of effective margins).
    local button_size = self.expand_button:getSize()
    local toc_menu = Menu:new{
        title = self:getTitle(),
        subtitle = self.search_string and T(_("Query: %1"), self.search_string) or "",
        state_w = can_collapse and button_size.w or 0,
        ui = self.ui,
        is_borderless = true,
        is_popout = false,
        single_line = true,
        align_baselines = true,
        with_dots = items_with_dots,
        items_per_page = items_per_page,
        items_font_size = items_font_size,
        items_padding = can_collapse and math.floor(Size.padding.fullscreen / 2) or nil, -- c.f., note above. Menu's default is twice that.
        line_color = Blitbuffer.COLOR_WHITE,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:showTocDialog()
        end,
        on_close_ges = {
            GestureRange:new{
                ges = "two_finger_swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                direction = BD.flipDirectionIfMirroredUILayout("west")
            }
        }
    }

    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        toc_menu,
    }

    function toc_menu:onMenuSelect(item, pos)
        -- if toc item has expand/collapse state and tap select on the left side
        -- the state switch action is triggered, otherwise goto the linked page
        local do_toggle_state = false
        if item.state and pos and pos.x then
            if BD.mirroredUILayout() then
                do_toggle_state = pos.x > 0.7
            else
                do_toggle_state = pos.x < 0.3
            end
        end
        if do_toggle_state then
            item.state.callback(item.index)
        else
            toc_menu:close_callback()
            self.ui.link:addCurrentLocationToStack()
            if item.xpointer then
                self.ui:handleEvent(Event:new("GotoXPointer", item.xpointer, item.xpointer))
            else
                self.ui:handleEvent(Event:new("GotoPage", item.page))
            end
        end
    end

    function toc_menu:onMenuHold(item)
        if not Device:isTouchDevice() and (item.state and item.state.callback) then
            -- non touch to expand toc
            item.state.callback(item.index)
        else
            -- Match the items' width
            local infomessage = InfoMessage:new{
                width = Screen:getWidth() - (Size.padding.fullscreen * (can_collapse and 4 or 3)),
                alignment = "center",
                show_icon = false,
                text = item.text,
                face = Font:getFace("infofont", self.items_font_size),
            }
            UIManager:show(infomessage)
        end
        return true
    end

    toc_menu.close_callback = function()
        UIManager:close(menu_container)
        BD.resetInvert()
    end

    toc_menu.show_parent = menu_container

    self.toc_menu = toc_menu

    self:updateCurrentNode()
    if self.search_string == nil then
        -- auto expand the parent node of current page
        local idx = self:getTocIndexByPage(self.pageno)
        if idx then
            self:expandParentNode(idx)
            -- Also do it for other toc items on current page
            idx = idx + 1
            while self.toc[idx] and self.toc[idx].page == self.pageno do
                self:expandParentNode(idx)
                idx = idx + 1
            end
        end
    end

    -- auto goto page of the current toc entry
    self.toc_menu:switchItemTable(nil, self.collapsed_toc, self.collapsed_toc.current or -1)

    UIManager:show(menu_container)

    return true
end

function ReaderToc:showTocDialog()
    self:searchToc()
end

function ReaderToc:searchToc()
    if #self.toc == 0 then return end
    if self.search_string then -- restore full ToC
        self.search_string = nil
        self.toc_menu_items_built = false
        self.expanded_nodes = {}
        self.collapsed_toc = {}
        self.toc_menu.close_callback()
        self:onShowToc()
        return
    end

    local input_dialog
    input_dialog = InputDialog:new{
        title =  _("Enter text to search for"),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Search"),
                callback = function()
                    local str = input_dialog:getInputText()
                    if str == "" then return end
                    UIManager:close(input_dialog)
                    local collapsed_toc, expanded_nodes = {}, {}
                    local depth = 0
                    for i = #self.toc, 1, -1 do
                        local v = self.toc[i]
                        if v.depth < depth or str == "*" or util.stringSearch(v.title, str) ~= 0 then
                            if v.depth < depth then
                                v.state = self.collapse_button:new{}
                                expanded_nodes[i] = true
                            end
                            table.insert(collapsed_toc, 1, v)
                            depth = v.depth
                        end
                    end
                    if #collapsed_toc > 0 then
                        self.search_string = str
                        self.filtered_toc = {}
                        for i, v in ipairs(collapsed_toc) do
                            v.index = i
                            self.filtered_toc[i] = v
                        end
                        self.collapsed_toc = collapsed_toc
                        self.expanded_nodes = expanded_nodes
                        self.toc_menu.close_callback()
                        self:onShowToc()
                    else
                        UIManager:show(InfoMessage:new{ text = _("No results in table of contents") })
                    end
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- expand TOC node of index in raw toc table
function ReaderToc:expandToc(index)
    if self.expanded_nodes[index] == true then return end

    self.expanded_nodes[index] = true
    local cur_node = self.filtered_toc[index]
    local cur_depth = cur_node.depth
    local collapsed_index = nil
    for i, v in ipairs(self.collapsed_toc) do
        if v.page == cur_node.page and v.depth == cur_depth
                and v.text == cur_node.text then
            collapsed_index = i
            break
        end
    end
    -- either the toc entry of index has no child nodes
    -- or it's parent nodes are not expanded yet
    if not collapsed_index then return end
    for i = index + 1, #self.filtered_toc do
        local v = self.filtered_toc[i]
        if v.depth == cur_depth + 1 then
            collapsed_index = collapsed_index + 1
            table.insert(self.collapsed_toc, collapsed_index, v)
        elseif v.depth <= cur_depth then
            break
        end
    end
    -- change state of current node to expanded
    if cur_node.state then cur_node.state:free() end
    cur_node.state = self.collapse_button:new{}
    self:updateCurrentNode()
    self.toc_menu:switchItemTable(nil, self.collapsed_toc, -1)
end

-- collapse TOC node of index in raw toc table
function ReaderToc:collapseToc(index)
    if self.expanded_nodes[index] == true then
        self.expanded_nodes[index] = nil
    end
    local cur_node = self.filtered_toc[index]
    local cur_depth = cur_node.depth
    local i = 1
    local is_child_node = false
    while i <= #self.collapsed_toc do
        local v = self.collapsed_toc[i]
        if v.page > cur_node.page and v.depth <= cur_depth then
            is_child_node = false
        end
        if is_child_node then
            if v.state then
                v.state:free()
                v.state = self.expand_button:new{}
                if self.expanded_nodes[v.index] == true then
                    self.expanded_nodes[v.index] = nil
                end
            end
            table.remove(self.collapsed_toc, i)
        else
            i = i + 1
        end
        if v.page == cur_node.page and v.depth == cur_depth
                    and v.text == cur_node.text then
            is_child_node = true
        end
    end
    -- change state of current node to collapsed
    cur_node.state:free()
    cur_node.state = self.expand_button:new{}
    self:updateCurrentNode()
    self.toc_menu:switchItemTable(nil, self.collapsed_toc, -1)
end

function ReaderToc:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.table_of_contents = {
        text_func = function()
            return self:getTitle()
        end,
        callback = function()
            self:onShowToc()
        end,
    }
    -- ToC (and other navigation) settings
    menu_items.navi_settings = {
        text = _("Settings"),
        max_per_page = 11,
    }
    -- Alternative ToC (only available with CRE documents)
    if self.ui.document:canHaveAlternativeToc() then
        menu_items.toc_alt_toc = {
            text = _("Alternative table of contents") .. " " .. self.alt_toc_symbol,
            help_text_func = function()
                local help_text = _([[
An alternative table of contents can be built from document headings <H1> to <H6>.
If the document contains no headings, or all are ignored, the alternative ToC will be built from document fragments and will point to the start of each individual HTML file in the EPUB.

Some of the headings can be ignored, and hints can be set to other non-heading elements in a user style tweak, so they can be used as ToC items.
See Style tweaks → Miscellaneous → Alternative ToC hints.]])
                if self.ui.handmade:isHandmadeTocEnabled() then
                    help_text = _([[To use the alternative ToC, disable your custom table of contents first.]]) .. "\n\n" .. help_text
                end
                return help_text
            end,
            enabled_func = function()
                return not self.ui.handmade:isHandmadeTocEnabled()
            end,
            checked_func = function()
                return self.ui.document:isTocAlternativeToc()
            end,
            check_callback_closes_menu = true,
            callback = function(touchmenu_instance)
                if self.ui.document:isTocAlternativeToc() then
                    UIManager:show(ConfirmBox:new{
                        text = _("The table of contents for this book is currently an alternative one built from the document headings.\nDo you want to get back the original table of contents? (The book will be reloaded.)"),
                        ok_callback = function()
                            touchmenu_instance:closeMenu()
                            self.ui.doc_settings:delSetting("alternative_toc")
                            self.ui.document:invalidateCacheFile()
                            self.toc_ticks_ignored_levels = {} -- reset this
                            -- Allow for ConfirmBox to be closed before showing
                            -- "Opening file" InfoMessage
                            UIManager:scheduleIn(0.5, function ()
                                self.ui:reloadDocument()
                            end)
                        end,
                    })
                else
                    UIManager:show(ConfirmBox:new{
                        text = _("Do you want to use an alternative table of contents built from the document headings?"),
                        ok_callback = function()
                            touchmenu_instance:closeMenu()
                            self:resetToc()
                            self.toc_ticks_ignored_levels = {} -- reset this
                            self.ui.document:buildAlternativeToc()
                            self.ui.doc_settings:makeTrue("alternative_toc")
                            self:onShowToc()
                            self.view.footer:setTocMarkers(true)
                            self.view.footer:onUpdateFooter()
                            self.ui:handleEvent(Event:new("UpdateTopStatusBarMarkers"))
                        end,
                    })
                end
            end,
        }
    end
    -- Allow to have getTocTicksFlattened() get rid of all items at some depths, which
    -- might be useful to have the footer and SkimTo progress bar less crowded.
    -- This also affects the footer current chapter title, but leave the ToC itself unchanged.
    local genTocLevelIgnoreMenuItem = function(level)
        local ticks = self:getTocTicks()
        if not ticks[level] then
            return
        end
        return {
            text_func = function()
                return T(N_("1 entry at ToC depth %2", "%1 entries at ToC depth %2", #ticks[level]), #ticks[level], level)
            end,
            checked_func = function()
                return not self.toc_ticks_ignored_levels[level]
            end,
            callback = function()
                self.toc_ticks_ignored_levels[level] = not self.toc_ticks_ignored_levels[level] or nil
                self:onUpdateToc()
                self.view.footer:onUpdateFooter(self.view.footer_visible)
                self.ui:handleEvent(Event:new("UpdateTopStatusBarMarkers"))
            end,
        }
    end
    menu_items.toc_ticks_level_ignore = {
        text_func = function()
            local nb_ticks = 0
            local ticks = self:getTocTicks()
            for level=1, #ticks do
                if not self.toc_ticks_ignored_levels[level] then
                    nb_ticks = nb_ticks + #ticks[level]
                end
            end
            return T(N_("Progress bars: 1 tick", "Progress bars: %1 ticks", nb_ticks), nb_ticks)
        end,
        help_text = _([[The progress bars in the footer and the skim dialog can become cramped when the table of contents is complex. This allows you to restrict the number of tick marks.]]),
        enabled_func = function()
            local ticks = self:getTocTicks()
            return #ticks > 0
        end,
        sub_item_table_func = function()
            local toc_ticks_levels = {}
            local level = 1
            while true do
                local item = genTocLevelIgnoreMenuItem(level)
                if item then
                    table.insert(toc_ticks_levels, item)
                    level = level + 1
                else
                    break
                end
            end
            if #toc_ticks_levels > 0 then
                toc_ticks_levels[#toc_ticks_levels].separator = true
            end
            table.insert(toc_ticks_levels, {
                text = _("Bind chapter navigation to ticks"),
                help_text = _([[Entries from ToC levels that are ignored in the progress bars will still be used for chapter navigation and 'page/time left until next chapter' in the footer.
Enabling this option will restrict chapter navigation to progress bar ticks.]]),
                enabled_func = function()
                    return next(self.toc_ticks_ignored_levels) ~= nil
                end,
                checked_func = function()
                    return self.toc_chapter_navigation_bind_to_ticks
                end,
                callback = function()
                    self.toc_chapter_navigation_bind_to_ticks = not self.toc_chapter_navigation_bind_to_ticks
                    self:onUpdateToc()
                    self.view.footer:onUpdateFooter(self.view.footer_visible)
                end,
            })
            table.insert(toc_ticks_levels, {
                text = _("Chapter titles from ticks only"),
                help_text = _([[Entries from ToC levels that are ignored in the progress bars will still be used for displaying the title of the current chapter in the footer and in bookmarks.
Enabling this option will restrict display to the chapter titles of progress bar ticks.]]),
                enabled_func = function()
                    return next(self.toc_ticks_ignored_levels) ~= nil
                end,
                checked_func = function()
                    return self.toc_chapter_title_bind_to_ticks
                end,
                callback = function()
                    self.toc_chapter_title_bind_to_ticks = not self.toc_chapter_title_bind_to_ticks
                    self.view.footer:onUpdateFooter(self.view.footer_visible)
                end,
            })
            return toc_ticks_levels
        end,
    }
    menu_items.toc_items_per_page = {
        text = _("ToC entries per page"),
        keep_menu_open = true,
        callback = function()
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_perpage = G_reader_settings:readSetting("toc_items_per_page") or self.toc_items_per_page_default
            local items = SpinWidget:new{
                value = curr_perpage,
                value_min = 6,
                value_max = 24,
                default_value = self.toc_items_per_page_default,
                title_text =  _("ToC entries per page"),
                callback = function(spin)
                    G_reader_settings:saveSetting("toc_items_per_page", spin.value)
                    -- We need to reset the TOC so cached expand/collapsed icons
                    -- instances (as item.state), which were sized for a previous
                    -- value or items_per_page, are forgotten.
                    self:resetToc()
                end
            }
            UIManager:show(items)
        end
    }
    menu_items.toc_items_font_size = {
        text = _("ToC entry font size"),
        keep_menu_open = true,
        callback = function()
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_perpage = G_reader_settings:readSetting("toc_items_per_page") or self.toc_items_per_page_default
            local default_font_size = Menu.getItemFontSize(curr_perpage)
            local curr_font_size = G_reader_settings:readSetting("toc_items_font_size") or default_font_size
            local items_font = SpinWidget:new{
                value = curr_font_size,
                value_min = 10,
                value_max = 72,
                default_value = default_font_size,
                title_text =  _("ToC entry font size"),
                callback = function(spin)
                    G_reader_settings:saveSetting("toc_items_font_size", spin.value)
                end
            }
            UIManager:show(items_font)
        end,
    }
    menu_items.toc_items_show_chapter_length = {
        text = _("Show chapter length"),
        keep_menu_open = true,
        checked_func = function()
            return not G_reader_settings:nilOrFalse("toc_items_show_chapter_length")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("toc_items_show_chapter_length")
            self.toc_menu_items_built = false
        end
    }
    menu_items.toc_items_with_dots = {
        text = _("Dot leaders"),
        keep_menu_open = true,
        checked_func = function()
            return G_reader_settings:nilOrTrue("toc_items_with_dots")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("toc_items_with_dots")
        end
    }
end

return ReaderToc
