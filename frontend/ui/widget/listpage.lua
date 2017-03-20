--[[--
Widget that presents a multi-page to show texts or other items defined by derived classes.

Example:

    local Foo = ListPage:new{
        title = "Statistics",

        "Current book",
        KeyValueItem:new{"Current period", "00:00:00"},
        -- single or more "-" will generate a solid line
        "----------------------------",
        KeyValueItem:new{"Page to read", "5"},
        KeyValueItem:new{"Time to read", "00:01:00"},
        KeyValueItem:new{"Press me", "will invoke the callback",
                         callback = function() print("hello") end },
        "Last book",
        "Sorry, no more books",
    }
    UIManager:show(Foo)

]]

local Blitbuffer = require("ffi/blitbuffer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderText = require("ui/rendertext")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local ListPageTitle = VerticalGroup:new{
    listpage = nil,
    title = "",
    tface = Font:getFace("tfont"),
    align = "left",
}

function ListPageTitle:init()
    self.close_button = CloseButton:new{ window = self }
    local btn_width = self.close_button:getSize().w
    local title_txt_width = RenderText:sizeUtf8Text(
                                0, self.width, self.tface, self.title).x
    local show_title_txt
    if self.width < (title_txt_width + btn_width) then
        show_title_txt = RenderText:truncateTextByWidth(
                            self.title, self.tface, self.width-btn_width)
    else
        show_title_txt = self.title
    end
    -- title and close button
    table.insert(self, OverlapGroup:new{
        dimen = { w = self.width },
        TextWidget:new{
            text = show_title_txt,
            face = self.tface,
        },
        self.close_button,
    })
    -- page count and separation line
    self.page_cnt = FrameContainer:new{
        padding = 4,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        -- overlap offset x will be updated in setPageCount method
        overlap_offset = {0, -15},
        TextWidget:new{
            text = "",  -- page count
            fgcolor = Blitbuffer.COLOR_GREY,
            face = Font:getFace("ffont", 16),
        },
    }
    self.title_bottom = OverlapGroup:new{
        dimen = { w = self.width, h = Screen:scaleBySize(2) },
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(2) },
            background = Blitbuffer.COLOR_GREY,
            style = "solid",
        },
        self.page_cnt,
    }
    table.insert(self, self.title_bottom)
    table.insert(self, VerticalSpan:new{ width = Screen:scaleBySize(5) })
end

function ListPageTitle:setPageCount(curr, total)
    if total == 1 then
        -- remove page count if there is only one page
        table.remove(self.title_bottom, 2)
        return
    end
    self.page_cnt[1]:setText(curr .. "/" .. total)
    self.page_cnt.overlap_offset[1] = (self.width - self.page_cnt:getSize().w - 10)
    self.title_bottom[2] = self.page_cnt
end

function ListPageTitle:onClose()
    self.listpage:onClose()
    return true
end

local ListPage = InputContainer:new{
    title = "",
    width = nil,
    height = nil,
    -- index for the first item to show
    show_page = 1,
    cface = Font:getFace("cfont"),
    item_height = Screen:scaleBySize(30),
}

function ListPage:init()
    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }

    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end

    local padding = Screen:scaleBySize(10)
    self.item_width = self.dimen.w - 2 * padding
    -- setup title bar
    self.title_bar = ListPageTitle:new{
        title = self.title,
        width = self.item_width,
        height = self.item_height,
        listpage = self,
    }
    -- setup main content
    self.item_margin = self.item_height / 4
    local line_height = self.item_height + 2 * self.item_margin
    local content_height = self.dimen.h - self.title_bar:getSize().h
    self.items_per_page = math.floor(content_height / line_height)
    self.pages = math.ceil(#self / self.items_per_page)
    self.main_content = VerticalGroup:new{}
    self:_populateItems()
    -- assemble page
    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            self.title_bar,
            self.main_content,
        },
    }
end

function ListPage:createItemWidget(item)
    if type(item) ~= "string" then
        assert(false, "No Listpage:createItemWidget() of the input item " .. type(item) .. " provided")
        return nil
    end

    if string.match(item, "-+") == item then
        return LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GREY,
            dimen = Geom:new{
                w = self.item_width,
                h = Screen:scaleBySize(2)
            },
            style = "solid",
        }
    end

    return TextWidget:new{
        text = RenderText:truncateTextByWidth(item, self.cfase, self.width),
        face = self.cface,
    }
end

function ListPage:nextPage()
    local new_page = math.min(self.show_page+1, self.pages)
    if new_page > self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

function ListPage:prevPage()
    local new_page = math.max(self.show_page-1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

-- make sure self.item_margin and self.item_height are set before calling this
function ListPage:_populateItems()
    self.main_content:clear()
    local idx_offset = (self.show_page - 1) * self.items_per_page
    for idx = 1, self.items_per_page do
        local entry = self[idx_offset + idx]
        if entry == nil then break end

        table.insert(self.main_content,
                     VerticalSpan:new{ width = self.item_margin })
        table.insert(self.main_content,
                     self:createItemWidget(entry))
        table.insert(self.main_content,
                     VerticalSpan:new{ width = self.item_margin })
    end
    self.title_bar:setPageCount(self.show_page, self.pages)
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function ListPage:onSwipe(arg, ges_ev)
    if ges_ev.direction == "west" then
        self:nextPage()
        return true
    elseif ges_ev.direction == "east" then
        self:prevPage()
        return true
    end
end

function ListPage:onClose()
    UIManager:close(self)
    return true
end

return ListPage
