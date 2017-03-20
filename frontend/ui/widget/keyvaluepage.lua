--[[--
Widget that presents a multi-page to show key value pairs.

Example:

    local Foo = KeyValuePage:new{
        title = "Statistics",
        kv_pairs = {
            {"Current period", "00:00:00"},
            -- single or more "-" will generate a solid line
            "----------------------------",
            {"Page to read", "5"},
            {"Time to read", "00:01:00"},
            {"Press me", "will invoke the callback",
             callback = function() print("hello") end },
        },
    }
    UIManager:show(Foo)

]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ListPage = require("ui/widget/listpage")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local RenderText = require("ui/rendertext")

local KeyValueItem = InputContainer:new{
    key = nil,
    value = nil,
    cface = nil,
    width = nil,
    height = nil,
}

function KeyValueItem:init()
    self.dimen = Geom:new{w = self.width, h = self.height}

    if self.callback and Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end

    local key_w = RenderText:sizeUtf8Text(0, self.width, self.cface, self.key).x
    local value_w = RenderText:sizeUtf8Text(0, self.width, self.cface, self.value).x
    if key_w + value_w > self.width then
        -- truncate key or value so they fits in one row
        if key_w >= value_w then
            self.show_key = RenderText:truncateTextByWidth(self.key, self.cface, self.width-value_w)
            self.show_value = self.value
        else
            self.show_value = RenderText:truncateTextByWidth(self.value, self.cface, self.width-key_w, true)
            self.show_key = self.key
        end
    else
        self.show_key = self.key
        self.show_value = self.value
    end

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        OverlapGroup:new{
            dimen = self.dimen:copy(),
            LeftContainer:new{
                dimen = self.dimen:copy(),
                TextWidget:new{
                    text = self.show_key,
                    face = self.cface,
                }
            },
            RightContainer:new{
                dimen = self.dimen:copy(),
                TextWidget:new{
                    text = self.show_value,
                    face = self.cface,
                }
            }
        }
    }
end

function KeyValueItem:onTap()
    self.callback()
    return true
end


local KeyValuePage = ListPage:new{}

function KeyValuePage:init()
    if self.kv_pairs then
        for _, item in pairs(self.kv_pairs) do
            table.insert(self, item)
        end
    end
end

function KeyValuePage:createItemWidget(item)
    if type(item) == "table" then
        return KeyValueItem:new{
            height = self.item_height,
            width = self.item_width,
            key = item[1] or "",
            value = item[2] or "",
            callback = item.callback,
            cface = self.cface,
        }
    end

    return ListPage.createItemWidget(self, item)
end

return KeyValuePage
