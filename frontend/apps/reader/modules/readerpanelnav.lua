--[[--
Panel navigation module for comics/manga.

This module enables panel-by-panel navigation in paged documents (PDF, DjVu).
Panels are detected automatically using image analysis and can be navigated
in the order specified by zoom_direction_settings (reading direction).

@module readerpanelnav
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local ReaderPanelNav = InputContainer:extend{
    name = "readerpanelnav",
    -- Panel navigation state
    panel_nav_enabled = false,
    current_page_panels = nil,  -- cached panels for current page
    current_panel_index = 0,    -- 0 means no panel selected (full page view)
    panels_page = nil,          -- page number for cached panels
    _panel_viewer = nil,        -- current ImageViewer widget (reused for performance)

    -- Visualization options
    highlight_current_panel = false, -- highlight only the current panel
    show_panel_boxes = false,   -- show bounding boxes around all detected panels (debug)

    -- Panel reading direction setting
    -- Options: LRTB, LRBT, RLTB, RLBT, TBLR, TBRL, BTLR, BTRL
    panel_direction = "LRTB",  -- default: left-to-right, top-to-bottom

    -- Direction settings lookup table
    -- Each direction defines: primary axis (h/v), primary order (+/-), secondary order (+/-)
    -- h = horizontal first (row mode), v = vertical first (column mode)
    -- + = increasing (left-to-right or top-to-bottom), - = decreasing (right-to-left or bottom-to-top)
    direction_settings = {
        LRTB = { primary = "h", primary_order = 1,  secondary_order = 1  }, -- Left-Right, Top-Bottom
        LRBT = { primary = "h", primary_order = 1,  secondary_order = -1 }, -- Left-Right, Bottom-Top
        RLTB = { primary = "h", primary_order = -1, secondary_order = 1  }, -- Right-Left, Top-Bottom
        RLBT = { primary = "h", primary_order = -1, secondary_order = -1 }, -- Right-Left, Bottom-Top
        TBLR = { primary = "v", primary_order = 1,  secondary_order = 1  }, -- Top-Bottom, Left-Right
        TBRL = { primary = "v", primary_order = 1,  secondary_order = -1 }, -- Top-Bottom, Right-Left
        BTLR = { primary = "v", primary_order = -1, secondary_order = 1  }, -- Bottom-Top, Left-Right
        BTRL = { primary = "v", primary_order = -1, secondary_order = -1 }, -- Bottom-Top, Right-Left
    },
}

function ReaderPanelNav:onDispatcherRegisterActions()
    Dispatcher:registerAction("goto_next_panel",
        {category="none", event="GotoNextPanel", title=_("Go to next panel"), paging=true})
    Dispatcher:registerAction("goto_prev_panel",
        {category="none", event="GotoPrevPanel", title=_("Go to previous panel"), paging=true})
    Dispatcher:registerAction("enter_panel_nav_mode",
        {category="none", event="EnterPanelNavMode", title=_("Enter panel navigation mode"), paging=true})
end

function ReaderPanelNav:init()
    self:onDispatcherRegisterActions()
    -- Register as view module to draw panel boxes
    self.view:registerViewModule("panel_nav", self)
end

function ReaderPanelNav:onReadSettings(config)
    -- Use hasNot to check if setting exists, otherwise use global or default
    if config:has("panel_nav_enabled") then
        self.panel_nav_enabled = config:isTrue("panel_nav_enabled")
    else
        self.panel_nav_enabled = G_reader_settings:isTrue("panel_nav_enabled")
    end
    self.panel_direction = config:readSetting("panel_direction")
        or G_reader_settings:readSetting("panel_direction")
        or "LRTB"
    if config:has("highlight_current_panel") then
        self.highlight_current_panel = config:isTrue("highlight_current_panel")
    else
        self.highlight_current_panel = G_reader_settings:isTrue("highlight_current_panel")
    end
    if config:has("show_panel_boxes") then
        self.show_panel_boxes = config:isTrue("show_panel_boxes")
    else
        self.show_panel_boxes = G_reader_settings:isTrue("show_panel_boxes")
    end
end

function ReaderPanelNav:onSaveSettings()
    self.ui.doc_settings:saveSetting("panel_nav_enabled", self.panel_nav_enabled)
    self.ui.doc_settings:saveSetting("panel_direction", self.panel_direction)
    self.ui.doc_settings:saveSetting("highlight_current_panel", self.highlight_current_panel)
    self.ui.doc_settings:saveSetting("show_panel_boxes", self.show_panel_boxes)
end

--[[--
Set panel reading direction.

@param direction string Direction code (LRTB, LRBT, RLTB, RLBT, TBLR, TBRL, BTLR, BTRL)
--]]
function ReaderPanelNav:setPanelDirection(direction)
    if self.direction_settings[direction] then
        self.panel_direction = direction
        -- Invalidate cached panels when direction changes
        self.current_page_panels = nil
        self.panels_page = nil
        self.current_panel_index = 0
        -- Refresh display if showing panel boxes
        if self.show_panel_boxes then
            UIManager:setDirty(self.view.dialog, "ui")
        end
    end
end

--[[--
Get human-readable description of a direction code.

@param direction string Direction code
@treturn string Human-readable description
--]]
function ReaderPanelNav:getDirectionDescription(direction)
    local descriptions = {
        LRTB = _("Left to right, top to bottom"),
        LRBT = _("Left to right, bottom to top"),
        RLTB = _("Right to left, top to bottom"),
        RLBT = _("Right to left, bottom to top"),
        TBLR = _("Top to bottom, left to right"),
        TBRL = _("Top to bottom, right to left"),
        BTLR = _("Bottom to top, left to right"),
        BTRL = _("Bottom to top, right to left"),
    }
    return descriptions[direction] or direction
end

--[[--
Assign row and column indices to panels based on 30% overlap.
Panels are grouped into lanes (rows/columns) and indices are assigned.

@param panels array of panel rectangles {x, y, w, h}
@treturn table panels with row/col fields added
--]]
function ReaderPanelNav:assignGridByOverlap(panels)
    if not panels or #panels == 0 then
        return panels
    end

    local direction = self.panel_direction or "LRTB"

    -- Helper to find unique lanes (Rows or Columns) based on 30% overlap
    local function getLanes(axis, dim)
        local lanes = {}

        -- Sort panels by dimension size (smallest first) so narrow/short panels
        -- establish lanes before wide/tall panels can merge them
        local sorted_panels = {}
        for i, p in ipairs(panels) do
            sorted_panels[i] = p
        end
        table.sort(sorted_panels, function(a, b)
            return a[dim] < b[dim]
        end)

        for _, p in ipairs(sorted_panels) do
            local found = false
            for _, lane in ipairs(lanes) do
                -- Calculate overlap between panel and existing lane
                local overlapStart = math.max(p[axis], lane.start)
                local overlapEnd = math.min(p[axis] + p[dim], lane.stop)
                local overlapSize = overlapEnd - overlapStart

                -- Check if overlap is > 30% of either the panel or the lane height/width
                if overlapSize > 0 then
                    local ratio = overlapSize / math.min(p[dim], lane.stop - lane.start)
                    if ratio > 0.30 then
                        found = true
                        -- Expand lane boundaries to encompass this panel
                        lane.start = math.min(lane.start, p[axis])
                        lane.stop = math.max(lane.stop, p[axis] + p[dim])
                        break
                    end
                end
            end
            if not found then
                table.insert(lanes, { start = p[axis], stop = p[axis] + p[dim] })
            end
        end
        -- Sort lanes based on position (ascending by default)
        table.sort(lanes, function(a, b) return a.start < b.start end)
        return lanes
    end

    -- Identify all global rows and columns
    local rows = getLanes("y", "h")
    local cols = getLanes("x", "w")

    -- Handle reverse directions (BT or RL) by reversing the lane indices
    if direction:find("BT") then
        table.sort(rows, function(a, b) return a.start > b.start end)
    end
    if direction:find("RL") then
        table.sort(cols, function(a, b) return a.start > b.start end)
    end

    -- Assign row/column indices to each panel
    for _, p in ipairs(panels) do
        -- Assign row
        for i, row in ipairs(rows) do
            local overlap = math.min(p.y + p.h, row.stop) - math.max(p.y, row.start)
            -- Use min of panel height and lane height for consistent comparison with getLanes
            local minHeight = math.min(p.h, row.stop - row.start)
            if overlap / minHeight > 0.30 then
                p.row = i
                break
            end
        end
        -- Assign column
        for j, col in ipairs(cols) do
            local overlap = math.min(p.x + p.w, col.stop) - math.max(p.x, col.start)
            -- Use min of panel width and lane width for consistent comparison with getLanes
            local minWidth = math.min(p.w, col.stop - col.start)
            if overlap / minWidth > 0.30 then
                p.col = j
                break
            end
        end
        logger.dbg("ReaderPanelNav: panel", p.x, p.y, p.w, p.h, "-> row", p.row, "col", p.col)
    end

    logger.dbg("ReaderPanelNav: rows:", #rows, "cols:", #cols)
    for i, row in ipairs(rows) do
        logger.dbg("  row", i, ":", row.start, "-", row.stop)
    end
    for j, col in ipairs(cols) do
        logger.dbg("  col", j, ":", col.start, "-", col.stop)
    end
    return panels
end

--[[--
Sort panels according to panel reading direction.

Groups panels into rows/columns based on overlap, then sorts accordingly.
For LRTB: group by rows (Y overlap), sort rows top-to-bottom, panels left-to-right.
For TBLR: group by columns (X overlap), sort columns left-to-right, panels top-to-bottom.

@param panels array of panel rectangles {x, y, w, h}
@treturn table sorted array of panels with row/col fields added
--]]
function ReaderPanelNav:sortPanelsByReadingDirection(panels)
    if not panels or #panels == 0 then
        return panels
    end

    -- Create a copy to work with
    local sorted = {}
    for i, p in ipairs(panels) do
        sorted[i] = { x = p.x, y = p.y, w = p.w, h = p.h }
    end

    local direction = self.panel_direction or "LRTB"
    local primary = direction:sub(1, 2)
    local secondary = direction:sub(3, 4)

    -- Determine sort direction flags
    local y_ascending = (secondary == "TB")  -- Top to Bottom
    local x_ascending = (primary == "LR")    -- Left to Right
    local row_first = (primary == "LR" or primary == "RL")

    local overlap_threshold = 0.25  -- 25% overlap required to be in same row/column
    local position_threshold = 5     -- Positions within 5 pixels are considered equal

    if row_first then
        -- LRTB, LRBT, RLTB, RLBT: Group by rows first
        -- Sort by Y to process top-to-bottom (or bottom-to-top)
        table.sort(sorted, function(a, b)
            if y_ascending then
                return a.y < b.y
            else
                return a.y > b.y
            end
        end)

        -- Group panels into rows based on Y overlap
        local rows = {}
        for _, panel in ipairs(sorted) do
            local p_top, p_bottom = panel.y, panel.y + panel.h
            local assigned = false

            for _, row in ipairs(rows) do
                local overlap_start = math.max(p_top, row.start_y)
                local overlap_end = math.min(p_bottom, row.end_y)
                local overlap_size = overlap_end - overlap_start

                if overlap_size > 0 then
                    local row_height = row.end_y - row.start_y
                    if overlap_size / row_height >= overlap_threshold then
                        table.insert(row.panels, panel)
                        row.start_y = math.min(row.start_y, p_top)
                        row.end_y = math.max(row.end_y, p_bottom)
                        assigned = true
                        break
                    end
                end
            end

            if not assigned then
                table.insert(rows, {
                    start_y = p_top,
                    end_y = p_bottom,
                    panels = { panel },
                })
            end
        end

        -- Sort rows by Y position
        table.sort(rows, function(a, b)
            if y_ascending then
                return a.start_y < b.start_y
            else
                return a.start_y > b.start_y
            end
        end)

        -- Build result: for each row, sort panels by X (with Y as tiebreaker)
        local result = {}
        for row_num, row in ipairs(rows) do
            table.sort(row.panels, function(a, b)
                if math.abs(a.x - b.x) > position_threshold then
                    if x_ascending then
                        return a.x < b.x
                    else
                        return a.x > b.x
                    end
                else
                    -- X within threshold, use Y as tiebreaker
                    if y_ascending then
                        return a.y < b.y
                    else
                        return a.y > b.y
                    end
                end
            end)
            for col_num, panel in ipairs(row.panels) do
                panel.row = row_num
                panel.col = col_num
                table.insert(result, panel)
            end
        end
        sorted = result
    else
        -- TBLR, TBRL, BTLR, BTRL: Group by columns first
        -- Sort by X to process left-to-right (or right-to-left)
        table.sort(sorted, function(a, b)
            if x_ascending then
                return a.x < b.x
            else
                return a.x > b.x
            end
        end)

        -- Group panels into columns based on X overlap
        local columns = {}
        for _, panel in ipairs(sorted) do
            local p_left, p_right = panel.x, panel.x + panel.w
            local assigned = false

            for _, col in ipairs(columns) do
                local overlap_start = math.max(p_left, col.start_x)
                local overlap_end = math.min(p_right, col.end_x)
                local overlap_size = overlap_end - overlap_start

                if overlap_size > 0 then
                    local col_width = col.end_x - col.start_x
                    if overlap_size / col_width >= overlap_threshold then
                        table.insert(col.panels, panel)
                        col.start_x = math.min(col.start_x, p_left)
                        col.end_x = math.max(col.end_x, p_right)
                        assigned = true
                        break
                    end
                end
            end

            if not assigned then
                table.insert(columns, {
                    start_x = p_left,
                    end_x = p_right,
                    panels = { panel },
                })
            end
        end

        -- Sort columns by X position
        table.sort(columns, function(a, b)
            if x_ascending then
                return a.start_x < b.start_x
            else
                return a.start_x > b.start_x
            end
        end)

        -- Build result: for each column, sort panels by Y (with X as tiebreaker)
        local result = {}
        for col_num, col in ipairs(columns) do
            table.sort(col.panels, function(a, b)
                if math.abs(a.y - b.y) > position_threshold then
                    if y_ascending then
                        return a.y < b.y
                    else
                        return a.y > b.y
                    end
                else
                    -- Y within threshold, use X as tiebreaker
                    if x_ascending then
                        return a.x < b.x
                    else
                        return a.x > b.x
                    end
                end
            end)
            for row_num, panel in ipairs(col.panels) do
                panel.row = row_num
                panel.col = col_num
                table.insert(result, panel)
            end
        end
        sorted = result
    end

    logger.dbg("ReaderPanelNav: sorted order (direction:", direction, "):")
    for i, p in ipairs(sorted) do
        logger.dbg("  ", i, ": (", p.x, ",", p.y, ")-(", p.x + p.w, ",", p.y + p.h, ") row=", p.row, "col=", p.col)
    end

    return sorted
end

--[[--
Check if panel A is completely contained within panel B.

@param a panel rectangle {x, y, w, h}
@param b panel rectangle {x, y, w, h}
@treturn bool true if A is completely inside B
--]]
function ReaderPanelNav:isPanelContainedIn(a, b)
    -- A is contained in B if all corners of A are within B
    local a_left = a.x
    local a_right = a.x + a.w
    local a_top = a.y
    local a_bottom = a.y + a.h

    local b_left = b.x
    local b_right = b.x + b.w
    local b_top = b.y
    local b_bottom = b.y + b.h

    -- A is inside B if B's boundaries completely enclose A
    -- Use a small tolerance (0 pixel) to handle floating point issues
    local tolerance = 0
    return a_left >= b_left - tolerance and
           a_right <= b_right + tolerance and
           a_top >= b_top - tolerance and
           a_bottom <= b_bottom + tolerance
end

--[[--
Filter out panels that are completely contained within other panels.
Keeps only the outermost panels.

@param panels array of panel rectangles {x, y, w, h}
@treturn table filtered array of panels
--]]
function ReaderPanelNav:filterNestedPanels(panels)
    if not panels or #panels <= 1 then
        return panels
    end

    local filtered = {}

    for i, panel_a in ipairs(panels) do
        local is_nested = false

        for j, panel_b in ipairs(panels) do
            if i ~= j then
                -- Check if panel_a is contained within panel_b
                -- but panel_b is not contained within panel_a (avoid equal panels)
                if self:isPanelContainedIn(panel_a, panel_b) and
                   not self:isPanelContainedIn(panel_b, panel_a) then
                    is_nested = true
                    break
                end
            end
        end

        if not is_nested then
            table.insert(filtered, panel_a)
        end
    end

    logger.dbg("ReaderPanelNav: filtered", #panels - #filtered, "nested panels, keeping", #filtered)
    return filtered
end

--[[--
Calculate the intersection area of two panels.

@param a panel rectangle {x, y, w, h}
@param b panel rectangle {x, y, w, h}
@treturn number intersection area (0 if no overlap)
--]]
function ReaderPanelNav:getPanelIntersectionArea(a, b)
    local a_left, a_right = a.x, a.x + a.w
    local a_top, a_bottom = a.y, a.y + a.h
    local b_left, b_right = b.x, b.x + b.w
    local b_top, b_bottom = b.y, b.y + b.h

    local inter_left = math.max(a_left, b_left)
    local inter_right = math.min(a_right, b_right)
    local inter_top = math.max(a_top, b_top)
    local inter_bottom = math.min(a_bottom, b_bottom)

    local inter_width = inter_right - inter_left
    local inter_height = inter_bottom - inter_top

    if inter_width > 0 and inter_height > 0 then
        return inter_width * inter_height
    end
    return 0
end

--[[--
Merge two panels into their bounding box.

@param a panel rectangle {x, y, w, h}
@param b panel rectangle {x, y, w, h}
@treturn table merged panel rectangle {x, y, w, h}
--]]
function ReaderPanelNav:mergePanels(a, b)
    local left = math.min(a.x, b.x)
    local top = math.min(a.y, b.y)
    local right = math.max(a.x + a.w, b.x + b.w)
    local bottom = math.max(a.y + a.h, b.y + b.h)

    return {
        x = left,
        y = top,
        w = right - left,
        h = bottom - top,
    }
end

--[[--
Merge overlapping panels into single panels.
If two panels overlap significantly (> threshold of smaller panel's area),
they are merged into their bounding box.

@param panels array of panel rectangles {x, y, w, h}
@param overlap_threshold fraction of overlap required to merge (default 0.3 = 30%)
@treturn table array of merged panels
--]]
function ReaderPanelNav:mergeOverlappingPanels(panels, overlap_threshold)
    if not panels or #panels <= 1 then
        return panels
    end

    overlap_threshold = overlap_threshold or 0.3

    -- Keep merging until no more merges happen
    local merged = true
    local result = {}

    -- Copy panels to result
    for _, p in ipairs(panels) do
        table.insert(result, { x = p.x, y = p.y, w = p.w, h = p.h })
    end

    while merged do
        merged = false
        local new_result = {}
        local merged_indices = {}

        for i = 1, #result do
            if not merged_indices[i] then
                local current = result[i]

                for j = i + 1, #result do
                    if not merged_indices[j] then
                        local other = result[j]
                        local intersection = self:getPanelIntersectionArea(current, other)

                        if intersection > 0 then
                            -- Calculate areas
                            local area_current = current.w * current.h
                            local area_other = other.w * other.h
                            local smaller_area = math.min(area_current, area_other)

                            -- Check if overlap is significant
                            if intersection / smaller_area >= overlap_threshold then
                                -- Merge the panels
                                current = self:mergePanels(current, other)
                                merged_indices[j] = true
                                merged = true
                            end
                        end
                    end
                end

                table.insert(new_result, current)
            end
        end

        result = new_result
    end

    local merged_count = #panels - #result
    if merged_count > 0 then
        logger.dbg("ReaderPanelNav: merged", merged_count, "overlapping panels, now have", #result)
    end

    return result
end

--[[--
Clip panels to ensure they are within page boundaries.
Panels that extend outside the page are clipped to the page bounds.
Panels that are completely outside the page are removed.

@param panels array of panel rectangles {x, y, w, h}
@param page_width width of the page
@param page_height height of the page
@treturn table array of clipped panels, or nil if no panels
--]]
function ReaderPanelNav:clipPanelsToPage(panels, page_width, page_height)
    if not panels or #panels == 0 then
        return nil
    end

    local clipped = {}

    for _, panel in ipairs(panels) do
        -- Calculate panel boundaries
        local left = panel.x
        local top = panel.y
        local right = panel.x + panel.w
        local bottom = panel.y + panel.h

        -- Clip to page boundaries
        local clipped_left = math.max(0, left)
        local clipped_top = math.max(0, top)
        local clipped_right = math.min(page_width, right)
        local clipped_bottom = math.min(page_height, bottom)

        -- Calculate new width and height
        local clipped_w = clipped_right - clipped_left
        local clipped_h = clipped_bottom - clipped_top

        -- Only keep panels with positive dimensions (visible on page)
        if clipped_w > 0 and clipped_h > 0 then
            table.insert(clipped, {
                x = clipped_left,
                y = clipped_top,
                w = clipped_w,
                h = clipped_h,
            })
        end
    end

    local removed = #panels - #clipped
    if removed > 0 then
        logger.dbg("ReaderPanelNav: clipped/removed", removed, "panels outside page bounds")
    end

    return clipped
end

--[[--
Get panels for the current page, sorted by reading direction.

@treturn table array of sorted panels, or nil if no panels found
--]]
function ReaderPanelNav:getPanelsForCurrentPage()
    -- Check if document supports panel detection
    if not self.ui.document.getAllPanelsFromPage then
        return nil
    end

    local pageno = self.ui.paging.current_page

    -- Return cached panels if available for current page
    if self.current_page_panels and self.panels_page == pageno then
        return self.current_page_panels
    end

    -- Get panels from document
    local panels = self.ui.document:getAllPanelsFromPage(pageno)
    if not panels or #panels == 0 then
        self.current_page_panels = nil
        self.panels_page = pageno
        return nil
    end

    -- Clip panels to page boundaries
    local page_size = self.ui.document:getNativePageDimensions(pageno)
    if page_size then
        panels = self:clipPanelsToPage(panels, page_size.w, page_size.h)
        if not panels or #panels == 0 then
            self.current_page_panels = nil
            self.panels_page = pageno
            return nil
        end
    end

    -- Merge overlapping panels (50% overlap threshold)
    panels = self:mergeOverlappingPanels(panels, 0.5)
    if not panels or #panels == 0 then
        self.current_page_panels = nil
        self.panels_page = pageno
        return nil
    end

    -- Filter out nested panels (keep only outermost ones)
    panels = self:filterNestedPanels(panels)
    if not panels or #panels == 0 then
        self.current_page_panels = nil
        self.panels_page = pageno
        return nil
    end

    -- Sort panels by reading direction
    self.current_page_panels = self:sortPanelsByReadingDirection(panels)
    self.panels_page = pageno
    self.current_panel_index = 0  -- Reset to full page view

    return self.current_page_panels
end

--[[--
Navigate to the next panel.

@treturn bool true if handled
--]]
function ReaderPanelNav:onGotoNextPanel()
    logger.dbg("ReaderPanelNav:onGotoNextPanel called, enabled:", self.panel_nav_enabled)

    if not self.panel_nav_enabled then
        return false
    end

    local panels = self:getPanelsForCurrentPage()
    logger.dbg("ReaderPanelNav: panels count:", panels and #panels or 0, "current index:", self.current_panel_index)

    if not panels or #panels == 0 then
        -- No panels on this page, go to next page
        logger.dbg("ReaderPanelNav: no panels, going to next page")
        self._turning_page = true
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        self._turning_page = false
        return true
    end

    if self.current_panel_index < #panels then
        -- Go to next panel
        self.current_panel_index = self.current_panel_index + 1
        logger.dbg("ReaderPanelNav: navigating to panel", self.current_panel_index)
        self:showPanel(panels[self.current_panel_index])
    else
        -- At last panel, go to next page
        logger.dbg("ReaderPanelNav: at last panel, going to next page")
        self.current_panel_index = 0
        self.current_page_panels = nil
        self.panels_page = nil
        self._turning_page = true
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        self._turning_page = false
    end

    return true
end

--[[--
Navigate to the previous panel.

@treturn bool true if handled
--]]
function ReaderPanelNav:onGotoPrevPanel()
    if not self.panel_nav_enabled then
        return false
    end

    local panels = self:getPanelsForCurrentPage()

    if self.current_panel_index > 1 then
        -- Go to previous panel
        self.current_panel_index = self.current_panel_index - 1
        self:showPanel(panels[self.current_panel_index])
    elseif self.current_panel_index == 1 then
        -- At first panel, show full page
        self.current_panel_index = 0
        self:showFullPage()
    else
        -- At full page view, go to previous page and show last panel
        self.current_page_panels = nil
        self.panels_page = nil
        self._turning_page = true
        self.ui:handleEvent(Event:new("GotoViewRel", -1))
        self._turning_page = false
        -- After page change, we need to get panels for the new page
        -- and navigate to the last panel
        UIManager:nextTick(function()
            local new_panels = self:getPanelsForCurrentPage()
            if new_panels and #new_panels > 0 then
                self.current_panel_index = #new_panels
                self:showPanel(new_panels[self.current_panel_index])
            end
        end)
    end

    return true
end

--[[--
Show a specific panel in the ImageViewer.

@param panel panel rectangle {x, y, w, h}
--]]
function ReaderPanelNav:showPanel(panel)
    local dbg = require("dbg")
    dbg.dassert(panel, "showPanel called with nil panel")
    if not panel then return end

    logger.dbg("ReaderPanelNav: showPanel called with panel:", panel)

    local pageno = self.ui.paging.current_page
    logger.dbg("ReaderPanelNav: drawing panel from page", pageno)

    -- Make sure we have the drawPagePart method
    if not self.ui.document.drawPagePart then
        logger.dbg("ReaderPanelNav: document does not support drawPagePart")
        UIManager:show(InfoMessage:new{
            text = _("Panel zoom not supported for this document type."),
            timeout = 2,
        })
        return
    end

    local image, rotate = self.ui.document:drawPagePart(pageno, panel, 0)

    if image then
        -- If we already have an ImageViewer open, just update the image
        if self._panel_viewer then
            logger.dbg("ReaderPanelNav: reusing existing ImageViewer")
            -- Guard against updating while a repaint is in progress
            if self._panel_viewer._updating then
                logger.dbg("ReaderPanelNav: skipping update, already updating")
                return
            end
            self._panel_viewer._updating = true
            self._panel_viewer.image = image
            -- Immediately clean the image widget so any pending refresh uses new image
            self._panel_viewer:_clean_image_wg()
            -- Now trigger the update synchronously
            self._panel_viewer:update()
            self._panel_viewer._updating = false
            return
        end

        logger.dbg("ReaderPanelNav: creating new ImageViewer")
        local ImageViewer = require("ui/widget/imageviewer")

        -- Keep reference to self for callbacks
        local panelnav = self

        -- Calculate height to leave room for status bar (footer)
        local footer_height = 0
        if self.view.footer and self.view.footer_visible
           and not self.view.footer.settings.reclaim_height then
            footer_height = self.view.footer:getHeight()
        end
        local viewer_height = Screen:getHeight() - footer_height

        local imgviewer = ImageViewer:new{
            image = image,
            image_disposable = false, -- It's a TileCache item
            with_title_bar = false,
            fullscreen = true,
            rotated = rotate,
            height = viewer_height, -- Leave room for footer
        }

        -- Patch update() to use our custom height (leaving room for footer)
        -- This ensures buttons appear above the status bar
        local orig_update = imgviewer.update
        imgviewer.update = function(iv)
            -- Temporarily override height before update runs
            local saved_getHeight = Screen.getHeight
            Screen.getHeight = function() return viewer_height end
            orig_update(iv)
            Screen.getHeight = saved_getHeight
            -- Also ensure region is correct
            iv.region.h = viewer_height
        end

        -- Paint footer on top of ImageViewer if visible
        if footer_height > 0 then
            local orig_paintTo = imgviewer.paintTo
            local last_footer_page = pageno  -- Track which page footer was last updated for
            imgviewer.paintTo = function(self_viewer, bb, x, y)
                orig_paintTo(self_viewer, bb, x, y)
                -- Paint footer at the bottom of the screen
                if panelnav.view.footer and panelnav.view.footer_visible then
                    local current_page = panelnav.ui.paging.current_page
                    -- Only refresh footer content when page changes
                    if current_page ~= last_footer_page then
                        logger.dbg("ReaderPanelNav: page changed from", last_footer_page, "to", current_page, "- refreshing footer")
                        panelnav.view.footer:onUpdateFooter(true)
                        last_footer_page = current_page
                    end
                    panelnav.view.footer:paintTo(bb, x, y)
                end
            end
        end

        -- Only add panel navigation if enabled
        if self.panel_nav_enabled then
            local is_rtl = BD.mirroredUILayout()

            -- Panel navigation handlers
            imgviewer.onNextPanel = function(self_viewer)
                local cur_panels = panelnav:getPanelsForCurrentPage()
                if cur_panels and panelnav.current_panel_index < #cur_panels then
                    -- Same page: just update the image in place
                    panelnav.current_panel_index = panelnav.current_panel_index + 1
                    panelnav:showPanel(cur_panels[panelnav.current_panel_index])
                elseif cur_panels then
                    -- End of page: go to next page, keep viewer open
                    -- Do everything in one tick so image updates before repaint
                    panelnav.current_panel_index = 0
                    panelnav.current_page_panels = nil
                    panelnav.panels_page = nil
                    UIManager:nextTick(function()
                        panelnav.ui:handleEvent(Event:new("GotoViewRel", 1))
                        local new_panels = panelnav:getPanelsForCurrentPage()
                        if new_panels and #new_panels > 0 then
                            panelnav.current_panel_index = 1
                            panelnav:showPanel(new_panels[1])
                        else
                            -- No panels on new page, close viewer
                            UIManager:close(self_viewer)
                        end
                    end)
                end
                return true
            end

            imgviewer.onPrevPanel = function(self_viewer)
                local cur_panels = panelnav:getPanelsForCurrentPage()
                if panelnav.current_panel_index > 1 then
                    -- Same page: just update the image in place
                    panelnav.current_panel_index = panelnav.current_panel_index - 1
                    panelnav:showPanel(cur_panels[panelnav.current_panel_index])
                else
                    -- Start of page: go to previous page, keep viewer open
                    -- Do everything in one tick so image updates before repaint
                    panelnav.current_page_panels = nil
                    panelnav.panels_page = nil
                    UIManager:nextTick(function()
                        panelnav.ui:handleEvent(Event:new("GotoViewRel", -1))
                        local new_panels = panelnav:getPanelsForCurrentPage()
                        if new_panels and #new_panels > 0 then
                            panelnav.current_panel_index = #new_panels
                            panelnav:showPanel(new_panels[panelnav.current_panel_index])
                        else
                            -- No panels on new page, close viewer
                            UIManager:close(self_viewer)
                        end
                    end)
                end
                return true
            end

            -- Key bindings (replace default zoom with panel navigation)
            if Device:hasKeys() then
                imgviewer.key_events.ZoomIn = nil
                imgviewer.key_events.ZoomOut = nil
                imgviewer.key_events.NextPanel = { { { "RPgFwd", "LPgFwd", is_rtl and "Left" or "Right" } }, event = "NextPanel" }
                imgviewer.key_events.PrevPanel = { { { "RPgBack", "LPgBack", is_rtl and "Right" or "Left" } }, event = "PrevPanel" }
            end

            -- Touch zones (tap left/right edges)
            if Device:isTouchDevice() then
                imgviewer:registerTouchZones({
                    {
                        id = "panel_tap_forward",
                        ges = "tap",
                        screen_zone = is_rtl
                            and { ratio_x = 0, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 }
                            or  { ratio_x = 0.75, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 },
                        handler = function() return imgviewer:onNextPanel() end,
                    },
                    {
                        id = "panel_tap_backward",
                        ges = "tap",
                        screen_zone = is_rtl
                            and { ratio_x = 0.75, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 }
                            or  { ratio_x = 0, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 },
                        handler = function() return imgviewer:onPrevPanel() end,
                    },
                })
            end
        end

        -- Handle device rotation: apply rotation, close viewer, re-show panel
        imgviewer.onSetRotationMode = function(self_viewer, mode)
            if mode ~= nil and mode ~= Screen:getRotationMode() then
                UIManager:close(self_viewer)
                -- Apply rotation via ReaderView
                panelnav.view:onSetRotationMode(mode)
                -- Re-show panel after rotation
                UIManager:nextTick(function()
                    local rot_panels = panelnav:getPanelsForCurrentPage()
                    if rot_panels and panelnav.current_panel_index > 0 then
                        panelnav:showPanel(rot_panels[panelnav.current_panel_index])
                    end
                end)
            end
            return true
        end

        -- Clear reference when ImageViewer is closed, but call original cleanup first
        local orig_onCloseWidget = imgviewer.onCloseWidget
        imgviewer.onCloseWidget = function(self_viewer)
            panelnav._panel_viewer = nil
            -- Call original cleanup to free resources
            if orig_onCloseWidget then
                orig_onCloseWidget(self_viewer)
            end
        end

        -- Store reference for reuse
        self._panel_viewer = imgviewer
        UIManager:show(imgviewer)
        logger.dbg("ReaderPanelNav: showing panel", self.current_panel_index, "of", #self.current_page_panels)
    else
        logger.dbg("ReaderPanelNav: drawPagePart returned nil image")
        UIManager:show(InfoMessage:new{
            text = _("Could not render panel."),
            timeout = 2,
        })
    end
end

--[[--
Show full page (exit panel zoom).
--]]
function ReaderPanelNav:showFullPage()
    self.current_panel_index = 0
    self.ui:handleEvent(Event:new("RedrawCurrentPage"))
end

--[[--
Toggle panel navigation enabled setting (for menu).
--]]
function ReaderPanelNav:togglePanelNavEnabled()
    self.panel_nav_enabled = not self.panel_nav_enabled

    if self.panel_nav_enabled then
        UIManager:show(InfoMessage:new{
            text = _("Panel navigation enabled."),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Panel navigation disabled."),
            timeout = 2,
        })
        -- Reset state
        self.current_panel_index = 0
        self.current_page_panels = nil
        self.panels_page = nil
    end
end

--[[--
Enter panel navigation mode - show current panel in ImageViewer.
Navigation keys only work if panel navigation is enabled.
--]]
function ReaderPanelNav:onEnterPanelNavMode()
    -- Check if panel zoom is enabled
    if self.ui.highlight and not self.ui.highlight.panel_zoom_enabled then
        UIManager:show(InfoMessage:new{
            text = _("Panel zoom must be enabled first."),
            timeout = 2,
        })
        return true
    end

    -- Get panels and show current one (or first if none selected)
    local panels = self:getPanelsForCurrentPage()
    if panels and #panels > 0 then
        -- If no current panel or index out of range, start at first panel
        if self.current_panel_index < 1 or self.current_panel_index > #panels then
            self.current_panel_index = 1
        end
        self:showPanel(panels[self.current_panel_index])
    else
        UIManager:show(InfoMessage:new{
            text = _("No panels detected on this page."),
            timeout = 2,
        })
    end

    return true
end

--[[--
Toggle panel box visualization for debugging.
--]]
function ReaderPanelNav:onToggleShowPanelBoxes()
    self.show_panel_boxes = not self.show_panel_boxes

    if self.show_panel_boxes then
        -- Force panel detection on current page
        self:getPanelsForCurrentPage()
        local panel_count = self.current_page_panels and #self.current_page_panels or 0
        UIManager:show(InfoMessage:new{
            text = _("Panel boxes visible.") .. "\n" .. string.format(_("Detected %d panels on this page."), panel_count),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Panel boxes hidden."),
            timeout = 2,
        })
    end

    -- Redraw the page
    UIManager:setDirty(self.dialog, "ui")
    return true
end

--[[--
Paint panel bounding boxes on the view.

This is called by ReaderView as a registered view module.

@param bb BlitBuffer to paint to
@param x X offset
@param y Y offset
--]]
function ReaderPanelNav:paintTo(bb, x, y)
    -- Check if any visualization is enabled
    if not self.show_panel_boxes and not self.highlight_current_panel then
        return
    end

    -- Don't show boxes if panel zoom is disabled
    if self.ui.highlight and not self.ui.highlight.panel_zoom_enabled then
        return
    end

    -- Don't show boxes if panel navigation is disabled
    if not self.panel_nav_enabled then
        return
    end

    local panels = self:getPanelsForCurrentPage()
    if not panels or #panels == 0 then
        return
    end

    -- Colors
    local box_color = Blitbuffer.ColorRGB24(0x00, 0xCC, 0x00)  -- Light green for all panels
    local current_box_color = Blitbuffer.ColorRGB24(0xFF, 0x00, 0x00)  -- Red for current panel
    local line_width = Size.line.thick

    -- Font for panel numbers (only used for debug view)
    local number_font = Font:getFace("infofont", 14)

    for i, panel in ipairs(panels) do
        -- Transform panel coordinates from page to screen
        local rect = self.view:pageToScreenTransform(self.panels_page, panel)
        if rect then
            local is_current = (i == self.current_panel_index)

            -- Determine if we should draw this panel
            local should_draw = false
            if self.show_panel_boxes then
                -- Debug mode: draw all panels
                should_draw = true
            elseif self.highlight_current_panel and is_current then
                -- Highlight current panel only
                should_draw = true
            end

            if should_draw then
                local color = is_current and current_box_color or box_color

                -- Draw rectangle border (4 lines)
                -- Top
                bb:paintRectRGB32(rect.x, rect.y, rect.w, line_width, color)
                -- Bottom
                bb:paintRectRGB32(rect.x, rect.y + rect.h - line_width, rect.w, line_width, color)
                -- Left
                bb:paintRectRGB32(rect.x, rect.y, line_width, rect.h, color)
                -- Right
                bb:paintRectRGB32(rect.x + rect.w - line_width, rect.y, line_width, rect.h, color)

                -- Only draw panel number in debug mode (show_panel_boxes)
                if self.show_panel_boxes then
                    local num_text = tostring(i)
                    local text_size = RenderText:sizeUtf8Text(0, Screen:getWidth(), number_font, num_text)
                    local num_w = text_size.x + 8
                    local num_h = number_font.size + 4

                    -- Draw background rectangle for number
                    bb:paintRectRGB32(rect.x + 4, rect.y + 4, num_w, num_h, color)

                    -- Draw the number text (white text on colored background)
                    RenderText:renderUtf8Text(bb, rect.x + 8, rect.y + 4 + number_font.size - 2, number_font, num_text, false, false, Blitbuffer.COLOR_WHITE)
                end
            end
        end
    end

    if self.show_panel_boxes then
        logger.dbg("ReaderPanelNav: painted", #panels, "panel boxes with numbers")
    end
end

--[[--
Handle page change to reset panel state.
--]]
function ReaderPanelNav:onPageUpdate(new_page_no)
    if self.panels_page ~= new_page_no then
        self.current_page_panels = nil
        self.panels_page = nil
        self.current_panel_index = 0
    end
end

return ReaderPanelNav
