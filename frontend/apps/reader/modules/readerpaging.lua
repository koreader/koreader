local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local Input = require("device").input
local Device = require("device")
local Screen = Device.screen
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local Math = require("optmath")
local logger = require("logger")
local _ = require("gettext")


local function copyPageState(page_state)
    return {
        page = page_state.page,
        zoom = page_state.zoom,
        rotation = page_state.rotation,
        gamma = page_state.gamma,
        offset = page_state.offset:copy(),
        visible_area = page_state.visible_area:copy(),
        page_area = page_state.page_area:copy(),
    }
end


local ReaderPaging = InputContainer:new{
    pan_rate = 30,  -- default 30 ops, will be adjusted in readerui
    current_page = 0,
    number_of_pages = 0,
    last_pan_relative_y = 0,
    visible_area = nil,
    page_area = nil,
    show_overlap_enable = nil,
    overlap = Screen:scaleBySize(DOVERLAPPIXELS),

    inverse_reading_order = false,
    page_flipping_mode = false,
    bookmark_flipping_mode = false,
    flip_steps = {0,1,2,5,10,20,50,100}
}

function ReaderPaging:init()
    if Device:hasKeyboard() or Device:hasKeys() then
        self.key_events = {
            GotoNextPage = {
                {Input.group.PgFwd}, doc = "go to next page",
                event = "PagingRel", args = 1 },
            GotoPrevPage = {
                {Input.group.PgBack}, doc = "go to previous page",
                event = "PagingRel", args = -1 },

            GotoFirst = {
                {"1"}, doc = "go to start", event = "GotoPercent", args = 0},
            Goto11 = {
                {"2"}, doc = "go to 11%", event = "GotoPercent", args = 11},
            Goto22 = {
                {"3"}, doc = "go to 22%", event = "GotoPercent", args = 22},
            Goto33 = {
                {"4"}, doc = "go to 33%", event = "GotoPercent", args = 33},
            Goto44 = {
                {"5"}, doc = "go to 44%", event = "GotoPercent", args = 44},
            Goto55 = {
                {"6"}, doc = "go to 55%", event = "GotoPercent", args = 55},
            Goto66 = {
                {"7"}, doc = "go to 66%", event = "GotoPercent", args = 66},
            Goto77 = {
                {"8"}, doc = "go to 77%", event = "GotoPercent", args = 77},
            Goto88 = {
                {"9"}, doc = "go to 88%", event = "GotoPercent", args = 88},
            GotoLast = {
                {"0"}, doc = "go to end", event = "GotoPercent", args = 100},
        }
    end
    self.number_of_pages = self.ui.document.info.number_of_pages
    self.ui.menu:registerToMainMenu(self)
end

function ReaderPaging:onReaderReady()
    self:setupTouchZones()
end

function ReaderPaging:setupTapTouchZones()
    local forward_zone = {
        ratio_x = DTAP_ZONE_FORWARD.x, ratio_y = DTAP_ZONE_FORWARD.y,
        ratio_w = DTAP_ZONE_FORWARD.w, ratio_h = DTAP_ZONE_FORWARD.h,
    }
    local backward_zone = {
        ratio_x = DTAP_ZONE_BACKWARD.x, ratio_y = DTAP_ZONE_BACKWARD.y,
        ratio_w = DTAP_ZONE_BACKWARD.w, ratio_h = DTAP_ZONE_BACKWARD.h,
    }

    if self.inverse_reading_order then
        forward_zone.ratio_x = 1 - forward_zone.ratio_x - forward_zone.ratio_w
        backward_zone.ratio_x = 1 - backward_zone.ratio_x - backward_zone.ratio_w
    end

    self.ui:registerTouchZones({
        {
            id = "tap_forward",
            ges = "tap",
            screen_zone = forward_zone,
            handler = function() return self:onTapForward() end
        },
        {
            id = "tap_backward",
            ges = "tap",
            screen_zone = backward_zone,
            handler = function() return self:onTapBackward() end
        },
    })
end

-- This method will be called in onSetDimensions handler
function ReaderPaging:setupTouchZones()
    -- deligate gesture listener to readerui
    self.ges_events = {}
    self.onGesture = nil

    if not Device:isTouchDevice() then return end

    self:setupTapTouchZones()
    self.ui:registerTouchZones({
        {
            id = "paging_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onSwipe(nil, ges) end
        },
        {
            id = "paging_pan",
            ges = "pan",
            rate = self.pan_rate,
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPan(nil, ges) end
        },
        {
            id = "paging_pan_release",
            ges = "pan_release",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPanRelease(nil, ges) end
        },
    })
