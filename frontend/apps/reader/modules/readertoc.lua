local BD = require("ui/bidi")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderToc = InputContainer:new{
    toc = nil,
    ticks = {},
    toc_indent = "    ",
    collapsed_toc = {},
    collapse_depth = 2,
    expanded_nodes = {},
    toc_menu_title = _("Table of contents"),
    alt_toc_menu_title = _("Table of contents *"),
}

function ReaderToc:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ShowToc = {
                { "T" },
                doc = "show Table of Content menu" },
        }
    end
    self:resetToc()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderToc:cleanUpTocTitle(title)
    return (title:gsub("\13", ""))
end

function ReaderToc:onSetDimensions(dimen)
    self.dimen = dimen
end

function ReaderToc:resetToc()
    self.toc = nil
    self.ticks = {}
    self.collapsed_toc = {}
    self.expanded_nodes = {}
end

function ReaderToc:onUpdateToc()
    self:resetToc()
    return true
end

function ReaderToc:onPageUpdate(pageno)
    self.pageno = pageno
    if UIManager.FULL_REFRESH_COUNT == -1 then
        if self:isChapterEnd(pageno, 0) then
            self.chapter_refresh = true
        elseif self:isChapterBegin(pageno, 0) and self.chapter_refresh then
            UIManager:setDirty(nil, "full")
            self.chapter_refresh = false
        else
            self.chapter_refresh = false
        end
    end
end

function ReaderToc:onPosUpdate(pos, pageno)
    if pageno then
        self.pageno = pageno
    end
end

function ReaderToc:fillToc()
    if self.toc then return end
    if self.ui.document:canHaveAlternativeToc() then
        if self.ui.doc_settings:readSetting("alternative_toc") then
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

    -- For testing: shuffle a bit a valid TOC and make it randomely invalid
    -- for i = first, last do
    --     toc[i].page = toc[i].page + math.random(10) - 5
    -- end

    -- Do a cheap quick scan first
    logger.dbg("validateAndFixToc(): quick scan")
    local has_bogus
    local cur_page = 0
    for i = first, last do
        local page = toc[i].page
        if page < cur_page then
            has_bogus = true
            break
        end
        cur_page = page
    end
    if not has_bogus then -- no TOC items, or all are valid
        logger.dbg("validateAndFixToc(): TOC is fine")
        return
    end
    logger.dbg("validateAndFixToc(): TOC needs fixing")

    -- Bad ordering previously noticed: try to fix the wrong items' page
    -- by setting it to the previous or next good item page.
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
        local page = toc[i].fixed_page or toc[i].page
        if page >= cur_page then
            cur_page = page
        else
            -- Bogus page (or bogus previous page)
            nb_bogus = nb_bogus + 1
            -- See how many pages we'd need fixing on either side
            local nb_prev = 0
            for j = i-1, first, -1 do
                local ppage = toc[j].fixed_page or toc[j].page
                if ppage <= page then
                    break
                else
                    nb_prev = nb_prev + 1
                end
            end
            local nb_next = 1
            for j = i+1, last do
                local npage = toc[j].fixed_page or toc[j].page
                if npage >= cur_page then
                    break
                else
                    nb_next = nb_next + 1
                end
            end
            logger.dbg("BOGUS TOC:", i, page, ">", i-1, cur_page, "-", nb_prev, nb_next)
            if nb_prev <= nb_next then -- less changes when fixing previous pages
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
            cur_page = toc[i].fixed_page or toc[i].page
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
end

function ReaderToc:getTocIndexByPage(pn_or_xp)
    self:fillToc()
    if #self.toc == 0 then return end
    local pageno = pn_or_xp
    if type(pn_or_xp) == "string" then
        return self:getAccurateTocIndexByXPointer(pn_or_xp)
    end
    local pre_index = 1
    for _k,_v in ipairs(self.toc) do
        if _v.page > pageno then
            break
        end
        pre_index = _k
    end
    return pre_index
