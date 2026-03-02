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
    -- Draw grid lines if enabled
    if self:shouldShowGridLines() then
        self:_drawGridLines(bb, bbox)
    end
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
    local logger = require("logger")
    local bbox = self.screen_bbox
    
    logger.info("=== ADJUST SCREEN BBOX ===")
    logger.info(string.format("Gesture: x=%.1f y=%.1f, relative=%s", ges.pos.x, ges.pos.y, tostring(relative)))
    logger.info(string.format("Current bbox: x0=%.1f y0=%.1f x1=%.1f y1=%.1f", bbox.x0, bbox.y0, bbox.x1, bbox.y1))
    
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
    
    local anchor_name = "unknown"
    if nearest == upper_left then
        anchor_name = "upper_left"
        upper_left.x = ges.pos.x
        upper_left.y = ges.pos.y
    elseif nearest == bottom_right then
        anchor_name = "bottom_right"
        bottom_right.x = ges.pos.x
        bottom_right.y = ges.pos.y
    elseif nearest == upper_right then
        anchor_name = "upper_right"
        bottom_right.x = ges.pos.x
        upper_left.y = ges.pos.y
    elseif nearest == bottom_left then
        anchor_name = "bottom_left"
        upper_left.x = ges.pos.x
        bottom_right.y = ges.pos.y
    elseif nearest == upper_center then
        anchor_name = "upper_center"
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
        anchor_name = "right_center"
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
        anchor_name = "bottom_center"
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
        anchor_name = "left_center"
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
        anchor_name = "center"
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
    
    logger.info(string.format("Nearest anchor: %s", anchor_name))
    logger.info(string.format("After anchor adjustment: x0=%.1f y0=%.1f x1=%.1f y1=%.1f",
        upper_left.x, upper_left.y, bottom_right.x, bottom_right.y))
    
    -- Apply smart crop snapping depending on mode
    local smart_enabled = self:isSmartCropEnabled()
    logger.info(string.format("Smart crop enabled: %s", tostring(smart_enabled)))
    
    if smart_enabled and nearest ~= center then
        local zoom_mode = self.parent_module and self.parent_module.orig_zoom_mode or self.view.zoom_mode
        logger.info(string.format("Zoom mode: %s", tostring(zoom_mode)))
        if zoom_mode == "content" then
            logger.info("Applying aspect ratio lock...")
            upper_left, bottom_right = self:applyAspectRatioLock(nearest, upper_left, bottom_right, bbox,
                {ul=upper_left, ur=upper_right, bl=bottom_left, br=bottom_right,
                 t=upper_center, b=bottom_center, l=left_center, r=right_center})
        elseif zoom_mode == "columns" or zoom_mode == "rows" then
            logger.info("Applying grid snap...")
            upper_left, bottom_right = self:applyGridSnap(nearest, upper_left, bottom_right, bbox,
                {ul=upper_left, ur=upper_right, bl=bottom_left, br=bottom_right,
                 t=upper_center, b=bottom_center, l=left_center, r=right_center})
        end
    end
    
    -- Round dimensions DOWN to avoid exceeding ideal grid size (prevents 2.001 columns)
    -- Calculate dimensions first, floor them, then reapply to coordinates
    local w = bottom_right.x - upper_left.x
    local h = bottom_right.y - upper_left.y
    local w_floored = math.floor(w)
    local h_floored = math.floor(h)
    
    -- Adjust coordinates to use floored dimensions (prefer keeping upper-left fixed)
    bottom_right.x = upper_left.x + w_floored
    bottom_right.y = upper_left.y + h_floored
    
    self.screen_bbox = {
        x0 = Math.round(upper_left.x),
        y0 = Math.round(upper_left.y),
        x1 = Math.round(bottom_right.x),
        y1 = Math.round(bottom_right.y)
    }
    
    logger.info(string.format("Final bbox: x0=%d y0=%d x1=%d y1=%d (w=%d h=%d)",
        self.screen_bbox.x0, self.screen_bbox.y0, self.screen_bbox.x1, self.screen_bbox.y1,
        self.screen_bbox.x1 - self.screen_bbox.x0, self.screen_bbox.y1 - self.screen_bbox.y0))
    logger.info("=== END ADJUST ===")

    UIManager:setDirty(self.ui, "ui")
end

-- Check if smart crop (aspect ratio lock) is enabled
function BBoxWidget:isSmartCropEnabled()
    if self.parent_module and self.parent_module.smart_crop_enabled then
        -- Also check that we're in a supported zoom mode
        local zoom_mode = self.parent_module.orig_zoom_mode or self.view.zoom_mode
        return zoom_mode and (zoom_mode == "content" or zoom_mode == "columns" or zoom_mode == "rows")
    end
    return false
end

-- Check if grid lines should be shown
-- Requires: smart crop enabled, show_grid_enabled, and columns/rows mode
function BBoxWidget:shouldShowGridLines()
    if not self.parent_module then return false end
    if not self.parent_module.smart_crop_enabled then return false end
    if not self.parent_module.show_grid_enabled then return false end
    local zoom_mode = self.parent_module.orig_zoom_mode or self.view.zoom_mode
    return zoom_mode and (zoom_mode == "columns" or zoom_mode == "rows")
end

