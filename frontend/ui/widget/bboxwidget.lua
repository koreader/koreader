--[[--
BBoxWidget shows a bbox for page cropping.
]]

local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Math = require("optmath")
local Screen = Device.screen
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local BBoxWidget = InputContainer:extend{
    page_bbox = nil,
    screen_bbox = nil,
    linesize = Size.line.thick,
    fine_factor = 10,
    dimen = Geom:new(),
}

function BBoxWidget:init()
    self.page_bbox = self.document:getPageBBox(self.view.state.page)
    -- snapshot original screen bbox at init so we have a constraint to fit within
    self.original_screen_bbox = self:getScreenBBox(self.page_bbox)
    if Device:isTouchDevice() then
        self.ges_events = {
            TapAdjust = {
                GestureRange:new{
                    ges = "tap",
                    range = self.view.dimen,
                }
            },
            SwipeAdjust = {
                GestureRange:new{
                    ges = "swipe",
                    range = self.view.dimen,
                }
            },
            HoldAdjust = {
                GestureRange:new{
                    ges = "hold",
                    range = self.view.dimen,
                }
            },
            ConfirmAdjust = {
                GestureRange:new{
                    ges = "double_tap",
                    range = self.view.dimen,
                }
            }
        }
    else
        self._confirm_stage = 1 -- 1 for left-top, 2 for right-bottom
        self.key_events.MoveIndicatorUp    = { { "Up" },    event="MoveIndicator", args = { 0, -1 } }
        self.key_events.MoveIndicatorDown  = { { "Down" },  event="MoveIndicator", args = { 0, 1 } }
        self.key_events.MoveIndicatorLeft  = { { "Left" },  event="MoveIndicator", args = { -1, 0 } }
        self.key_events.MoveIndicatorRight = { { "Right" }, event="MoveIndicator", args = { 1, 0 } }
        -- Keyboard shortcut to open crop settings (calls back to parent module if provided)
        self.key_events.ShowCropSettings = { { "S" }, event = "ShowCropSettings" }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.Select = { { "Press" } }
    end
end

function BBoxWidget:getSize()
    return self.view.dimen
end

function BBoxWidget:paintTo(bb, x, y)
    self.dimen = self.view.dimen:copy()
    self.dimen.x, self.dimen.y = x, y

    -- As getScreenBBox uses view states, screen_bbox initialization is postponed.
    self.screen_bbox = self.screen_bbox or self:getScreenBBox(self.page_bbox)
    local bbox = self.screen_bbox
    -- top edge
    bb:invertRect(bbox.x0 + self.linesize, bbox.y0, bbox.x1 - bbox.x0, self.linesize)
    -- bottom edge
    bb:invertRect(bbox.x0 + self.linesize, bbox.y1, bbox.x1 - bbox.x0 - self.linesize, self.linesize)
    -- left edge
    bb:invertRect(bbox.x0, bbox.y0, self.linesize, bbox.y1 - bbox.y0 + self.linesize)
    -- right edge
    bb:invertRect(bbox.x1, bbox.y0 + self.linesize, self.linesize, bbox.y1 - bbox.y0)
    -- center crosshair (always visible)
    local center_x = Math.round((bbox.x0 + bbox.x1) / 2)
    local center_y = Math.round((bbox.y0 + bbox.y1) / 2)
    self:_drawIndicator(bb, center_x, center_y)
    if self._confirm_stage == 1 then
        -- left top indicator
        self:_drawIndicator(bb, bbox.x0, bbox.y0)
    elseif self._confirm_stage == 2 then
        -- right bottom indicator
        self:_drawIndicator(bb, bbox.x1, bbox.y1)
    end
end

function BBoxWidget:_drawIndicator(bb, x, y)
    local rect = Geom:new({
        x = x - Size.item.height_default / 2,
        y = y - Size.item.height_default / 2,
        w = Size.item.height_default,
        h = Size.item.height_default,
    })
    -- paint big cross line +
    bb:invertRect(
        rect.x,
        rect.y + rect.h / 2 - Size.border.thick / 2,
        rect.w,
        Size.border.thick
    )
    bb:invertRect(
        rect.x + rect.w / 2 - Size.border.thick / 2,
        rect.y,
        Size.border.thick,
        rect.h
    )
