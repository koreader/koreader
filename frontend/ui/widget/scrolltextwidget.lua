--[[--
Text widget with vertical scroll bar.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local UIManager = require("ui/uimanager")
local Input = Device.input
local Screen = Device.screen

local ScrollTextWidget = InputContainer:new{
    text = nil,
    charlist = nil,
    charpos = nil,
    editable = false,
    justified = false,
    face = nil,
    fgcolor = Blitbuffer.COLOR_BLACK,
    width = Screen:scaleBySize(400),
    height = Screen:scaleBySize(20),
    scroll_bar_width = Screen:scaleBySize(6),
    text_scroll_span = Screen:scaleBySize(12),
    dialog = nil,
    images = nil,
}

function ScrollTextWidget:init()
    self.text_widget = TextBoxWidget:new{
        text = self.text,
        charlist = self.charlist,
        charpos = self.charpos,
        editable = self.editable,
        justified = self.justified,
        face = self.face,
        image_alt_face = self.image_alt_face,
        fgcolor = self.fgcolor,
        width = self.width - self.scroll_bar_width - self.text_scroll_span,
        height = self.height,
        images = self.images,
    }
    local visible_line_count = self.text_widget:getVisLineCount()
    local total_line_count = self.text_widget:getAllLineCount()
    self.v_scroll_bar = VerticalScrollBar:new{
        enable = visible_line_count < total_line_count,
        low = 0,
        high = visible_line_count / total_line_count,
        width = self.scroll_bar_width,
        height = self.height,
    }
    local horizontal_group = HorizontalGroup:new{}
    table.insert(horizontal_group, self.text_widget)
    table.insert(horizontal_group, HorizontalSpan:new{width=self.text_scroll_span})
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
            TapScrollText = { -- allow scrolling with tap
                GestureRange:new{
                    ges = "tap",
                    range = function() return self.dimen end,
                },
            },
        }
    end
    if Device:hasKeyboard() or Device:hasKeys() then
        self.key_events = {
            ScrollDown = {{Input.group.PgFwd}, doc = "scroll down"},
            ScrollUp = {{Input.group.PgBack}, doc = "scroll up"},
        }
    end
end

function ScrollTextWidget:unfocus()
    self.text_widget:unfocus()
end

function ScrollTextWidget:focus()
    self.text_widget:focus()
end

function ScrollTextWidget:moveCursor(x, y)
    self.text_widget:moveCursor(x, y)
end

function ScrollTextWidget:scrollText(direction)
    if direction == 0 then return end
    local low, high
    if direction > 0 then
        low, high = self.text_widget:scrollDown()
    else
        low, high = self.text_widget:scrollUp()
    end
    self.v_scroll_bar:set(low, high)
    UIManager:setDirty(self.dialog, function()
        return "partial", self.dimen
    end)
end

function ScrollTextWidget:onScrollText(arg, ges)
    if ges.direction == "north" then
        self:scrollText(1)
        return true
    elseif ges.direction == "south" then
        self:scrollText(-1)
        return true
    end
    -- if swipe west/east, let it propagate up (e.g. for quickdictlookup to
    -- go to next/prev result)
end

function ScrollTextWidget:onTapScrollText(arg, ges)
    -- same tests as done in TextBoxWidget:scrollUp/Down
    if ges.pos.x < Screen:getWidth()/2 then
        if self.text_widget.virtual_line_num > 1 then
            self:scrollText(-1)
            return true
        end
    else
        if self.text_widget.virtual_line_num + self.text_widget:getVisLineCount() <= #self.text_widget.vertical_string_list then
            self:scrollText(1)
            return true
        end
    end
    -- if we couldn't scroll (because we're already at top or bottom),
    -- let it propagate up (e.g. for quickdictlookup to go to next/prev result)
end

function ScrollTextWidget:onScrollDown()
    self:scrollText(1)
    return true
end

function ScrollTextWidget:onScrollUp()
    self:scrollText(-1)
    return true
end

return ScrollTextWidget
