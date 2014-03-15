local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Input = require("ui/input")
local GestureRange = require("ui/gesturerange")
local Device = require("ui/device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local Math = require("optmath")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderPaging = InputContainer:new{
    current_page = 0,
    number_of_pages = 0,
    last_pan_relative_y = 0,
    visible_area = nil,
    page_area = nil,
    show_overlap_enable = nil,
    overlap = Screen:scaleByDPI(DOVERLAPPIXELS),
    
    page_flipping_mode = false,
    bookmark_flipping_mode = false,
    flip_steps = {0,1,2,5,10,20,50,100}
}

function ReaderPaging:init()
    if Device:hasKeyboard() then
        self.key_events = {
            GotoNextPage = {
                {Input.group.PgFwd}, doc = "go to next page",
                event = "GotoPageRel", args = 1 },
            GotoPrevPage = {
                {Input.group.PgBack}, doc = "go to previous page",
                event = "GotoPageRel", args = -1 },

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

-- This method will  be called in onSetDimensions handler
function ReaderPaging:initGesListener()
    self.ges_events = {
        TapForward = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Screen:getWidth()*DTAP_ZONE_FORWARD.x,
                    y = Screen:getHeight()*DTAP_ZONE_FORWARD.y,
                    w = Screen:getWidth()*DTAP_ZONE_FORWARD.w,
                    h = Screen:getHeight()*DTAP_ZONE_FORWARD.h,
                }
            }
        },
        TapBackward = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Screen:getWidth()*DTAP_ZONE_BACKWARD.x,
                    y = Screen:getHeight()*DTAP_ZONE_BACKWARD.y,
                    w = Screen:getWidth()*DTAP_ZONE_BACKWARD.w,
                    h = Screen:getHeight()*DTAP_ZONE_BACKWARD.h,
                }
            }
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        },
        Pan = {
            GestureRange:new{
                ges = "pan",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                rate = 4.0,
            }
        },
        PanRelease = {
            GestureRange:new{
                ges = "pan_release",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            }
        },
    }
end

function ReaderPaging:onReadSettings(config)
    self.page_positions = config:readSetting("page_positions") or {}
    self:gotoPage(config:readSetting("last_page") or 1)
    self.show_overlap_enable = config:readSetting("show_overlap_enable")
    if self.show_overlap_enable == nil then
        self.show_overlap_enable = DSHOWOVERLAP
    end
end

function ReaderPaging:onSaveSettings()
    self.ui.doc_settings:saveSetting("page_positions", self.page_positions)
    self.ui.doc_settings:saveSetting("last_page", self:getTopPage())
    self.ui.doc_settings:saveSetting("percent_finished", self.current_page/self.number_of_pages)
    self.ui.doc_settings:saveSetting("show_overlap_enable", self.show_overlap_enable)
end

function ReaderPaging:addToMainMenu(tab_item_table)
    if self.ui.document.info.has_pages then
        table.insert(tab_item_table.typeset, {
            text_func = function() 
                return self.show_overlap_enable and 
                _("Turn off page overlap") or 
                _("Turn on page overlap")
            end,
            callback = function()
                self.show_overlap_enable = not self.show_overlap_enable
            end
        })
    end
end

--[[
Set reading position on certain page
Page position is a fractional number ranging from 0 to 1, indicating the read percentage on
certain page. With the position information on each page whenever users change font size, 
page margin or line spacing or close and reopen the book, the page view will be roughly the same.
--]]
function ReaderPaging:setPagePosition(page, pos)
    DEBUG("set page position", pos)
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
    DEBUG("get page position", self.page_positions[page])
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
    self.view:resetLayout()
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
        self:gotoPage(self.bm_flipping_orig_page)
    end
    self.view:resetLayout()
    self.ui:handleEvent(Event:new("SetHinting", not self.bookmark_flipping_mode))
    self.ui:handleEvent(Event:new("ReZoom"))
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:enterFlippingMode()
    self.orig_reflow_mode = self.view.document.configurable.text_wrap
    self.orig_footer_mode = self.view.footer_visible
    self.orig_scroll_mode = self.view.page_scroll
    self.orig_zoom_mode = self.view.zoom_mode
    DEBUG("store zoom mode", self.orig_zoom_mode)
    self.DGESDETECT_DISABLE_DOUBLE_TAP = DGESDETECT_DISABLE_DOUBLE_TAP
    
    self.view.document.configurable.text_wrap = 0
    self.view.page_scroll = false
    self.view.footer_visible = true
    Input.disable_double_tap = false
    DGESDETECT_DISABLE_DOUBLE_TAP = false
    self.ui:handleEvent(Event:new("SetZoomMode", "page"))
