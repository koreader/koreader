--[[--
ReaderView module handles all the screen painting for document browsing.
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderDogear = require("apps/reader/modules/readerdogear")
local ReaderFlipping = require("apps/reader/modules/readerflipping")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local logger = require("logger")
local optionsutil = require("ui/data/optionsutil")
local Size = require("ui/size")
local time = require("ui/time")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderView = OverlapGroup:extend{
    document = nil,
    view_modules = nil, -- array

    -- single page state
    state = nil, -- table
    outer_page_color = Blitbuffer.gray(G_defaults:readSetting("DOUTER_PAGE_COLOR") * (1/15)),
    -- highlight with "lighten" or "underscore" or "strikeout" or "invert"
    highlight = nil, -- table
    highlight_visible = true,
    note_mark_line_w = 3, -- side line thickness
    note_mark_sign = nil,
    note_mark_pos_x1 = nil, -- page 1
    note_mark_pos_x2 = nil, -- page 2 in two-page mode
    -- PDF/DjVu continuous paging
    page_scroll = nil,
    page_bgcolor = Blitbuffer.gray(G_defaults:readSetting("DBACKGROUND_COLOR") * (1/15)),
    page_states = nil, -- table
    -- properties of the gap drawn between each page in scroll mode:
    page_gap = nil, -- table
    -- DjVu page rendering mode (used in djvu.c:drawPage())
    render_mode = G_defaults:readSetting("DRENDER_MODE"), -- default to COLOR
    -- Crengine view mode
    view_mode = G_defaults:readSetting("DCREREADER_VIEW_MODE"), -- default to page mode
    hinting = true,
    emitHintPageEvent = nil,

    -- visible area within current viewing page
    visible_area = nil,
    -- dimen for current viewing page
    page_area = nil,
    -- dimen for area to dim
    dim_area = nil,
    -- has footer
    footer_visible = nil,
    -- has dogear
    dogear_visible = false,
    -- in flipping state
    flipping_visible = false,
    -- to ensure periodic flush of settings
    settings_last_save_time = nil,
    -- might be directly updated by readerpaging/readerrolling when
    -- they handle some panning/scrolling, to request "fast" refreshes
    currently_scrolling = false,
}

function ReaderView:init()
    self.view_modules = {}

    self.state = {
        page = nil,
        pos = 0,
        zoom = 1.0,
        rotation = 0,
        gamma = 1.0,
        offset = nil,
        bbox = nil,
    }
    self.highlight = {
        lighten_factor = G_reader_settings:readSetting("highlight_lighten_factor", 0.2),
        note_mark = G_reader_settings:readSetting("highlight_note_marker"),
        temp_drawer = "invert",
        temp = {},
        saved_drawer = "lighten",
        saved = {},
        indicator = nil, -- geom: non-touch highlight position indicator: {x = 50, y=50}
    }
    self.page_states = {}
    self.page_gap = {
        -- color (0 = white, 8 = gray, 15 = black)
        color = Blitbuffer.gray((G_reader_settings:readSetting("page_gap_color") or 8) * (1/15)),
    }
    self.visible_area = Geom:new{x = 0, y = 0, w = 0, h = 0}
    self.page_area = Geom:new{x = 0, y = 0, w = 0, h = 0}
    self.dim_area = Geom:new{x = 0, y = 0, w = 0, h = 0}

    self:addWidgets()
    self.emitHintPageEvent = function()
        self.ui:handleEvent(Event:new("HintPage", self.hinting))
    end

    -- We've subclassed OverlapGroup, go through its init, because it does some funky stuff with self.dimen...
    OverlapGroup.init(self)
end

function ReaderView:addWidgets()
    self.dogear = ReaderDogear:new{
        view = self,
        ui = self.ui,
    }
    self.footer = ReaderFooter:new{
        view = self,
        ui = self.ui,
    }
    self.flipping = ReaderFlipping:new{
        view = self,
        ui = self.ui,
    }
    local arrow_size = Screen:scaleBySize(16)
    self.arrow = IconWidget:new{
        icon = "control.expand.alpha",
        width = arrow_size,
        height = arrow_size,
        alpha = true, -- Keep the alpha layer intact, the fill opacity is set at 75%
    }

    self[1] = self.dogear
    self[2] = self.footer
    self[3] = self.flipping
end

--[[--
Register a view UI widget module for document browsing.

@tparam string name module name, registered widget can be accessed by readerui.view.view_modules[name].
@tparam ui.widget.widget.Widget widget paintable widget, i.e. has a paintTo method.

@usage
local ImageWidget = require("ui/widget/imagewidget")
local dummy_image = ImageWidget:new{
    file = "resources/koreader.png",
}
-- the image will be painted on all book pages
readerui.view:registerViewModule('dummy_image', dummy_image)
]]
function ReaderView:registerViewModule(name, widget)
    if not widget.paintTo then
        print(name .. " view module does not have paintTo method!")
        return
    end
    widget.view = self
    widget.ui = self.ui
    self.view_modules[name] = widget
end

function ReaderView:resetLayout()
    for _, widget in ipairs(self) do
        widget:resetLayout()
    end
    for _, m in pairs(self.view_modules) do
        if m.resetLayout then m:resetLayout() end
    end
end

function ReaderView:paintTo(bb, x, y)
    dbg:v("readerview painting", self.visible_area, "to", x, y)
    if self.page_scroll then
        self:drawPageBackground(bb, x, y)
    else
        self:drawPageSurround(bb, x, y)
    end

    -- draw page content
    if self.ui.paging then
        if self.page_scroll then
            self:drawScrollPages(bb, x, y)
        else
            self:drawSinglePage(bb, x, y)
        end
    else
        if self.view_mode == "page" then
            self:drawPageView(bb, x, y)
        elseif self.view_mode == "scroll" then
            self:drawScrollView(bb, x, y)
        end
        local should_repaint = self.ui.rolling:handlePartialRerendering()
        if should_repaint then
            -- ReaderRolling may have repositionned on another page containing
            -- the xpointer of the top of the original page: recalling this is
            -- all there is to do.
            self:paintTo(bb, x, y)
            return
        end
    end

    -- dim last read area
    if not self.dim_area:isEmpty() and self:isOverlapAllowed() then
        if self.page_overlap_style == "dim" then
            bb:dimRect(
                self.dim_area.x, self.dim_area.y,
                self.dim_area.w, self.dim_area.h
            )
        elseif self.page_overlap_style == "arrow" then
            local center_offset = bit.rshift(self.arrow.height, 1)
            -- Paint at the proper y origin depending on wheter we paged forward (dim_area.y == 0) or backward
            self.arrow:paintTo(bb, 0, self.dim_area.y == 0 and self.dim_area.h - center_offset or self.dim_area.y - center_offset)
        elseif self.page_overlap_style == "line" then
            bb:paintRect(0, self.dim_area.y == 0 and self.dim_area.h or self.dim_area.y,
                self.dim_area.w, Size.line.medium, Blitbuffer.COLOR_BLACK)
        end
    end
    -- draw saved highlight
    if self.highlight_visible then
        self:drawSavedHighlight(bb, x, y)
    end
    -- draw temporary highlight
    if self.highlight.temp then
        self:drawTempHighlight(bb, x, y)
    end
    -- draw highlight position indicator for non-touch
    if self.highlight.indicator then
        self:drawHighlightIndicator(bb, x, y)
    end
    -- paint dogear
    if self.dogear_visible then
        self.dogear:paintTo(bb, x, y)
    end
    -- paint footer
    if self.footer_visible then
        self.footer:paintTo(bb, x, y)
    end
    -- paint top left corner indicator
    self.flipping:paintTo(bb, x, y)
    -- paint view modules
    for _, m in pairs(self.view_modules) do
        m:paintTo(bb, x, y)
    end
    -- stop activity indicator
    self.ui:handleEvent(Event:new("StopActivityIndicator"))

    -- Most pages should not require dithering
    self.dialog.dithered = nil
    -- For KOpt, let the user choose.
    if self.ui.paging then
        if self.document.hw_dithering then
            self.dialog.dithered = true
        end
    else
        -- Whereas for CRe,
        -- If we're attempting to show a large enough amount of image data, request dithering (without triggering another repaint ;)).
        local img_count, img_coverage = self.document:getDrawnImagesStatistics()
        -- With some nil guards because this may not be implemented in every engine ;).
        if img_count and img_count > 0 and img_coverage and img_coverage >= 0.075 then
            self.dialog.dithered = true
            -- Request a flashing update while we're at it, but only if it's the first time we're painting it
            if self.state.drawn == false and G_reader_settings:nilOrTrue("refresh_on_pages_with_images") then
                UIManager:setDirty(nil, "full")
            end
        end
        self.state.drawn = true
    end
end

--[[
Given coordinates on the screen return position in original page
]]--
function ReaderView:screenToPageTransform(pos)
    if self.ui.paging then
        if self.page_scroll then
            return self:getScrollPagePosition(pos)
        else
            return self:getSinglePagePosition(pos)
        end
    else
        pos.page = self.document:getCurrentPage()
        return pos
    end
end

--[[
Given rectangle in original page return rectangle on the screen
]]--
function ReaderView:pageToScreenTransform(page, rect)
    if self.ui.paging then
        if self.page_scroll then
            return self:getScrollPageRect(page, rect)
        else
            return self:getSinglePageRect(rect)
        end
    else
        return rect
    end
end

--[[
Get page area on screen for a given page number
--]]
function ReaderView:getScreenPageArea(page)
    if self.ui.paging then
        local area = Geom:new{x = 0, y = 0}
        if self.page_scroll then
            for _, state in ipairs(self.page_states) do
                if page ~= state.page then
                    area.y = area.y + state.visible_area.h + state.offset.y
                    area.y = area.y + self.page_gap.height
                else
                    area.x = state.offset.x
                    area.w = state.visible_area.w
                    area.h = state.visible_area.h
                    return area
                end
            end
        else
            area.x = self.state.offset.x
            area.y = self.state.offset.y
            area.w = self.visible_area.w
            area.h = self.visible_area.h
            return area
        end
    else
        return self.dimen
    end
end

function ReaderView:drawPageBackground(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, self.page_bgcolor)
end

function ReaderView:drawPageSurround(bb, x, y)
    if self.dimen.h > self.visible_area.h then
        bb:paintRect(x, y, self.dimen.w, self.state.offset.y, self.outer_page_color)
        local bottom_margin = y + self.visible_area.h + self.state.offset.y
        bb:paintRect(x, bottom_margin, self.dimen.w, self.state.offset.y +
            self.footer:getHeight(), self.outer_page_color)
    end
    if self.dimen.w > self.visible_area.w then
        bb:paintRect(x, y, self.state.offset.x, self.dimen.h, self.outer_page_color)
        bb:paintRect(x + self.dimen.w - self.state.offset.x - 1, y,
            self.state.offset.x + 1, self.dimen.h, self.outer_page_color)
    end
end

function ReaderView:drawScrollPages(bb, x, y)
    local pos = Geom:new{x = x , y = y}
    for page, state in ipairs(self.page_states) do
        self.document:drawPage(
            bb,
            pos.x + state.offset.x,
            pos.y + state.offset.y,
            state.visible_area,
            state.page,
            state.zoom,
            state.rotation,
            state.gamma,
            self.render_mode)
        pos.y = pos.y + state.visible_area.h
        -- draw page gap if not the last part
        if page ~= #self.page_states then
            self:drawPageGap(bb, pos.x, pos.y)
            pos.y = pos.y + self.page_gap.height
        end
    end
    UIManager:nextTick(self.emitHintPageEvent)
end

function ReaderView:getCurrentPageList()
    local pages = {}
    if self.ui.paging then
        if self.page_scroll then
            for _, state in ipairs(self.page_states) do
                table.insert(pages, state.page)
            end
        else
            table.insert(pages, self.state.page)
        end
    end
    return pages
end

function ReaderView:getScrollPagePosition(pos)
    local x_p, y_p
    local x_s, y_s = pos.x, pos.y
    for _, state in ipairs(self.page_states) do
        if y_s < state.visible_area.h + state.offset.y then
            y_p = (state.visible_area.y + y_s - state.offset.y) / state.zoom
            x_p = (state.visible_area.x + x_s - state.offset.x) / state.zoom
            return {
                x = x_p,
                y = y_p,
                page = state.page,
                zoom = state.zoom,
                rotation = state.rotation,
            }
        else
            y_s = y_s - state.visible_area.h - self.page_gap.height
        end
    end
end

function ReaderView:getScrollPageRect(page, rect_p)
    local rect_s = Geom:new{}
    for _, state in ipairs(self.page_states) do
        local trans_p = Geom:new(rect_p):copy()
        trans_p:transformByScale(state.zoom, state.zoom)
        if page == state.page and state.visible_area:intersectWith(trans_p) then
            rect_s.x = rect_s.x + state.offset.x + trans_p.x - state.visible_area.x
            rect_s.y = rect_s.y + state.offset.y + trans_p.y - state.visible_area.y
            rect_s.w = trans_p.w
            rect_s.h = trans_p.h
            return rect_s
        end
        rect_s.y = rect_s.y + state.visible_area.h + self.page_gap.height
    end
end

function ReaderView:drawPageGap(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.page_gap.height, self.page_gap.color)
end

function ReaderView:drawSinglePage(bb, x, y)
    self.document:drawPage(
        bb,
        x + self.state.offset.x,
        y + self.state.offset.y,
        self.visible_area,
        self.state.page,
        self.state.zoom,
        self.state.rotation,
        self.state.gamma,
        self.render_mode)
    UIManager:nextTick(self.emitHintPageEvent)
end

function ReaderView:getSinglePagePosition(pos)
    local x_s, y_s = pos.x, pos.y
    return {
        x = (self.visible_area.x + x_s - self.state.offset.x) / self.state.zoom,
        y = (self.visible_area.y + y_s - self.state.offset.y) / self.state.zoom,
        page = self.state.page,
        zoom = self.state.zoom,
        rotation = self.state.rotation,
    }
end

function ReaderView:getSinglePageRect(rect_p)
    local rect_s = Geom:new{}
    local trans_p = Geom:new(rect_p):copy()
    trans_p:transformByScale(self.state.zoom, self.state.zoom)
    if self.visible_area:intersectWith(trans_p) then
        rect_s.x = self.state.offset.x + trans_p.x - self.visible_area.x
        rect_s.y = self.state.offset.y + trans_p.y - self.visible_area.y
        rect_s.w = trans_p.w
        rect_s.h = trans_p.h
        return rect_s
    end
end

function ReaderView:drawPageView(bb, x, y)
    self.document:drawCurrentViewByPage(
        bb,
        x + self.state.offset.x,
        y + self.state.offset.y,
        self.visible_area,
        self.state.page)
end

function ReaderView:drawScrollView(bb, x, y)
    self.document:drawCurrentViewByPos(
        bb,
        x + self.state.offset.x,
        y + self.state.offset.y,
        self.visible_area,
        self.state.pos)
end

function ReaderView:drawHighlightIndicator(bb, x, y)
    local rect = self.highlight.indicator
    -- paint big cross line +
    bb:paintRect(
        rect.x,
        rect.y + rect.h / 2 - Size.border.thick / 2,
        rect.w,
        Size.border.thick
    )
    bb:paintRect(
        rect.x + rect.w / 2 - Size.border.thick / 2,
        rect.y,
        Size.border.thick,
        rect.h
    )
end

function ReaderView:drawTempHighlight(bb, x, y)
    for page, boxes in pairs(self.highlight.temp) do
        for i = 1, #boxes do
            local rect = self:pageToScreenTransform(page, boxes[i])
            if rect then
                self:drawHighlightRect(bb, x, y, rect, self.highlight.temp_drawer)
            end
        end
    end
end

function ReaderView:drawSavedHighlight(bb, x, y)
    if self.ui.paging then
        self:drawPageSavedHighlight(bb, x, y)
    else
        self:drawXPointerSavedHighlight(bb, x, y)
    end
end

-- Returns the list of highlights in page.
-- The list includes full single-page highlights and parts of multi-page highlights.
function ReaderView:getPageSavedHighlights(page)
    local highlights = {}
    local is_reflow = self.document.configurable.text_wrap
    self.document.configurable.text_wrap = 0
    for page_num, page_highlights in pairs(self.highlight.saved) do
        for i, highlight in ipairs(page_highlights) do
            -- old single-page reflow highlights do not have page in position
            local pos0_page = highlight.pos0.page or page_num
            local pos1_page = highlight.pos1.page or page_num
            if pos0_page <= page and page <= pos1_page then
                if pos0_page == pos1_page then -- single-page highlight
                    table.insert(highlights, highlight)
                else -- multi-page highlight
                    local item = self.ui.highlight:getSavedExtendedHighlightPage(highlight, page, i)
                    table.insert(highlights, item)
                end
            end
        end
    end
    self.document.configurable.text_wrap = is_reflow
    return highlights
end

function ReaderView:drawPageSavedHighlight(bb, x, y)
    local pages = self:getCurrentPageList()
    for _, page in ipairs(pages) do
        local items = self:getPageSavedHighlights(page)
        for _, item in ipairs(items) do
            local boxes = self.document:getPageBoxesFromPositions(page, item.pos0, item.pos1)
            if boxes then
                local drawer = item.drawer or self.highlight.saved_drawer
                local draw_note_mark = self.highlight.note_mark and
                    self.ui.bookmark:getBookmarkNote({datetime = item.datetime})
                for _, box in ipairs(boxes) do
                    local rect = self:pageToScreenTransform(page, box)
                    if rect then
                        self:drawHighlightRect(bb, x, y, rect, drawer, draw_note_mark)
                        if draw_note_mark and self.highlight.note_mark == "sidemark" then
                            draw_note_mark = false -- side mark in the first line only
                        end
                    end
                end
            end
        end
    end
end

function ReaderView:drawXPointerSavedHighlight(bb, x, y)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    local cur_view_top, cur_view_bottom
    for _, items in pairs(self.highlight.saved) do
        if items then
            for j = 1, #items do
                local item = items[j]
                local pos0, pos1 = item.pos0, item.pos1
                -- document:getScreenBoxesFromPositions() is expensive, so we
                -- first check this item is on current page
                if not cur_view_top then
                    -- Even in page mode, it's safer to use pos and ui.dimen.h
                    -- than pages' xpointers pos, even if ui.dimen.h is a bit
                    -- larger than pages' heights
                    cur_view_top = self.document:getCurrentPos()
                    if self.view_mode == "page" and self.document:getVisiblePageCount() > 1 then
                        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
                    else
                        cur_view_bottom = cur_view_top + self.ui.dimen.h
                    end
                end
                local spos0 = self.document:getPosFromXPointer(pos0)
                local spos1 = self.document:getPosFromXPointer(pos1)
                local start_pos = math.min(spos0, spos1)
                local end_pos = math.max(spos0, spos1)
                if start_pos <= cur_view_bottom and end_pos >= cur_view_top then
                    local boxes = self.document:getScreenBoxesFromPositions(pos0, pos1, true) -- get_segments=true
                    if boxes then
                        local drawer = item.drawer or self.highlight.saved_drawer
                        local draw_note_mark = self.highlight.note_mark and
                            self.ui.bookmark:getBookmarkNote({datetime = item.datetime})
                        for _, box in ipairs(boxes) do
                            if box.h ~= 0 then
                                self:drawHighlightRect(bb, x, y, box, drawer, draw_note_mark)
                                if draw_note_mark and self.highlight.note_mark == "sidemark" then
                                    draw_note_mark = false -- side mark in the first line only
                                end
                            end
                        end -- end for each box
                    end -- end if boxes
                end
            end -- end for each highlight
        end
    end -- end for all saved highlight
end

function ReaderView:drawHighlightRect(bb, _x, _y, rect, drawer, draw_note_mark)
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    if drawer == "lighten" then
        bb:lightenRect(x, y, w, h, self.highlight.lighten_factor)
    elseif drawer == "underscore" then
        bb:paintRect(x, y + h - 1, w, Size.line.medium, Blitbuffer.COLOR_GRAY)
    elseif drawer == "strikeout" then
        local line_y = y + math.floor(h / 2) + 1
        if self.ui.paging then
            line_y = line_y + 2
        end
        bb:paintRect(x, line_y, w, Size.line.medium, Blitbuffer.COLOR_BLACK)
    elseif drawer == "invert" then
        bb:invertRect(x, y, w, h)
    end
    if draw_note_mark then
        if self.highlight.note_mark == "underline" then
            bb:paintRect(x, y + h - 1, w, Size.line.medium, Blitbuffer.COLOR_BLACK)
        else
            local note_mark_pos_x
            if self.ui.paging or
                    (self.ui.document:getVisiblePageCount() == 1) or -- one-page mode
                    (x < Screen:getWidth() / 2) then -- page 1 in two-page mode
                note_mark_pos_x = self.note_mark_pos_x1
            else
                note_mark_pos_x = self.note_mark_pos_x2
            end
            if self.highlight.note_mark == "sideline" then
                bb:paintRect(note_mark_pos_x, y, self.note_mark_line_w, h, Blitbuffer.COLOR_BLACK)
            elseif self.highlight.note_mark == "sidemark" then
                self.note_mark_sign:paintTo(bb, note_mark_pos_x, y)
            end
        end
    end
end

function ReaderView:getPageArea(page, zoom, rotation)
    if self.use_bbox then
        return self.document:getUsedBBoxDimensions(page, zoom, rotation)
    else
        return self.document:getPageDimensions(page, zoom, rotation)
    end
end

--[[
This method is supposed to be only used by ReaderPaging
--]]
function ReaderView:recalculate()
    -- Start by resetting the dithering flag early, so it doesn't carry over from the previous page.
    self.dialog.dithered = nil

    if self.ui.paging and self.state.page then
        self.page_area = self:getPageArea(
            self.state.page,
            self.state.zoom,
            self.state.rotation)
        -- reset our size
        self.visible_area:setSizeTo(self.dimen)
        if self.footer_visible and not self.footer.settings.reclaim_height then
            self.visible_area.h = self.visible_area.h - self.footer:getHeight()
        end
        if self.document.configurable.writing_direction == 0 then
            -- starts from left of page_area
            self.visible_area.x = self.page_area.x
        else
            -- start from right of page_area
            self.visible_area.x = self.page_area.x + self.page_area.w - self.visible_area.w
        end
        if self.ui.zooming.zoom_bottom_to_top then
            -- starts from bottom of page_area
            self.visible_area.y = self.page_area.y + self.page_area.h - self.visible_area.h
        else
            -- starts from top of page_area
            self.visible_area.y = self.page_area.y
        end
        if not self.page_scroll then
            -- and recalculate it according to page size
            self.visible_area:offsetWithin(self.page_area, 0, 0)
        end
        -- clear dim area
        self.dim_area:clear()
        self.ui:handleEvent(
            Event:new("ViewRecalculate", self.visible_area, self.page_area))
    else
        self.visible_area:setSizeTo(self.dimen)
    end
    self.state.offset = Geom:new{x = 0, y = 0}
    if self.dimen.h > self.visible_area.h then
        if self.footer_visible and not self.footer.settings.reclaim_height then
            self.state.offset.y = (self.dimen.h - (self.visible_area.h + self.footer:getHeight())) / 2
        else
            self.state.offset.y = (self.dimen.h - self.visible_area.h) / 2
        end
    end
    if self.dimen.w > self.visible_area.w then
        self.state.offset.x = (self.dimen.w - self.visible_area.w) / 2
    end

    self:setupNoteMarkPosition()

    -- Flag a repaint so self:paintTo will be called
    -- NOTE: This is also unfortunately called during panning, essentially making sure we'll never be using "fast" for pans ;).
    UIManager:setDirty(self.dialog, self.currently_scrolling and "fast" or "partial")
end

function ReaderView:PanningUpdate(dx, dy)
    logger.dbg("pan by", dx, dy)
    local old = self.visible_area:copy()
    self.visible_area:offsetWithin(self.page_area, dx, dy)
    if self.visible_area ~= old then
        -- flag a repaint
        UIManager:setDirty(self.dialog, "partial")
        logger.dbg("on pan: page_area", self.page_area)
        logger.dbg("on pan: visible_area", self.visible_area)
        self.ui:handleEvent(
            Event:new("ViewRecalculate", self.visible_area, self.page_area))
    end
    return true
end

function ReaderView:PanningStart(x, y)
    logger.dbg("panning start", x, y)
    if not self.panning_visible_area then
        self.panning_visible_area = self.visible_area:copy()
    end
    self.visible_area = self.panning_visible_area:copy()
    self.visible_area:offsetWithin(self.page_area, x, y)
    self.ui:handleEvent(Event:new("ViewRecalculate", self.visible_area, self.page_area))
    UIManager:setDirty(self.dialog, "partial")
end

function ReaderView:PanningStop()
    self.panning_visible_area = nil
end

function ReaderView:SetZoomCenter(x, y)
    local old = self.visible_area:copy()
    self.visible_area:centerWithin(self.page_area, x, y)
    if self.visible_area ~= old then
        self.ui:handleEvent(Event:new("ViewRecalculate", self.visible_area, self.page_area))
        UIManager:setDirty(self.dialog, "partial")
    end
end

function ReaderView:getViewContext()
    if self.page_scroll then
        return self.page_states
    else
        return {
            {
                page = self.state.page,
                pos = self.state.pos,
                zoom = self.state.zoom,
                rotation = self.state.rotation,
                gamma = self.state.gamma,
                offset = self.state.offset:copy(),
                bbox = self.state.bbox,
            },
            self.visible_area:copy(),
            self.page_area:copy(),
        }
    end
end

function ReaderView:restoreViewContext(ctx)
    -- The format of the context is different depending on page_scroll.
    -- If we're asked to restore the other format, just ignore it
    -- (our only caller, ReaderPaging:onRestoreBookLocation(), will
    -- at least change to the page of the context, which is all that
    -- can be done when restoring from a different mode)
    if self.page_scroll then
        if ctx[1] and ctx[1].visible_area then
            self.page_states = ctx
            return true
        end
    else
        if ctx[1] and ctx[1].pos then
            self.state = ctx[1]
            self.visible_area = ctx[2]
            self.page_area = ctx[3]
            return true
        end
    end
    return false
end

function ReaderView:onSetRotationMode(rotation)
    if rotation ~= nil then
        if rotation == Screen:getRotationMode() then
            return true
        end
        Screen:setRotationMode(rotation)
    end
    UIManager:setDirty(self.dialog, "full")
    local new_screen_size = Screen:getSize()
    self.ui:handleEvent(Event:new("SetDimensions", new_screen_size))
    self.ui:onScreenResize(new_screen_size)
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
    Notification:notify(T(_("Rotation mode set to: %1"), optionsutil:getOptionText("SetRotationMode", rotation)))
    return true
end

function ReaderView:onSetDimensions(dimensions)
    self:resetLayout()
    self.dimen = dimensions
    -- recalculate view
    self:recalculate()
end

function ReaderView:onRestoreDimensions(dimensions)
    self:resetLayout()
    self.dimen = dimensions
    -- recalculate view
    self:recalculate()
end

function ReaderView:onSetFullScreen(full_screen)
    self.footer_visible = not full_screen
    self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
end

function ReaderView:onSetScrollMode(page_scroll)
    if self.ui.paging and page_scroll
            and self.ui.zooming.paged_modes[self.zoom_mode]
            and self.document.configurable.text_wrap == 0 then
        UIManager:show(InfoMessage:new{
            text = _([[
Continuous view (scroll mode) works best with zoom to page width, zoom to content width or zoom to rows.

In combination with zoom to fit page, page height, content height, content or columns, continuous view can cause unexpected shifts when turning pages.]]),
            timeout = 5,
        })
    end

    self.page_scroll = page_scroll
    if not page_scroll then
        self.document.configurable.page_scroll = 0
    end
    self:recalculate()
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

function ReaderView:onReadSettings(config)
    if self.ui.paging then
        self.document:setTileCacheValidity(config:readSetting("tile_cache_validity_ts"))
        self.render_mode = config:readSetting("render_mode") or 0
        self.state.gamma = config:readSetting("gamma") or 1.0
    end
    local rotation_mode = nil
    local locked = G_reader_settings:isTrue("lock_rotation")
    -- Keep current rotation by doing nothing when sticky rota is enabled.
    if not locked then
        -- Honor docsettings's rotation
        if config:has("rotation_mode") then
            rotation_mode = config:readSetting("rotation_mode") -- Doc's
        else
            -- No doc specific rotation, pickup global defaults for the doc type
            local setting_name = self.ui.paging and "kopt_rotation_mode" or "copt_rotation_mode"
            rotation_mode = G_reader_settings:readSetting(setting_name) or Screen.DEVICE_ROTATED_UPRIGHT
        end
    end
    if rotation_mode then
        self:onSetRotationMode(rotation_mode)
    end
    local full_screen = config:readSetting("kopt_full_screen") or self.document.configurable.full_screen
    if full_screen == 0 then
        self.footer_visible = false
    end
    self:resetLayout()
    local page_scroll = config:readSetting("kopt_page_scroll") or self.document.configurable.page_scroll
    self.page_scroll = page_scroll == 1 and true or false
    self.highlight.saved = config:readSetting("highlight", {})
    -- Highlight formats in crengine and mupdf are incompatible.
    -- Backup highlights when the document is opened with incompatible engine.
    local page, page_highlights
    while true do -- remove empty tables for pages without highlights and get the first page with highlights
        page, page_highlights = next(self.highlight.saved)
        if not page or #page_highlights > 0 then
            break -- we're done (there is none, or there is some usable)
        else
            self.highlight.saved[page] = nil -- clean it up while we're at it, and find another one
        end
    end
    if page_highlights then
        local highlight_type = type(page_highlights[1].pos0)
        if self.ui.rolling and highlight_type == "table" then
            config:saveSetting("highlight_paging", self.highlight.saved)
            self.highlight.saved = config:readSetting("highlight_rolling", {})
            config:saveSetting("highlight", self.highlight.saved)
            config:delSetting("highlight_rolling")
        elseif self.ui.paging and highlight_type == "string" then
            config:saveSetting("highlight_rolling", self.highlight.saved)
            self.highlight.saved = config:readSetting("highlight_paging", {})
            config:saveSetting("highlight", self.highlight.saved)
            config:delSetting("highlight_paging")
        end
    else
        if self.ui.rolling and config:has("highlight_rolling") then
            self.highlight.saved = config:readSetting("highlight_rolling")
            config:delSetting("highlight_rolling")
        elseif self.ui.paging and config:has("highlight_paging") then
            self.highlight.saved = config:readSetting("highlight_paging")
            config:delSetting("highlight_paging")
        end
    end
    self.inverse_reading_order = config:isTrue("inverse_reading_order") or G_reader_settings:isTrue("inverse_reading_order")
    self.page_overlap_enable = config:isTrue("show_overlap_enable") or G_reader_settings:isTrue("page_overlap_enable") or G_defaults:readSetting("DSHOWOVERLAP")
    self.page_overlap_style = config:readSetting("page_overlap_style") or G_reader_settings:readSetting("page_overlap_style") or "dim"
    self.page_gap.height = Screen:scaleBySize(config:readSetting("kopt_page_gap_height")
                                              or G_reader_settings:readSetting("kopt_page_gap_height")
                                              or 8)
end

function ReaderView:shouldInvertBiDiLayoutMirroring()
    -- A few widgets may temporarily invert UI layout mirroring when both these settings are true
    return self.inverse_reading_order and G_reader_settings:isTrue("invert_ui_layout_mirroring")
end

function ReaderView:onPageUpdate(new_page_no)
    self.state.page = new_page_no
    self.state.drawn = false
    self:recalculate()
    self.highlight.temp = {}
    self:checkAutoSaveSettings()
end

function ReaderView:onPosUpdate(new_pos)
    self.state.pos = new_pos
    self:recalculate()
    self.highlight.temp = {}
    self:checkAutoSaveSettings()
end

function ReaderView:onZoomUpdate(zoom)
    self.state.zoom = zoom
    self:recalculate()
    self.highlight.temp = {}
end

function ReaderView:onBBoxUpdate(bbox)
    self.use_bbox = bbox and true or false
end

function ReaderView:onRotationUpdate(rotation)
    self.state.rotation = rotation
    self:recalculate()
end

function ReaderView:onPageChangeAnimation(forward)
    if Device:canDoSwipeAnimation() and G_reader_settings:isTrue("swipe_animations") then
        if self.inverse_reading_order then forward = not forward end
        Screen:setSwipeAnimations(true)
        Screen:setSwipeDirection(forward)
    end
end

function ReaderView:onTogglePageChangeAnimation()
    G_reader_settings:flipNilOrFalse("swipe_animations")
end

function ReaderView:onReaderFooterVisibilityChange()
    -- Don't bother ReaderRolling with this nonsense, the footer's height is NOT handled via visible_area there ;)
    if self.ui.paging and self.state.page then
        -- We don't need to do anything if reclaim is enabled ;).
        if not self.footer.settings.reclaim_height then
            -- NOTE: Mimic what onSetFullScreen does, since, without reclaim, toggling the footer affects the available area,
            --       so we need to recompute the full layout.
            self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
            -- NOTE: Scroll mode's behavior after this might be suboptimal (until next page),
            --       but I'm not familiar enough with it to make it behave...
            --       (e.g., RedrawCurrentPage & co will snap to the top of the "current" page).
        end
    end