end

function ReaderToc:getAccurateTocIndexByXPointer(xptr)
    local pageno = self.ui.document:getPageFromXPointer(xptr)
    -- get toc entry(index) on for the current page
    -- we don't get infinite loop, because the this call is not
    -- with xpointer, but with page
    local index = self:getTocIndexByPage(pageno)
    if not index or not self.toc[index] then return end
    local initial_comparison = self.ui.document:compareXPointers(self.toc[index].xpointer, xptr)
    if initial_comparison and initial_comparison < 0 then
        local i = index - 1
        while self.toc[i] do
            local toc_xptr = self.toc[i].xpointer
            local cmp = self.ui.document:compareXPointers(toc_xptr, xptr)
            if cmp and cmp >= 0 then -- toc_xptr is before xptr(xptr >= toc_xptr)
                return i
            end
            i = i - 1
        end
    else
        local i = index + 1
        while self.toc[i] do
            local toc_xptr = self.toc[i].xpointer
            local cmp = self.ui.document:compareXPointers(toc_xptr, xptr)
            if cmp and cmp < 0 then -- toc_xptr is after xptr(xptr < toc_xptr)
                return i - 1
            end
            i = i + 1
        end
    end
    return index
end

function ReaderToc:getTocTitleByPage(pn_or_xp)
    local index = self:getTocIndexByPage(pn_or_xp)
    if index then
        return self:cleanUpTocTitle(self.toc[index].title)
    else
        return ""
    end
end

function ReaderToc:getTocTitleOfCurrentPage()
    if self.pageno then
        return self:getTocTitleByPage(self.pageno)
    end
end

function ReaderToc:getMaxDepth()
    self:fillToc()
    local max_depth = 0
    for _, v in ipairs(self.toc) do
        if v.depth > max_depth then
            max_depth = v.depth
        end
    end
    return max_depth
end

--[[
TOC ticks is a list of page number in ascending order of TOC nodes at certain level
positive level counts nodes of the depth level (level 1 for depth 1)
negative level counts nodes of reversed depth level (level -1 for max_depth)
zero level counts leaf nodes of the toc tree
--]]
function ReaderToc:getTocTicks(level)
    if self.ticks[level] then return self.ticks[level] end
    -- build toc ticks if not found
    self:fillToc()
    local ticks = {}

    if #self.toc > 0 then
        if level == 0 then
            local depth = 0
            for i = #self.toc, 1, -1 do
                local v = self.toc[i]
                if v.depth >= depth then
                    table.insert(ticks, v.page)
                end
                depth = v.depth
            end
        else
            local depth
            if level > 0 then
                depth = level
            else
                depth = self:getMaxDepth() + level + 1
            end
            for _, v in ipairs(self.toc) do
                if v.depth == depth then
                    table.insert(ticks, v.page)
                end
            end
        end
        -- normally the ticks are sorted already but in rare cases
        -- toc nodes may be not in ascending order
        table.sort(ticks)
        -- cache ticks only if ticks are available
        self.ticks[level] = ticks
    end
    return ticks
end