end

function ReaderPaging:onReadSettings(config)
    self.page_positions = config:readSetting("page_positions") or {}
    self:_gotoPage(config:readSetting("last_page") or 1)
    self.show_overlap_enable = config:readSetting("show_overlap_enable")
    if self.show_overlap_enable == nil then
        self.show_overlap_enable = DSHOWOVERLAP
    end
    self.flipping_zoom_mode = config:readSetting("flipping_zoom_mode") or "page"
    self.flipping_scroll_mode = config:readSetting("flipping_scroll_mode") or false
    self.inverse_reading_order = config:readSetting("inverse_reading_order") or false
end

function ReaderPaging:onSaveSettings()
    -- TODO: only save current_page page position
    self.ui.doc_settings:saveSetting("page_positions", self.page_positions)
    self.ui.doc_settings:saveSetting("last_page", self:getTopPage())
    self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())
    self.ui.doc_settings:saveSetting("show_overlap_enable", self.show_overlap_enable)
    self.ui.doc_settings:saveSetting("flipping_zoom_mode", self.flipping_zoom_mode)
    self.ui.doc_settings:saveSetting("flipping_scroll_mode", self.flipping_scroll_mode)
    self.ui.doc_settings:saveSetting("inverse_reading_order", self.inverse_reading_order)
end

function ReaderPaging:getLastProgress()
    return self:getTopPage()
end

function ReaderPaging:getLastPercent()
    if self.current_page > 0 and self.number_of_pages > 0 then
        return self.current_page/self.number_of_pages
    end
end

function ReaderPaging:addToMainMenu(menu_items)
    -- FIXME: repeated code with page overlap menu for readerrolling
    -- needs to keep only one copy of the logic as for the DRY principle.
    -- The difference between the two menus is only the enabled func.
    local page_overlap_menu = {
        {
            text_func = function()
                return self.show_overlap_enable and _("Disable") or _("Enable")
            end,
            callback = function()
                self.show_overlap_enable = not self.show_overlap_enable
                if not self.show_overlap_enable then
                    self.view:resetDimArea()
                end
            end
        },
    }
    for _, menu_entry in ipairs(self.view:genOverlapStyleMenu()) do
        table.insert(page_overlap_menu, menu_entry)
    end
    menu_items.page_overlap = {
        text = _("Page overlap"),
        enabled_func = function()
            return not self.view.page_scroll and self.zoom_mode ~= "page"
                    and not self.zoom_mode:find("height")
        end,
        sub_item_table = page_overlap_menu,
    }
    menu_items.read_from_right_to_left = {
        text = _("Read from right to left"),
        checked_func = function() return self.inverse_reading_order end,
        callback = function()
            self.inverse_reading_order = not self.inverse_reading_order
            self:setupTapTouchZones()
        end,
    }
end

function ReaderPaging:onColorRenderingUpdate()
    self.ui.document:updateColorRendering()
end

--[[
Set reading position on certain page
Page position is a fractional number ranging from 0 to 1, indicating the read
percentage on certain page. With the position information on each page whenever
users change font size, page margin or line spacing or close and reopen the
book, the page view will be roughly the same.
--]]
function ReaderPaging:setPagePosition(page, pos)
    logger.dbg("set page position", pos)
    self.page_positions[page] = pos
end

--[[
Get reading position on certain page
--]]
function ReaderPaging:getPagePosition(page)
    -- Page number ought to be integer, somehow I notice that with
    -- fractional page number the reader runs silently well, but the
    -- number won't fit to retrieve page position.
    page = math.floor(page)
    logger.dbg("get page position", self.page_positions[page])
    return self.page_positions[page] or 0
end

function ReaderPaging:onTapForward()
    self:onPagingRel(1)
    return true
end

function ReaderPaging:onTapBackward()
    self:onPagingRel(-1)
    return true
end

