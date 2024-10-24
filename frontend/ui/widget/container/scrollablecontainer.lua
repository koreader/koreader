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
local Input = Device.input
local Screen = Device.screen
local logger = require("logger")

local ScrollableContainer = InputContainer:extend{
    -- Events to ignore (ie: ignore_events={"hold", "hold_release"})
    ignore_events = nil,
    scroll_bar_width = Screen:scaleBySize(6),

    -- Scroll behaviour
    -- If true, swipe a full visible width or height no matter the swipe distance
    swipe_full_view = true,

    -- Array of rows info: if provided, swipe will align the top of the view on
    -- a row, and ensure any truncated row at top or bottom gets fully visible
    -- after the swipe.
    -- Each array element (a row) must contain:
    --   top = y of the top of a row
    --   bottom = y of the bottom of a row (included, no overlap with 'top' of next row)
    -- It may contain:
    --   content_top = y of the content top of a row
    --   content_bottom = y of the content bottom of a row (included)
    -- that should not account for any top or bottom padding (which should be accounted in
    -- top/bottom), which will be used instead of top/bottom when looking for truncated rows.
    -- The distinction allows (if only some top or bottom padding is truncated, but not the
    -- content) to consider it fully visible and to not need to be visible after the swipe,
    -- but to still use these padding for the alignments.
    step_scroll_grid = nil,      -- either this array
    step_scroll_grid_func = nil, -- or a function returning this array
        -- Not implemented, but could be when this behaviour is needed on the x-axis:
        -- each row element could contain an array with the same kind of info (left,
        -- right, content_left, content_right) for its horizontal components, so
        -- swiping horizontally can "step" on those of the row at top.

    -- If true, don't draw a truncated row at bottom (we currently let a truncated row
    -- at top be shown).
    hide_truncated_grid_items = false,

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
    _crop_dx = 0,
    _crop_w = nil,
    _crop_h = nil,
    _crop_h_limited = nil,
}

function ScrollableContainer:getScrollbarWidth(scroll_bar_width)
    -- Return the width taken by the (default) scroll bar and its paddings
    if not scroll_bar_width then
        scroll_bar_width = self.scroll_bar_width
    end
    return 3 * scroll_bar_width
end

