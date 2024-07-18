--[[--
Text widget with vertical scroll bar.
--]]

local BD = require("ui/bidi")
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

local ScrollTextWidget = InputContainer:extend{
    text = nil,
    charlist = nil,
    charpos = nil,
    top_line_num = nil,
    editable = false,
    select_mode = nil, -- select mode in InputText
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
    -- See TextBoxWidget for details about these options
    alignment = "left",
    justified = false,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = false,
    alignment_strict = false,

    -- for internal use
    for_measurement_only = nil, -- When the widget is a one-off used to compute text height
}

function ScrollTextWidget:init()
    self.text_widget = TextBoxWidget:new{
        text = self.text,
        charlist = self.charlist,
        charpos = self.charpos,
        top_line_num = self.top_line_num,
        dialog = self.dialog,
        editable = self.editable,
        select_mode = self.select_mode,
        face = self.face,
        image_alt_face = self.image_alt_face,
        fgcolor = self.fgcolor,
        width = self.width - self.scroll_bar_width - self.text_scroll_span,
        height = self.height,
        images = self.images,
        alignment = self.alignment,
        justified = self.justified,
        lang = self.lang,
        para_direction_rtl = self.para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        alignment_strict = self.alignment_strict,
        for_measurement_only = self.for_measurement_only,
    }
    local visible_line_count = self.text_widget:getVisLineCount()
    local total_line_count = self.text_widget:getAllLineCount()
    self.v_scroll_bar = VerticalScrollBar:new{
        enable = visible_line_count < total_line_count,
        low = 0,
        high = visible_line_count / total_line_count,
        width = self.scroll_bar_width,
        height = self.text_widget:getTextHeight(),
        scroll_callback = function(ratio)
            self:scrollToRatio(ratio, false)
        end
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
    if Device:hasKeys() then
        self.key_events = {
            ScrollDown = { { Input.group.PgFwd } },
            ScrollUp = { { Input.group.PgBack } },
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

function ScrollTextWidget:getCharPosAtXY(x, y)
    return self.text_widget:getCharPosAtXY(x, y)
end

function ScrollTextWidget:getCharPosLineNum(charpos)
    local _, _, line_num = self.text_widget:_getXYForCharPos(charpos)
    return line_num -- screen line number
end

function ScrollTextWidget:updateScrollBar(is_partial)
    local low, high = self.text_widget:getVisibleHeightRatios()
    if low ~= self.prev_low or high ~= self.prev_high then
        self.prev_low = low
        self.prev_high = high
        self.v_scroll_bar:set(low, high)

        -- Don't even try to refresh dummy widgets used for text height computations...
        if not self.for_measurement_only then
            local refreshfunc = "ui"
            if is_partial then
                refreshfunc = "partial"
            end
            -- Reset transparency if the dialog's MovableContainer is currently translucent...
            if is_partial and self.dialog.movable and self.dialog.movable.alpha then
                self.dialog.movable.alpha = nil
                UIManager:setDirty(self.dialog, function()
                    return refreshfunc, self.dialog.movable.dimen
                end)
            else
                UIManager:setDirty(self.dialog, function()
                    return refreshfunc, self.dimen
                end)
            end
        end

        if self.scroll_callback then
            self.scroll_callback(low, high)
        end
    end
end

-- Reset the scrolling *state* to the top of the document, but don't actually re-render/refresh anything.
-- (Useful when replacing a Scroll*Widget during an update call, c.f., DictQuickLookup).
function ScrollTextWidget:resetScroll()
    local low, high = self.text_widget:getVisibleHeightRatios()
    self.v_scroll_bar:set(low, high)

    local visible_line_count = self.text_widget:getVisLineCount()
    local total_line_count = self.text_widget:getAllLineCount()
    self.v_scroll_bar.enable = visible_line_count < total_line_count
end

function ScrollTextWidget:moveCursorToCharPos(charpos, centered_lines_count)
    if centered_lines_count then
        self.text_widget:moveCursorToCharPosKeepingViewCentered(charpos, centered_lines_count)
    else
        self.text_widget:moveCursorToCharPos(charpos)
    end
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorToXY(x, y, no_overflow)
    if BD.mirroredUILayout() then -- the scroll bar is on the left
        x = x - self.scroll_bar_width - self.text_scroll_span
    end
    self.text_widget:moveCursorToXY(x, y, no_overflow)
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorLeft()
    self.text_widget:moveCursorLeft()
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorRight()
    self.text_widget:moveCursorRight()
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorUp()
    self.text_widget:moveCursorUp()
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorDown()
    self.text_widget:moveCursorDown()
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorHome()
    self.text_widget:moveCursorHome()
    self:updateScrollBar()
end

function ScrollTextWidget:moveCursorEnd()
    self.text_widget:moveCursorEnd()
    self:updateScrollBar()
end

function ScrollTextWidget:scrollDown()
    self.text_widget:scrollDown()
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollUp()
    self.text_widget:scrollUp()
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollToTop()
    self.text_widget:scrollToTop()
    self:updateScrollBar(true)
end

function ScrollTextWidget:scrollToBottom()
    self.text_widget:scrollToBottom()
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

function ScrollTextWidget:scrollToRatio(ratio, force_to_page)
    if force_to_page == nil then
        -- default to force to page, for consistency with
        -- ScrollHtmlWidget that always forces to page (for
        -- DictQuickLookup when going back to previous dict)
        force_to_page = true
    end
    self.text_widget:scrollToRatio(ratio, force_to_page)
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
    if BD.flipIfMirroredUILayout(ges.pos.x < Screen:getWidth()/2) then
        return self:onScrollUp()
    else
        return self:onScrollDown()
    end
end

function ScrollTextWidget:onScrollUp()
    if self.text_widget.virtual_line_num > 1 then
        self:scrollText(-1)
        return true
    end
    -- if we couldn't scroll (because we're already at top or bottom),
    -- let it propagate up (e.g. for quickdictlookup to go to next/prev result)
end

function ScrollTextWidget:onScrollDown()
    if self.text_widget.virtual_line_num + self.text_widget:getVisLineCount() <= #self.text_widget.vertical_string_list then
        self:scrollText(1)
        return true
    end
    -- if we couldn't scroll (because we're already at top or bottom),
    -- let it propagate up (e.g. for quickdictlookup to go to next/prev result)
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