end

function ReaderPaging:exitFlippingMode()
    self.view.document.configurable.text_wrap = self.orig_reflow_mode
    self.view.page_scroll = self.orig_scroll_mode
    self.view.footer_visible = self.orig_footer_mode
    DGESDETECT_DISABLE_DOUBLE_TAP = self.DGESDETECT_DISABLE_DOUBLE_TAP
    Input.disable_double_tap = DGESDETECT_DISABLE_DOUBLE_TAP
    DEBUG("restore zoom mode", self.orig_zoom_mode)
    self.ui:handleEvent(Event:new("SetZoomMode", self.orig_zoom_mode))
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
        self:gotoPage(flipping_page - self.flip_steps[math.ceil(steps*stp_proportion)])
    elseif flipping_ges.direction == "west" then
        self:gotoPage(flipping_page + self.flip_steps[math.ceil(steps*stp_proportion)])
    elseif flipping_ges.direction == "south" then
        self:gotoPage(flipping_page - math.floor(whole*abs_proportion))
    elseif flipping_ges.direction == "north" then
        self:gotoPage(flipping_page + math.floor(whole*abs_proportion))
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

function ReaderPaging:onSwipe(arg, ges)
    if self.bookmark_flipping_mode then
        self:bookmarkFlipping(self.current_page, ges)
    elseif self.page_flipping_mode and self.original_page then
        self:gotoPage(self.original_page)
    elseif ges.direction == "west" then
        self:onPagingRel(1)
    elseif ges.direction == "east" then
        self:onPagingRel(-1)
    else
        UIManager.full_refresh = true
    end
    return true
end

function ReaderPaging:onPan(arg, ges)
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

function ReaderPaging:onPanRelease(arg, ges)
    if self.page_flipping_mode then
        if self.view.zoom_mode == "page" then
            self:updateFlippingPage(self.current_page)
        else
            self.view:PanningStop()
        end
    else
        self.last_pan_relative_y = 0
        UIManager.full_refresh = true
    end
end

function ReaderPaging:onZoomModeUpdate(new_mode)
    -- we need to remember zoom mode to handle page turn event
    self.zoom_mode = new_mode
end

function ReaderPaging:onPageUpdate(new_page_no, orig)
    self.current_page = new_page_no
    if orig ~= "scrolling" then
        self.ui:handleEvent(Event:new("InitScrollPageStates", orig))
    end
end

function ReaderPaging:onViewRecalculate(visible_area, page_area)
    -- we need to remember areas to handle page turn event
    self.visible_area = visible_area:copy()
    self.page_area = page_area
end

function ReaderPaging:onGotoPercent(percent)
    DEBUG("goto document offset in percent:", percent)
    local dest = math.floor(self.number_of_pages * percent / 100)
    if dest < 1 then dest = 1 end
    if dest > self.number_of_pages then
        dest = self.number_of_pages
    end
    self:gotoPage(dest)
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

