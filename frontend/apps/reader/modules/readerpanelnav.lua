--[[--
Panel navigation module for comics/manga.

This module enables panel-by-panel navigation in paged documents (PDF, DjVu).
Panels are detected automatically using image analysis and can be navigated
in the order specified by zoom_direction_settings (reading direction).

@module readerpanelnav
--]]

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
    self:registerKeyEvents()
    -- Register as view module to draw panel boxes
    self.view:registerViewModule("panel_nav", self)
end

function ReaderPanelNav:registerKeyEvents()
    if Device:hasKeys() then
        -- P enters panel navigation view from the main view
        self.key_events = {
            EnterPanelNavMode = {
                { "P" },
                event = "EnterPanelNavMode",
            },
        }
    end
end

ReaderPanelNav.onPhysicalKeyboardConnected = ReaderPanelNav.registerKeyEvents

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
Sort panels according to panel reading direction.

@param panels array of panel rectangles {x, y, w, h}
@treturn table sorted array of panels
--]]
function ReaderPanelNav:sortPanelsByReadingDirection(panels)
    if not panels or #panels == 0 then
        return panels
    end

    -- Get direction settings
    local dir_settings = self.direction_settings[self.panel_direction] or self.direction_settings.LRTB

    -- Create a copy to sort
    local sorted = {}
    for i, p in ipairs(panels) do
        sorted[i] = p
    end

    -- Calculate panel centers for comparison
    local function getCenter(panel)
        return {
            x = panel.x + panel.w / 2,
            y = panel.y + panel.h / 2,
        }
    end

    -- Minimum overlap threshold to consider panels in the same row/column
    -- Overlap must be at least this fraction of the smaller panel's dimension
    local overlap_threshold = 0.3  -- 30%

    -- Check if two panels overlap significantly in X axis (same column)
    -- Returns true only if overlap is >= threshold of smaller panel's width
    local function overlapsInX(pa, pb)
        local a_left, a_right = pa.x, pa.x + pa.w
        local b_left, b_right = pb.x, pb.x + pb.w

        -- Calculate overlap amount
        local overlap_left = math.max(a_left, b_left)
        local overlap_right = math.min(a_right, b_right)
        local overlap_amount = overlap_right - overlap_left

        if overlap_amount <= 0 then
            return false
        end

        -- Check if overlap is significant relative to smaller panel's width
        local smaller_width = math.min(pa.w, pb.w)
        return overlap_amount / smaller_width >= overlap_threshold
    end

    -- Check if two panels overlap significantly in Y axis (same row)
    -- Returns true only if overlap is >= threshold of smaller panel's height
    local function overlapsInY(pa, pb)
        local a_top, a_bottom = pa.y, pa.y + pa.h
        local b_top, b_bottom = pb.y, pb.y + pb.h

        -- Calculate overlap amount
        local overlap_top = math.max(a_top, b_top)
        local overlap_bottom = math.min(a_bottom, b_bottom)
        local overlap_amount = overlap_bottom - overlap_top

        if overlap_amount <= 0 then
            return false
        end

        -- Check if overlap is significant relative to smaller panel's height
        local smaller_height = math.min(pa.h, pb.h)
        return overlap_amount / smaller_height >= overlap_threshold
    end

    -- Sort panels based on panel reading direction
    -- primary = "h" means horizontal first (row mode): group by Y overlap, then sort by X
    -- primary = "v" means vertical first (column mode): group by X overlap, then sort by Y
    -- primary_order: 1 = increasing (L-R or T-B), -1 = decreasing (R-L or B-T)
    -- secondary_order: same for the secondary axis
    table.sort(sorted, function(a, b)
        local ca, cb = getCenter(a), getCenter(b)

        if dir_settings.primary == "v" then
            -- Column mode: panels that overlap in X are in the same column
            if overlapsInX(a, b) then
                -- Same column, sort by Y (primary_order: 1=top-to-bottom, -1=bottom-to-top)
                if dir_settings.primary_order == -1 then
                    return ca.y > cb.y
                else
                    return ca.y < cb.y
                end
            else
                -- Different columns, sort by X (secondary_order: 1=left-to-right, -1=right-to-left)
                if dir_settings.secondary_order == -1 then
                    return ca.x > cb.x
                else
                    return ca.x < cb.x
                end
            end
        else
            -- Row mode: panels that overlap in Y are in the same row
            if overlapsInY(a, b) then
                -- Same row, sort by X (primary_order: 1=left-to-right, -1=right-to-left)
                if dir_settings.primary_order == -1 then
                    return ca.x > cb.x
                else
                    return ca.x < cb.x
                end
            else
                -- Different rows, sort by Y (secondary_order: 1=top-to-bottom, -1=bottom-to-top)
                if dir_settings.secondary_order == -1 then
                    return ca.y > cb.y
                else
                    return ca.y < cb.y
                end
            end
        end
    end)

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

    logger.dbg("ReaderPanelNav: found", #self.current_page_panels, "panels on page", pageno)
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
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
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
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
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
        self.ui:handleEvent(Event:new("GotoViewRel", -1))
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
        logger.dbg("ReaderPanelNav: got image for panel, showing ImageViewer")
        local ImageViewer = require("ui/widget/imageviewer")

        -- Keep reference to self for callbacks
        local panelnav = self

        local imgviewer = ImageViewer:new{
            image = image,
            image_disposable = false, -- It's a TileCache item
            with_title_bar = false,
            fullscreen = true,
            rotated = rotate,
        }

        -- Only add panel navigation if enabled
        if self.panel_nav_enabled then
            -- Add panel navigation key events
            if Device:hasKeys() then
                imgviewer.key_events.NextPanel = { { "Right" }, event = "NextPanel" }
                imgviewer.key_events.PrevPanel = { { "Left" }, event = "PrevPanel" }
            end

            -- Add panel navigation handlers
            imgviewer.onNextPanel = function(self_viewer)
                logger.dbg("ImageViewer: onNextPanel triggered")
                UIManager:close(self_viewer)
                -- Navigate to next panel
                local panels = panelnav:getPanelsForCurrentPage()
                if panels and panelnav.current_panel_index < #panels then
                    panelnav.current_panel_index = panelnav.current_panel_index + 1
                    panelnav:showPanel(panels[panelnav.current_panel_index])
                elseif panels then
                    -- At last panel, go to next page
                    panelnav.current_panel_index = 0
                    panelnav.current_page_panels = nil
                    panelnav.panels_page = nil
                    panelnav.ui:handleEvent(Event:new("GotoViewRel", 1))
                    -- Show first panel of next page
                    UIManager:nextTick(function()
                        local new_panels = panelnav:getPanelsForCurrentPage()
                        if new_panels and #new_panels > 0 then
                            panelnav.current_panel_index = 1
                            panelnav:showPanel(new_panels[1])
                        end
                    end)
                end
                return true
            end

            imgviewer.onPrevPanel = function(self_viewer)
                logger.dbg("ImageViewer: onPrevPanel triggered")
                UIManager:close(self_viewer)
                -- Navigate to previous panel
                local panels = panelnav:getPanelsForCurrentPage()
                if panelnav.current_panel_index > 1 then
                    panelnav.current_panel_index = panelnav.current_panel_index - 1
                    panelnav:showPanel(panels[panelnav.current_panel_index])
                else
                    -- At first panel, go to previous page
                    panelnav.current_page_panels = nil
                    panelnav.panels_page = nil
                    panelnav.ui:handleEvent(Event:new("GotoViewRel", -1))
                    -- Show last panel of previous page
                    UIManager:nextTick(function()
                        local new_panels = panelnav:getPanelsForCurrentPage()
                        if new_panels and #new_panels > 0 then
                            panelnav.current_panel_index = #new_panels
                            panelnav:showPanel(new_panels[panelnav.current_panel_index])
                        end
                    end)
                end
                return true
            end

            -- Override onTap for touch-based panel navigation
            -- Tap on right side: next panel, tap on left side: previous panel
            imgviewer.onTap = function(self_viewer, _, ges)
                local BD = require("ui/bidi")

                -- Check if tap is outside the main frame (close viewer)
                if self_viewer.main_frame and ges.pos:notIntersectWith(self_viewer.main_frame.dimen) then
                    self_viewer:onClose()
                    return true
                end

                -- Determine if tap is on left or right edge for panel navigation
                local screen_width = Screen:getWidth()
                local tap_zone_width = screen_width / 4  -- 25% on each side for navigation

                local is_left_tap = ges.pos.x < tap_zone_width
                local is_right_tap = ges.pos.x > screen_width - tap_zone_width

                -- Account for RTL layout (manga reading direction)
                local go_prev, go_next
                if BD.mirroredUILayout() then
                    go_prev = is_right_tap
                    go_next = is_left_tap
                else
                    go_prev = is_left_tap
                    go_next = is_right_tap
                end

                if go_next then
                    logger.dbg("ImageViewer: tap on right side, going to next panel")
                    return self_viewer:onNextPanel()
                elseif go_prev then
                    logger.dbg("ImageViewer: tap on left side, going to previous panel")
                    return self_viewer:onPrevPanel()
                else
                    -- Tap in the middle: toggle buttons visibility (default behavior)
                    self_viewer.buttons_visible = not self_viewer.buttons_visible
                    self_viewer:update()
                    return true
                end
            end
        end

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

                -- Only draw panel number and coordinates in debug mode (show_panel_boxes)
                if self.show_panel_boxes then
                    local x_left = math.floor(panel.x)
                    local y_top = math.floor(panel.y)
                    local x_right = math.floor(panel.x + panel.w)
                    local y_bottom = math.floor(panel.y + panel.h)
                    local num_text = string.format("%d (%d,%d)-(%d,%d)", i, x_left, y_top, x_right, y_bottom)
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
