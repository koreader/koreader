--[[--
A MovableContainer can have its content moved on screen
with Swipe/Hold/Pan.
Can optionally apply alpha transparency to its content.

With Swipe: the widget will be constrained to screen borders.
With Hold and pan, the widget can overflow the borders.

Hold with no move will reset the widget to its original position.
If the widget has not been moved or is already at its original
position, Hold will toggle between full opacity and 0.7 transparency.

This container's content is expected to not change its width and height.
]]

local BlitBuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Math = require("optmath")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local logger = require("logger")

local MovableContainer = InputContainer:new{
    -- Alpha value for subwidget transparency
    -- 0 = fully invisible, 1 = fully opaque (0.6 / 0.7 / 0.8 are some interesting values)
    alpha = nil,

    -- Move threshold (if move distance less than that, considered as a Hold
    -- with no movement, used for reseting move to original position)
    move_threshold = Screen:scaleBySize(5),

    -- Events to ignore (ie: ignore_events={"hold", "hold_release"})
    ignore_events = nil,

    -- Current move offset (use getMovedOffset()/setMovedOffset() to access them)
    _moved_offset_x = 0,
    _moved_offset_y = 0,
    -- Internal state between events
    _touch_pre_pan_was_inside = false,
    _moving = true,
    _move_relative_x = nil,
    _move_relative_y = nil,
    -- Original painting position from outer widget
    _orig_x = nil,
    _orig_y = nil,
}

function MovableContainer:init()
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
        -- ways a user can move things:
        --   Hold happens if he holds at start
        --   Pan happens if he doesn't hold at start, but holds at end
        --   Swipe happens if he doesn't hold at any moment
        -- Note that Swipe is tied to 0/45/90/135 degree... directions,
        -- which is somehow nice and gives a kind of magnetic move that
        -- stick the widget to some invisible rulers.
        -- (Touch is needed for accurate pan)
        self.ges_events = {}
        self.ges_events.MovableTouch = not ignore.touch and { GestureRange:new{ ges = "touch", range = range } } or nil
        self.ges_events.MovableSwipe = not ignore.swipe and { GestureRange:new{ ges = "swipe", range = range } } or nil
        self.ges_events.MovableHold = not ignore.hold and { GestureRange:new{ ges = "hold", range = range } } or nil
        self.ges_events.MovableHoldPan = not ignore.hold_pan and { GestureRange:new{ ges = "hold_pan", range = range } } or nil
        self.ges_events.MovableHoldRelease = not ignore.hold_release and { GestureRange:new{ ges = "hold_release", range = range } } or nil
        self.ges_events.MovablePan = not ignore.pan and { GestureRange:new{ ges = "pan", range = range } } or nil
        self.ges_events.MovablePanRelease = not ignore.pan_release and { GestureRange:new{ ges = "pan_release", range = range } } or nil
    end
end

function MovableContainer:getMovedOffset()
    return Geom:new{
        x = self._moved_offset_x,
        y = self._moved_offset_y,
    }
end

function MovableContainer:setMovedOffset(offset_point)
    if offset_point and offset_point.x and offset_point.y then
        self._moved_offset_x = offset_point.x
        self._moved_offset_y = offset_point.y
    end
end

function MovableContainer:paintTo(bb, x, y)
    if self[1] == nil then
        return
    end

    local content_size = self[1]:getSize()
    if not self.dimen then
        self.dimen = Geom:new{w = content_size.w, h = content_size.h}
    end

    self._orig_x = x
    self._orig_y = y
    -- We just need to shift painting by our _moved_offset_x/y
    self.dimen.x = x + self._moved_offset_x
    self.dimen.y = y + self._moved_offset_y

    if self.alpha then
        -- Create private blitbuffer for our child widget to paint to
        local private_bb = BlitBuffer.new(bb:getWidth(), bb:getHeight(), bb:getType())
        private_bb:fill(BlitBuffer.COLOR_WHITE) -- for round corners' outside to not stay black
        self[1]:paintTo(private_bb, self.dimen.x, self.dimen.y)
        -- And blend our private blitbuffer over the original bb
        bb:addblitFrom(private_bb, self.dimen.x, self.dimen.y, self.dimen.x, self.dimen.y,
            self.dimen.w, self.dimen.h, self.alpha)
        private_bb:free()
    else
        -- No alpha, just paint
        self[1]:paintTo(bb, self.dimen.x, self.dimen.y)
    end
end

