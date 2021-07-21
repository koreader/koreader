--[[--
ReaderView module handles all the screen painting for document browsing.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderDogear = require("apps/reader/modules/readerdogear")
local ReaderFlipping = require("apps/reader/modules/readerflipping")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local logger = require("logger")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderView = OverlapGroup:extend{
    document = nil,

    -- single page state
    state = {
        page = nil,
        pos = 0,
        zoom = 1.0,
        rotation = 0,
        gamma = 1.0,
        offset = nil,
        bbox = nil,
    },
    outer_page_color = Blitbuffer.gray(DOUTER_PAGE_COLOR / 15),
    -- highlight with "lighten" or "underscore" or "invert"
    highlight = {
        lighten_factor = G_reader_settings:readSetting("highlight_lighten_factor", 0.2),
        temp_drawer = "invert",
        temp = {},
        saved_drawer = "lighten",
        saved = {},
    },
    highlight_visible = true,
    -- PDF/DjVu continuous paging
    page_scroll = nil,
    page_bgcolor = Blitbuffer.gray(DBACKGROUND_COLOR / 15),
    page_states = {},
    -- properties of the gap drawn between each page in scroll mode:
    page_gap = {
        -- color (0 = white, 8 = gray, 15 = black)
        color = Blitbuffer.gray((G_reader_settings:readSetting("page_gap_color") or 8) / 15),
    },
    -- DjVu page rendering mode (used in djvu.c:drawPage())
    render_mode = DRENDER_MODE, -- default to COLOR
    -- Crengine view mode
    view_mode = DCREREADER_VIEW_MODE, -- default to page mode
    hinting = true,

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
    settings_last_save_tv = nil,
    -- might be directly updated by readerpaging/readerrolling when
    -- they handle some panning/scrolling, to request "fast" refreshes
    currently_scrolling = false,
}

function ReaderView:init()
    self.view_modules = {}
    -- fix recalculate from close document pageno
    self.state.page = nil

    -- Reset the various areas across documents
    self.visible_area = Geom:new{x = 0, y = 0, w = 0, h = 0}
    self.page_area = Geom:new{x = 0, y = 0, w = 0, h = 0}
    self.dim_area = Geom:new{x = 0, y = 0, w = 0, h = 0}

    self:addWidgets()
    self.emitHintPageEvent = function()
        self.ui:handleEvent(Event:new("HintPage", self.hinting))
    end
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
    if self.ui.document.info.has_pages then
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
    end

    -- dim last read area
    if not self.dim_area:isEmpty() then
        if self.page_overlap_style == "dim" then
            bb:dimRect(
                self.dim_area.x, self.dim_area.y,
                self.dim_area.w, self.dim_area.h
            )
        elseif self.page_overlap_style == "arrow" then
            local center_offset = bit.rshift(self.arrow.height, 1)
            -- Paint at the proper y origin depending on wheter we paged forward (dim_area.y == 0) or backward
            self.arrow:paintTo(bb, 0, self.dim_area.y == 0 and self.dim_area.h - center_offset or self.dim_area.y - center_offset)
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
    -- paint dogear
    if self.dogear_visible then
        self.dogear:paintTo(bb, x, y)
    end
    -- paint footer
    if self.footer_visible then
        self.footer:paintTo(bb, x, y)
    end
    -- paint flipping
    if self.flipping_visible then
        self.flipping:paintTo(bb, x, y)
    end
    for _, m in pairs(self.view_modules) do
        m:paintTo(bb, x, y)
    end
    -- stop activity indicator
    self.ui:handleEvent(Event:new("StopActivityIndicator"))

    -- Most pages should not require dithering
    self.dialog.dithered = nil
    -- For KOpt, let the user choose.
    if self.ui.document.info.has_pages then
        -- Also enforce dithering in PicDocument
        if self.ui.document.is_pic or self.document.configurable.hw_dithering == 1 then
            self.dialog.dithered = true
        end
    else
        -- Whereas for CRe,
        -- If we're attempting to show a large enough amount of image data, request dithering (without triggering another repaint ;)).
        local img_count, img_coverage = self.ui.document:getDrawnImagesStatistics()
        -- With some nil guards because this may not be implemented in every engine ;).
        if img_count and img_count > 0 and img_coverage and img_coverage >= 0.075 then
            self.dialog.dithered = true
            -- Request a flashing update while we're at it, but only if it's the first time we're painting it
            if self.state.drawn == false then
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
    if self.ui.document.info.has_pages then
        if self.page_scroll then
            return self:getScrollPagePosition(pos)
        else
            return self:getSinglePagePosition(pos)
        end
    else
        pos.page = self.ui.document:getCurrentPage()
        -- local last_y = self.ui.document:getCurrentPos()
        logger.dbg("document has no pages at", pos)
        return pos
    end
end

--[[
Given rectangle in original page return rectangle on the screen
]]--
function ReaderView:pageToScreenTransform(page, rect)
    if self.ui.document.info.has_pages then
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
    if self.ui.document.info.has_pages then
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
            self.ui.view.footer:getHeight(), self.outer_page_color)
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
        self.ui.document:drawPage(
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
    if self.ui.document.info.has_pages then
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
    self.ui.document:drawPage(
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
    self.ui.document:drawCurrentViewByPage(
        bb,
        x + self.state.offset.x,
        y + self.state.offset.y,
        self.visible_area,
        self.state.page)
end

function ReaderView:drawScrollView(bb, x, y)
    self.ui.document:drawCurrentViewByPos(
        bb,
        x + self.state.offset.x,
        y + self.state.offset.y,
        self.visible_area,
        self.state.pos)
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
    if self.ui.document.info.has_pages then
        self:drawPageSavedHighlight(bb, x, y)
    else
        self:drawXPointerSavedHighlight(bb, x, y)
    end
end

function ReaderView:drawPageSavedHighlight(bb, x, y)
    local pages = self:getCurrentPageList()
    for _, page in pairs(pages) do
        local items = self.highlight.saved[page]
        if items then
            for i = 1, #items do
                local item = items[i]
                local pos0, pos1 = item.pos0, item.pos1
                local boxes = self.ui.document:getPageBoxesFromPositions(page, pos0, pos1)
                if boxes then
                    for _, box in pairs(boxes) do
                        local rect = self:pageToScreenTransform(page, box)
                        if rect then
                            self:drawHighlightRect(bb, x, y, rect, item.drawer or self.highlight.saved_drawer)
                        end
                    end -- end for each box
                end -- end if boxes
            end -- end for each highlight
        end
    end -- end for each page
end

function ReaderView:drawXPointerSavedHighlight(bb, x, y)
    -- Getting screen boxes is done for each tap on screen (changing pages,
    -- showing menu...). We might want to cache these boxes per page (and
    -- clear that cache when page layout change or highlights are added
    -- or removed).
    local cur_view_top, cur_view_bottom
    for page, items in pairs(self.highlight.saved) do
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
                    cur_view_top = self.ui.document:getCurrentPos()
                    if self.view_mode == "page" and self.ui.document:getVisiblePageCount() > 1 then
                        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
                    else
                        cur_view_bottom = cur_view_top + self.ui.dimen.h
                    end
                end
                local spos0 = self.ui.document:getPosFromXPointer(pos0)
                local spos1 = self.ui.document:getPosFromXPointer(pos1)
                local start_pos = math.min(spos0, spos1)
                local end_pos = math.max(spos0, spos1)
                if start_pos <= cur_view_bottom and end_pos >= cur_view_top then
                    local boxes = self.ui.document:getScreenBoxesFromPositions(pos0, pos1, true) -- get_segments=true
                    if boxes then
                        for _, box in pairs(boxes) do
                            local rect = self:pageToScreenTransform(page, box)
                            if rect then
                                self:drawHighlightRect(bb, x, y, rect, item.drawer or self.highlight.saved_drawer)
                            end
                        end -- end for each box
                    end -- end if boxes
                end
            end -- end for each highlight
        end
    end -- end for all saved highlight
end

function ReaderView:drawHighlightRect(bb, _x, _y, rect, drawer)
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h

    if drawer == "underscore" then
        self.highlight.line_width = self.highlight.line_width or 2
        self.highlight.line_color = self.highlight.line_color or Blitbuffer.COLOR_GRAY
        bb:paintRect(x, y+h-1, w,
            self.highlight.line_width,
            self.highlight.line_color)
    elseif drawer == "lighten" then
        bb:lightenRect(x, y, w, h, self.highlight.lighten_factor)
    elseif drawer == "invert" then
        bb:invertRect(x, y, w, h)
    end
end

function ReaderView:getPageArea(page, zoom, rotation)
    if self.use_bbox then
        return self.ui.document:getUsedBBoxDimensions(page, zoom, rotation)
    else
        return self.ui.document:getPageDimensions(page, zoom, rotation)
    end
end

--[[
This method is supposed to be only used by ReaderPaging
--]]
function ReaderView:recalculate()
    -- Start by resetting the dithering flag early, so it doesn't carry over from the previous page.
    self.dialog.dithered = nil

    if self.ui.document.info.has_pages and self.state.page then
        self.page_area = self:getPageArea(
            self.state.page,
            self.state.zoom,
            self.state.rotation)
        -- reset our size
        self.visible_area:setSizeTo(self.dimen)
        if self.ui.view.footer_visible and not self.ui.view.footer.settings.reclaim_height then
            self.visible_area.h = self.visible_area.h - self.ui.view.footer:getHeight()
        end
        if self.ui.document.configurable.writing_direction == 0 then
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
        if self.ui.view.footer_visible and not self.ui.view.footer.settings.reclaim_height then
            self.state.offset.y = (self.dimen.h - (self.visible_area.h + self.ui.view.footer:getHeight())) / 2
        else
            self.state.offset.y = (self.dimen.h - self.visible_area.h) / 2
        end
    end
    if self.dimen.w > self.visible_area.w then
        self.state.offset.x = (self.dimen.w - self.visible_area.w) / 2
    end
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
    if self.ui.document.info.has_pages and page_scroll
            and self.ui.zooming.paged_modes[self.zoom_mode]
            and self.ui.document.configurable.text_wrap == 0 then
        UIManager:show(InfoMessage:new{
            text = _([[
Continuous view (scroll mode) works best with zoom to page width, zoom to content width or zoom to rows.

In combination with zoom to fit page, page height, content height, content or columns, continuous view can cause unexpected shifts when turning pages.]]),
            timeout = 5,
        })
    end

    self.page_scroll = page_scroll
    if not page_scroll then
        self.ui.document.configurable.page_scroll = 0
    end
    self:recalculate()
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

function ReaderView:onReadSettings(config)
    self.document:setTileCacheValidity(config:readSetting("tile_cache_validity_ts"))
    self.render_mode = config:readSetting("render_mode") or 0
    local rotation_mode = nil
    local locked = G_reader_settings:isTrue("lock_rotation")
    -- Keep current rotation by doing nothing when sticky rota is enabled.
    if not locked then
        -- Honor docsettings's rotation
        if config:has("rotation_mode") then
            rotation_mode = config:readSetting("rotation_mode") -- Doc's
        else
            -- No doc specific rotation, pickup global defaults for the doc type
            if self.ui.document.info.has_pages then
                rotation_mode = G_reader_settings:readSetting("kopt_rotation_mode") or Screen.ORIENTATION_PORTRAIT
            else
                rotation_mode = G_reader_settings:readSetting("copt_rotation_mode") or Screen.ORIENTATION_PORTRAIT
            end
        end
    end
    if rotation_mode then
        self:onSetRotationMode(rotation_mode)
    end
    self.state.gamma = config:readSetting("gamma") or 1.0
    local full_screen = config:readSetting("kopt_full_screen") or self.document.configurable.full_screen
    if full_screen == 0 then
        self.footer_visible = false
    end
    self:resetLayout()
    local page_scroll = config:readSetting("kopt_page_scroll") or self.document.configurable.page_scroll
    self.page_scroll = page_scroll == 1 and true or false
    self.highlight.saved = config:readSetting("highlight") or {}
    self.page_overlap_style = config:readSetting("page_overlap_style") or G_reader_settings:readSetting("page_overlap_style") or "dim"
    self.page_gap.height = Screen:scaleBySize(config:readSetting("kopt_page_gap_height")
                                              or G_reader_settings:readSetting("kopt_page_gap_height")
                                              or 8)
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

function ReaderView:onReaderFooterVisibilityChange()
    -- Don't bother ReaderRolling with this nonsense, the footer's height is NOT handled via visible_area there ;)
    if self.ui.document.info.has_pages and self.state.page then
        -- NOTE: Simply relying on recalculate would be a wee bit too much: it'd reset the in-page offsets,
        --       which would be wrong, and is also not necessary, since the footer is at the bottom of the screen ;).
        --       So, simply mangle visible_area's height ourselves...
        if not self.ui.view.footer.settings.reclaim_height then
            -- NOTE: Yes, this means that toggling reclaim_height requires a page switch (for a proper recalculate).
            --       Thankfully, most of the time, the quirks are barely noticeable ;).
            if self.ui.view.footer_visible then
                self.visible_area.h = self.visible_area.h - self.ui.view.footer:getHeight()
            else
                self.visible_area.h = self.visible_area.h + self.ui.view.footer:getHeight()
            end
        end
        self.ui:handleEvent(Event:new("ViewRecalculate", self.visible_area, self.page_area))
    end