function ReaderPaging:onTogglePageFlipping()
    self.view.flipping_visible = not self.view.flipping_visible
    self.page_flipping_mode = self.view.flipping_visible
    self.flipping_page = self.current_page

    if self.page_flipping_mode then
        self:updateOriginalPage(self.current_page)
        self:enterFlippingMode()
    else
        self:updateOriginalPage(nil)
        self:exitFlippingMode()
    end
    self.ui:handleEvent(Event:new("SetHinting", not self.page_flipping_mode))
    self.ui:handleEvent(Event:new("ReZoom"))
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:onToggleBookmarkFlipping()
     self.bookmark_flipping_mode = not self.bookmark_flipping_mode

    if self.bookmark_flipping_mode then
        self.orig_flipping_mode = self.view.flipping_visible
        self.orig_dogear_mode = self.view.dogear_visible

        self.view.flipping_visible = true
        self.view.dogear_visible = true
        self.bm_flipping_orig_page = self.current_page
        self:enterFlippingMode()
    else
        self.view.flipping_visible = self.orig_flipping_mode
        self.view.dogear_visible = self.orig_dogear_mode
        self:exitFlippingMode()
        self:_gotoPage(self.bm_flipping_orig_page)
    end
    self.ui:handleEvent(Event:new("SetHinting", not self.bookmark_flipping_mode))
    self.ui:handleEvent(Event:new("ReZoom"))
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:enterFlippingMode()
    self.orig_reflow_mode = self.view.document.configurable.text_wrap
    self.orig_scroll_mode = self.view.page_scroll
    self.orig_zoom_mode = self.view.zoom_mode
    logger.dbg("store zoom mode", self.orig_zoom_mode)
    self.view.document.configurable.text_wrap = 0
    self.view.page_scroll = self.flipping_scroll_mode
    Input.disable_double_tap = false
    self.ui:handleEvent(Event:new("EnterFlippingMode", self.flipping_zoom_mode))
end

function ReaderPaging:exitFlippingMode()
    self.view.document.configurable.text_wrap = self.orig_reflow_mode
    self.view.page_scroll = self.orig_scroll_mode
    Input.disable_double_tap = true
    self.flipping_zoom_mode = self.view.zoom_mode
    self.flipping_scroll_mode = self.view.page_scroll
    logger.dbg("restore zoom mode", self.orig_zoom_mode)
    self.ui:handleEvent(Event:new("ExitFlippingMode", self.orig_zoom_mode))
end

function ReaderPaging:updateOriginalPage(page)
    self.original_page = page
end

function ReaderPaging:updateFlippingPage(page)
    self.flipping_page = page
end

function ReaderPaging:pageFlipping(flipping_page, flipping_ges)
    local whole = self.number_of_pages
    local steps = #self.flip_steps
    local stp_proportion = flipping_ges.distance / Screen:getWidth()
    local abs_proportion = flipping_ges.distance / Screen:getHeight()
    if flipping_ges.direction == "east" then
        self:_gotoPage(flipping_page - self.flip_steps[math.ceil(steps*stp_proportion)])
    elseif flipping_ges.direction == "west" then
        self:_gotoPage(flipping_page + self.flip_steps[math.ceil(steps*stp_proportion)])
    elseif flipping_ges.direction == "south" then
        self:_gotoPage(flipping_page - math.floor(whole*abs_proportion))
    elseif flipping_ges.direction == "north" then
        self:_gotoPage(flipping_page + math.floor(whole*abs_proportion))
    end
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:bookmarkFlipping(flipping_page, flipping_ges)
    if flipping_ges.direction == "east" then
        self.ui:handleEvent(Event:new("GotoPreviousBookmark", flipping_page))
    elseif flipping_ges.direction == "west" then
        self.ui:handleEvent(Event:new("GotoNextBookmark", flipping_page))
    end
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:onSwipe(_, ges)
    if self.bookmark_flipping_mode then
        self:bookmarkFlipping(self.current_page, ges)
    elseif self.page_flipping_mode and self.original_page then
        self:_gotoPage(self.original_page)
    elseif ges.direction == "west" then
        if self.inverse_reading_order then
            self:onPagingRel(-1)
        else
            self:onPagingRel(1)
        end
    elseif ges.direction == "east" then
        if self.inverse_reading_order then
            self:onPagingRel(1)
        else
            self:onPagingRel(-1)
        end
    else
        -- update footer (time & battery)
        self.view.footer:updateFooter()
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
    end
end

function ReaderPaging:onPan(_, ges)
    if self.bookmark_flipping_mode then
        return true
    elseif self.page_flipping_mode then
        if self.view.zoom_mode == "page" then
            self:pageFlipping(self.flipping_page, ges)
        else
            self.view:PanningStart(-ges.relative.x, -ges.relative.y)
        end
    elseif ges.direction == "north" or ges.direction == "south" then
        self:onPanningRel(self.last_pan_relative_y - ges.relative.y)
        self.last_pan_relative_y = ges.relative.y
    end
    return true
