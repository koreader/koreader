local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Device = require("ui/device")
local Blitbuffer = require("ffi/blitbuffer")

--[[
Text widget with vertical scroll bar
--]]
local ScrollTextWidget = InputContainer:new{
    text = nil,
    face = nil,
    fgcolor = Blitbuffer.COLOR_BLACK,
    width = 400,
    height = 20,
    scroll_bar_width = Screen:scaleByDPI(6),
    text_scroll_span = Screen:scaleByDPI(6),
    dialog = nil,
}

function ScrollTextWidget:init()
    self.text_widget = TextBoxWidget:new{
        text = self.text,
        face = self.face,
        fgcolor = self.fgcolor,
        width = self.width - self.scroll_bar_width - self.text_scroll_span,
        height = self.height
    }
    local visible_line_count = self.text_widget:getVisLineCount()
    local total_line_count = self.text_widget:getAllLineCount()
    self.v_scroll_bar = VerticalScrollBar:new{
        enable = visible_line_count < total_line_count,
        low = 0,
        high = visible_line_count/total_line_count,
        width = Screen:scaleByDPI(6),
        height = self.height,
    }
    local horizontal_group = HorizontalGroup:new{}
    table.insert(horizontal_group, self.text_widget)
    table.insert(horizontal_group, HorizontalSpan:new{width = Screen:scaleByDPI(6)})
    table.insert(horizontal_group, self.v_scroll_bar)
    self[1] = horizontal_group
    self.dimen = Geom:new(self[1]:getSize())
    if Device:isTouchDevice() then
        self.ges_events = {
            ScrollText = {
                GestureRange:new{
                    ges = "swipe",
                    range = function() return self.dimen end,
                },
            },
        }
    end
end

function ScrollTextWidget:updateScrollBar(text)
    local virtual_line_num = text:getVirtualLineNum()
    local visible_line_count = text:getVisLineCount()
    local all_line_count = text:getAllLineCount()
    self.v_scroll_bar:set(
        (virtual_line_num - 1) / all_line_count,
        (virtual_line_num - 1 + visible_line_count) / all_line_count
    )
end

function ScrollTextWidget:onScrollText(arg, ges)
    if ges.direction == "north" then
        self.text_widget:scrollDown()
        self:updateScrollBar(self.text_widget)
    elseif ges.direction == "south" then
        self.text_widget:scrollUp()
        self:updateScrollBar(self.text_widget)
    end
    UIManager:setDirty(self.dialog, "partial")
end

return ScrollTextWidget
