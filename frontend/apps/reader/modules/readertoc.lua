local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local GestureRange = require("ui/gesturerange")
local Menu = require("ui/widget/menu")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderToc = InputContainer:new{
    toc = nil,
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
    return true
end

function ReaderToc:onPageUpdate(pageno)
    self.pageno = pageno
end

function ReaderToc:fillToc()
    self.toc = self.ui.document:getToc()
end

-- _getTocTitleByPage wrapper, so specific reader
-- can tranform pageno according its need
function ReaderToc:getTocTitleByPage(pn_or_xp)
    local page = pn_or_xp
    if type(pn_or_xp) == "string" then
        page = self.ui.document:getPageFromXPointer(pn_or_xp)
    end
    return self:_getTocTitleByPage(page)
end

function ReaderToc:_getTocTitleByPage(pageno)
    if not self.toc then
        -- build toc when needed.
        self:fillToc()
    end

    -- no table of content
    if #self.toc == 0 then
        return ""
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

function ReaderToc:onShowToc()
    if not self.toc then
        self:fillToc()
    end
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
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
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
    table.insert(tab_item_table.navi, {
        text = self.toc_menu_title,
        callback = function()
            self:onShowToc()
        end,
    })
end

return ReaderToc
