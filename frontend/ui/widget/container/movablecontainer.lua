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

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Math = require("optmath")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local logger = require("logger")

local MovableContainer = InputContainer:extend{
    -- Alpha value for subwidget transparency
    -- 0 = fully invisible, 1 = fully opaque (0.6 / 0.7 / 0.8 are some interesting values)
    alpha = nil,

    -- Move threshold (if move distance less than that, considered as a Hold
    -- with no movement, used for resetting move to original position)
    move_threshold = Screen:scaleBySize(5),

    -- Events to ignore (ie: ignore_events={"hold", "hold_release"})
    ignore_events = nil,

    -- This can be passed if a MovableContainer should be present (as a no-op),
    -- so we don't need to change the widget layout.
    unmovable = nil,
    -- Whether this container should be movable with keyboard/dpad
    is_movable_with_keys = true,

    -- Initial position can be set related to an existing widget
    -- 'anchor' should be a Geom object (a widget's 'dimen', or a point), and
    -- can be a function returning that object
    anchor = nil,
    _anchor_ensured = nil,

    -- Current move offset (use getMovedOffset()/setMovedOffset() to access them)
    _moved_offset_x = 0,
    _moved_offset_y = 0,
    -- Internal state between events
    _touch_pre_pan_was_inside = false,
    _moving = false,
    _move_relative_x = nil,
    _move_relative_y = nil,
    -- Original painting position from outer widget
    _orig_x = nil,
    _orig_y = nil,

    -- We cache a compose canvas for alpha handling
    compose_bb = nil,
}

function MovableContainer:init()
    if Device:hasKeys() and self.is_movable_with_keys then
        if Device:hasKeyboard() or Device:hasScreenKB() then
            local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
            self.key_events.MovePositionTop     = { { modifier, "Up" },    event = "MovePosition", args = true }
            self.key_events.MovePositionBottom  = { { modifier, "Down" },  event = "MovePosition", args = false }
        end
    end
    if Device:isTouchDevice() and not self.unmovable then
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
        self.ges_events = {
            MovableTouch       = not ignore.touch        and { GestureRange:new{ ges = "touch", range = range } } or nil,
            MovableSwipe       = not ignore.swipe        and { GestureRange:new{ ges = "swipe", range = range } } or nil,
            MovableHold        = not ignore.hold         and { GestureRange:new{ ges = "hold", range = range } } or nil,
            MovableHoldPan     = not ignore.hold_pan     and { GestureRange:new{ ges = "hold_pan", range = range } } or nil,
            MovableHoldRelease = not ignore.hold_release and { GestureRange:new{ ges = "hold_release", range = range } } or nil,
            MovablePan         = not ignore.pan          and { GestureRange:new{ ges = "pan", range = range } } or nil,
            MovablePanRelease  = not ignore.pan_release  and { GestureRange:new{ ges = "pan_release", range = range } } or nil,
        }
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

function MovableContainer:ensureAnchor(x, y)
    local anchor_dimen = self.anchor
    local prefers_pop_down
    if type(self.anchor) == "function" then
        anchor_dimen, prefers_pop_down = self.anchor()
    end
    if not anchor_dimen then
        return
    end
    -- We try to find the best way to draw our content, depending on
    -- the size of the content and the space available on the screen.
    local content_w, content_h = self.dimen.w, self.dimen.h
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local left, top
    if BD.mirroredUILayout() then
        left = anchor_dimen.x + anchor_dimen.w - content_w
    else
        left = anchor_dimen.x
    end
    if left < 0 then
        left = 0
    elseif left + content_w > screen_w then
        left = screen_w - content_w
    end
    -- We prefer displaying above the anchor if there is room (so it looks like popping up)
    -- except if anchor() returned prefers_pop_down
    local h_remaining_if_above = anchor_dimen.y - content_h
    local h_remaining_if_below = screen_h - (anchor_dimen.y + anchor_dimen.h + content_h)
    if h_remaining_if_above >= 0 and not prefers_pop_down then
        -- Enough room above the anchor
        top = anchor_dimen.y - content_h
    elseif h_remaining_if_below >= 0 then
        -- Enough room below the anchor
        top = anchor_dimen.y + anchor_dimen.h
    elseif h_remaining_if_above >= 0 then
        -- Enough room above the anchor
        top = anchor_dimen.y - content_h
    else -- both negative
        if h_remaining_if_above >= h_remaining_if_below then
            top = 0
        else
            top = screen_h - content_h
        end
    end
    -- Ensure we show the top if we would overflow
    if top < 0 then
        top = 0
    end
    -- Make the initial offsets so that we display at left/top
    self._moved_offset_x = left - x
    self._moved_offset_y = top - y
end

function MovableContainer:paintTo(bb, x, y)
    if self[1] == nil then
        return
    end

    local content_size = self[1]:getSize()
    if not self.dimen then
        self.dimen = Geom:new{x = 0, y = 0, w = content_size.w, h = content_size.h}
    end

    self._orig_x = x
    self._orig_y = y
    -- If there is a widget passed as anchor, we need to set our initial position
    -- related to it. After that, we allow it to be moved like any other movable.
    if self.anchor and not self._anchor_ensured then
        self:ensureAnchor(x, y)
        self._anchor_ensured = true
    end
    -- We just need to shift painting by our _moved_offset_x/y
    self.dimen.x = x + self._moved_offset_x
    self.dimen.y = y + self._moved_offset_y

    if self.alpha then
        -- Create/Recreate the compose cache if we changed screen geometry
        if not self.compose_bb
            or self.compose_bb:getWidth() ~= bb:getWidth()
            or self.compose_bb:getHeight() ~= bb:getHeight()
        then
            if self.compose_bb then
                self.compose_bb:free()
            end
            -- create a canvas for our child widget to paint to
            self.compose_bb = Blitbuffer.new(bb:getWidth(), bb:getHeight(), bb:getType())
            -- fill it with our usual background color
            self.compose_bb:fill(Blitbuffer.COLOR_WHITE)
        end

        -- now, compose our child widget's content on our canvas
        -- NOTE: Unlike AlphaContainer, we aim to support interactive widgets.
        --       Most InputContainer-based widgets register their touchzones at paintTo time,
        --       and they rely on the target coordinates fed to paintTo for proper on-screen positioning.
        --       As such, we have to compose on a target bb sized canvas, at the expected coordinates.
        self[1]:paintTo(self.compose_bb, self.dimen.x, self.dimen.y)

        -- and finally blit the canvas to the target blitbuffer at the requested opacity level
        bb:addblitFrom(self.compose_bb, self.dimen.x, self.dimen.y, self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h, self.alpha)
    else
        -- No alpha, just paint
        self[1]:paintTo(bb, self.dimen.x, self.dimen.y)
    end
end

function MovableContainer:onCloseWidget()
    if self.compose_bb then
        self.compose_bb:free()
        self.compose_bb = nil
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
        -- Ensure the offsets are integers, to avoid refresh area glitches
        self._moved_offset_x = Math.round(self._moved_offset_x)
        self._moved_offset_y = Math.round(self._moved_offset_y)
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
    if not self.dimen then -- not yet painted
        return false
    end
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
    if not self.dimen then -- not yet painted
        return false
    end
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
    if not self.dimen then -- not yet painted
        return false
    end
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
    if not self.dimen then -- not yet painted
        return false
    end
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
    if not self.dimen then -- not yet painted
        return false
    end
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
    if not self.dimen then -- not yet painted
        return false
    end
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
    if not self.dimen then -- not yet painted
        return false
    end
    if self._moving then
        self:_moveBy(self._move_relative_x, self._move_relative_y)
        self._moving = false
        self._move_relative_x = nil
        self._move_relative_y = nil
        return true
    end
    return false
end

function MovableContainer:resetEventState()
    -- Cancel some internal moving-or-about-to-move state.
    -- Can be called explicitly to prevent bad widget interactions.
    self._touch_pre_pan_was_inside = false
    self._moving = false
end

function MovableContainer:onMovePosition(move_to_top)
    if not self.is_movable_with_keys then return false end
    local screen_h = Screen:getHeight()
    local dialog_h = self.dimen.h
    local padding = Size.padding.small
    local new_y
    if move_to_top then
        new_y = padding
    else -- move to the bottom
        new_y = screen_h - dialog_h - padding
    end
    -- Calculate the offset required to position the container at new_y
    local offset = Geom:new{
        x = self._moved_offset_x, -- keep current x offset
        y = new_y - self._orig_y,  -- set new y offset
    }
    self:setMovedOffset(offset)
    -- Force a complete screen redraw to ensure the old position is cleared
    UIManager:setDirty("all", "ui")
    return true
end

return MovableContainer
