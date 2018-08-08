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
local Math = require("optmath")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local UIManager = require("ui/uimanager")
local Input = Device.input
local Screen = Device.screen

local ScrollTextWidget = InputContainer:new{
    text = nil,
    charlist = nil,
    charpos = nil,
    top_line_num = nil,
    editable = false,
    justified = false,
    scroll_callback = nil, -- called with (low, high) when view is scrolled
    scroll_by_pan = false, -- allow scrolling by lines with Pan
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
        top_line_num = self.top_line_num,
        dialog = self.dialog,
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
        height = self.text_widget:getTextHeight(),
    }
    self:updateScrollBar()
    local horizontal_group = HorizontalGroup:new{ align = "top" }
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
        if self.scroll_by_pan then
            self.ges_events.PanText = {
                GestureRange:new{
                    ges = "pan",
                    range = function() return self.dimen end,
                },
            }
            self.ges_events.PanReleaseText = {
                GestureRange:new{
                    ges = "pan_release",
                    range = function() return self.dimen end,
                },
            }
        end
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

function ScrollTextWidget:getTextHeight()
    return self.text_widget:getTextHeight()
end

function ScrollTextWidget:getLineHeight()
    return self.text_widget:getLineHeight()
end

function ScrollTextWidget:getCharPos()
    return self.text_widget:getCharPos()
end

function ScrollTextWidget:updateScrollBar(is_partial)
    local low, high = self.text_widget:getVisibleHeightRatios()
    if low ~= self.prev_low or high ~= self.prev_high then
        self.prev_low = low
        self.prev_high = high
        self.v_scroll_bar:set(low, high)
        local refreshfunc = "ui"
        if is_partial then
            refreshfunc = "partial"
        end
        UIManager:setDirty(self.dialog, function()
            return refreshfunc, self.dimen
        end)
        if self.scroll_callback then
            self.scroll_callback(low, high)
        end
    end
end

function ScrollTextWidget:moveCursorToCharPos(charpos)
    self.text_widget:moveCursorToCharPos(charpos)
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorToXY(x, y, no_overflow)
    self.text_widget:moveCursorToXY(x, y, no_overflow)
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorLeft()
    self.text_widget:moveCursorLeft();
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorRight()
    self.text_widget:moveCursorRight();
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorUp()
    self.text_widget:moveCursorUp();
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorDown()
    self.text_widget:moveCursorDown();
    self:updateScrollBar()
end

function ScrollTextWidget:scrollDown()
    self.text_widget:scrollDown();
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollUp()
    self.text_widget:scrollUp();
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollToTop()
    self.text_widget:scrollToTop();
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollToBottom()
    self.text_widget:scrollToBottom();
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollText(direction)
    if direction == 0 then return end
    if direction > 0 then
        self.text_widget:scrollDown()
    else
        self.text_widget:scrollUp()
    end
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollToRatio(ratio)
    self.text_widget:scrollToRatio(ratio)
    self:updateScrollBar(true)
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
    if self.editable then
        -- Tap is used to position cursor
        return false
    end
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

function ScrollTextWidget:onPanText(arg, ges)
    self._pan_direction = ges.direction
    self._pan_relative_x = ges.relative.x
    self._pan_relative_y = ges.relative.y
    return true
end

function ScrollTextWidget:onPanReleaseText(arg, ges)
    if self._pan_direction and self._pan_relative_y then -- went thru onPanText
        if self._pan_direction == "north" or self._pan_direction == "south" then
            local nb_lines = Math.round(self._pan_relative_y / self:getLineHeight())
            self.text_widget:scrollLines(-nb_lines)
            self:updateScrollBar(true)
        end
        self._pan_direction = nil
        self._pan_relative_x = nil
        self._pan_relative_y = nil
        return true
    end
    return false
end

return ScrollTextWidget