end

-- transform page bbox to screen bbox
function BBoxWidget:getScreenBBox(page_bbox)
    local bbox = {}
    local scale = self.view.state.zoom
    local screen_offset = self.view.state.offset
    bbox.x0 = Math.round(page_bbox.x0 * scale + screen_offset.x)
    bbox.y0 = Math.round(page_bbox.y0 * scale + screen_offset.y)
    bbox.x1 = Math.round(page_bbox.x1 * scale + screen_offset.x)
    bbox.y1 = Math.round(page_bbox.y1 * scale + screen_offset.y)
    return bbox
end

-- transform screen bbox to page bbox
function BBoxWidget:getPageBBox(screen_bbox)
    local bbox = {}
    local scale = self.view.state.zoom
    local screen_offset = self.view.state.offset
    bbox.x0 = Math.round((screen_bbox.x0 - screen_offset.x) / scale)
    bbox.y0 = Math.round((screen_bbox.y0 - screen_offset.y) / scale)
    bbox.x1 = Math.round((screen_bbox.x1 - screen_offset.x) / scale)
    bbox.y1 = Math.round((screen_bbox.y1 - screen_offset.y) / scale)
    return bbox
end

function BBoxWidget:inPageArea(ges)
    local offset = self.view.state.offset
    local page_area = self.view.page_area
    local page_dimen = Geom:new{ x = offset.x, y = offset.y, h = page_area.h, w = page_area.w}
    return not ges.pos:notIntersectWith(page_dimen)
end