end

function ReaderPaging:onPanRelease(_, ges)
    if self.page_flipping_mode then
        if self.view.zoom_mode == "page" then
            self:updateFlippingPage(self.current_page)
        else
            self.view:PanningStop()
        end
    else
        self.last_pan_relative_y = 0
        -- trigger full refresh to clear ghosting generated by previous fast refresh
        UIManager:setDirty(nil, "full")
    end
end

function ReaderPaging:onZoomModeUpdate(new_mode)
    -- we need to remember zoom mode to handle page turn event
    self.zoom_mode = new_mode
end

function ReaderPaging:onPageUpdate(new_page_no, orig_mode)
    self.current_page = new_page_no
    if self.view.page_scroll and orig_mode ~= "scrolling" then
        self.ui:handleEvent(Event:new("InitScrollPageStates", orig_mode))
    end
end

function ReaderPaging:onViewRecalculate(visible_area, page_area)
    -- we need to remember areas to handle page turn event
    self.visible_area = visible_area:copy()
    self.page_area = page_area
end

function ReaderPaging:onGotoPercent(percent)
    logger.dbg("goto document offset in percent:", percent)
    local dest = math.floor(self.number_of_pages * percent / 100)
    if dest < 1 then dest = 1 end
    if dest > self.number_of_pages then
        dest = self.number_of_pages
    end
    self:_gotoPage(dest)
    return true
end

function ReaderPaging:onPagingRel(diff)
    if self.view.page_scroll then
        self:onScrollPageRel(diff)
    else
        self:onGotoPageRel(diff)
    end
    self:setPagePosition(self:getTopPage(), self:getTopPosition())
    return true
end

function ReaderPaging:onPanningRel(diff)
    if self.view.page_scroll then
        self:onScrollPanRel(diff)
    end
    self:setPagePosition(self:getTopPage(), self:getTopPosition())
    return true
end

function ReaderPaging:getBookLocation()
    return self.view:getViewContext()
end

function ReaderPaging:onRestoreBookLocation(saved_location)
    if self.view.page_scroll then
        self.view:restoreViewContext(saved_location)
        self:_gotoPage(self.view.page_states[1].page, "scrolling")
    else
        -- gotoPage will emit PageUpdate event, which will trigger recalculate
        -- in ReaderView and resets the view context. So we need to call
        -- restoreViewContext after gotoPage
        self:_gotoPage(saved_location[1].page)
        self.view:restoreViewContext(saved_location)
    end
    self:setPagePosition(self:getTopPage(), self:getTopPosition())
    return true
end

--[[
Get read percentage on current page.
--]]
function ReaderPaging:getTopPosition()
    if self.view.page_scroll then
        local state = self.view.page_states[1]
        return (state.visible_area.y - state.page_area.y)/state.page_area.h
    else
        return 0
    end
end

--[[
Get page number of the page drawn at the very top part of the screen.
--]]
function ReaderPaging:getTopPage()
    if self.view.page_scroll then
        local state = self.view.page_states[1]
        return state and state.page or self.current_page
    else
        return self.current_page
    end
end

function ReaderPaging:onInitScrollPageStates(orig_mode)
    logger.dbg("init scroll page states", orig_mode)
    if self.view.page_scroll and self.view.state.page then
        self.orig_page = self.current_page
        self.view.page_states = {}
        local blank_area = Geom:new{}
        blank_area:setSizeTo(self.view.dimen)
        while blank_area.h > 0 do
            local offset = Geom:new{}
            -- caculate position in current page
            if self.current_page == self.orig_page then
                local page_area = self.view:getPageArea(
                    self.view.state.page,
                    self.view.state.zoom,
                    self.view.state.rotation)
                offset.y = page_area.h * self:getPagePosition(self.current_page)
            end
            local state = self:getNextPageState(blank_area, offset)
            table.insert(self.view.page_states, state)
            if blank_area.h > 0 then
                blank_area.h = blank_area.h - self.view.page_gap.height
            end
            if blank_area.h > 0 then
                self:_gotoPage(self.current_page + 1, "scrolling")
            end
        end
        self:_gotoPage(self.orig_page, "scrolling")
    end
    return true
end

