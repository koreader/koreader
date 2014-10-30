local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local GestureRange = require("ui/gesturerange")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderToc = InputContainer:new{
    toc = nil,
    ticks = {},
    toc_indent = "    ",
    collapsed_toc = {},
    collapse_depth = 2,
    expanded_nodes = {},
    toc_menu_title = _("Table of contents"),
}

function ReaderToc:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ShowToc = {
                { "T" },
                doc = "show Table of Content menu" },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            ShowToc = {
                GestureRange:new{
                    ges = "two_finger_swipe",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    },
                    direction = "east"
                }
            },
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
end

function ReaderToc:onUpdateToc()
    self:resetToc()
    return true
end

function ReaderToc:onPageUpdate(pageno)
    self.pageno = pageno
end

function ReaderToc:fillToc()
    if self.toc and #self.toc > 0 then return end
    self.toc = self.ui.document:getToc()
end

function ReaderToc:getTocTitleByPage(pn_or_xp)
    self:fillToc()
    if #self.toc == 0 then return "" end
    local pageno = pn_or_xp
    if type(pn_or_xp) == "string" then
        pageno = self.ui.document:getPageFromXPointer(pn_or_xp)
    end
    local pre_entry = self.toc[1]
    for _k,_v in ipairs(self.toc) do
        if _v.page > pageno then
            break
        end
        pre_entry = _v
    end
    return self:cleanUpTocTitle(pre_entry.title)
end

function ReaderToc:getTocTitleOfCurrentPage()
    return self:getTocTitleByPage(self.pageno)
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
            local depth = nil
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
    if #self.collapsed_toc > 0 then
        for i, v in ipairs(self.collapsed_toc) do
            if v.page > self.pageno then
                self.collapsed_toc.current = i > 1 and i - 1 or 1
                break
            end
        end
    end
end

function ReaderToc:onShowToc()
    self:fillToc()
    local max_depth = self:getMaxDepth()
    -- build menu items
    if #self.toc > 0 and not self.toc[1].text then
        for _,v in ipairs(self.toc) do
            v.text = self.toc_indent:rep(v.depth-1)..self:cleanUpTocTitle(v.title)
            v.mandatory = v.page
        end
    end

    -- update collapsible state
    self.expand_button = Button:new{
        icon = "resources/icons/appbar.control.expand.png",
        width = Screen:scaleByDPI(30),
        bordersize = 0,
        show_parent = self,
    }

    self.collapse_button = Button:new{
        icon = "resources/icons/appbar.control.collapse.png",
        width = Screen:scaleByDPI(30),
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

    self:updateCurrentNode()

    local button_size = self.expand_button:getSize()
    local toc_menu = Menu:new{
        title = _("Table of Contents"),
        item_table = self.collapsed_toc,
        state_size = button_size,
        ui = self.ui,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        cface = Font:getFace("cfont", 20),
        on_close_ges = {
            GestureRange:new{
                ges = "two_finger_swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                direction = "west"
            }
        }
    }

    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        toc_menu,
    }

    function toc_menu:onMenuSelect(item, pos)
        -- if toc item has expand/collapse state and tap select on the left side
        -- the state switch action is triggered, otherwise goto the linked page
        if item.state and pos.x < 0.3 then
            item.state.callback()
        else
            toc_menu:close_callback()
            self.ui:handleEvent(Event:new("GotoPage", item.page))
        end
    end

    toc_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    toc_menu.show_parent = menu_container

    self.toc_menu = toc_menu

    UIManager:show(menu_container)

    return true
end

-- expand TOC node of index in raw toc table
function ReaderToc:expandToc(index)
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
    self.toc_menu:swithItemTable(nil, self.collapsed_toc, -1)
end

-- collapse TOC node of index in raw toc table
function ReaderToc:collapseToc(index)
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
    self.toc_menu:swithItemTable(nil, self.collapsed_toc, -1)
end

function ReaderToc:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.navi, 1, {
        text = self.toc_menu_title,
        callback = function()
            self:onShowToc()
        end,
    })
end

return ReaderToc