end

function ReaderView:onGammaUpdate(gamma)
    self.state.gamma = gamma
    if self.page_scroll then
        self.ui:handleEvent(Event:new("UpdateScrollPageGamma", gamma))
    end
    Notification:notify(T(_("Font gamma set to: %1."), gamma))
end

-- For ReaderKOptListener
function ReaderView:onDitheringUpdate()
    -- Do the device cap checks again, to avoid snafus when sharing configs between devices
    if Device:hasEinkScreen() then
        if Device:canHWDither() then
            if self.document.configurable.hw_dithering then
                self.document.hw_dithering = self.document.configurable.hw_dithering == 1
            end
        elseif Screen.fb_bpp == 8 then
            if self.document.configurable.sw_dithering then
                self.document.sw_dithering = self.document.configurable.sw_dithering == 1
            end
        end
    end
end

-- For KOptOptions
function ReaderView:onHWDitheringUpdate(toggle)
    self.document.hw_dithering = toggle
    Notification:notify(T(_("Hardware dithering set to: %1."), tostring(toggle)))
end

function ReaderView:onSWDitheringUpdate(toggle)
    self.document.sw_dithering = toggle
    Notification:notify(T(_("Software dithering set to: %1."), tostring(toggle)))
end

function ReaderView:onFontSizeUpdate(font_size)
    if self.ui.paging then
        self.ui:handleEvent(Event:new("ReZoom", font_size))
        Notification:notify(T(_("Font zoom set to: %1."), font_size))
    end