function ReaderPaging:onUpdateScrollPageRotation(rotation)
    for _, state in ipairs(self.view.page_states) do
        state.rotation = rotation
    end
    return true
end

function ReaderPaging:onUpdateScrollPageGamma(gamma)
    for _, state in ipairs(self.view.page_states) do
        state.gamma = gamma
    end
    return true
end

function ReaderPaging:getNextPageState(blank_area, offset)
    local page_area = self.view:getPageArea(
        self.view.state.page,
        self.view.state.zoom,
        self.view.state.rotation)
    local visible_area = Geom:new{x = 0, y = 0}
    visible_area.w, visible_area.h = blank_area.w, blank_area.h
    visible_area.x, visible_area.y = page_area.x, page_area.y
    visible_area = visible_area:shrinkInside(page_area, offset.x, offset.y)
    -- shrink blank area by the height of visible area
    blank_area.h = blank_area.h - visible_area.h
    return {
        page = self.view.state.page,
        zoom = self.view.state.zoom,
        rotation = self.view.state.rotation,
        gamma = self.view.state.gamma,
        offset = Geom:new{ x = self.view.state.offset.x, y = 0},
        visible_area = visible_area,
        page_area = page_area,
    }
end

function ReaderPaging:getPrevPageState(blank_area, offset)
    local page_area = self.view:getPageArea(
        self.view.state.page,
        self.view.state.zoom,
        self.view.state.rotation)
    local visible_area = Geom:new{x = 0, y = 0}
    visible_area.w, visible_area.h = blank_area.w, blank_area.h
    visible_area.x = page_area.x
    visible_area.y = page_area.y + page_area.h - visible_area.h
    visible_area = visible_area:shrinkInside(page_area, offset.x, offset.y)
    -- shrink blank area by the height of visible area
    blank_area.h = blank_area.h - visible_area.h
    return {
        page = self.view.state.page,
        zoom = self.view.state.zoom,
        rotation = self.view.state.rotation,
        gamma = self.view.state.gamma,
        offset = Geom:new{ x = self.view.state.offset.x, y = 0},
        visible_area = visible_area,
        page_area = page_area,
    }
end

function ReaderPaging:updateTopPageState(state, blank_area, offset)
    local visible_area = Geom:new{
        x = state.visible_area.x,
        y = state.visible_area.y,
        w = blank_area.w,
        h = blank_area.h,
    }
    if state.page == self.number_of_pages then
        visible_area:offsetWithin(state.page_area, offset.x, offset.y)
    else
        visible_area = visible_area:shrinkInside(state.page_area, offset.x, offset.y)
    end
    -- shrink blank area by the height of visible area
    blank_area.h = blank_area.h - visible_area.h
    state.visible_area = visible_area
end

function ReaderPaging:updateBottomPageState(state, blank_area, offset)
    local visible_area = Geom:new{
        x = state.page_area.x,
        y = state.visible_area.y + state.visible_area.h - blank_area.h,
        w = blank_area.w,
        h = blank_area.h,
    }
    if state.page == 1 then
        visible_area:offsetWithin(state.page_area, offset.x, offset.y)
    else
        visible_area = visible_area:shrinkInside(state.page_area, offset.x, offset.y)
    end
    -- shrink blank area by the height of visible area
    blank_area.h = blank_area.h - visible_area.h
    state.visible_area = visible_area
end

function ReaderPaging:genPageStatesFromTop(top_page_state, blank_area, offset)
    -- Offset should always be greater than 0
    -- otherwise if offset is less than 0 the height of blank area will be
    -- larger than 0 even if page area is much larger than visible area,
    -- which will trigger the drawing of next page leaving part of current
    -- page undrawn. This should also be true for generating from bottom.
    if offset.y < 0 then offset.y = 0 end
    self:updateTopPageState(top_page_state, blank_area, offset)
    local page_states = {}
    if top_page_state.visible_area.h > 0 then
        -- offset does not scroll pass top_page_state
        table.insert(page_states, top_page_state)
    end
    local state
    local current_page = top_page_state.page
    while blank_area.h > 0 do
        blank_area.h = blank_area.h - self.view.page_gap.height
        if blank_area.h > 0 then
            if current_page == self.number_of_pages then break end
            self:_gotoPage(current_page + 1, "scrolling")
            current_page = current_page + 1
            state = self:getNextPageState(blank_area, Geom:new{})
            table.insert(page_states, state)
        end
    end
    return page_states