-- Calculate grid layout for the current crop box
-- Returns table with: cols, rows, cell_w, cell_h, positions (array of {x, y} for each cell)
function BBoxWidget:getGridInfo()
    local zoom_mode = self.parent_module and self.parent_module.orig_zoom_mode or self.view.zoom_mode
    if not zoom_mode or (zoom_mode ~= "columns" and zoom_mode ~= "rows") then
        return nil
    end
    
    local bbox = self.screen_bbox
    if not bbox then return nil end
    
    local W_crop = bbox.x1 - bbox.x0
    local H_crop = bbox.y1 - bbox.y0
    if W_crop <= 0 or H_crop <= 0 then return nil end
    
    local W_screen, H_screen = self:getEffectiveViewport()
    if W_screen <= 0 or H_screen <= 0 then return nil end
    
    local OH = self:getOverlapH()
    local OV = self:getOverlapV()
    
    local C, R, cell_w_crop, cell_h_crop
    
    if zoom_mode == "columns" then
        -- Number of columns is fixed
        C = self:getGridColumnCount()
        -- Cell width in crop space
        local cell_portion_w = 1 / (1 + (C - 1) * (100 - OH) / 100)
        cell_w_crop = W_crop * cell_portion_w
        -- Zoom factor from crop cell to screen
        local zoom_factor = W_screen / cell_w_crop
        -- Cell height in crop space (screen height / zoom)
        cell_h_crop = H_screen / zoom_factor
        -- Calculate number of rows
        if OV == 0 then
            R = Math.round(H_crop / cell_h_crop)
        else
            R = Math.round(1 + ((H_crop / cell_h_crop) - 1) * 100 / (100 - OV))
        end
        if R < 1 then R = 1 end
    else -- rows mode
        -- Number of rows is fixed
        R = self:getGridRowCount()
        -- Cell height in crop space
        local cell_portion_h = 1 / (1 + (R - 1) * (100 - OV) / 100)
        cell_h_crop = H_crop * cell_portion_h
        -- Zoom factor from crop cell to screen
        local zoom_factor = H_screen / cell_h_crop
        -- Cell width in crop space (screen width / zoom)
        cell_w_crop = W_screen / zoom_factor
        -- Calculate number of columns
        if OH == 0 then
            C = Math.round(W_crop / cell_w_crop)
        else
            C = Math.round(1 + ((W_crop / cell_w_crop) - 1) * 100 / (100 - OH))
        end
        if C < 1 then C = 1 end
    end
    
    return {
        cols = C,
        rows = R,
        cell_w = cell_w_crop,
        cell_h = cell_h_crop,
        overlap_h = OH,
        overlap_v = OV,
    }
end

-- Draw grid lines inside the crop box
function BBoxWidget:_drawGridLines(bb, bbox)
    local grid = self:getGridInfo()
    if not grid then return end
    
    local C = grid.cols
    local R = grid.rows
    local OH = grid.overlap_h
    local OV = grid.overlap_v
    
    -- Calculate cell sizes and step sizes
    local W_crop = bbox.x1 - bbox.x0
    local H_crop = bbox.y1 - bbox.y0
    
    local cell_w, cell_h, step_x, step_y
    if C > 1 then
        cell_w = W_crop / (1 + (C - 1) * (100 - OH) / 100)
        step_x = cell_w * (100 - OH) / 100
    else
        cell_w = W_crop
        step_x = W_crop
    end
    if R > 1 then
        cell_h = H_crop / (1 + (R - 1) * (100 - OV) / 100)
        step_y = cell_h * (100 - OV) / 100
    else
        cell_h = H_crop
        step_y = H_crop
    end
    
    -- Draw vertical grid lines (column separators)
    -- For each column boundary, draw up to 2 lines if there's overlap
    for i = 1, C - 1 do
        local x_step = Math.round(bbox.x0 + i * step_x)
        -- First line: end of non-overlap region (start of overlap)
        bb:invertRect(x_step, bbox.y0 + self.linesize, self.linesize, H_crop - self.linesize)
        
        -- Second line: end of overlap region (if overlap exists)
        if OH > 0 then
            local x_overlap_end = Math.round(bbox.x0 + i * step_x + cell_w * OH / 100)
            if x_overlap_end > x_step then
                bb:invertRect(x_overlap_end, bbox.y0 + self.linesize, self.linesize, H_crop - self.linesize)
            end
        end
    end
    
    -- Draw horizontal grid lines (row separators)
    -- For each row boundary, draw up to 2 lines if there's overlap
    for i = 1, R - 1 do
        local y_step = Math.round(bbox.y0 + i * step_y)
        -- First line: end of non-overlap region (start of overlap)
        bb:invertRect(bbox.x0 + self.linesize, y_step, W_crop - self.linesize, self.linesize)
        
        -- Second line: end of overlap region (if overlap exists)
        if OV > 0 then
            local y_overlap_end = Math.round(bbox.y0 + i * step_y + cell_h * OV / 100)
            if y_overlap_end > y_step then
                bb:invertRect(bbox.x0 + self.linesize, y_overlap_end, W_crop - self.linesize, self.linesize)
            end
        end
    end
end