end

function ReaderView:onDefectSizeUpdate()
    self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onPageCrop()
    self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onMarginUpdate()
    self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onSetViewMode(new_mode)
    if new_mode ~= self.view_mode then
        self.view_mode = new_mode
        self.document:setViewMode(new_mode)
        self.ui:handleEvent(Event:new("ChangeViewMode"))
        Notification:notify(T( _("View mode set to: %1"), optionsutil:getOptionText("SetViewMode", new_mode)))
    end
end

--Refresh after changing a variable done by koptoptions.lua since all of them
--requires full screen refresh. If this handler used for changing page gap from
--another source (eg. coptions.lua) triggering a redraw is needed.
function ReaderView:onPageGapUpdate(page_gap)
    self.page_gap.height = page_gap
    Notification:notify(T(_("Page gap set to %1."), page_gap))
    return true
end

function ReaderView:onSaveSettings()
    if self.ui.paging then
        if self.document:isEdited() and G_reader_settings:readSetting("save_document") ~= "always" then
            -- Either "disable" (and the current tiles will be wrong) or "prompt" (but the
            -- prompt will happen later, too late to catch "Don't save"), so force cached
            -- tiles to be ignored on next opening.
            self.document:resetTileCacheValidity()
        end
        self.ui.doc_settings:saveSetting("tile_cache_validity_ts", self.document:getTileCacheValidity())
        self.ui.doc_settings:saveSetting("render_mode", self.render_mode)
        self.ui.doc_settings:saveSetting("gamma", self.state.gamma)
    end
    -- Don't etch the current rotation in stone when sticky rotation is enabled
    local locked = G_reader_settings:isTrue("lock_rotation")
    if not locked then
        self.ui.doc_settings:saveSetting("rotation_mode", Screen:getRotationMode())
    end
    self.ui.doc_settings:saveSetting("highlight", self.highlight.saved)
    self.ui.doc_settings:saveSetting("inverse_reading_order", self.inverse_reading_order)
    self.ui.doc_settings:saveSetting("show_overlap_enable", self.page_overlap_enable)
    self.ui.doc_settings:saveSetting("page_overlap_style", self.page_overlap_style)