function ReaderPaging:onInitScrollPageStates(orig)
    --DEBUG.traceback()
    DEBUG("init scroll page states", orig)
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
            --DEBUG("init new state", state)
            table.insert(self.view.page_states, state)
            if blank_area.h > 0 then
                blank_area.h = blank_area.h - self.view.page_gap.height
            end
            if blank_area.h > 0 then
                self:gotoPage(self.current_page + 1, "scrolling")
            end
        end
        self:gotoPage(self.orig_page, "scrolling")
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
    local visible_area = Geom:new{x = 0, y = 0}
    visible_area.w, visible_area.h = blank_area.w, blank_area.h
    visible_area.x, visible_area.y = state.visible_area.x, state.visible_area.y
    if state.page == self.number_of_pages then
        visible_area:offsetWithin(state.page_area, offset.x, offset.y)
    else
        visible_area = visible_area:shrinkInside(state.page_area, offset.x, offset.y)
    end
    -- shrink blank area by the height of visible area
    blank_area.h = blank_area.h - visible_area.h
    state.visible_area = visible_area
    return state
end

function ReaderPaging:updateBottomPageState(state, blank_area, offset)
    local visible_area = Geom:new{x = 0, y = 0}
    visible_area.w, visible_area.h = blank_area.w, blank_area.h
    visible_area.x = state.page_area.x
    visible_area.y = state.visible_area.y + state.visible_area.h - visible_area.h
    if state.page == 1 then
        visible_area:offsetWithin(state.page_area, offset.x, offset.y)
    else
        visible_area = visible_area:shrinkInside(state.page_area, offset.x, offset.y)
    end
    -- shrink blank area by the height of visible area
    blank_area.h = blank_area.h - visible_area.h
    state.visible_area = visible_area
    return state
end

function ReaderPaging:genPageStatesFromTop(top_page_state, blank_area, offset)
    -- Offset should always be greater than 0
    -- otherwise if offset is less than 0 the height of blank area will be
    -- larger than 0 even if page area is much larger than visible area,
    -- which will trigger the drawing of next page leaving part of current
    -- page undrawn. This should also be true for generating from bottom.
    if offset.y < 0 then offset.y = 0 end
    local state = self:updateTopPageState(top_page_state, blank_area, offset)
    --DEBUG("updated state", state)
    local page_states = {}
    if state.visible_area.h > 0 then
        table.insert(page_states, state)
    end
    --DEBUG("blank area", blank_area)
    local current_page = state.page
    while blank_area.h > 0 do
        blank_area.h = blank_area.h - self.view.page_gap.height
        if blank_area.h > 0 then
            if self.current_page == self.number_of_pages then break end
            self:gotoPage(current_page + 1, "scrolling")
            current_page = current_page + 1
            local state = self:getNextPageState(blank_area, Geom:new{})
            --DEBUG("new state", state)
            table.insert(page_states, state)
        end
    end
    return page_states
end

function ReaderPaging:genPageStatesFromBottom(bottom_page_state, blank_area, offset)
    -- scroll up offset should always be less than 0
    if offset.y > 0 then offset.y = 0 end
    local state = self:updateBottomPageState(bottom_page_state, blank_area, offset)
    --DEBUG("updated state", state)
    local page_states = {}
    if state.visible_area.h > 0 then
        table.insert(page_states, state)
    end
    --DEBUG("blank area", blank_area)
    local current_page = state.page
    while blank_area.h > 0 do
        blank_area.h = blank_area.h - self.view.page_gap.height
        if blank_area.h > 0 then
            if self.current_page == 1 then break end
            self:gotoPage(current_page - 1, "scrolling")
            current_page = current_page - 1
            local state = self:getPrevPageState(blank_area, Geom:new{})
            --DEBUG("new state", state)
            table.insert(page_states, 1, state)
        end
    end
    return page_states
end