function ScrollableContainer:init()
    -- Unflatten self.ignore_events to table keys for cleaner code below
    local ignore = {}
    if self.ignore_events then
        for _, evname in pairs(self.ignore_events) do
            ignore[evname] = true
        end
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
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
    if Device:hasKeys() then
        self.key_events = {
            ScrollPageUp   = not ignore.key_pg_back and { { Input.group.PgBack } } or nil,
            ScrollPageDown = not ignore.key_pg_fwd  and { { Input.group.PgFwd } } or nil,
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
        if self.step_scroll_grid_func then
            self.step_scroll_grid = self.step_scroll_grid_func()
        end
        if self.step_scroll_grid then
            -- Ensure we anchor on the scroll step grid
            self:_scrollBy(0, 0, true)
        end
        self:_hideTruncatedGridItemsIfRequested()
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

function ScrollableContainer:_getStepScrollRowAtY(y, check_below)
    for _, row in ipairs(self.step_scroll_grid) do
        if y >= row.top and y <= row.bottom then
            if check_below then
                -- return row, is row fully below y, is its content fully below y
                return row, y == row.top, y <= (row.content_top or row.top)
            else
                -- return row, is row fully above y, is its content fully above y
                return row, y == row.bottom, y >= (row.content_bottom or row.bottom)
            end
        end
    end
end

function ScrollableContainer:_hideTruncatedGridItemsIfRequested()
    self._crop_h_limited = nil
    if self.hide_truncated_grid_items and self.step_scroll_grid then
        local new_bottom_row, new_bottom_row_fully_visible = self:_getStepScrollRowAtY(self._scroll_offset_y + self._crop_h - 1, false)
        if new_bottom_row and not new_bottom_row_fully_visible then
            self._crop_h_limited = new_bottom_row.top - self._scroll_offset_y
        end
    end
end

function ScrollableContainer:_scrollBy(dx, dy, ensure_scroll_steps)
    dx = Math.round(dx)
    dy = Math.round(dy)
    if BD.mirroredUILayout() then
        dx = -dx
    end
    local allow_overflow_x, allow_overflow_y = false, false

    -- We allow controlled scrolling with swipes and PgDown/PgUp where the scroll
    -- will align on a grid provided by the containee, so we can get better
    -- alignment of the content and avoid truncated items.
    if ensure_scroll_steps and self.step_scroll_grid then
        -- We want to ensure that after the scroll, we won't have a truncated row at top,
        -- and that any truncated row content at the point we're crossing will be fully
        -- visible after the scroll.
        -- When reaching top or bottom, we also allow overflow and display blank content,
        -- for easier continuous browsing so we don't have to guess where we were if we
        -- scrolled by less than a screen
        local orig_x, orig_y = self._scroll_offset_x, self._scroll_offset_y
        local new_x = orig_x + dx
        local new_y = orig_y + dy

        if orig_y <= 0 and dy <= 0 then
            -- Already overflowing, and scrolling again in the same direction: reset the
            -- overflow so we can get back in the sane state of anchored at top/bottom.
            new_y = 0
        elseif orig_y >= self._max_scroll_offset_y and dy >=0 then
            -- Already overflowing, as above.
            new_y = self._max_scroll_offset_y
        else
            allow_overflow_y = true -- this might be an option ?
            local top_row, top_row_fully_visible, top_row_content_visible = -- luacheck: no unused
                                self:_getStepScrollRowAtY(orig_y, true)
            local bottom_row, bottom_row_fully_visible, bottom_row_content_visible = -- luacheck: no unused
                                self:_getStepScrollRowAtY(orig_y + self._crop_h - 1, false)
            local new_view_bottom_y = new_y + self._crop_h - 1
            local new_top_row, new_top_row_fully_visible, new_top_row_content_visible = -- luacheck: no unused
                                self:_getStepScrollRowAtY(new_y, true)
            if dy >= 0 then -- Scrolling down
                if bottom_row and not bottom_row_content_visible and new_y > bottom_row.top then
                    -- If we'd go past the not fully visible original bottom button, have it fully at top
                    new_y = bottom_row.top
                else
                    -- Ensure the new top row is anchored as its top
                    if new_top_row then
                        new_y = new_top_row.top
                    end
                end
            else -- Scrolling up
                if top_row and not top_row_content_visible
                           and new_view_bottom_y < (top_row.content_bottom or top_row.bottom) then
                    -- If we'd go past the not fully visible original top button, be sure we'll
                    -- have its content fully at bottom
                    new_y = (top_row.content_bottom or top_row.bottom) - self._crop_h + 1
                    new_top_row, new_top_row_fully_visible, new_top_row_content_visible = -- luacheck: no unused
                                self:_getStepScrollRowAtY(new_y, true)
                end
                if not new_top_row and new_y < 0 then
                    -- Overflow. If the overflow is less than a ghost row before the first row,
                    -- do as what the next 'if's would do if it were there: anchor on the first row.
                    -- This may happen when back up to the first page: we don't want that small overflow.
                    -- (Not super sure this may not cause other issues like having the previous top
                    -- row duplicated at the new bottom.)
                    local first_row = self:_getStepScrollRowAtY(0)
                    if - new_y < first_row.bottom then
                        new_top_row, new_top_row_fully_visible, new_top_row_content_visible = -- luacheck: no unused
                                    self:_getStepScrollRowAtY(0, true)
                    end
                end
                -- If the new top row is not fully visible, use the next row
                if new_top_row and not new_top_row_fully_visible then
                    new_top_row, new_top_row_fully_visible, new_top_row_content_visible = -- luacheck: no unused
                                self:_getStepScrollRowAtY(new_top_row.bottom + 1, true)
                end
                -- Ensure the new top row is anchored as its top
                if new_top_row then
                    new_y = new_top_row.top
                end
            end
        end
        self._scroll_offset_y = new_y
        -- Step scrolling on the x-asis not yet implemented.
        -- We should find in the top row table:
        --   columns = { array of similar info about each button in that row's HorizontalGroup }
        -- Its absence would mean free scrolling on the x-axis.
        -- For now, allow free scrolling on the x-axis.
        self._scroll_offset_x = new_x
    else
        -- Free scrolling
        self._scroll_offset_x = self._scroll_offset_x + dx
        self._scroll_offset_y = self._scroll_offset_y + dy
    end

    if self._scroll_offset_x < 0 and not allow_overflow_x then
        self._scroll_offset_x = 0
    end
    if self._scroll_offset_y < 0 and not allow_overflow_y then
        self._scroll_offset_y = 0
    end
    if self._scroll_offset_x > self._max_scroll_offset_x and not allow_overflow_x then
        self._scroll_offset_x = self._max_scroll_offset_x
    end
    if self._scroll_offset_y > self._max_scroll_offset_y and not allow_overflow_y then
        self._scroll_offset_y = self._max_scroll_offset_y
    end
    self:_hideTruncatedGridItemsIfRequested()
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
    self._crop_h_limited = nil
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
    bb:blitFrom(self._bb, x + self._crop_dx, y, x + self._crop_dx, y, self._crop_w, self._crop_h_limited or self._crop_h)

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
    if self.swipe_full_view then
        -- Swipe by a full visible area, no matter the swipe distance
        if     direction == "north"     then self:_scrollBy(0, self._crop_h, true)
        elseif direction == "south"     then self:_scrollBy(0, -self._crop_h, true)
        elseif direction == "east"      then self:_scrollBy(-self._crop_w, 0, true)
        elseif direction == "west"      then self:_scrollBy(self._crop_w, 0, true)
        elseif direction == "northeast" then self:_scrollBy(-self._crop_w, self._crop_h, true)
        elseif direction == "northwest" then self:_scrollBy(self._crop_w, self._crop_h, true)
        elseif direction == "southeast" then self:_scrollBy(-self._crop_w, -self._crop_h, true)
        elseif direction == "southwest" then self:_scrollBy(self._crop_w, -self._crop_h, true)
        end
    else
        local distance = ges.distance
        local sq_distance = math.floor(math.sqrt(distance*distance/2))
        if     direction == "north"     then self:_scrollBy(0, distance, true)
        elseif direction == "south"     then self:_scrollBy(0, -distance, true)
        elseif direction == "east"      then self:_scrollBy(-distance, 0, true)
        elseif direction == "west"      then self:_scrollBy(distance, 0, true)
        elseif direction == "northeast" then self:_scrollBy(-sq_distance, sq_distance, true)
        elseif direction == "northwest" then self:_scrollBy(sq_distance, sq_distance, true)
        elseif direction == "southeast" then self:_scrollBy(-sq_distance, -sq_distance, true)
        elseif direction == "southwest" then self:_scrollBy(sq_distance, -sq_distance, true)
        end
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

function ScrollableContainer:_notifyParentOfPageScroll()
    -- For ButtonDialog's focus shenanigans, as we ourselves are not a FocusManager
    if self.show_parent and self.show_parent._onPageScrollToRow then
        local top_row = self:_getStepScrollRowAtY(self._scroll_offset_y, true)
        self.show_parent:_onPageScrollToRow(top_row and top_row.row_num or 1)
    end
end

function ScrollableContainer:onScrollPageUp()
    if not self._is_scrollable then
        return false
    end
    self:_scrollBy(0, -self._crop_h, true)
    self:_notifyParentOfPageScroll()
    return true
end

function ScrollableContainer:onScrollPageDown()
    if not self._is_scrollable then
        return false
    end
    self:_scrollBy(0, self._crop_h, true)
    self:_notifyParentOfPageScroll()
    return true
end

return ScrollableContainer