end

function ReaderView:getRenderModeMenuTable()
    local view = self
    local function make_mode(text, mode)
        return {
            text = text,
            checked_func = function() return view.render_mode == mode end,
            callback = function() view.render_mode = mode end,
        }
    end
    return  {
        -- @translators Selects which layers of the DjVu image should be rendered.  Valid  rendering  modes are color, black, mask, foreground, and background. See http://djvu.sourceforge.net/ and https://en.wikipedia.org/wiki/DjVu for more information about the format.
        text = _("DjVu render mode"),
        sub_item_table = {
            make_mode(_("COLOUR (works for both colour and b&w pages)"), 0),
            make_mode(_("BLACK & WHITE (for b&w pages only, much faster)"), 1),
            make_mode(_("COLOUR ONLY (slightly faster than COLOUR)"), 2),
            make_mode(_("MASK ONLY (for b&w pages only)"), 3),
            make_mode(_("COLOUR BACKGROUND (show only background)"), 4),
            make_mode(_("COLOUR FOREGROUND (show only foreground)"), 5),
        }
    }
end

function ReaderView:onCloseWidget()
    -- Stop any pending HintPage event
    UIManager:unschedule(self.emitHintPageEvent)
    --- @fixme: The awful readerhighlight_spec test *relies* on this pointer being left dangling...
    if not self.ui._testsuite then
        self.emitHintPageEvent = nil
    end