-- Get effective viewport dimensions, accounting for footer if visible
-- This matches the logic in ReaderZooming:getZoom()
function BBoxWidget:getEffectiveViewport()
    local logger = require("logger")
    
    -- Log all available dimension sources for debugging
    logger.info(string.format("=== VIEWPORT DIMENSIONS DEBUG ==="))
    logger.info(string.format("  Screen (framebuffer): %dx%d", Screen:getWidth(), Screen:getHeight()))
    if self.view.dimen then
        logger.info(string.format("  view.dimen: %dx%d", self.view.dimen.w, self.view.dimen.h))
    end
    if self.view.page_area then
        logger.info(string.format("  view.page_area: %dx%d", self.view.page_area.w, self.view.page_area.h))
    end
    if self.ui and self.ui.zooming and self.ui.zooming.dimen then
        logger.info(string.format("  ui.zooming.dimen: %dx%d", self.ui.zooming.dimen.w, self.ui.zooming.dimen.h))
    end
    
    -- Check footer visibility - use the ORIGINAL state from before entering crop mode
    -- because readercropping hides the footer during cropping
    local footer_is_visible = false
    if self.parent_module and self.parent_module.orig_view_footer_visibility ~= nil then
        footer_is_visible = self.parent_module.orig_view_footer_visibility
        logger.info(string.format("  Using parent_module.orig_view_footer_visibility: %s", tostring(footer_is_visible)))
    elseif self.ui and self.ui.view then
        footer_is_visible = self.ui.view.footer_visible
        logger.info(string.format("  Using ui.view.footer_visible: %s", tostring(footer_is_visible)))
    end
    
    if footer_is_visible and self.ui and self.ui.view and self.ui.view.footer then
        logger.info(string.format("  footer height: %d", self.ui.view.footer:getHeight()))
        if self.ui.view.footer.settings then
            logger.info(string.format("  footer reclaim_height: %s", tostring(self.ui.view.footer.settings.reclaim_height)))
        end
    end
    
    -- Use the actual screen (framebuffer) dimensions - this is what the reader actually renders to
    local w = Screen:getWidth()
    local h = Screen:getHeight()
    logger.info(string.format("  Using Screen framebuffer dimensions"))
    
    -- Subtract footer height if footer is visible and not reclaiming height
    if footer_is_visible and self.ui and self.ui.view and self.ui.view.footer 
       and self.ui.view.footer.settings and not self.ui.view.footer.settings.reclaim_height then
        local footer_h = self.ui.view.footer:getHeight()
        h = h - footer_h
        logger.info(string.format("  Subtracted footer height: %d", footer_h))
    end
    
    logger.info(string.format("  RESULT: %dx%d", w, h))
    logger.info("=== END VIEWPORT DEBUG ===")
    
    return w, h
end

-- Project point (mx,my) onto the line through (fx,fy) with slope K.
-- Uses the orthogonal projection matrix you provided.
-- Returns the new absolute coordinates (nx, ny).
function BBoxWidget:projectOntoAspectLine(fx, fy, mx, my, K)
    -- translate to origin
    local p1 = mx - fx
    local p2 = my - fy
    local denom = 1 + K * K
    if denom == 0 then return fx, fy end
    local p1_proj = (p1 + K * p2) / denom
    local p2_proj = (K * p1 + K * K * p2) / denom
    return fx + p1_proj, fy + p2_proj
end

-- Given original bounds (orig_w, orig_h) and current preferred sizes
-- (curr_w, curr_h) return a (w,h) with aspect ratio K that fits inside
-- orig and preserves the preferred dimension when possible.
function BBoxWidget:fitSizeWithin(orig_w, orig_h, curr_w, curr_h, K)
    -- try keeping width
    local target_h_from_w = curr_w * K
    if target_h_from_w > 0 and target_h_from_w <= orig_h then
        return curr_w, target_h_from_w
    end
    -- try keeping height
    local target_w_from_h = curr_h / K
    if target_w_from_h > 0 and target_w_from_h <= orig_w then
        return target_w_from_h, curr_h
    end
    -- neither fits, choose the maximal that fits inside orig
    if orig_w * K <= orig_h then
        local w = orig_w
        return w, w * K
    else
        local h = orig_h
        return h / K, h
    end
end

-- Center a rectangle of size (w,h) at (cx,cy) and clamp it inside orig bbox
-- orig is a table with x0,y0,x1,y1
function BBoxWidget:centerAndClamp(cx, cy, w, h, orig)
    local x0 = cx - w / 2
    local x1 = cx + w / 2
    local y0 = cy - h / 2
    local y1 = cy + h / 2
    if x0 < orig.x0 then x0 = orig.x0; x1 = x0 + w end
    if x1 > orig.x1 then x1 = orig.x1; x0 = x1 - w end
    if y0 < orig.y0 then y0 = orig.y0; y1 = y0 + h end
    if y1 > orig.y1 then y1 = orig.y1; y0 = y1 - h end
    return Math.round(x0), Math.round(y0), Math.round(x1), Math.round(y1)
end

-- Read overlap percentage from settings, fallback to zero
function BBoxWidget:getOverlapPerc(kind)
    local perc
    local ds = self.ui and self.ui.doc_settings
    if ds and ds.readSetting then
        if kind == "v" then
            perc = ds:readSetting("kopt_zoom_overlap_v")
        else
            perc = ds:readSetting("kopt_zoom_overlap_h")
        end
    end
    if not perc then
        -- Try view fields, else fallback to 0
        if kind == "v" and self.view.zoom_overlap_v then
            perc = self.view.zoom_overlap_v
        elseif kind == "h" and self.view.zoom_overlap_h then
            perc = self.view.zoom_overlap_h
        else
            perc = 0
        end
    end
    return tonumber(perc)
end