function BBoxWidget:adjustScreenBBox(ges, relative)
    if not self:inPageArea(ges) then return end
    local bbox = self.screen_bbox
    local upper_left = Geom:new{ x = bbox.x0, y = bbox.y0}
    local upper_right = Geom:new{ x = bbox.x1, y = bbox.y0}
    local bottom_left = Geom:new{ x = bbox.x0, y = bbox.y1}
    local bottom_right = Geom:new{ x = bbox.x1, y = bbox.y1}
    local upper_center = Geom:new{ x = (bbox.x0 + bbox.x1) / 2, y = bbox.y0}
    local bottom_center = Geom:new{ x = (bbox.x0 + bbox.x1) / 2, y = bbox.y1}
    local right_center = Geom:new{ x = bbox.x1, y = (bbox.y0 + bbox.y1) / 2}
    local left_center = Geom:new{ x = bbox.x0, y = (bbox.y0 + bbox.y1) / 2}
    local center = Geom:new{ x = (bbox.x0 + bbox.x1) / 2, y = (bbox.y0 + bbox.y1) / 2}
    local anchors = {
        upper_left, upper_center,     upper_right,
        left_center, center,         right_center,
        bottom_left, bottom_center, bottom_right,
    }
    local _, nearest = Math.tmin(anchors, function(a,b)
        return a:distance(ges.pos) > b:distance(ges.pos)
    end)
    if nearest == upper_left then
        upper_left.x = ges.pos.x
        upper_left.y = ges.pos.y
    elseif nearest == bottom_right then
        bottom_right.x = ges.pos.x
        bottom_right.y = ges.pos.y
    elseif nearest == upper_right then
        bottom_right.x = ges.pos.x
        upper_left.y = ges.pos.y
    elseif nearest == bottom_left then
        upper_left.x = ges.pos.x
        bottom_right.y = ges.pos.y
    elseif nearest == upper_center then
        if relative then
            local delta = 0
            if ges.direction == "north" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "south" then
                delta = ges.distance / self.fine_factor
            end
            upper_left.y = upper_left.y + delta
        else
            upper_left.y = ges.pos.y
        end
    elseif nearest == right_center then
        if relative then
            local delta = 0
            if ges.direction == "west" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "east" then
                delta = ges.distance / self.fine_factor
            end
            bottom_right.x = bottom_right.x + delta
        else
            bottom_right.x = ges.pos.x
        end
    elseif nearest == bottom_center then
        if relative then
            local delta = 0
            if ges.direction == "north" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "south" then
                delta = ges.distance / self.fine_factor
            end
            bottom_right.y = bottom_right.y + delta
        else
            bottom_right.y = ges.pos.y
        end
    elseif nearest == left_center then
        if relative then
            local delta = 0
            if ges.direction == "west" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "east" then
                delta = ges.distance / self.fine_factor
            end
            upper_left.x = upper_left.x + delta
        else
            upper_left.x = ges.pos.x
        end
    elseif nearest == center then
        -- Move entire box while preserving width/height. Clamp to page area.
        local w = bbox.x1 - bbox.x0
        local h = bbox.y1 - bbox.y0
        local new_cx = ges.pos.x
        local new_cy = ges.pos.y

        upper_left.x = new_cx - w / 2
        upper_left.y = new_cy - h / 2
        bottom_right.x = new_cx + w / 2
        bottom_right.y = new_cy + h / 2

        -- Clamp to page boundaries (page area is in screen coords)
        local offset = self.view.state.offset
        local page_area = self.view.page_area
        local min_x = offset.x
        local min_y = offset.y
        local max_x = offset.x + page_area.w
        local max_y = offset.y + page_area.h

        if upper_left.x < min_x then
            upper_left.x = min_x
            bottom_right.x = upper_left.x + w
        end
        if bottom_right.x > max_x then
            bottom_right.x = max_x
            upper_left.x = bottom_right.x - w
        end
        if upper_left.y < min_y then
            upper_left.y = min_y
            bottom_right.y = upper_left.y + h
        end
        if bottom_right.y > max_y then
            bottom_right.y = max_y
            upper_left.y = bottom_right.y - h
        end
    end
    
    -- Apply aspect ratio locking if smart crop is enabled (Fit content mode only)
    if self:isSmartCropEnabled() and nearest ~= center then
        upper_left, bottom_right = self:applyAspectRatioLock(
            nearest, 
            upper_left, 
            bottom_right, 
            bbox
        )
    end
    
    self.screen_bbox = {
        x0 = Math.round(upper_left.x),
        y0 = Math.round(upper_left.y),
        x1 = Math.round(bottom_right.x),
        y1 = Math.round(bottom_right.y)
    }

    UIManager:setDirty(self.ui, "ui")
end

-- Check if smart crop (aspect ratio lock) is enabled
function BBoxWidget:isSmartCropEnabled()
    if self.parent_module and self.parent_module.smart_crop_enabled then
        -- Also check that we're in a content zoom mode
        local zoom_mode = self.parent_module.orig_zoom_mode or self.view.zoom_mode
        return zoom_mode and (zoom_mode:match("^content") ~= nil)
    end
    return false
end

