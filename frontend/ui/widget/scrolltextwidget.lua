local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")

--[[
Text widget with vertical scroll bar
--]]
local ScrollTextWidget = InputContainer:new{
    text = nil,
	charlist = nil,
	charpos = nil,
	editable = false,
    face = nil,
    fgcolor = Blitbuffer.COLOR_BLACK,
    width = 400,
    height = 20,
    scroll_bar_width = Screen:scaleBySize(6),
    text_scroll_span = Screen:scaleBySize(6),
    dialog = nil,
}

function ScrollTextWidget:init()
	print("####################################################### ScrollTextWidget width", self.width)
    self.text_widget = TextBoxWidget:new{
        text = self.text,
		charlist = self.charlist,
		charpos = self.charpos,
		editable = self.editable,
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
        width = self.scroll_bar_width,
        height = self.height,
    }
    local horizontal_group = HorizontalGroup:new{}
    table.insert(horizontal_group, self.text_widget)
    table.insert(horizontal_group, HorizontalSpan:new{self.text_scroll_span})
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

function ScrollTextWidget:onScrollText(arg, ges)
    if ges.direction == "north" then
        low, high = self.text_widget:scrollDown()
		self.v_scroll_bar:set(low, high)
    elseif ges.direction == "south" then
        low, high = self.text_widget:scrollUp()
		self.v_scroll_bar:set(low, high)
    end
    UIManager:setDirty(self.dialog, function()
        return "partial", self.dimen
    end)
end

return ScrollTextWidget