function ReaderPaging:onScrollPanRel(diff)
    DEBUG("pan relative height:", diff)
    local blank_area = Geom:new{}
    blank_area:setSizeTo(self.view.dimen)
    if diff > 0 then
        local first_page_state = table.remove(self.view.page_states, 1)
        local offset = Geom:new{
            x = 0,
            y = diff,
        }
        self.view.page_states = self:genPageStatesFromTop(first_page_state, blank_area, offset)
    end
    if diff < 0 then
        local last_page_state = table.remove(self.view.page_states)
        local offset = Geom:new{
            x = 0,
            y = diff
        }
        self.view.page_states = self:genPageStatesFromBottom(last_page_state, blank_area, offset)
    end
    -- update current pageno to the very last part in current view
    self:gotoPage(self.view.page_states[#self.view.page_states].page, "scrolling")
    
    UIManager:setDirty(self.view.dialog, "fast")
end

function ReaderPaging:onScrollPageRel(diff)
    DEBUG("scroll relative page:", diff)
    local blank_area = Geom:new{}
    blank_area:setSizeTo(self.view.dimen)
    if diff > 0 then
        local last_page_state = table.remove(self.view.page_states)
        local offset = Geom:new{
            x = 0,
            y = last_page_state.visible_area.h - self.overlap
        }
        self.view.page_states = self:genPageStatesFromTop(last_page_state, blank_area, offset)
    end
    if diff < 0 then
        local first_page_state = table.remove(self.view.page_states, 1)
        local offset = Geom:new{
            x = 0,
            y = -first_page_state.visible_area.h + self.overlap
        }
        self.view.page_states = self:genPageStatesFromBottom(first_page_state, blank_area, offset)
    end
    -- update current pageno to the very last part in current view
    self:gotoPage(self.view.page_states[#self.view.page_states].page, "scrolling")
    UIManager:setDirty(self.view.dialog)
end

function ReaderPaging:onGotoPageRel(diff)
    DEBUG("goto relative page:", diff)
    local new_va = self.visible_area:copy()
    local x_pan_off, y_pan_off = 0, 0

    if self.zoom_mode == "free" then
        -- do nothing in free zoom mode
    elseif self.zoom_mode:find("width") then
        y_pan_off = self.visible_area.h * diff
    elseif self.zoom_mode:find("height") then
        x_pan_off = self.visible_area.w * diff
    else
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
        self:gotoPage(self.current_page + diff)
        -- if we are going back to previous page, reset
        -- view area to bottom of previous page
        if x_pan_off < 0 then
            self.view:PanningUpdate(self.page_area.w, 0)
        elseif y_pan_off < 0 then
            self.view:PanningUpdate(0, self.page_area.h)
        end
        -- reset dim_area
        --self.view.dim_area.h = 0
        --self.view.dim_area.w = 0
        --
    else
        -- not end of page yet, goto next view
        -- adjust panning step according to overlap
        if x_pan_off > self.overlap then
            -- moving to next view, move view
            x_pan_off = x_pan_off - self.overlap
        elseif x_pan_off < -self.overlap then
            x_pan_off = x_pan_off + self.overlap
        end
        if y_pan_off > self.overlap then
            y_pan_off = y_pan_off - self.overlap
        elseif y_pan_off < -self.overlap then
            y_pan_off = y_pan_off + self.overlap
        end
        -- we have to calculate again to count into overlap
        new_va.x = Math.roundAwayFromZero(self.visible_area.x+x_pan_off)
        new_va.y = Math.roundAwayFromZero(self.visible_area.y+y_pan_off)
        -- fit new view area into page area
        new_va:offsetWithin(self.page_area, 0, 0)
        -- calculate panning offsets
        local panned_x = new_va.x - self.visible_area.x
        local panned_y = new_va.y - self.visible_area.y
        -- adjust for crazy float point overflow...
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

function ReaderPaging:onSetDimensions()
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

-- wrapper for bounds checking
function ReaderPaging:gotoPage(number, orig)
    --DEBUG.traceback()
    if number == self.current_page or not number then
        return true
    end
    if number > self.number_of_pages
    or number < 1 then
        DEBUG("wrong page number: "..number.."!")
        return false
    end
    DEBUG("going to page number", number)

    -- this is an event to allow other controllers to be aware of this change
    self.ui:handleEvent(Event:new("PageUpdate", number, orig))
    return true
end

function ReaderPaging:onGotoPage(number)
    self:gotoPage(number)
    return true
end

function ReaderPaging:onGotoPercentage(percentage)
    if percentage < 0 then percentage = 0 end
    if percentage > 1 then percentage = 1 end
    self:gotoPage(math.floor(percentage*self.number_of_pages))
    return true
end

return ReaderPaging
