local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local GestureRange = require("ui/gesturerange")
local Menu = require("ui/widget/menu")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderToc = InputContainer:new{
    toc = nil,
    ticks = {},
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
    self.ui.menu:registerToMainMenu(self)
end

function ReaderToc:cleanUpTocTitle(title)
    return (title:gsub("\13", ""))
end

function ReaderToc:onSetDimensions(dimen)
    self.dimen = dimen
end

function ReaderToc:onUpdateToc()
    self.toc = nil
    self.ticks = {}
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
non-positive level counts nodes of reversed depth level (level -1 for max_depth-1)
--]]
function ReaderToc:getTocTicks(level)
    if self.ticks[level] then return self.ticks[level] end
    -- build toc ticks if not found
    self:fillToc()
    local ticks = {}

    if #self.toc > 0 then
        local depth = nil
        if level > 0 then
            depth = level
        else
            depth = self:getMaxDepth() + level
        end
        for _, v in ipairs(self.toc) do
            if v.depth == depth then
                table.insert(ticks, v.page)
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

function ReaderToc:onShowToc()
    self:fillToc()
    -- build menu items
    if #self.toc > 0 and not self.toc[1].text then
        for _,v in ipairs(self.toc) do
            v.text = ("    "):rep(v.depth-1)..self:cleanUpTocTitle(v.title)
            v.mandatory = v.page
        end
    end
    -- update current entry
    if #self.toc > 0 then
        for i=1, #self.toc do
            v = self.toc[i]
            if v.page > self.pageno then
                self.toc.current = i > 1 and i - 1 or 1
                break
            end
        end
    end

    local toc_menu = Menu:new{
        title = _("Table of Contents"),
        item_table = self.toc,
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

    function toc_menu:onMenuChoice(item)
        self.ui:handleEvent(Event:new("PageUpdate", item.page))
    end

    toc_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    toc_menu.show_parent = menu_container

    UIManager:show(menu_container)

    return true
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