end

function ReaderView:onReaderReady()
    self.ui.doc_settings:delSetting("docsettings_reset_done")
    self.settings_last_save_time = UIManager:getElapsedTimeSinceBoot()
end

function ReaderView:onResume()
    -- As settings were saved on suspend, reset this on resume,
    -- as there's no need for a possibly immediate save.
    self.settings_last_save_time = UIManager:getElapsedTimeSinceBoot()
end

function ReaderView:checkAutoSaveSettings()
    if not self.settings_last_save_time then -- reader not yet ready
        return
    end
    if G_reader_settings:nilOrFalse("auto_save_settings_interval_minutes") then
        -- no auto save
        return
    end

    local interval_m = G_reader_settings:readSetting("auto_save_settings_interval_minutes")
    local interval = time.s(interval_m * 60)
    local now = UIManager:getElapsedTimeSinceBoot()
    if now - self.settings_last_save_time >= interval then
        self.settings_last_save_time = now
        -- I/O, delay until after the pageturn
        UIManager:tickAfterNext(function()
            self.ui:saveSettings()
        end)
    end
end

function ReaderView:isOverlapAllowed()
    if self.ui.paging then
        return not self.page_scroll
            and (self.ui.paging.zoom_mode ~= "page"
                or (self.ui.paging.zoom_mode == "page" and self.document.configurable.text_wrap == 1))
            and not self.ui.paging.zoom_mode:find("height")
    else
        return self.view_mode ~= "page"
    end