-- Grid getters: return the number of columns/rows and overlap percentages.
-- These are simple stubs so maintainers can integrate real values later.
function BBoxWidget:getGridColumnCount()
    -- TODO: Integrate with ReaderZooming:getNumberOf("columns", overlap)
    -- e.g. return math.floor((self.ui.zooming and self.ui.zooming:getNumberOf and
    --      self.ui.zooming:getNumberOf("columns", self:getOverlapPerc("h")) ) or 2 + 0.5)
    return 2
end

function BBoxWidget:getGridRowCount()
    -- TODO: Integrate with ReaderZooming:getNumberOf("rows", overlap)
    return 2
end

function BBoxWidget:getOverlapH()
    return tonumber(self:getOverlapPerc("h") or 0)
end

function BBoxWidget:getOverlapV()
    return tonumber(self:getOverlapPerc("v") or 0)
end

-- Compute snapped steps and ideal size given crop size, viewport, and overlap
function BBoxWidget:_snapSteps(crop_size, viewport_size, overlap_perc)
    local step_delta = viewport_size * (1 - (overlap_perc / 100))
    if step_delta <= 0 then
        return 1, viewport_size
    end
    local real = 1 + (crop_size - viewport_size) / step_delta
    if real < 1 then real = 1 end
    local snapped = Math.round(real)
    local ideal = viewport_size + (snapped - 1) * step_delta
    return snapped, ideal
end