-- Apply aspect ratio lock for Fit content mode
-- For edges: adjust the opposite dimension to maintain aspect ratio
-- For corners: project the dragged corner onto the aspect ratio line from the fixed corner
function BBoxWidget:applyAspectRatioLock(nearest, upper_left, bottom_right, original_bbox)
    -- Calculate aspect ratio from the viewport (screen dimensions), not the crop box
    -- This ensures the crop box will fill the screen perfectly in Fit content mode
    local viewport_w = self.view.dimen.w
    local viewport_h = self.view.dimen.h
    if viewport_w <= 0 or viewport_h <= 0 then
        return upper_left, bottom_right
    end
    local aspect_ratio = viewport_h / viewport_w
    
    -- Determine which anchor was moved
    local center_x = (original_bbox.x0 + original_bbox.x1) / 2
    local center_y = (original_bbox.y0 + original_bbox.y1) / 2
    
    -- Check if nearest is an edge anchor (top, bottom, left, right)
    local is_top_edge = (nearest.y == original_bbox.y0) and (math.abs(nearest.x - center_x) < 1)
    local is_bottom_edge = (nearest.y == original_bbox.y1) and (math.abs(nearest.x - center_x) < 1)
    local is_left_edge = (nearest.x == original_bbox.x0) and (math.abs(nearest.y - center_y) < 1)
    local is_right_edge = (nearest.x == original_bbox.x1) and (math.abs(nearest.y - center_y) < 1)
    
    if is_top_edge or is_bottom_edge then
        -- Vertical edge moved: adjust width to maintain aspect ratio
        local new_h = bottom_right.y - upper_left.y
        local new_w = new_h / aspect_ratio
        local center_x_current = (upper_left.x + bottom_right.x) / 2
        upper_left.x = center_x_current - new_w / 2
        bottom_right.x = center_x_current + new_w / 2
    elseif is_left_edge or is_right_edge then
        -- Horizontal edge moved: adjust height to maintain aspect ratio
        local new_w = bottom_right.x - upper_left.x
        local new_h = new_w * aspect_ratio
        local center_y_current = (upper_left.y + bottom_right.y) / 2
        upper_left.y = center_y_current - new_h / 2
        bottom_right.y = center_y_current + new_h / 2
    else
        -- Corner was moved: project onto aspect ratio line through the fixed corner
        -- Determine which corner was moved by checking which position changed the most
        local ul_dist = math.abs(upper_left.x - original_bbox.x0) + math.abs(upper_left.y - original_bbox.y0)
        local br_dist = math.abs(bottom_right.x - original_bbox.x1) + math.abs(bottom_right.y - original_bbox.y1)
        local ur_dist = math.abs(bottom_right.x - original_bbox.x1) + math.abs(upper_left.y - original_bbox.y0)
        local bl_dist = math.abs(upper_left.x - original_bbox.x0) + math.abs(bottom_right.y - original_bbox.y1)
        
        local fixed_x, fixed_y, moved_x, moved_y
        local slope_sign -- +1 for upper-left/bottom-right diagonal, -1 for upper-right/bottom-left diagonal
        
        -- Find which corner moved the most (that's the one that was dragged)
        if ul_dist > br_dist and ul_dist > ur_dist and ul_dist > bl_dist then
            -- Upper-left corner moved, bottom-right is fixed
            fixed_x = original_bbox.x1
            fixed_y = original_bbox.y1
            moved_x = upper_left.x
            moved_y = upper_left.y
            slope_sign = 1
        elseif br_dist > ul_dist and br_dist > ur_dist and br_dist > bl_dist then
            -- Bottom-right corner moved, upper-left is fixed
            fixed_x = original_bbox.x0
            fixed_y = original_bbox.y0
            moved_x = bottom_right.x
            moved_y = bottom_right.y
            slope_sign = 1
        elseif ur_dist > ul_dist and ur_dist > br_dist and ur_dist > bl_dist then
            -- Upper-right corner moved, bottom-left is fixed
            fixed_x = original_bbox.x0
            fixed_y = original_bbox.y1
            moved_x = bottom_right.x
            moved_y = upper_left.y
            slope_sign = -1
        else
            -- Bottom-left corner moved, upper-right is fixed
            fixed_x = original_bbox.x1
            fixed_y = original_bbox.y0
            moved_x = upper_left.x
            moved_y = bottom_right.y
            slope_sign = -1
        end
        
        -- Translate to make the line go through origin
        local p1 = moved_x - fixed_x
        local p2 = moved_y - fixed_y
        
        -- The line has slope K = aspect_ratio * slope_sign
        -- Using the projection formula: p* = P * p
        local K = aspect_ratio * slope_sign
        local denom = 1 + K * K
        
        -- p1* = (p1 + K * p2) / (1 + K^2)
        -- p2* = (K * p1 + K^2 * p2) / (1 + K^2)
        local p1_proj = (p1 + K * p2) / denom
        local p2_proj = (K * p1 + K * K * p2) / denom
        
        -- Translate back to fixed corner position
        local new_x = fixed_x + p1_proj
        local new_y = fixed_y + p2_proj
        
        -- Update the appropriate corners
        if ul_dist > br_dist and ul_dist > ur_dist and ul_dist > bl_dist then
            upper_left.x = new_x
            upper_left.y = new_y
        elseif br_dist > ul_dist and br_dist > ur_dist and br_dist > bl_dist then
            bottom_right.x = new_x
            bottom_right.y = new_y
        elseif ur_dist > ul_dist and ur_dist > br_dist and ur_dist > bl_dist then
            bottom_right.x = new_x
            upper_left.y = new_y
        else
            upper_left.x = new_x
            bottom_right.y = new_y
        end
    end
    
    return upper_left, bottom_right
end

-- Resize and center the current crop to match viewport aspect ratio while
-- staying within the original crop bounds. Keeps the crop centered around
-- its previous center and shrinks only the offending dimension where needed.
function BBoxWidget:applySmartCropFull()
    local orig = self.original_screen_bbox or self:getScreenBBox(self.page_bbox)
    if not orig then return end

    local curr = self.screen_bbox or orig
    local center_x = (curr.x0 + curr.x1) / 2
    local center_y = (curr.y0 + curr.y1) / 2

    local viewport_w = self.view.dimen.w
    local viewport_h = self.view.dimen.h
    if viewport_w <= 0 or viewport_h <= 0 then return end
    local K = viewport_h / viewport_w

    local orig_w = orig.x1 - orig.x0
    local orig_h = orig.y1 - orig.y0
    local curr_w = curr.x1 - curr.x0
    local curr_h = curr.y1 - curr.y0

    -- Preferred: keep the non-offending dimension (try width first)
    local target_h_from_w = curr_w * K
    local new_w, new_h
    if target_h_from_w > 0 and target_h_from_w <= orig_h then
        -- keep width, adjust height
        new_w = curr_w
        new_h = target_h_from_w
    else
        -- try keeping height
        local target_w_from_h = curr_h / K
        if target_w_from_h > 0 and target_w_from_h <= orig_w then
            new_w = target_w_from_h
            new_h = curr_h
        else
            -- neither fits with current dimensions; choose maximum that fits inside original
            if orig_w * K <= orig_h then
                new_w = orig_w
                new_h = new_w * K
            else
                new_h = orig_h
                new_w = new_h / K
            end
        end
    end

    -- Center and clamp inside original bounds
    local x0 = center_x - new_w / 2
    local x1 = center_x + new_w / 2
    local y0 = center_y - new_h / 2
    local y1 = center_y + new_h / 2

    if x0 < orig.x0 then x0 = orig.x0; x1 = x0 + new_w end
    if x1 > orig.x1 then x1 = orig.x1; x0 = x1 - new_w end
    if y0 < orig.y0 then y0 = orig.y0; y1 = y0 + new_h end
    if y1 > orig.y1 then y1 = orig.y1; y0 = y1 - new_h end

    self.screen_bbox = {
        x0 = Math.round(x0),
        y0 = Math.round(y0),
        x1 = Math.round(x1),
        y1 = Math.round(y1),
    }

    UIManager:setDirty(self.ui, "ui")
end

function BBoxWidget:onMoveIndicator(args)
    local dx, dy = unpack(args)
    local bbox = self.screen_bbox
    local move_distance = Size.item.height_default / 4
    local half_indicator_size = move_distance * 2
    -- mark edges dirty to redraw
    -- top edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - move_distance,
        y = bbox.y0 - move_distance,
        w = bbox.x1 - bbox.x0 + move_distance,
        h = move_distance * 2
    })
    -- left edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - move_distance,
        y = bbox.y0 - move_distance,
        w = move_distance * 2,
        h = bbox.y1 - bbox.y0 + move_distance,
    })
    -- right edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x1 - move_distance,
        y = bbox.y0 - move_distance,
        w = move_distance * 2,
        h = bbox.y1 - bbox.y0 + move_distance,
    })
    -- bottom edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - move_distance,
        y = bbox.y1 - move_distance,
        w = bbox.x1 - bbox.x0 + move_distance,
        h = move_distance * 2,
    })
    -- left top indicator
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - half_indicator_size - move_distance,
        y = bbox.y0 - half_indicator_size - move_distance,
        w = half_indicator_size * 2 + move_distance,
        h = half_indicator_size * 2 + move_distance
    })
    -- bottom right indicator
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x1 - half_indicator_size,
        y = bbox.y1 - half_indicator_size,
        w = half_indicator_size * 2 + move_distance,
        h = half_indicator_size * 2 + move_distance
    })
    if self._confirm_stage == 1 then
        local x = self.screen_bbox.x0 + dx * Size.item.height_default / 4
        local y = self.screen_bbox.y0 + dy * Size.item.height_default / 4
        local max_x = self.screen_bbox.x1 - Size.item.height_default
        local max_y = self.screen_bbox.y1 - Size.item.height_default
        x = (x > 0 and x) or 0
        x = (x < max_x and x) or max_x
        y = (y > 0 and y) or 0
        y = (y < max_y and y) or max_y
        self.screen_bbox.x0 = Math.round(x)
        self.screen_bbox.y0 = Math.round(y)
        return true
    elseif self._confirm_stage == 2 then
        local x = self.screen_bbox.x1 + dx * Size.item.height_default / 4
        local y = self.screen_bbox.y1 + dy * Size.item.height_default / 4
        local min_x = self.screen_bbox.x0 + Size.item.height_default
        local min_y = self.screen_bbox.y0 + Size.item.height_default
        x = (x > min_x and x) or min_x
        x = (x < Screen:getWidth() and x) or Screen:getWidth()
        y = (y > min_y and y) or min_y
        y = (y < Screen:getHeight() and y) or Screen:getHeight()
        self.screen_bbox.x1 = Math.round(x)
        self.screen_bbox.y1 = Math.round(y)
        return true
    end