end

function ReaderView:onGammaUpdate(gamma)
    self.state.gamma = gamma
    if self.page_scroll then
        self.ui:handleEvent(Event:new("UpdateScrollPageGamma", gamma))
    end
    Notification:notify(T(_("Font gamma set to: %1."), gamma))
end

function ReaderView:onFontSizeUpdate(font_size)
    self.ui:handleEvent(Event:new("ReZoom", font_size))
    Notification:notify(T(_("Font zoom set to: %1."), font_size))
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
        self.ui.document:setViewMode(new_mode)
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
    if self.document:isEdited() and G_reader_settings:readSetting("save_document") ~= "always" then
        -- Either "disable" (and the current tiles will be wrong) or "prompt" (but the
        -- prompt will happen later, too late to catch "Don't save"), so force cached
        -- tiles to be ignored on next opening.
        self.document:resetTileCacheValidity()
    end
    self.ui.doc_settings:saveSetting("tile_cache_validity_ts", self.document:getTileCacheValidity())
    self.ui.doc_settings:saveSetting("render_mode", self.render_mode)
    -- Don't etch the current rotation in stone when sticky rotation is enabled
    local locked = G_reader_settings:isTrue("lock_rotation")
    if not locked then
        self.ui.doc_settings:saveSetting("rotation_mode", Screen:getRotationMode())
    end
    self.ui.doc_settings:saveSetting("gamma", self.state.gamma)
    self.ui.doc_settings:saveSetting("highlight", self.highlight.saved)
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

