--[[--
ScrollableContainer allows scrolling its content (1 widget) within its own dimensions

This scrollable container needs to be known as widget.cropping_widget in
the widget using it that is passed to UIManager:show() for UIManager to
ensure proper interception of inner widget self-repainting/invert (mostly
used when flashing for UI feedback that we want to limit to the cropped
area).
If we notice some inner element flashing leaking outside the scrollable
area, it's probably some 'show_parent' forwarding missing from the main
widget to some of the inner widgets: chase the missing ones and add them.
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalScrollBar = require("ui/widget/horizontalscrollbar")
local InputContainer = require("ui/widget/container/inputcontainer")
local Math = require("optmath")
local UIManager = require("ui/uimanager")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local Screen = Device.screen
local logger = require("logger")

local ScrollableContainer = InputContainer:extend{
    -- Events to ignore (ie: ignore_events={"hold", "hold_release"})
    ignore_events = nil,
    scroll_bar_width = Screen:scaleBySize(6),

    -- Set to true if child widget is larger, false otherwise
    _is_scrollable = nil,
    -- Current scroll offset (use getScrolledOffset()/setScrolledOffset() to access them)
    _scroll_offset_x = 0,
    _scroll_offset_y = 0,
    _max_scroll_offset_x = 0,
    _max_scroll_offset_y = 0,
    -- Internal state between events
    _touch_pre_pan_was_inside = false,
    _scrolling = false,
    _scroll_relative_x = nil,
    _scroll_relative_y = nil,
    -- Scrollbar widgets, created as needed
    _v_scroll_bar = nil,
    _h_scroll_bar = nil,
    -- Scratch buffer
    _bb = nil,
    _crop_w = nil,
    _crop_h = nil,
    _crop_dx = 0,
}

function ScrollableContainer:getScrollbarWidth(scroll_bar_width)
    -- Return the width taken by the (default) scroll bar and its paddings
    if not scroll_bar_width then
        scroll_bar_width = self.scroll_bar_width
    end
    return 3 * scroll_bar_width
end

function ScrollableContainer:init()
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        -- Unflatten self.ignore_events to table keys for cleaner code below
        local ignore = {}
        if self.ignore_events then
            for _, evname in pairs(self.ignore_events) do
                ignore[evname] = true
            end
        end
        -- The following gestures need to be supported, depending on the
        -- ways a user can move/scroll things:
        --   Hold happens if he holds at start
        --   Pan happens if he doesn't hold at start, but holds at end
        --   Swipe happens if he doesn't hold at any moment
        -- (Touch is needed for accurate pan)
        self.ges_events = {
            ScrollableTouch       = not ignore.touch        and { GestureRange:new{ ges = "touch", range = range } } or nil,
            ScrollableSwipe       = not ignore.swipe        and { GestureRange:new{ ges = "swipe", range = range } } or nil,
            ScrollableHold        = not ignore.hold         and { GestureRange:new{ ges = "hold", range = range } } or nil,
            ScrollableHoldPan     = not ignore.hold_pan     and { GestureRange:new{ ges = "hold_pan", range = range } } or nil,
            ScrollableHoldRelease = not ignore.hold_release and { GestureRange:new{ ges = "hold_release", range = range } } or nil,
            ScrollablePan         = not ignore.pan          and { GestureRange:new{ ges = "pan", range = range } } or nil,
            ScrollablePanRelease  = not ignore.pan_release  and { GestureRange:new{ ges = "pan_release", range = range } } or nil,
        }
    end
end

function ScrollableContainer:initState()
    local content_size = self[1]:getSize()
    self._max_scroll_offset_x = math.max(0, content_size.w - self.dimen.w)
    self._max_scroll_offset_y = math.max(0, content_size.h - self.dimen.h)
    if self._max_scroll_offset_x == 0 and self._max_scroll_offset_y == 0 then
        -- Inner widget fits entirely: no need for anything scrollable
        self._is_scrollable = false
    else
        self._is_scrollable = true
        self._crop_w = self.dimen.w
        self._crop_h = self.dimen.h
        if self._max_scroll_offset_y > 0 then
            -- Adding a vertical scrollbar reduces the available width: recompute
            self._max_scroll_offset_x = math.max(0, content_size.w - (self.dimen.w - 3*self.scroll_bar_width))
        end
        if self._max_scroll_offset_x > 0 then
            -- Adding a horizontal scrollbar reduces the available height: recompute
            self._max_scroll_offset_y = math.max(0, content_size.h - (self.dimen.h - 3*self.scroll_bar_width))
            if self._max_scroll_offset_y > 0 then
                -- And re-compute again if we have to now add a vertical scrollbar
                self._max_scroll_offset_x = math.max(0, content_size.w - (self.dimen.w - 3*self.scroll_bar_width))
            end
        end
        -- Scrollbars won't be classic sub-widgets, we'll handle their painting ourselves
        if self._max_scroll_offset_y > 0 then
            self._v_scroll_bar = VerticalScrollBar:new{
                width = self.scroll_bar_width,
                height = self.dimen.h,
                scroll_callback = function(ratio)
                    self:scrollToRatio(nil, ratio)
                end
            }
            self._crop_w = self.dimen.w - 3*self.scroll_bar_width
        end
        if self._max_scroll_offset_x > 0 then
            self._h_scroll_bar_shift = 0
            if self._v_scroll_bar then
                -- Reduce its width so to not overlap with the vertical scroll bar
                self._h_scroll_bar_shift = 3*self.scroll_bar_width
            end
            self._h_scroll_bar = HorizontalScrollBar:new{
                height = self.scroll_bar_width,
                width = self.dimen.w - self._h_scroll_bar_shift,
                scroll_callback = function(ratio)
                    self:scrollToRatio(ratio, nil)
                end
            }
            self._crop_h = self.dimen.h - 3*self.scroll_bar_width
        end
        if BD.mirroredUILayout() then
            if self._v_scroll_bar then
                self._crop_dx = self.dimen.w - self._crop_w
            end
        end
        self:_updateScrollBars()
    end
end

function ScrollableContainer:getCropRegion()
    return Geom:new{
        x = self.dimen.x + self._crop_dx,
        y = self.dimen.y,
        w = self._crop_w,
        h = self._crop_h,
    }
end

function ScrollableContainer:_updateScrollBars()
    if self._v_scroll_bar then
        local dheight = self._crop_h / (self._max_scroll_offset_y + self._crop_h)
        local low = self._scroll_offset_y / (self._max_scroll_offset_y + self._crop_h)
        local high = low + dheight
        self._v_scroll_bar:set(low, high)
    end
    if self._h_scroll_bar then
        local dwidth = self._crop_w / (self._max_scroll_offset_x + self._crop_w)
        local low = self._scroll_offset_x / (self._max_scroll_offset_x + self._crop_w)
        local high = low + dwidth
        self._h_scroll_bar:set(low, high)
    end
end

function ScrollableContainer:scrollToRatio(ratio_x, ratio_y)
    if ratio_y then
        local dy = ratio_y * (self._max_scroll_offset_y + self._crop_h)
        self._scroll_offset_y = dy - Math.round(self._crop_h/2)
        if self._scroll_offset_y < 0 then
            self._scroll_offset_y = 0
        end
        if self._scroll_offset_y > self._max_scroll_offset_y then
            self._scroll_offset_y = self._max_scroll_offset_y
        end
    end
    if ratio_x then
        local dx = ratio_x * (self._max_scroll_offset_x + self._crop_w)
        self._scroll_offset_x = dx - Math.round(self._crop_w/2)
        if self._scroll_offset_x < 0 then
            self._scroll_offset_x = 0
        end
        if self._scroll_offset_x > self._max_scroll_offset_x then
            self._scroll_offset_x = self._max_scroll_offset_x
        end
    end
    self:_scrollBy(0, 0) -- get the additional work done
end

function ScrollableContainer:_scrollBy(dx, dy)
    if BD.mirroredUILayout() then
        dx = -dx
    end
    self._scroll_offset_x = self._scroll_offset_x + Math.round(dx)
    self._scroll_offset_y = self._scroll_offset_y + Math.round(dy)
    if self._scroll_offset_x < 0 then
        self._scroll_offset_x = 0
    end
    if self._scroll_offset_y < 0 then
        self._scroll_offset_y = 0
    end
    if self._scroll_offset_x > self._max_scroll_offset_x then
        self._scroll_offset_x = self._max_scroll_offset_x
    end
    if self._scroll_offset_y > self._max_scroll_offset_y then
        self._scroll_offset_y = self._max_scroll_offset_y
    end
    self:_updateScrollBars()
    UIManager:setDirty(self.show_parent, function()
        return "ui", self.dimen
    end)
end

function ScrollableContainer:getScrolledOffset()
    return Geom:new{
        x = self._scroll_offset_x,
        y = self._scroll_offset_y,
    }
end

function ScrollableContainer:setScrolledOffset(offset_point)
    if offset_point and offset_point.x and offset_point.y then
        self._scroll_offset_x = offset_point.x
        self._scroll_offset_y = offset_point.y
    end
end

function ScrollableContainer:onCloseWidget()
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

function ScrollableContainer:reset()
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
    self._is_scrollable = nil
    self._scroll_offset_x = 0
    self._scroll_offset_y = 0
end

function ScrollableContainer:paintTo(bb, x, y)
    if self[1] == nil then
        return
    end
    self.dimen.x = x
    self.dimen.y = y

    if self._is_scrollable == nil then -- not checked yet
        self:initState()
    end

    local _mirroredUI = BD.mirroredUILayout()

    if not self._is_scrollable then
        -- nothing to scroll: pass-through
        if _mirroredUI then -- behave as LeftContainer
            x = x + (self.dimen.w - self[1]:getSize().w)
        end
        self[1]:paintTo(bb, x, y)
        return
    end

    local screen_size = Screen:getSize()
    -- Create/Recreate the compose cache if we changed screen geometry
    if not self._bb or self._bb:getWidth() ~= screen_size.w or self._bb:getHeight() ~= screen_size.h then
        if self._bb then
            self._bb:free()
        end
        -- create a canvas for our child widget to paint to
        self._bb = Blitbuffer.new(screen_size.w, screen_size.h, bb:getType())
    end

    -- We need to fill it with our usual background color on each drawing,
    -- to erase bits that may not be overwritten after a scroll
    self._bb:fill(Blitbuffer.COLOR_WHITE)
    local dx
    if _mirroredUI then
        dx = self._max_scroll_offset_x - self._scroll_offset_x - self._crop_dx
    else
        dx = self._scroll_offset_x
    end
    self[1]:paintTo(self._bb, x - dx, y - self._scroll_offset_y)
    bb:blitFrom(self._bb, x + self._crop_dx, y, x + self._crop_dx, y, self._crop_w, self._crop_h)

    -- Draw our scrollbars over
    if self._h_scroll_bar then
        if _mirroredUI then
            self._h_scroll_bar:paintTo(bb, x + self._h_scroll_bar_shift, y + self.dimen.h - 2*self.scroll_bar_width)
        else
            self._h_scroll_bar:paintTo(bb, x, y + self.dimen.h - 2*self.scroll_bar_width)
        end
    end
    if self._v_scroll_bar then
        if _mirroredUI then
            self._v_scroll_bar:paintTo(bb, x + self.scroll_bar_width, y)
        else
            self._v_scroll_bar:paintTo(bb, x + self.dimen.w - 2*self.scroll_bar_width, y)
        end
    end
end

function ScrollableContainer:propagateEvent(event)
    -- Override WidgetContainer:propagateEvent() (which propagates an event
    -- to children before having it handled by the widget itself)
    if not self._is_scrollable then
        -- pass-through
        return InputContainer.propagateEvent(self, event)
    end
    if event.handler == "onGesture" and #event.args == 1 then
        local ges = event.args[1]
        -- Don't propagate events that happen out of view (in the hidden
        -- scrolled-out area) to child
        if ges.pos and not ges.pos:intersectWith(self.dimen) then
            return false -- we may handle it here
        end
    end
    -- Give any event first to our scrollbars
    if self._v_scroll_bar and self._v_scroll_bar:handleEvent(event) then
        return true
    end
    if self._h_scroll_bar and self._h_scroll_bar:handleEvent(event) then
        return true
    end
    -- Pass non-gestures events, and gestures event in the view, to our child
    return InputContainer.propagateEvent(self, event)
end

function ScrollableContainer:onScrollableSwipe(_, ges)
    if not self._is_scrollable then
        return false
    end
    logger.dbg("ScrollableContainer:onScrollableSwipe", ges)
    if not ges.pos:intersectWith(self.dimen) then
        -- with swipe, ges.pos is swipe's start position, which should
        -- be on us to consider it
        return false
    end
    self._scrolling = false -- could have been set by "pan" event received before "swipe"
    local direction = ges.direction
    local distance = ges.distance
    local sq_distance = math.floor(math.sqrt(distance*distance/2))
    if direction == "north" then self:_scrollBy(0, distance)
    elseif direction == "south" then self:_scrollBy(0, -distance)
    elseif direction == "east" then self:_scrollBy(-distance, 0)
    elseif direction == "west" then self:_scrollBy(distance, 0)
    elseif direction == "northeast" then self:_scrollBy(-sq_distance, sq_distance)
    elseif direction == "northwest" then self:_scrollBy(sq_distance, sq_distance)
    elseif direction == "southeast" then self:_scrollBy(-sq_distance, -sq_distance)
    elseif direction == "southwest" then self:_scrollBy(sq_distance, -sq_distance)
    end
    return true
end

function ScrollableContainer:onScrollableTouch(_, ges)
    if not self._is_scrollable then
        return false
    end
    -- First "pan" event may already be outside of us, we need to
    -- remember any "touch" event on us prior to "pan"
    logger.dbg("ScrollableContainer:onScrollableTouch", ges)
    if ges.pos:intersectWith(self.dimen) then
        self._touch_pre_pan_was_inside = true
        self._scroll_relative_x = ges.pos.x
        self._scroll_relative_y = ges.pos.y
    else
        self._touch_pre_pan_was_inside = false
    end
    return false
end

function ScrollableContainer:onScrollableHold(_, ges)
    if not self._is_scrollable then
        return false
    end
    logger.dbg("ScrollableContainer:onScrollableHold", ges)
    if ges.pos:intersectWith(self.dimen) then
        self._scrolling = true -- start of pan
        self._scroll_relative_x = ges.pos.x
        self._scroll_relative_y = ges.pos.y
        return true
    end
    return false
end

function ScrollableContainer:onScrollableHoldPan(_, ges)
    if not self._is_scrollable then
        return false
    end
    logger.dbg("ScrollableContainer:onScrollableHoldPan", ges)
    -- we may sometimes not see the "hold" event
    if ges.pos:intersectWith(self.dimen) or self._scrolling or self._touch_pre_pan_was_inside then
        self._touch_pre_pan_was_inside = false -- reset it
        self._scrolling = true
        return true
    end
    return false
end

function ScrollableContainer:onScrollableHoldRelease(_, ges)
    if not self._is_scrollable then
        return false
    end
    logger.dbg("ScrollableContainer:onScrollableHoldRelease", ges)
    if self._scrolling or self._touch_pre_pan_was_inside then
        self._scrolling = false
        if not self._scroll_relative_x or not self._scroll_relative_y then
            -- no previous event gave us accurate scroll info, ignore it
            return false
        end
        self._scroll_relative_x = ges.pos.x - self._scroll_relative_x
        self._scroll_relative_y = ges.pos.y - self._scroll_relative_y
        self:_scrollBy(-self._scroll_relative_x, -self._scroll_relative_y)
        self._scroll_relative_x = nil
        self._scroll_relative_y = nil
        return true
    end
    return false
end

function ScrollableContainer:onScrollablePan(_, ges)
    if not self._is_scrollable then
        return false
    end
    logger.dbg("ScrollableContainer:onScrollablePan", ges)
    if ges.pos:intersectWith(self.dimen) or self._scrolling or self._touch_pre_pan_was_inside then
        self._touch_pre_pan_was_inside = false -- reset it
        self._scrolling = true
        self._scroll_relative_x = ges.relative.x
        self._scroll_relative_y = ges.relative.y
        return true
    end
    return false
end

function ScrollableContainer:onScrollablePanRelease(_, ges)
    if not self._is_scrollable then
        return false
    end
    logger.dbg("ScrollableContainer:onScrollablePanRelease", ges)
    if self._scrolling then
        self:_scrollBy(-self._scroll_relative_x, -self._scroll_relative_y)
        self._scrolling = false
        self._scroll_relative_x = nil
        self._scroll_relative_y = nil
        return true
    end
    return false
end

return ScrollableContainer