end

function ReaderView:setupTouchZones()
    (self.ui.rolling or self.ui.paging):setupTouchZones()
end

function ReaderView:onToggleReadingOrder()
    self.inverse_reading_order = not self.inverse_reading_order
    self:setupTouchZones()
    local is_rtl = self.inverse_reading_order ~= BD.mirroredUILayout() -- mirrored reading
    Notification:notify(is_rtl and _("RTL page turning.") or _("LTR page turning."))
    return true
end

function ReaderView:getTapZones()
    local forward_zone, backward_zone
    local tap_zones_type = G_reader_settings:readSetting("page_turns_tap_zones", "default")
    if tap_zones_type == "default" then
        local DTAP_ZONE_FORWARD = G_defaults:readSetting("DTAP_ZONE_FORWARD")
        forward_zone = {
            ratio_x = DTAP_ZONE_FORWARD.x, ratio_y = DTAP_ZONE_FORWARD.y,
            ratio_w = DTAP_ZONE_FORWARD.w, ratio_h = DTAP_ZONE_FORWARD.h,
        }
        local DTAP_ZONE_BACKWARD = G_defaults:readSetting("DTAP_ZONE_BACKWARD")
        backward_zone = {
            ratio_x = DTAP_ZONE_BACKWARD.x, ratio_y = DTAP_ZONE_BACKWARD.y,
            ratio_w = DTAP_ZONE_BACKWARD.w, ratio_h = DTAP_ZONE_BACKWARD.h,
        }
    else -- user defined page turns tap zones
        local tap_zone_forward_w = G_reader_settings:readSetting("page_turns_tap_zone_forward_size_ratio", G_defaults:readSetting("DTAP_ZONE_FORWARD").w)
        local tap_zone_backward_w = G_reader_settings:readSetting("page_turns_tap_zone_backward_size_ratio", G_defaults:readSetting("DTAP_ZONE_BACKWARD").w)
        if tap_zones_type == "left_right" then
            forward_zone = {
                ratio_x = 1 - tap_zone_forward_w, ratio_y = 0,
                ratio_w = tap_zone_forward_w, ratio_h = 1,
            }
            backward_zone = {
                ratio_x = 0, ratio_y = 0,
                ratio_w = tap_zone_backward_w, ratio_h = 1,
            }
        else
            forward_zone = {
                ratio_x = 0, ratio_y = 1 - tap_zone_forward_w,
                ratio_w = 1, ratio_h = tap_zone_forward_w,
            }
            backward_zone = {
                ratio_x = 0, ratio_y = 0,
                ratio_w = 1, ratio_h = tap_zone_backward_w,
            }
        end
    end
    if self.inverse_reading_order ~= BD.mirroredUILayout() then -- mirrored reading
        forward_zone.ratio_x = 1 - forward_zone.ratio_x - forward_zone.ratio_w
        backward_zone.ratio_x = 1 - backward_zone.ratio_x - backward_zone.ratio_w
    end
    return forward_zone, backward_zone