function ReaderToc:getTocTicksForFooter()
    local ticks_candidates = {}
    local max_level = self:getMaxDepth()
    for i = 0, -max_level, -1 do
        local ticks = self:getTocTicks(i)
        table.insert(ticks_candidates, ticks)
    end
    if #ticks_candidates > 0 then
        -- Find the finest toc ticks by sorting out the largest one
        table.sort(ticks_candidates, function(a, b) return #a > #b end)
        return ticks_candidates[1]
    end
    return {}
end

function ReaderToc:getNextChapter(cur_pageno, level)
    local ticks = self:getTocTicks(level)
    local next_chapter = nil
    for i = 1, #ticks do
        if ticks[i] > cur_pageno then
            next_chapter = ticks[i]
            break
        end
    end
    return next_chapter
end

function ReaderToc:getPreviousChapter(cur_pageno, level)
    local ticks = self:getTocTicks(level)
    local previous_chapter = nil
    for i = 1, #ticks do
        if ticks[i] >= cur_pageno then
            break
        end
        previous_chapter = ticks[i]
    end
    return previous_chapter
end

function ReaderToc:isChapterBegin(cur_pageno, level)
    local ticks = self:getTocTicks(level)
    local _begin = false
    for i = 1, #ticks do
        if ticks[i] == cur_pageno then
            _begin = true
            break
        end
    end
    return _begin
end

function ReaderToc:isChapterEnd(cur_pageno, level)
    local ticks = self:getTocTicks(level)
    local _end= false
    for i = 1, #ticks do
        if ticks[i] - 1 == cur_pageno then
            _end = true
            break
        end
    end
    return _end
end

function ReaderToc:getChapterPagesLeft(pageno, level)
    --if self:isChapterEnd(pageno, level) then return 0 end
    local next_chapter = self:getNextChapter(pageno, level)
    if next_chapter then
        next_chapter = next_chapter - pageno - 1
    end
    return next_chapter
end

function ReaderToc:getChapterPagesDone(pageno, level)
    if self:isChapterBegin(pageno, level) then return 0 end
    local previous_chapter = self:getPreviousChapter(pageno, level)
    if previous_chapter then
        previous_chapter = pageno - previous_chapter
    end
    return previous_chapter
end

function ReaderToc:updateCurrentNode()
    if #self.collapsed_toc > 0 and self.pageno then
        for i, v in ipairs(self.collapsed_toc) do
            if v.page > self.pageno then
                self.collapsed_toc.current = i > 1 and i - 1 or 1
                return
            end
        end
        self.collapsed_toc.current = #self.collapsed_toc
    end
end

function ReaderToc:expandParentNode(index)
    if index then
        local nodes_to_expand = {}
        local depth = self.toc[index].depth
        for i = index - 1, 1, -1 do
            if depth > self.toc[i].depth then
                depth = self.toc[i].depth
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
    self:fillToc()
    -- build menu items
    if #self.toc > 0 and not self.toc[1].text then
        for _,v in ipairs(self.toc) do
            v.text = self.toc_indent:rep(v.depth-1)..self:cleanUpTocTitle(v.title)
            v.mandatory = v.page
            if v.orig_page then -- bogus page fixed: show original page number
                v.mandatory = T("(%1) %2", v.orig_page, v.page)
            end
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                v.mandatory = self.ui.pagemap:getXPointerPageLabel(v.xpointer)
            end
        end
    end

    -- update collapsible state
    self.expand_button = Button:new{
        icon = "resources/icons/appbar.control.expand.png",
        icon_rotation_angle = BD.mirroredUILayout() and 180 or 0,
        width = Screen:scaleBySize(30),
        bordersize = 0,
        show_parent = self,
    }

    self.collapse_button = Button:new{
        icon = "resources/icons/appbar.control.collapse.png",
        width = Screen:scaleBySize(30),
        bordersize = 0,
        show_parent = self,
    }

    if #self.toc > 0 and #self.collapsed_toc == 0 then
        local depth = 0
        for i = #self.toc, 1, -1 do
            local v = self.toc[i]
            -- node v has child node(s)
            if v.depth < depth then
                v.state = self.expand_button:new{
                    callback = function() self:expandToc(i) end,
                    indent = self.toc_indent:rep(v.depth-1),
                }
            end
            if v.depth < self.collapse_depth then
                table.insert(self.collapsed_toc, 1, v)
            end
            depth = v.depth
        end
    end

    local button_size = self.expand_button:getSize()
    local toc_menu = Menu:new{
        title = _("Table of Contents"),
        item_table = self.collapsed_toc,
        state_size = button_size,
        ui = self.ui,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("x_smallinfofont"),
        single_line = true,
        align_baselines = true,
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
            item.state.callback()
        else
            toc_menu:close_callback()
            self.ui.link:addCurrentLocationToStack()
            self.ui:handleEvent(Event:new("GotoPage", item.page))
        end
    end

    toc_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    toc_menu.show_parent = menu_container

    self.toc_menu = toc_menu

    self:updateCurrentNode()
    -- auto expand the parent node of current page
    self:expandParentNode(self:getTocIndexByPage(self.pageno))
    -- auto goto page of the current toc entry
    self.toc_menu:switchItemTable(nil, self.collapsed_toc, self.collapsed_toc.current or -1)

    UIManager:show(menu_container)

    return true
end

-- expand TOC node of index in raw toc table
function ReaderToc:expandToc(index)
    for k, v in ipairs(self.expanded_nodes) do
        if v == index then return end
    end
    table.insert(self.expanded_nodes, index)
    local cur_node = self.toc[index]
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
    for i = index + 1, #self.toc do
        local v = self.toc[i]
        if v.depth == cur_depth + 1 then
            collapsed_index = collapsed_index + 1
            table.insert(self.collapsed_toc, collapsed_index, v)
        elseif v.depth <= cur_depth then
            break
        end
    end
    -- change state of current node to expanded
    cur_node.state = self.collapse_button:new{
        callback = function() self:collapseToc(index) end,
        indent = self.toc_indent:rep(cur_depth-1),
    }
    self:updateCurrentNode()
    self.toc_menu:switchItemTable(nil, self.collapsed_toc, -1)
end

-- collapse TOC node of index in raw toc table
function ReaderToc:collapseToc(index)
    for k, v in ipairs(self.expanded_nodes) do
        if v == index then
            table.remove(self.expanded_nodes, k)
            break
        end
    end
    local cur_node = self.toc[index]
    local cur_depth = cur_node.depth
    local i = 1
    local is_child_node = false
    while i <= #self.collapsed_toc do
        local v = self.collapsed_toc[i]
        if v.page > cur_node.page and v.depth <= cur_depth then
            is_child_node = false
        end
        if is_child_node then
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
    cur_node.state = self.expand_button:new{
        callback = function() self:expandToc(index) end,
        indent = self.toc_indent:rep(cur_depth-1),
    }
    self:updateCurrentNode()
    self.toc_menu:switchItemTable(nil, self.collapsed_toc, -1)
end

function ReaderToc:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.table_of_contents = {
        text_func = function()
            return self.ui.document:isTocAlternativeToc() and self.alt_toc_menu_title or self.toc_menu_title
        end,
        callback = function()
            self:onShowToc()
        end,
    }
    if self.ui.document:canHaveAlternativeToc() then
        menu_items.table_of_contents.hold_callback = function(touchmenu_instance)
            if self.ui.document:isTocAlternativeToc() then
                UIManager:show(ConfirmBox:new{
                    text = _("The table of content for this book is currently an alternative one built from the document headings.\nDo you want to get back the original table of content? (The book will be reloaded.)"),
                    ok_callback = function()
                        touchmenu_instance:closeMenu()
                        self.ui.doc_settings:delSetting("alternative_toc")
                        self.ui.document:invalidateCacheFile()
                        -- Allow for ConfirmBox to be closed before showing
                        -- "Opening file" InfoMessage
                        UIManager:scheduleIn(0.5, function ()
                            self.ui:reloadDocument()
                        end)
                    end,
                })
            else
                UIManager:show(ConfirmBox:new{
                    text = _("Do you want to use an alternative table of content built from the document headings?"),
                    ok_callback = function()
                        touchmenu_instance:closeMenu()
                        self:resetToc()
                        self.ui.document:buildAlternativeToc()
                        self.ui.doc_settings:saveSetting("alternative_toc", true)
                        self:onShowToc()
                        self.view.footer:setTocMarkers(true)
                        self.view.footer:onUpdateFooter()
                    end,
                })
            end
        end
    end
end

return ReaderToc
