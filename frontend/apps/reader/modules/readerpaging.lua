local BD = require("ui/bidi")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Math = require("optmath")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local bit = require("bit")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen


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
    visible_area = nil,
    page_area = nil,
    show_overlap_enable = nil,
    overlap = Screen:scaleBySize(DOVERLAPPIXELS),

    inverse_reading_order = nil,
    page_flipping_mode = false,
    bookmark_flipping_mode = false,
    flip_steps = {0,1,2,5,10,20,50,100},
}

function ReaderPaging:init()
    self.key_events = {}
    if Device:hasKeys() then
        self.key_events.GotoNextPage = {
            { {"RPgFwd", "LPgFwd", "Right" } }, doc = "go to next page",
            event = "GotoViewRel", args = 1,
        }
        self.key_events.GotoPrevPage = {
            { { "RPgBack", "LPgBack", "Left" } }, doc = "go to previous page",
            event = "GotoViewRel", args = -1,
        }
        if Device:hasFewKeys() then
            table.remove(self.key_events.GotoNextPage[1][1], 3) -- right
            table.remove(self.key_events.GotoPrevPage[1][1], 3) -- left
        end
        self.key_events.GotoNextPos = {
            { {"Down" } }, doc = "go to next position",
            event = "GotoPosRel", args = 1,
        }
        self.key_events.GotoPrevPos = {
            { { "Up" } }, doc = "go to previous position",
            event = "GotoPosRel", args = -1,
        }

    end
    if Device:hasKeyboard() then
        self.key_events.GotoFirst = {
            {"1"}, doc = "go to start", event = "GotoPercent", args = 0,
        }
        self.key_events.Goto11 = {
            {"2"}, doc = "go to 11%", event = "GotoPercent", args = 11,
        }
        self.key_events.Goto22 = {
            {"3"}, doc = "go to 22%", event = "GotoPercent", args = 22,
        }
        self.key_events.Goto33 = {
            {"4"}, doc = "go to 33%", event = "GotoPercent", args = 33,
        }
        self.key_events.Goto44 = {
            {"5"}, doc = "go to 44%", event = "GotoPercent", args = 44,
        }
        self.key_events.Goto55 = {
            {"6"}, doc = "go to 55%", event = "GotoPercent", args = 55,
        }
        self.key_events.Goto66 = {
            {"7"}, doc = "go to 66%", event = "GotoPercent", args = 66,
        }
        self.key_events.Goto77 = {
            {"8"}, doc = "go to 77%", event = "GotoPercent", args = 77,
        }
        self.key_events.Goto88 = {
            {"9"}, doc = "go to 88%", event = "GotoPercent", args = 88,
        }
        self.key_events.GotoLast = {
            {"0"}, doc = "go to end", event = "GotoPercent", args = 100,
        }
    end
    self.pan_interval = TimeVal:new{ usec = 1000000 / self.pan_rate }
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

    local do_mirror = BD.mirroredUILayout()
    if self.inverse_reading_order then
        do_mirror = not do_mirror
    end
    if do_mirror then
        forward_zone.ratio_x = 1 - forward_zone.ratio_x - forward_zone.ratio_w
        backward_zone.ratio_x = 1 - backward_zone.ratio_x - backward_zone.ratio_w
    end

    self.ui:registerTouchZones({
        {
            id = "tap_forward",
            ges = "tap",
            screen_zone = forward_zone,
            handler = function()
                if G_reader_settings:nilOrFalse("page_turns_disable_tap") then
                    return self:onGotoViewRel(1)
                end
            end,
        },
        {
            id = "tap_backward",
            ges = "tap",
            screen_zone = backward_zone,
            handler = function()
                if G_reader_settings:nilOrFalse("page_turns_disable_tap") then
                    return self:onGotoViewRel(-1)
                end
            end,
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
            handler = function(ges) return self:onSwipe(nil, ges) end,
        },
        {
            id = "paging_pan",
            ges = "pan",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPan(nil, ges) end,
        },
        {
            id = "paging_pan_release",
            ges = "pan_release",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPanRelease(nil, ges) end,
        },
    })
end

