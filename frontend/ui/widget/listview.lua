--[[--
Widget component that handles pagination for a list of items.

Example:

    local list_view = ListView:new{
        height = Screen:scaleBySize(400),
        width = Screen:scaleBySize(200),
        page_update_cb = function(curr_page_num, total_pages)
            -- This callback function will be called whenever a page
            -- turn event is triggered. You can use it to update
            -- information on the parent widget.
        end,
        items = {
            FrameContainer:new{
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                TextWidget:new{
                    text = "foo",
                    face = Font:getFace("cfont"),
                }
            },
            FrameContainer:new{
                bordersize = 0,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                TextWidget:new{
                    text = "bar",
                    face = Font:getFace("cfont"),
                }
            },
            -- You can add as many widgets as you want here...
        }
    }

Note that ListView is created mainly to be used as a building block for other
widgets like @{ui.widget.networksetting|NetworkSetting}, so they can share the same pagination code.
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")

local ListView = InputContainer:extend{
    width = nil,
    height = nil,
    padding = nil,
    item_height = nil,
    items = nil,
}

function ListView:init()
    if #self.items <= 0 then return end

    self.show_page = 1
    self.dimen = Geom:new{x = 0, y = 0, w = self.width, h = self.height}

    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end

    local padding = self.padding or Size.padding.large
    self.item_height = self.item_height or self.items[1]:getSize().h
    self.item_width = self.dimen.w - 2 * padding
    self.items_per_page = math.floor(self.height / self.item_height)
    self.main_content = VerticalGroup:new{}
    self:_populateItems()
    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.main_content,
    }
end

-- make sure self.item_height are set before calling this
function ListView:_populateItems()
    self.pages = math.ceil(#self.items / self.items_per_page)
    self.main_content:clear()
    local idx_offset = (self.show_page - 1) * self.items_per_page
    for idx = 1, self.items_per_page do
        local item = self.items[idx_offset + idx]
        if item == nil then break end
        table.insert(self.main_content, item)
    end
    self.page_update_cb(self.show_page, self.pages)
end

function ListView:nextPage()
    local new_page = math.min(self.show_page+1, self.pages)
    if new_page > self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

function ListView:prevPage()
    local new_page = math.max(self.show_page-1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

function ListView:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:nextPage()
        return true
    elseif direction == "east" then
        self:prevPage()
        return true
    end
end

return ListView