-- Apply grid snapping for columns/rows modes
function BBoxWidget:applyGridSnap(nearest, upper_left, bottom_right, bbox, anchors)
    local zoom_mode = self.parent_module and self.parent_module.orig_zoom_mode or self.view.zoom_mode
    local logger = require("logger")
    
    logger.info("=== GRID SNAP START ===")
    logger.info(string.format("Mode: %s", zoom_mode))
    logger.info(string.format("Crop box BEFORE: x0=%.1f y0=%.1f x1=%.1f y1=%.1f", 
        upper_left.x, upper_left.y, bottom_right.x, bottom_right.y))
    logger.info(string.format("Original bbox: x0=%.1f y0=%.1f x1=%.1f y1=%.1f",
        bbox.x0, bbox.y0, bbox.x1, bbox.y1))
    
    -- Get page bounds
    local offset = self.view.state.offset
    local page_area = self.view.page_area
    local min_x = offset.x
    local min_y = offset.y
    local max_x = offset.x + page_area.w
    local max_y = offset.y + page_area.h
    
    logger.info(string.format("Page bounds: x[%.1f-%.1f] y[%.1f-%.1f]", min_x, max_x, min_y, max_y))
    
    -- Get viewport dimensions (accounting for footer)
    local W_screen, H_screen = self:getEffectiveViewport()
    logger.info(string.format("Viewport: %dx%d (effective, footer-adjusted)", W_screen, H_screen))
    
    -- Determine center
    local center_x = (upper_left.x + bottom_right.x) / 2
    local center_y = (upper_left.y + bottom_right.y) / 2
    
    -- Determine which anchor was moved (use reference comparison)
    local is_top_edge = (nearest == anchors.t)
    local is_bottom_edge = (nearest == anchors.b)
    local is_left_edge = (nearest == anchors.l)
    local is_right_edge = (nearest == anchors.r)
    local is_upper_left = (nearest == anchors.ul)
    local is_upper_right = (nearest == anchors.ur)
    local is_bottom_left = (nearest == anchors.bl)
    local is_bottom_right = (nearest == anchors.br)
    
    logger.info(string.format("Anchor: top=%s bottom=%s left=%s right=%s",
        tostring(is_top_edge), tostring(is_bottom_edge), tostring(is_left_edge), tostring(is_right_edge)))
    logger.info(string.format("Corner: UL=%s UR=%s BL=%s BR=%s",
        tostring(is_upper_left), tostring(is_upper_right), tostring(is_bottom_left), tostring(is_bottom_right)))

    if zoom_mode == "columns" then
        -- Step 1: C is fixed (number of columns), discover R (rows)
        -- For columns mode, we need to determine how many columns from the zooming module
        -- For now, assume C is derived from the view state or default to 2
        local C = self:getGridColumnCount()
        local OH = self:getOverlapH()
        local OV = self:getOverlapV()
        
        logger.info(string.format("Step 1: C (columns) = %d, OH = %.1f%%, OV = %.1f%%", C, OH, OV))
        
        -- Step 2: Calculate cell size in crop box
        local W_crop = bottom_right.x - upper_left.x
        local H_crop = bottom_right.y - upper_left.y
        logger.info(string.format("Step 2: Crop dimensions W=%.1f H=%.1f", W_crop, H_crop))
        
        -- Cell width in crop: portion taken by one cell
        local cell_portion_w = 1 / (1 + (C - 1) * (100 - OH) / 100)
        local cell_w_crop = W_crop * cell_portion_w
        logger.info(string.format("Step 2: Cell portion=%.4f, cell_w_crop=%.1f", cell_portion_w, cell_w_crop))
        
        -- Step 3: Translate to screen space to find zoom factor
        local zoom_factor = W_screen / cell_w_crop
        logger.info(string.format("Step 3: Zoom factor = W_screen/cell_w_crop = %.1f/%.1f = %.4f", 
            W_screen, cell_w_crop, zoom_factor))
        
        -- Step 3b: Calculate what cell height would be in screen space
        local cell_h_screen = H_screen
        local cell_h_crop = cell_h_screen / zoom_factor
        logger.info(string.format("Step 3b: cell_h_screen = %.1f, cell_h_crop = %.1f", cell_h_screen, cell_h_crop))
        
        -- Step 4: Calculate real number of rows
        local R_real
        if OV == 0 then
            R_real = H_crop / cell_h_crop
        else
            -- With overlap: H_crop = cell_h * (1 + (R-1) * (100-OV)/100)
            -- Solve for R: R = 1 + ((H_crop / cell_h) - 1) * 100 / (100-OV)
            R_real = 1 + ((H_crop / cell_h_crop) - 1) * 100 / (100 - OV)
        end
        logger.info(string.format("Step 4: R_real (rows) = %.4f", R_real))
        
        -- Step 5: Round to nearest integer
        local R_snapped = math.floor(R_real + 0.5)
        if R_snapped < 1 then R_snapped = 1 end
        logger.info(string.format("Step 5: R_snapped = %d", R_snapped))
        
        -- Step 6: Recompute ideal crop height for that integer
        local H_crop_ideal
        if OV == 0 then
            H_crop_ideal = R_snapped * cell_h_crop
        else
            H_crop_ideal = cell_h_crop * (1 + (R_snapped - 1) * (100 - OV) / 100)
        end
        logger.info(string.format("Step 6: H_crop_ideal = %.1f (was %.1f)", H_crop_ideal, H_crop))
        
        -- Step 7: Apply the adjustment
        -- Determine how to adjust based on which anchor was moved
        local anchor_desc = "unknown"
        if is_top_edge then
            anchor_desc = "top edge"
            bottom_right.y = upper_left.y + H_crop_ideal
        elseif is_bottom_edge then
            anchor_desc = "bottom edge"
            upper_left.y = bottom_right.y - H_crop_ideal
        elseif is_left_edge or is_right_edge then
            anchor_desc = is_left_edge and "left edge" or "right edge"
            -- Center vertically
            upper_left.y = center_y - H_crop_ideal / 2
            bottom_right.y = center_y + H_crop_ideal / 2
        elseif is_upper_left then
            anchor_desc = "upper-left corner"
            bottom_right.y = upper_left.y + H_crop_ideal
        elseif is_upper_right then
            anchor_desc = "upper-right corner"
            bottom_right.y = upper_left.y + H_crop_ideal
        elseif is_bottom_left then
            anchor_desc = "bottom-left corner"
            upper_left.y = bottom_right.y - H_crop_ideal
        elseif is_bottom_right then
            anchor_desc = "bottom-right corner"
            upper_left.y = bottom_right.y - H_crop_ideal
        else
            anchor_desc = "center (no adjustment)"
        end
        logger.info(string.format("Step 7: Adjusted via %s", anchor_desc))
        
        -- Edge case handling: check if it leaves PDF
        local attempt = 1
        while attempt <= 5 do
            logger.info(string.format("Attempt %d: y0=%.1f y1=%.1f (height=%.1f, rows=%d)", 
                attempt, upper_left.y, bottom_right.y, bottom_right.y - upper_left.y, R_snapped))
            
            if upper_left.y >= min_y and bottom_right.y <= max_y then
                logger.info("  -> Fits within bounds!")
                break
            end
            
            -- Try to shift
            if upper_left.y < min_y then
                local shift = min_y - upper_left.y
                logger.info(string.format("  -> Above bounds by %.1f, trying shift down", shift))
                upper_left.y = min_y
                bottom_right.y = upper_left.y + H_crop_ideal
            end
            if bottom_right.y > max_y then
                local shift = bottom_right.y - max_y
                logger.info(string.format("  -> Below bounds by %.1f, trying shift up", shift))
                bottom_right.y = max_y
                upper_left.y = bottom_right.y - H_crop_ideal
            end
            
            -- Check again
            if upper_left.y >= min_y and bottom_right.y <= max_y then
                logger.info("  -> Shift successful!")
                break
            end
            
            -- Still doesn't fit, reduce rows
            R_snapped = R_snapped - 1
            logger.info(string.format("  -> Still doesn't fit, reducing to %d rows", R_snapped))
            
            if R_snapped < 1 then
                logger.info("  -> Cannot fit even 1 row, adjusting width instead")
                -- Adjust width to make it narrower
                local W_crop_new = W_crop * 0.8
                local w_delta = W_crop - W_crop_new
                upper_left.x = upper_left.x + w_delta / 2
                bottom_right.x = bottom_right.x - w_delta / 2
                R_snapped = 1
                -- Recalculate for 1 row
                if OV == 0 then
                    H_crop_ideal = cell_h_crop
                else
                    H_crop_ideal = cell_h_crop
                end
                upper_left.y = center_y - H_crop_ideal / 2
                bottom_right.y = center_y + H_crop_ideal / 2
                break
            end
            
            -- Recalculate ideal height for reduced rows
            if OV == 0 then
                H_crop_ideal = R_snapped * cell_h_crop
            else
                H_crop_ideal = cell_h_crop * (1 + (R_snapped - 1) * (100 - OV) / 100)
            end
            
            -- Re-apply based on which anchor was moved
            if is_top_edge or is_upper_left or is_upper_right then
                bottom_right.y = upper_left.y + H_crop_ideal
            elseif is_bottom_edge or is_bottom_left or is_bottom_right then
                upper_left.y = bottom_right.y - H_crop_ideal
            else
                upper_left.y = center_y - H_crop_ideal / 2
                bottom_right.y = center_y + H_crop_ideal / 2
            end
            
            attempt = attempt + 1
        end
        
    elseif zoom_mode == "rows" then
        -- Similar logic for rows mode (snaps columns instead)
        local R = self:getGridRowCount()
        local OH = self:getOverlapH()
        local OV = self:getOverlapV()
        
        logger.info(string.format("Step 1: R (rows) = %d, OH = %.1f%%, OV = %.1f%%", R, OH, OV))
        
        local W_crop = bottom_right.x - upper_left.x
        local H_crop = bottom_right.y - upper_left.y
        logger.info(string.format("Step 2: Crop dimensions W=%.1f H=%.1f", W_crop, H_crop))
        
        local cell_portion_h = 1 / (1 + (R - 1) * (100 - OV) / 100)
        local cell_h_crop = H_crop * cell_portion_h
        logger.info(string.format("Step 2: Cell portion=%.4f, cell_h_crop=%.1f", cell_portion_h, cell_h_crop))
        
        local zoom_factor = H_screen / cell_h_crop
        logger.info(string.format("Step 3: Zoom factor = %.4f", zoom_factor))
        
        local cell_w_screen = W_screen
        local cell_w_crop = cell_w_screen / zoom_factor
        logger.info(string.format("Step 3b: cell_w_crop = %.1f", cell_w_crop))
        
        local C_real
        if OH == 0 then
            C_real = W_crop / cell_w_crop
        else
            C_real = 1 + ((W_crop / cell_w_crop) - 1) * 100 / (100 - OH)
        end
        logger.info(string.format("Step 4: C_real (columns) = %.4f", C_real))
        
        local C_snapped = math.floor(C_real + 0.5)
        if C_snapped < 1 then C_snapped = 1 end
        logger.info(string.format("Step 5: C_snapped = %d", C_snapped))
        
        local W_crop_ideal
        if OH == 0 then
            W_crop_ideal = C_snapped * cell_w_crop
        else
            W_crop_ideal = cell_w_crop * (1 + (C_snapped - 1) * (100 - OH) / 100)
        end
        logger.info(string.format("Step 6: W_crop_ideal = %.1f", W_crop_ideal))
        
        -- Apply adjustment based on which anchor was moved
        local anchor_desc = "unknown"
        if is_left_edge then
            anchor_desc = "left edge"
            bottom_right.x = upper_left.x + W_crop_ideal
        elseif is_right_edge then
            anchor_desc = "right edge"
            upper_left.x = bottom_right.x - W_crop_ideal
        elseif is_top_edge or is_bottom_edge then
            anchor_desc = is_top_edge and "top edge" or "bottom edge"
            upper_left.x = center_x - W_crop_ideal / 2
            bottom_right.x = center_x + W_crop_ideal / 2
        elseif is_upper_left then
            anchor_desc = "upper-left corner"
            bottom_right.x = upper_left.x + W_crop_ideal
        elseif is_upper_right then
            anchor_desc = "upper-right corner"
            upper_left.x = bottom_right.x - W_crop_ideal
        elseif is_bottom_left then
            anchor_desc = "bottom-left corner"
            bottom_right.x = upper_left.x + W_crop_ideal
        elseif is_bottom_right then
            anchor_desc = "bottom-right corner"
            upper_left.x = bottom_right.x - W_crop_ideal
        else
            anchor_desc = "center (no adjustment)"
        end
        logger.info(string.format("Step 7: Adjusted via %s", anchor_desc))
        
        -- Edge case handling for horizontal bounds
        local attempt = 1
        while attempt <= 5 do
            logger.info(string.format("Attempt %d: x0=%.1f x1=%.1f (width=%.1f, cols=%d)", 
                attempt, upper_left.x, bottom_right.x, bottom_right.x - upper_left.x, C_snapped))
            
            if upper_left.x >= min_x and bottom_right.x <= max_x then
                logger.info("  -> Fits within bounds!")
                break
            end
            
            if upper_left.x < min_x then
                upper_left.x = min_x
                bottom_right.x = upper_left.x + W_crop_ideal
            end
            if bottom_right.x > max_x then
                bottom_right.x = max_x
                upper_left.x = bottom_right.x - W_crop_ideal
            end
            
            if upper_left.x >= min_x and bottom_right.x <= max_x then
                logger.info("  -> Shift successful!")
                break
            end
            
            C_snapped = C_snapped - 1
            logger.info(string.format("  -> Reducing to %d columns", C_snapped))
            
            if C_snapped < 1 then
                logger.info("  -> Cannot fit 1 column, adjusting height")
                local H_crop_new = H_crop * 0.8
                local h_delta = H_crop - H_crop_new
                upper_left.y = upper_left.y + h_delta / 2
                bottom_right.y = bottom_right.y - h_delta / 2
                C_snapped = 1
                W_crop_ideal = cell_w_crop
                upper_left.x = center_x - W_crop_ideal / 2
                bottom_right.x = center_x + W_crop_ideal / 2
                break
            end
            
            if OH == 0 then
                W_crop_ideal = C_snapped * cell_w_crop
            else
                W_crop_ideal = cell_w_crop * (1 + (C_snapped - 1) * (100 - OH) / 100)
            end
            
            -- Re-apply based on which anchor was moved
            if is_left_edge or is_upper_left or is_bottom_left then
                bottom_right.x = upper_left.x + W_crop_ideal
            elseif is_right_edge or is_upper_right or is_bottom_right then
                upper_left.x = bottom_right.x - W_crop_ideal
            else
                upper_left.x = center_x - W_crop_ideal / 2
                bottom_right.x = center_x + W_crop_ideal / 2
            end
            
            attempt = attempt + 1
        end
    end
    
    logger.info(string.format("Crop box AFTER: x0=%.1f y0=%.1f x1=%.1f y1=%.1f", 
        upper_left.x, upper_left.y, bottom_right.x, bottom_right.y))
    logger.info("=== GRID SNAP END ===")
    
    return upper_left, bottom_right