end

function BBoxWidget:getModifiedPageBBox()
    return self:getPageBBox(self.screen_bbox)
end

function BBoxWidget:onTapAdjust(arg, ges)
    self:adjustScreenBBox(ges)
    return true
end

function BBoxWidget:onSwipeAdjust(arg, ges)
    self:adjustScreenBBox(ges, true)
    return true
end

function BBoxWidget:onHoldAdjust(arg, ges)
    --- @fixme this is a dirty hack to disable hold gesture in page cropping
    -- since Kobo devices may append hold gestures to each swipe gesture rendering
    -- relative replacement impossible. See koreader/koreader#987 at Github.
    --self:adjustScreenBBox(ges)
    return true
end

function BBoxWidget:onConfirmAdjust(arg, ges)
    if self:inPageArea(ges) then
        self.ui:handleEvent(Event:new("ConfirmPageCrop"))
    end
    return true
end

function BBoxWidget:onClose()
    self.ui:handleEvent(Event:new("CancelPageCrop"))
    return true
end

function BBoxWidget:onSelect()
    if not self._confirm_stage or self._confirm_stage == 2 then
        self.ui:handleEvent(Event:new("ConfirmPageCrop"))
    else
        local bbox = self.screen_bbox
        self._confirm_stage = self._confirm_stage + 1
        -- left top indicator
        UIManager:setDirty(self.ui, "ui", Geom:new{
            x = bbox.x0 - Size.item.height_default / 2,
            y = bbox.y0 - Size.item.height_default / 2,
            w = Size.item.height_default,
            h = Size.item.height_default,
        })
        -- right bottom indicator
        UIManager:setDirty(self.ui, "ui", Geom:new{
            x = bbox.x1 - Size.item.height_default / 2,
            y = bbox.y1 - Size.item.height_default / 2,
            w = Size.item.height_default,
            h = Size.item.height_default,
        })
    end
    return true
end

function BBoxWidget:onShowCropSettings()
    -- If the parent module is provided (ReaderCropping passes itself as parent_module), delegate to it.
    if self.parent_module and type(self.parent_module.onShowCropSettings) == "function" then
        return self.parent_module:onShowCropSettings()
    end
    -- Otherwise, try to emit a UI event for other handlers (no-op if unhandled)
    if self.ui and self.ui.handleEvent then
        self.ui:handleEvent(Event:new("ShowCropSettings"))
        return true
    end
    return false
end


return BBoxWidget