end

function ReaderView:setupNoteMarkPosition()
    local is_sidemark = self.highlight.note_mark == "sidemark"

    -- set/free note marker sign
    if is_sidemark then
        if not self.note_mark_sign then
            self.note_mark_sign = TextWidget:new{
                text = "\u{F040}", -- pencil
                face = Font:getFace("smallinfofont", 14),
                padding = 0,
            }
        end
    else
        if self.note_mark_sign then
            self.note_mark_sign:free()
            self.note_mark_sign = nil
        end
    end

    -- calculate position x of the note side line/mark
    if is_sidemark or self.highlight.note_mark == "sideline" then
        local screen_w = Screen:getWidth()
        local sign_w = is_sidemark and self.note_mark_sign:getWidth() or self.note_mark_line_w
        local sign_gap = Screen:scaleBySize(5) -- to the text (cre) or to the screen edge (pdf)
        if self.ui.paging then
            if BD.mirroredUILayout() then
                self.note_mark_pos_x1 = sign_gap
            else
                self.note_mark_pos_x1 = screen_w - sign_gap - sign_w
            end
        else
            local doc_margins = self.ui.document:getPageMargins()
            local pos_x_r = screen_w - doc_margins["right"] + sign_gap -- mark in the right margin
            local pos_x_l = doc_margins["left"] - sign_gap - sign_w -- mark in the left margin
            if self.ui.document:getVisiblePageCount() == 1 then
                if BD.mirroredUILayout() then
                    self.note_mark_pos_x1 = pos_x_l
                else
                    self.note_mark_pos_x1 = pos_x_r
                end
            else -- two-page mode
                local page2_x = self.ui.document:getPageOffsetX(self.ui.document:getCurrentPage(true)+1)
                if BD.mirroredUILayout() then
                    self.note_mark_pos_x1 = pos_x_l
                    self.note_mark_pos_x2 = pos_x_l + page2_x
                else
                    self.note_mark_pos_x1 = pos_x_r - page2_x
                    self.note_mark_pos_x2 = pos_x_r
                end
            end
        end
    end
end

return ReaderView