local page_overlap_styles = {
    arrow = _("Arrow"),
    dim = _("Gray out"),
}

function ReaderView:genOverlapStyleMenu(overlap_enabled_func)
    local view = self
    local get_overlap_style = function(style)
        return {
            text = page_overlap_styles[style],
            enabled_func = overlap_enabled_func,
            checked_func = function()
                return view.page_overlap_style == style
            end,
            callback = function()
                view.page_overlap_style = style
            end,
            hold_callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(
                        _("Set default overlap style to %1?"),
                        style
                    ),
                    ok_callback = function()
                        view.page_overlap_style = style
                        G_reader_settings:saveSetting("page_overlap_style", style)
                    end,
                })
            end,
        }
    end
    return {
        get_overlap_style("arrow"),
        get_overlap_style("dim"),
    }
end

function ReaderView:onCloseDocument()
    self.hinting = false
    -- stop any in fly HintPage event
    UIManager:unschedule(self.emitHintPageEvent)
end

function ReaderView:onReaderReady()
    self.settings_last_save_tv = UIManager:getTime()
end

function ReaderView:onResume()
    -- As settings were saved on suspend, reset this on resume,
    -- as there's no need for a possibly immediate save.
    self.settings_last_save_tv = UIManager:getTime()
end

function ReaderView:checkAutoSaveSettings()
    if not self.settings_last_save_tv then -- reader not yet ready
        return
    end
    if G_reader_settings:nilOrFalse("auto_save_settings_interval_minutes") then
        -- no auto save
        return
    end

    local interval = G_reader_settings:readSetting("auto_save_settings_interval_minutes")
    interval = TimeVal:new{ sec = interval*60, usec = 0 }
    local now_tv = UIManager:getTime()
    if now_tv - self.settings_last_save_tv >= interval then
        self.settings_last_save_tv = now_tv
        -- I/O, delay until after the pageturn
        UIManager:tickAfterNext(function()
            self.ui:saveSettings()
        end)
    end
end

return ReaderView