end

-- Apply aspect ratio lock for Fit content mode
-- For edges: adjust the opposite dimension to maintain aspect ratio
-- For corners: project the dragged corner onto the aspect ratio line from the fixed corner
function BBoxWidget:applyAspectRatioLock(nearest, upper_left, bottom_right, original_bbox, anchors)
    local logger = require("logger")
    
    -- Calculate aspect ratio from the viewport (screen dimensions), not the crop box
    -- This ensures the crop box will fill the screen perfectly in Fit content mode
    -- Use effective viewport which accounts for footer
    local viewport_w, viewport_h = self:getEffectiveViewport()
    if viewport_w <= 0 or viewport_h <= 0 then
        return upper_left, bottom_right
    end
    local aspect_ratio = viewport_h / viewport_w
    
    logger.info(string.format("=== ASPECT RATIO LOCK: nearest=(%.1f,%.1f) orig_bbox=(%.1f,%.1f,%.1f,%.1f) aspect=%.3f ===",
        nearest.x, nearest.y, original_bbox.x0, original_bbox.y0, original_bbox.x1, original_bbox.y1, aspect_ratio))
    
    -- Determine which anchor was moved (use reference comparison)
    local is_top_edge = (nearest == anchors.t)
    local is_bottom_edge = (nearest == anchors.b)
    local is_left_edge = (nearest == anchors.l)
    local is_right_edge = (nearest == anchors.r)
    local is_upper_left = (nearest == anchors.ul)
    local is_upper_right = (nearest == anchors.ur)
    local is_bottom_left = (nearest == anchors.bl)
    local is_bottom_right = (nearest == anchors.br)
    
    logger.info(string.format("Edges: top=%s bottom=%s left=%s right=%s", 
        tostring(is_top_edge), tostring(is_bottom_edge), tostring(is_left_edge), tostring(is_right_edge)))
    logger.info(string.format("Corners: UL=%s UR=%s BL=%s BR=%s",
        tostring(is_upper_left), tostring(is_upper_right), tostring(is_bottom_left), tostring(is_bottom_right)))
    
    if is_top_edge or is_bottom_edge then
        logger.info("Handling vertical edge")
        -- Vertical edge moved: adjust width to maintain aspect ratio
        local new_h = bottom_right.y - upper_left.y
        local new_w = new_h / aspect_ratio
        local center_x_current = (upper_left.x + bottom_right.x) / 2
        upper_left.x = center_x_current - new_w / 2
        bottom_right.x = center_x_current + new_w / 2
    elseif is_left_edge or is_right_edge then
        logger.info("Handling horizontal edge")
        -- Horizontal edge moved: adjust height to maintain aspect ratio
        local new_w = bottom_right.x - upper_left.x
        local new_h = new_w * aspect_ratio
        local center_y_current = (upper_left.y + bottom_right.y) / 2
        upper_left.y = center_y_current - new_h / 2
        bottom_right.y = center_y_current + new_h / 2
    elseif is_upper_left or is_bottom_right then
        logger.info(string.format("Handling UL/BR corner (is_upper_left=%s)", tostring(is_upper_left)))
        -- Upper-left or bottom-right corner moved (UL↔BR diagonal, positive slope)
        local fixed_x, fixed_y, moved_x, moved_y
        if is_upper_left then
            -- Upper-left moved, bottom-right is fixed
            fixed_x = original_bbox.x1
            fixed_y = original_bbox.y1
            moved_x = upper_left.x
            moved_y = upper_left.y
        else
            -- Bottom-right moved, upper-left is fixed
            fixed_x = original_bbox.x0
            fixed_y = original_bbox.y0
            moved_x = bottom_right.x
            moved_y = bottom_right.y
        end
        
        -- Project onto aspect line with positive slope
        local K = aspect_ratio
        local new_x, new_y = self:projectOntoAspectLine(fixed_x, fixed_y, moved_x, moved_y, K)
        
        if is_upper_left then
            upper_left.x = new_x
            upper_left.y = new_y
        else
            bottom_right.x = new_x
            bottom_right.y = new_y
        end
    elseif is_upper_right or is_bottom_left then
        logger.info(string.format("Handling UR/BL corner (is_upper_right=%s)", tostring(is_upper_right)))
        -- Upper-right or bottom-left corner moved (UR↔BL diagonal, negative slope)
        local fixed_x, fixed_y, moved_x, moved_y
        if is_upper_right then
            -- Upper-right moved, bottom-left is fixed
            fixed_x = original_bbox.x0
            fixed_y = original_bbox.y1
            moved_x = bottom_right.x
            moved_y = upper_left.y
        else
            -- Bottom-left moved, upper-right is fixed
            fixed_x = original_bbox.x1
            fixed_y = original_bbox.y0
            moved_x = upper_left.x
            moved_y = bottom_right.y
        end
        
        -- Project onto aspect line with negative slope
        local K = -aspect_ratio
        local new_x, new_y = self:projectOntoAspectLine(fixed_x, fixed_y, moved_x, moved_y, K)
        
        if is_upper_right then
            bottom_right.x = new_x
            upper_left.y = new_y
        else
            upper_left.x = new_x
            bottom_right.y = new_y
        end
    else
        -- Fallback: should not happen if anchor detection is correct
        logger.warn(string.format("applyAspectRatioLock: Could not identify which anchor was moved! nearest=(%.1f,%.1f)", 
            nearest.x, nearest.y))
    end
    
    logger.info(string.format("=== ASPECT RATIO RESULT (before bounds check): ul=(%.1f,%.1f) br=(%.1f,%.1f) ===",
        upper_left.x, upper_left.y, bottom_right.x, bottom_right.y))
    
    -- Get page bounds
    local offset = self.view.state.offset
    local page_area = self.view.page_area
    local min_x = offset.x
    local min_y = offset.y
    local max_x = offset.x + page_area.w
    local max_y = offset.y + page_area.h
    
    logger.info(string.format("Page bounds: x=[%.1f-%.1f] y=[%.1f-%.1f]", min_x, max_x, min_y, max_y))
    
    -- First, try to shift the box to fit within bounds (preserve size)
    local w = bottom_right.x - upper_left.x
    local h = bottom_right.y - upper_left.y
    
    logger.info(string.format("Before shifting: x=[%.1f-%.1f] y=[%.1f-%.1f] (w=%.1f h=%.1f)",
        upper_left.x, bottom_right.x, upper_left.y, bottom_right.y, w, h))
    
    -- Try to shift vertically
    if upper_left.y < min_y then
        logger.info(string.format("  Top exceeds: %.1f < %.1f, shifting down", upper_left.y, min_y))
        upper_left.y = min_y
        bottom_right.y = upper_left.y + h
    end
    if bottom_right.y > max_y then
        logger.info(string.format("  Bottom exceeds: %.1f > %.1f, shifting up", bottom_right.y, max_y))
        bottom_right.y = max_y
        upper_left.y = bottom_right.y - h
    end
    
    -- Try to shift horizontally
    if upper_left.x < min_x then
        logger.info(string.format("  Left exceeds: %.1f < %.1f, shifting right", upper_left.x, min_x))
        upper_left.x = min_x
        bottom_right.x = upper_left.x + w
    end
    if bottom_right.x > max_x then
        logger.info(string.format("  Right exceeds: %.1f > %.1f, shifting left", bottom_right.x, max_x))
        bottom_right.x = max_x
        upper_left.x = bottom_right.x - w
    end
    
    logger.info(string.format("After shifting: x=[%.1f-%.1f] y=[%.1f-%.1f]",
        upper_left.x, bottom_right.x, upper_left.y, bottom_right.y))
    
    -- Check if still out of bounds after shifting
    local x_still_out = (upper_left.x < min_x) or (bottom_right.x > max_x)
    local y_still_out = (upper_left.y < min_y) or (bottom_right.y > max_y)
    
    logger.info(string.format("Still out of bounds: x=%s y=%s", tostring(x_still_out), tostring(y_still_out)))
    
    if x_still_out or y_still_out then
        -- Shifting alone couldn't fix it, need to resize while maintaining aspect ratio
        if y_still_out and not x_still_out then
            -- Y dimension is too large, clamp it and adjust width
            logger.info("  -> Y too large, clamping Y and adjusting width to maintain aspect ratio")
            upper_left.y = math.max(upper_left.y, min_y)
            bottom_right.y = math.min(bottom_right.y, max_y)
            local new_h = bottom_right.y - upper_left.y
            local new_w = new_h / aspect_ratio
            local center_x_current = (upper_left.x + bottom_right.x) / 2
            upper_left.x = center_x_current - new_w / 2
            bottom_right.x = center_x_current + new_w / 2
            logger.info(string.format("    Clamped y: [%.1f-%.1f], adjusted width for aspect: [%.1f-%.1f]",
                upper_left.y, bottom_right.y, upper_left.x, bottom_right.x))
            
        elseif x_still_out and not y_still_out then
            -- X dimension is too large, clamp it and adjust height
            logger.info("  -> X too large, clamping X and adjusting height to maintain aspect ratio")
            upper_left.x = math.max(upper_left.x, min_x)
            bottom_right.x = math.min(bottom_right.x, max_x)
            local new_w = bottom_right.x - upper_left.x
            local new_h = new_w * aspect_ratio
            local center_y_current = (upper_left.y + bottom_right.y) / 2
            upper_left.y = center_y_current - new_h / 2
            bottom_right.y = center_y_current + new_h / 2
            logger.info(string.format("    Clamped x: [%.1f-%.1f], adjusted height for aspect: [%.1f-%.1f]",
                upper_left.x, bottom_right.x, upper_left.y, bottom_right.y))
            
        else
            -- Both are still out (means box is larger than available space)
            -- Clamp both dimensions
            logger.info("  -> Both X and Y too large, clamping both")
            upper_left.x = math.max(upper_left.x, min_x)
            bottom_right.x = math.min(bottom_right.x, max_x)
            upper_left.y = math.max(upper_left.y, min_y)
            bottom_right.y = math.min(bottom_right.y, max_y)
            logger.info(string.format("    Clamped to: x=[%.1f-%.1f] y=[%.1f-%.1f]",
                upper_left.x, bottom_right.x, upper_left.y, bottom_right.y))
        end
    end
    
    logger.info(string.format("=== ASPECT RATIO FINAL: ul=(%.1f,%.1f) br=(%.1f,%.1f) ===",
        upper_left.x, upper_left.y, bottom_right.x, bottom_right.y))
    
    return upper_left, bottom_right
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