end

function ReaderPaging:genPageStatesFromBottom(bottom_page_state, blank_area, offset)
    -- scroll up offset should always be less than 0
    if offset.y > 0 then offset.y = 0 end
    -- find out number of pages need to be removed from current view
    self:updateBottomPageState(bottom_page_state, blank_area, offset)
    local page_states = {}
    if bottom_page_state.visible_area.h > 0 then
        table.insert(page_states, bottom_page_state)
    end
    -- fill up current view from bottom to top
    local state
    local current_page = bottom_page_state.page
    while blank_area.h > 0 do
        blank_area.h = blank_area.h - self.view.page_gap.height
        if blank_area.h > 0 then
            if current_page == 1 then break end
            self:_gotoPage(current_page - 1, "scrolling")
            current_page = current_page - 1
            state = self:getPrevPageState(blank_area, Geom:new{})
            table.insert(page_states, 1, state)
        end
    end
    return page_states
end

function ReaderPaging:onScrollPanRel(diff)
    if diff == 0 then return true end
    logger.dbg("pan relative height:", diff)
    local offset = Geom:new{x = 0, y = diff}
    local blank_area = Geom:new{}
    blank_area:setSizeTo(self.view.dimen)
    local new_page_states
    if diff > 0 then
        -- pan to scroll down
        local first_page_state = copyPageState(self.view.page_states[1])
        new_page_states = self:genPageStatesFromTop(
            first_page_state, blank_area, offset)
    elseif diff < 0 then
        local last_page_state = copyPageState(
            self.view.page_states[#self.view.page_states])
        new_page_states = self:genPageStatesFromBottom(
            last_page_state, blank_area, offset)
    end
    if #new_page_states == 0 then
        -- if we are already at the top of first page or bottom of the last
        -- page, new_page_states will be empty, in this case, nothing to update
        return true
    end
    self.view.page_states = new_page_states
    -- update current pageno to the very last part in current view
    self:_gotoPage(self.view.page_states[#self.view.page_states].page,
                   "scrolling")
    UIManager:setDirty(self.view.dialog, "fast")
    return true
end

function ReaderPaging:calculateOverlap()
    local footer_height = (self.view.footer_visible and 1 or 0) * self.view.footer.bar_height
    return self.overlap + footer_height
end

function ReaderPaging:onScrollPageRel(page_diff)
    if page_diff == 0 then return true end
    if page_diff > 0 then
        -- page down, last page should be moved to top
        local last_page_state = table.remove(self.view.page_states)
        local last_visible_area = last_page_state.visible_area
        if last_page_state.page == self.number_of_pages and
                last_visible_area.y + last_visible_area.h >= last_page_state.page_area.h then
            table.insert(self.view.page_states, last_page_state)
            self.ui:handleEvent(Event:new("EndOfBook"))
            return true
        end

        local blank_area = Geom:new{}
        blank_area:setSizeTo(self.view.dimen)
        local overlap = self:calculateOverlap()
        local offset = Geom:new{
            x = 0,
            y = last_visible_area.h - overlap
        }
        self.view.page_states = self:genPageStatesFromTop(last_page_state, blank_area, offset)
    elseif page_diff < 0 then
        -- page up, first page should be moved to bottom
        local blank_area = Geom:new{}
        blank_area:setSizeTo(self.view.dimen)
        local overlap = self:calculateOverlap()
        local first_page_state = table.remove(self.view.page_states, 1)
        local offset = Geom:new{
            x = 0,
            y = -first_page_state.visible_area.h + overlap
        }
        self.view.page_states = self:genPageStatesFromBottom(
            first_page_state, blank_area, offset)
    end
    -- update current pageno to the very last part in current view
    self:_gotoPage(self.view.page_states[#self.view.page_states].page, "scrolling")
    UIManager:setDirty(self.view.dialog, "partial")
    return true
end

function ReaderPaging:onGotoPageRel(diff)
    logger.dbg("goto relative page:", diff)
    local new_va = self.visible_area:copy()
    local x_pan_off, y_pan_off = 0, 0

    if self.zoom_mode:find("width") then
        y_pan_off = self.visible_area.h * diff
    elseif self.zoom_mode:find("height") then
        -- negative x panning if writing direction is right to left
        local direction = self.ui.document.configurable.writing_direction
        x_pan_off = self.visible_area.w * diff * (direction == 1 and -1 or 1)
    elseif self.zoom_mode ~= "free" then  -- do nothing in "free" zoom mode
        -- must be fit content or page zoom mode
        if self.visible_area.w == self.page_area.w then
            y_pan_off = self.visible_area.h * diff
        else
            x_pan_off = self.visible_area.w * diff
        end
    end
    -- adjust offset to help with page turn decision
    -- we dont take overlap into account here yet, otherwise new_va will
    -- always intersect with page_area
    x_pan_off = Math.roundAwayFromZero(x_pan_off)
    y_pan_off = Math.roundAwayFromZero(y_pan_off)
    new_va.x = Math.roundAwayFromZero(self.visible_area.x+x_pan_off)
    new_va.y = Math.roundAwayFromZero(self.visible_area.y+y_pan_off)

    if new_va:notIntersectWith(self.page_area) then
        -- view area out of page area, do a page turn
        local new_page = self.current_page + diff
        if diff > 0 and new_page == self.number_of_pages + 1 then
            self.ui:handleEvent(Event:new("EndOfBook"))
        else
            self:_gotoPage(new_page)
        end
        -- if we are going back to previous page, reset
        -- view area to bottom of previous page
        if x_pan_off < 0 then
            self.view:PanningUpdate(self.page_area.w, 0)
        elseif y_pan_off < 0 then
            self.view:PanningUpdate(0, self.page_area.h)
        end
    else
        -- not end of page yet, goto next view
        -- adjust panning step according to overlap
        local overlap = self:calculateOverlap()
        if x_pan_off > overlap then
            -- moving to next view, move view
            x_pan_off = x_pan_off - overlap
        elseif x_pan_off < -overlap then
            x_pan_off = x_pan_off + overlap
        end
        if y_pan_off > overlap then
            y_pan_off = y_pan_off - overlap
        elseif y_pan_off < -overlap then
            y_pan_off = y_pan_off + overlap
        end
        -- we have to calculate again to count into overlap
        new_va.x = Math.roundAwayFromZero(self.visible_area.x+x_pan_off)
        new_va.y = Math.roundAwayFromZero(self.visible_area.y+y_pan_off)
        -- fit new view area into page area
        new_va:offsetWithin(self.page_area, 0, 0)
        -- calculate panning offsets
        local panned_x = new_va.x - self.visible_area.x
        local panned_y = new_va.y - self.visible_area.y
        -- adjust for crazy floating point overflow...
        if math.abs(panned_x) < 1 then
            panned_x = 0
        end
        if math.abs(panned_y) < 1 then
            panned_y = 0
        end
        -- singal panning update
        self.view:PanningUpdate(panned_x, panned_y)
        -- update dime area in ReaderView
        if self.show_overlap_enable then
            self.view.dim_area.h = new_va.h - math.abs(panned_y)
            self.view.dim_area.w = new_va.w - math.abs(panned_x)
            if panned_y < 0 then
                self.view.dim_area.y = new_va.y - panned_y
            else
                self.view.dim_area.y = 0
            end
            if panned_x < 0 then
                self.view.dim_area.x = new_va.x - panned_x
            else
                self.view.dim_area.x = 0
            end
        end
        -- update self.visible_area
        self.visible_area = new_va
    end

    return true
end

function ReaderPaging:onRedrawCurrentPage()
    self.ui:handleEvent(Event:new("PageUpdate", self.current_page))
    return true
end

-- wrapper for bounds checking
function ReaderPaging:_gotoPage(number, orig_mode)
    if number == self.current_page or not number then
        -- update footer even if we stay on the same page (like when
        -- viewing the bottom part of a page from a top part view)
        self.view.footer:updateFooter()
        return true
    end
    if number > self.number_of_pages or number < 1 then
        logger.warn("wrong page number: "..number.."!")
        return false
    end
    -- this is an event to allow other controllers to be aware of this change
    self.ui:handleEvent(Event:new("PageUpdate", number, orig_mode))
    return true
end

function ReaderPaging:onGotoPage(number)
    self:_gotoPage(number)
    return true
end

function ReaderPaging:onGotoRelativePage(number)
    self:_gotoPage(self.current_page + number)
    return true
end

function ReaderPaging:onGotoPercentage(percentage)
    if percentage < 0 then percentage = 0 end
    if percentage > 1 then percentage = 1 end
    self:_gotoPage(math.floor(percentage*self.number_of_pages))
    return true
end

return ReaderPaging