function ReaderPaging:onReadSettings(config)
    self.page_positions = config:readSetting("page_positions") or {}
    self:_gotoPage(config:readSetting("last_page") or 1)
    if config:has("show_overlap_enable") then
        self.show_overlap_enable = config:isTrue("show_overlap_enable")
    else
        self.show_overlap_enable = DSHOWOVERLAP
    end
    self.flipping_zoom_mode = config:readSetting("flipping_zoom_mode") or "page"
    self.flipping_scroll_mode = config:isTrue("flipping_scroll_mode")
    self.is_reflowed = config:has("kopt_text_wrap") and config:readSetting("kopt_text_wrap") == 1
    if config:has("inverse_reading_order") then
        self.inverse_reading_order = config:isTrue("inverse_reading_order")
    else
        self.inverse_reading_order = G_reader_settings:isTrue("inverse_reading_order")
    end
    for _, v in ipairs(ReaderZooming.zoom_pan_settings) do
        self[v] = config:readSetting(v) or G_reader_settings:readSetting(v) or ReaderZooming[v]
    end
end

function ReaderPaging:onSaveSettings()
    --- @todo only save current_page page position
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
    --- @fixme repeated code with page overlap menu for readerrolling
    -- needs to keep only one copy of the logic as for the DRY principle.
    -- The difference between the two menus is only the enabled func.
    local page_overlap_menu = {
        {
            text = _("Page overlap"),
            checked_func = function()
                return self.show_overlap_enable
            end,
            callback = function()
                self.show_overlap_enable = not self.show_overlap_enable
                if not self.show_overlap_enable then
                    self.view.dim_area:clear()
                end
            end,
            separator = true,
        },
    }
    local overlap_enabled_func = function() return self.show_overlap_enable end
    for _, menu_entry in ipairs(self.view:genOverlapStyleMenu(overlap_enabled_func)) do
        table.insert(page_overlap_menu, menu_entry)
    end
    menu_items.page_overlap = {
        text = _("Page overlap"),
        enabled_func = function()
            return not self.view.page_scroll
                    and (self.zoom_mode ~= "page" or (self.zoom_mode == "page" and self.is_reflowed))
                    and not self.zoom_mode:find("height")
        end,
        sub_item_table = page_overlap_menu,
    }
    menu_items.invert_page_turn_gestures = {
        text = _("Invert page turn taps and swipes"),
        checked_func = function() return self.inverse_reading_order end,
        callback = function()
            self.ui:handleEvent(Event:new("ToggleReadingOrder"))
        end,
        hold_callback = function(touchmenu_instance)
            local inverse_reading_order = G_reader_settings:isTrue("inverse_reading_order")
            UIManager:show(MultiConfirmBox:new{
                text = inverse_reading_order and _("The default (★) for newly opened books is right-to-left (RTL) page turning.\n\nWould you like to change it?")
                or _("The default (★) for newly opened books is left-to-right (LTR) page turning.\n\nWould you like to change it?"),
                choice1_text_func = function()
                    return inverse_reading_order and _("LTR") or _("LTR (★)")
                end,
                choice1_callback = function()
                     G_reader_settings:makeFalse("inverse_reading_order")
                     if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                choice2_text_func = function()
                    return inverse_reading_order and _("RTL (★)") or _("RTL")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("inverse_reading_order")
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    }
end

function ReaderPaging:onColorRenderingUpdate()
    self.ui.document:updateColorRendering()
    UIManager:setDirty(self.view.dialog, "partial")
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
    self.ui:handleEvent(Event:new("PagePositionUpdated"))
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

function ReaderPaging:onTogglePageFlipping()
    if self.bookmark_flipping_mode then
        -- do nothing if we're in bookmark flipping mode
        return
    end
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
    Input.disable_double_tap = true
    self.view.document.configurable.text_wrap = self.orig_reflow_mode
    self.view.page_scroll = self.orig_scroll_mode
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
    local direction = BD.flipDirectionIfMirroredUILayout(flipping_ges.direction)
    if direction == "east" then
        self:_gotoPage(flipping_page - self.flip_steps[math.ceil(steps*stp_proportion)])
    elseif direction == "west" then
        self:_gotoPage(flipping_page + self.flip_steps[math.ceil(steps*stp_proportion)])
    elseif direction == "south" then
        self:_gotoPage(flipping_page - math.floor(whole*abs_proportion))
    elseif direction == "north" then
        self:_gotoPage(flipping_page + math.floor(whole*abs_proportion))
    end
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:bookmarkFlipping(flipping_page, flipping_ges)
    local direction = BD.flipDirectionIfMirroredUILayout(flipping_ges.direction)
    if direction == "east" then
        self.ui:handleEvent(Event:new("GotoPreviousBookmark", flipping_page))
    elseif direction == "west" then
        self.ui:handleEvent(Event:new("GotoNextBookmark", flipping_page))
    end
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:onScrollSettingsUpdated(scroll_method, inertial_scroll_enabled, scroll_activation_delay)
    self.scroll_method = scroll_method
    self.scroll_activation_delay = TimeVal:new{ usec = scroll_activation_delay * 1000 }
    if inertial_scroll_enabled then
        self.ui.scrolling:setInertialScrollCallbacks(
            function(distance) -- do_scroll_callback
                if not self.ui.document then
                    return false
                end
                UIManager.currently_scrolling = true
                local top_page, top_position = self:getTopPage(), self:getTopPosition()
                self:onPanningRel(distance)
                return not (top_page == self:getTopPage() and top_position == self:getTopPosition())
            end,
            function() -- scroll_done_callback
                UIManager.currently_scrolling = false
                UIManager:setDirty(self.view.dialog, "partial")
            end
        )
    else
        self.ui.scrolling:setInertialScrollCallbacks(nil, nil)
    end
end

function ReaderPaging:onSwipe(_, ges)
    if self._pan_has_scrolled then
        -- We did some panning but released after a short amount of time,
        -- so this gesture ended up being a Swipe - and this swipe was
        -- not handled by the other modules (so, not opening the menus).
        -- Do as :onPanRelese() and ignore this swipe.
        self:onPanRelease() -- no arg, so we know there we come from here
        return true
    else
        self._pan_started = false
        UIManager.currently_scrolling = false
        self._pan_page_states_to_restore = nil
    end
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if self.bookmark_flipping_mode then
        self:bookmarkFlipping(self.current_page, ges)
        return true
    elseif self.page_flipping_mode and self.original_page then
        self:_gotoPage(self.original_page)
        return true
    elseif direction == "west" then
        if G_reader_settings:nilOrFalse("page_turns_disable_swipe") then
            if self.inverse_reading_order then
                self:onGotoViewRel(-1)
            else
                self:onGotoViewRel(1)
            end
            return true
        end
    elseif direction == "east" then
        if G_reader_settings:nilOrFalse("page_turns_disable_swipe") then
            if self.inverse_reading_order then
                self:onGotoViewRel(1)
            else
                self:onGotoViewRel(-1)
            end
            return true
        end
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
        if ges.mousewheel_direction and not self.view.page_scroll then
            -- Mouse wheel generates a Pan event: in page mode, move one
            -- page per event. Scroll mode is handled in the 'else' branch
            -- and use the wheeled distance.
            self:onGotoViewRel(-1 * ges.mousewheel_direction)
        elseif self.view.page_scroll then
            if not self._pan_started then
                self._pan_started = true
                -- Re-init state variables
                self._pan_has_scrolled = false
                self._pan_prev_relative_y = 0
                self._pan_to_scroll_later = 0
                self._pan_real_last_time = TimeVal.zero
                if ges.mousewheel_direction then
                    self._pan_activation_time = false
                else
                    self._pan_activation_time = ges.time + self.scroll_activation_delay
                end
                -- We will restore the previous position if this pan
                -- ends up being a swipe or a multiswipe
                -- Somehow, accumulating the distances scrolled in a self._pan_dist_to_restore
                -- so we can scroll these back may not always put us back to the original
                -- position (possibly because of these page_states?). It's safer
                -- to remember the original page_states and restore that. We can keep
                -- a reference to the original table as onPanningRel() will have this
                -- table replaced.
                self._pan_page_states_to_restore = self.view.page_states
            end
            local scroll_now = false
            if self._pan_activation_time and ges.time >= self._pan_activation_time then
                self._pan_activation_time = false -- We can go on, no need to check again
            end
            if not self._pan_activation_time and ges.time - self._pan_real_last_time >= self.pan_interval then
                scroll_now = true
                self._pan_real_last_time = ges.time
            end
            local scroll_dist = 0
            if self.scroll_method == self.ui.scrolling.SCROLL_METHOD_CLASSIC then
                -- Scroll by the distance the finger moved since last pan event,
                -- having the document follows the finger
                scroll_dist = self._pan_prev_relative_y - ges.relative.y
                self._pan_prev_relative_y = ges.relative.y
                if not self._pan_has_scrolled then
                    -- Avoid checking this for each pan, no need once we have scrolled
                    if self.ui.scrolling:cancelInertialScroll() or self.ui.scrolling:cancelledByTouch() then
                        -- If this pan or its initial touch did cancel some inertial scrolling,
                        -- ignore activation delay to allow continuous scrolling
                        self._pan_activation_time = false
                        scroll_now = true
                        self._pan_real_last_time = ges.time
                    end
                end
                self.ui.scrolling:accountManualScroll(scroll_dist, ges.time)
            elseif self.scroll_method == self.ui.scrolling.SCROLL_METHOD_TURBO then
                -- Legacy scrolling "buggy" behaviour, that can actually be nice
                -- Scroll by the distance from the initial finger position, this distance
                -- controlling the speed of the scrolling)
                if scroll_now then
                    scroll_dist = -ges.relative.y
                end
                -- We don't accumulate in _pan_to_scroll_later
            elseif self.scroll_method == self.ui.scrolling.SCROLL_METHOD_ON_RELEASE then
                self._pan_to_scroll_later = -ges.relative.y
                if scroll_now then
                    self._pan_has_scrolled = true -- so we really apply it later
                end
                scroll_dist = 0
                scroll_now = false
            end
            if scroll_now then
                local dist = self._pan_to_scroll_later + scroll_dist
                self._pan_to_scroll_later = 0
                if dist ~= 0 then
                    self._pan_has_scrolled = true
                    UIManager.currently_scrolling = true
                    self:onPanningRel(dist)
                end
            else
                self._pan_to_scroll_later = self._pan_to_scroll_later + scroll_dist
            end
        end
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
        if self._pan_has_scrolled and self._pan_to_scroll_later ~= 0 then
            self:onPanningRel(self._pan_to_scroll_later)
        end
        self._pan_started = false
        self._pan_page_states_to_restore = nil
        UIManager.currently_scrolling = false
        if self._pan_has_scrolled then
            self._pan_has_scrolled = false
            -- Don't do any inertial scrolling if pan events come from
            -- a mousewheel (which may have itself some inertia)
            if (ges and ges.from_mousewheel) or not self.ui.scrolling:startInertialScroll() then
                UIManager:setDirty(self.view.dialog, "partial")
            end
        end
    end
end

function ReaderPaging:onHandledAsSwipe()
    if self._pan_started then
        -- Restore original position as this pan we've started handling
        -- has ended up being a multiswipe or handled as a swipe to open
        -- top or bottom menus
        if self._pan_has_scrolled then
            self.view.page_states = self._pan_page_states_to_restore
            self:_gotoPage(self.view.page_states[#self.view.page_states].page, "scrolling")
            UIManager:setDirty(self.view.dialog, "ui")
        end
        self._pan_page_states_to_restore = nil
        self._pan_started = false
        self._pan_has_scrolled = false
        UIManager.currently_scrolling = false
    end
    return true
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

function ReaderPaging:onGotoViewRel(diff)
    if self.view.page_scroll then
        self:onScrollPageRel(diff)
    else
        self:onGotoPageRel(diff)
    end
    self:setPagePosition(self:getTopPage(), self:getTopPosition())
    return true
end

function ReaderPaging:onGotoPosRel(diff)
    if self.view.page_scroll then
        self:onPanningRel(100*diff)
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

-- Used by ReaderBack & ReaderLink.
function ReaderPaging:getBookLocation()
    local ctx = self.view:getViewContext()
    if ctx then
        -- We need a copy, as we're getting references to
        -- objects ReaderPaging/ReaderView may still modify
        local current_location = {}
        for i=1, #ctx do
            current_location[i] = util.tableDeepCopy(ctx[i])
        end
        return current_location
    end
end

function ReaderPaging:onRestoreBookLocation(saved_location)
    if self.view.page_scroll then
        if self.view:restoreViewContext(saved_location) then
            self:_gotoPage(saved_location[1].page, "scrolling")
        else
            -- If context is unusable (not from scroll mode), trigger
            -- this to go at least to its page and redraw it
            self.ui:handleEvent(Event:new("PageUpdate", saved_location[1].page))
        end
    else
        -- gotoPage may emit PageUpdate event, which will trigger recalculate
        -- in ReaderView and resets the view context. So we need to call
        -- restoreViewContext after gotoPage.
        -- But if we're restoring to the same page, it will not emit
        -- PageUpdate event - so we need to do it for a correct redrawing
        local send_PageUpdate = saved_location[1].page == self.current_page
        self:_gotoPage(saved_location[1].page)
        if not self.view:restoreViewContext(saved_location) then
            -- If context is unusable (not from page mode), also
            -- send PageUpdate event to go to its page and redraw it
            send_PageUpdate = true
        end
        if send_PageUpdate then
            self.ui:handleEvent(Event:new("PageUpdate", saved_location[1].page))
        end
    end
    self:setPagePosition(self:getTopPage(), self:getTopPosition())
    -- In some cases (same page, different offset), doing the above
    -- might not redraw the screen. Ensure it is.
    UIManager:setDirty(self.view.dialog, "partial")
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
        blank_area:setSizeTo(self.view.visible_area)
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
    blank_area:setSizeTo(self.view.visible_area)
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
    UIManager:setDirty(self.view.dialog, "partial")
    return true
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
        blank_area:setSizeTo(self.view.visible_area)
        local overlap = self.overlap
        local offset = Geom:new{
            x = 0,
            y = last_visible_area.h - overlap
        }
        self.view.page_states = self:genPageStatesFromTop(last_page_state, blank_area, offset)
    elseif page_diff < 0 then
        -- page up, first page should be moved to bottom
        local blank_area = Geom:new{}
        blank_area:setSizeTo(self.view.visible_area)
        local overlap = self.overlap
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
    local right_to_left = self.ui.document.configurable.writing_direction and self.ui.document.configurable.writing_direction > 0
    local bottom_to_top = self.ui.zooming.zoom_bottom_to_top
    local h_progress = 1 - self.ui.zooming.zoom_overlap_h / 100
    local v_progress = 1 - self.ui.zooming.zoom_overlap_v / 100
    local old_va = self.visible_area
    local old_page = self.current_page
    local x, y, w, h = "x", "y", "w", "h"
    local x_diff = diff
    local y_diff = diff

    -- Adjust directions according to settings
    if self.ui.zooming.zoom_direction_vertical then  -- invert axes
        y, x, h, w = x, y, w, h
        h_progress, v_progress = v_progress, h_progress
        if right_to_left then
            x_diff, y_diff = -x_diff, -y_diff
        end
        if bottom_to_top then
            x_diff = -x_diff
        end
    elseif bottom_to_top then
        y_diff = -y_diff
    end
    if right_to_left then
        x_diff = -x_diff
    end

    if self.zoom_mode ~= "free" then
        x_pan_off = Math.roundAwayFromZero(self.visible_area[w] * h_progress * x_diff)
        y_pan_off = Math.roundAwayFromZero(self.visible_area[h] * v_progress * y_diff)
    end

    -- Auxiliary functions to (as much as possible) keep things clear
    -- If going backwards (diff < 0) "end" is equivalent to "beginning", "next" to "previous";
    -- in column mode, "line" is equivalent to "column".
    local function at_end(axis)
        -- returns true if we're at the end of line (axis = x) or page (axis = y)
        local len, _diff
        if axis == x then
            len, _diff = w, x_diff
        else
            len, _diff = h, y_diff
        end
        return old_va[axis] + old_va[len] + _diff > self.page_area[axis] + self.page_area[len]
            or old_va[axis] + _diff < self.page_area[axis]
    end
    local function goto_end(axis, _diff)
        -- updates view area to the end of line (axis = x) or page (axis = y)
        local len = axis == x and w or h
        _diff = _diff or (axis == x and x_diff or y_diff)
        new_va[axis] = _diff > 0
                    and old_va[axis] + self.page_area[len] - old_va[len]
                    or self.page_area[axis]
    end
    local function goto_next_line()
        new_va[y] = old_va[y] + y_pan_off
        goto_end(x, -x_diff)
    end
    local function goto_next_page()
        local new_page = self.current_page + diff
        if new_page > self.number_of_pages then
            self.ui:handleEvent(Event:new("EndOfBook"))
            goto_end(y)
            goto_end(x)
        elseif new_page > 0 then
            self:_gotoPage(new_page)
            goto_end(y, -y_diff)
        else
            goto_end(x)
        end
    end

    -- Move the view area towards line end
    new_va[x] = old_va[x] + x_pan_off
    new_va[y] = old_va[y]

    local prev_page = self.current_page

    -- Handle cases when the view area gets out of page boundaries
    if not self.page_area:contains(new_va) then
        if not at_end(x) then
            goto_end(x)
        else
            goto_next_line()
            if not self.page_area:contains(new_va) then
                if not at_end(y) then
                    goto_end(y)
                else
                    goto_next_page()
                end
            end
        end
    end

    if self.current_page == prev_page then
        -- Page number haven't changed when panning inside a page,
        -- but time may: keep the footer updated
        self.view.footer:onUpdateFooter(self.view.footer_visible)
    end

    -- signal panning update
    local panned_x, panned_y = math.floor(new_va.x - old_va.x), math.floor(new_va.y - old_va.y)
    self.view:PanningUpdate(panned_x, panned_y)

    -- Update dim area in ReaderView
    if self.show_overlap_enable then
        if self.current_page ~= old_page then
            self.view.dim_area:clear()
        else
            -- We're post PanningUpdate, recompute via self.visible_area instead of new_va for accuracy, it'll have been updated via ViewRecalculate
            panned_x, panned_y = math.floor(self.visible_area.x - old_va.x), math.floor(self.visible_area.y - old_va.y)

            self.view.dim_area.h = self.visible_area.h - math.abs(panned_y)
            self.view.dim_area.w = self.visible_area.w - math.abs(panned_x)
            if panned_y < 0 then
                self.view.dim_area.y = self.visible_area.h - self.view.dim_area.h
            else
                self.view.dim_area.y = 0
            end
            if panned_x < 0 then
                self.view.dim_area.x = self.visible_area.w - self.view.dim_area.w
            else
                self.view.dim_area.x = 0
            end
        end
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
        self.view.footer:onUpdateFooter(self.view.footer_visible)
        return true
    end
    if number > self.number_of_pages then
        logger.warn("page number too high: "..number.."!")
        number = self.number_of_pages
    elseif number < 1 then
        logger.warn("page number too low: "..number.."!")
        number = 1
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

-- These might need additional work to behave fine in scroll
-- mode, and other zoom modes than Fit page
function ReaderPaging:onGotoNextChapter()
    local pageno = self.current_page
    local new_page = self.ui.toc:getNextChapter(pageno)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self:onGotoPage(new_page)
    end
    return true
end

function ReaderPaging:onGotoPrevChapter()
    local pageno = self.current_page
    local new_page = self.ui.toc:getPreviousChapter(pageno)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self:onGotoPage(new_page)
    end
    return true
end

function ReaderPaging:onToggleReflow()
    self.view.document.configurable.text_wrap = bit.bxor(self.view.document.configurable.text_wrap, 1)
    self.ui:handleEvent(Event:new("RedrawCurrentPage"))
    self.ui:handleEvent(Event:new("RestoreZoomMode"))
    self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

-- Duplicated in ReaderRolling
function ReaderPaging:onToggleReadingOrder()
    self.inverse_reading_order = not self.inverse_reading_order
    self:setupTouchZones()
    local is_rtl = BD.mirroredUILayout()
    if self.inverse_reading_order then
        is_rtl = not is_rtl
    end
    UIManager:show(Notification:new{
        text = is_rtl and _("RTL page turning.") or _("LTR page turning."),
    })
    return true
end

return ReaderPaging