function MovableContainer:_moveBy(dx, dy, restrict_to_screen)
    logger.dbg("MovableContainer:_moveBy:", dx, dy)
    if dx and dy then
        self._moved_offset_x = self._moved_offset_x + Math.round(dx)
        self._moved_offset_y = self._moved_offset_y + Math.round(dy)
        if restrict_to_screen then
            local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
            if self._orig_x + self._moved_offset_x < 0 then
                self._moved_offset_x = - self._orig_x
            end
            if self._orig_y + self._moved_offset_y < 0 then
                self._moved_offset_y = - self._orig_y
            end
            if self._orig_x + self._moved_offset_x + self.dimen.w > screen_w then
                self._moved_offset_x = screen_w - self._orig_x - self.dimen.w
            end
            if self._orig_y + self._moved_offset_y + self.dimen.h > screen_h then
                self._moved_offset_y = screen_h - self._orig_y - self.dimen.h
            end
        end
        -- if not restrict_to_screen, we don't need to check anything:
        -- we trust gestures' position and distances: if we started with our
        -- finger on widget, and moved our finger to screen border, a part
        -- of the widget should always be on the screen.
    else
        -- Not-moving Hold can be used to revert to original position
        if self._moved_offset_x == 0 and self._moved_offset_y == 0 then
            -- If we hold while already in initial position, take that
            -- as a wish to toggle between alpha or no-alpha
            if self.alpha then
                self.orig_alpha = self.alpha
                self.alpha = nil
            else
                self.alpha = self.orig_alpha or 0.7
                -- For testing: to visually see how different alpha
                -- values look: loop thru decreasing alpha values
                -- self.alpha = self.orig_alpha or 1.0
                -- if self.alpha > 0.55 then -- below 0.5 are too transparent
                --     self.alpha = self.alpha - 0.1
                -- else
                --     self.alpha = 0.9
                -- end
            end
        end
        self._moved_offset_x = 0
        self._moved_offset_y = 0
    end
    -- We need to have all widgets in the area between orig and move position
    -- redraw themselves
    local orig_dimen = self.dimen:copy() -- dimen before move/paintTo
    UIManager:setDirty("all", function()
        local update_region = orig_dimen:combine(self.dimen)
        logger.dbg("MovableContainer refresh region", update_region)
        return "ui", update_region
    end)
end

function MovableContainer:onMovableSwipe(_, ges)
    logger.dbg("MovableContainer:onMovableSwipe", ges)
    if not ges.pos:intersectWith(self.dimen) then
        -- with swipe, ges.pos is swipe's start position, which should
        -- be on us to consider it
        return false
    end
    self._moving = false -- could have been set by "pan" event received before "swipe"
    local direction = ges.direction
    local distance = ges.distance
    local sq_distance = math.floor(math.sqrt(distance*distance/2))
    -- Use restrict_to_screen for all move with Swipe for easy push to screen
    -- borders (user can Hold and pan if he wants them outside)
    if direction == "north" then self:_moveBy(0, -distance, true)
    elseif direction == "south" then self:_moveBy(0, distance, true)
    elseif direction == "east" then self:_moveBy(distance, 0, true)
    elseif direction == "west" then self:_moveBy(-distance, 0, true)
    elseif direction == "northeast" then self:_moveBy(sq_distance, -sq_distance, true)
    elseif direction == "northwest" then self:_moveBy(-sq_distance, -sq_distance, true)
    elseif direction == "southeast" then self:_moveBy(sq_distance, sq_distance, true)
    elseif direction == "southwest" then self:_moveBy(-sq_distance, sq_distance, true)
    end
    return true
end

function MovableContainer:onMovableTouch(_, ges)
    -- First "pan" event may already be outsise us, we need to
    -- remember any "touch" event on us prior to "pan"
    logger.dbg("MovableContainer:onMovableTouch", ges)
    if ges.pos:intersectWith(self.dimen) then
        self._touch_pre_pan_was_inside = true
        self._move_relative_x = ges.pos.x
        self._move_relative_y = ges.pos.y
    else
        self._touch_pre_pan_was_inside = false
    end
    return false
end

function MovableContainer:onMovableHold(_, ges)
    logger.dbg("MovableContainer:onMovableHold", ges)
    if ges.pos:intersectWith(self.dimen) then
        self._moving = true -- start of pan
        self._move_relative_x = ges.pos.x
        self._move_relative_y = ges.pos.y
        return true
    end
    return false
end

function MovableContainer:onMovableHoldPan(_, ges)
    logger.dbg("MovableContainer:onMovableHoldPan", ges)
    -- we may sometimes not see the "hold" event
    if ges.pos:intersectWith(self.dimen) or self._moving or self._touch_pre_pan_was_inside then
        self._touch_pre_pan_was_inside = false -- reset it
        self._moving = true
        return true
    end
    return false
end

function MovableContainer:onMovableHoldRelease(_, ges)
    logger.dbg("MovableContainer:onMovableHoldRelease", ges)
    if self._moving or self._touch_pre_pan_was_inside then
        self._moving = false
        if not self._move_relative_x or not self._move_relative_y then
            -- no previous event gave us accurate move info, ignore it
            return false
        end
        self._move_relative_x = ges.pos.x - self._move_relative_x
        self._move_relative_y = ges.pos.y - self._move_relative_y
        if math.abs(self._move_relative_x) < self.move_threshold and math.abs(self._move_relative_y) < self.move_threshold then
            -- Hold with no move (or less than self.move_threshold): use this to reposition to original position
            self:_moveBy()
        else
            self:_moveBy(self._move_relative_x, self._move_relative_y)
            self._move_relative_x = nil
            self._move_relative_y = nil
        end
        return true
    end
    return false
end

function MovableContainer:onMovablePan(_, ges)
    logger.dbg("MovableContainer:onMovablePan", ges)
    if ges.pos:intersectWith(self.dimen) or self._moving or self._touch_pre_pan_was_inside then
        self._touch_pre_pan_was_inside = false -- reset it
        self._moving = true
        self._move_relative_x = ges.relative.x
        self._move_relative_y = ges.relative.y
        return true
    end
    return false
end

function MovableContainer:onMovablePanRelease(_, ges)
    logger.dbg("MovableContainer:onMovablePanRelease", ges)
    if self._moving then
        self:_moveBy(self._move_relative_x, self._move_relative_y)
        self._moving = false
        self._move_relative_x = nil
        self._move_relative_y = nil
        return true
    end
    return false
end

return MovableContainer
