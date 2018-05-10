local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local InputContainer = require("ui/widget/container/inputcontainer")
local Event = require("ui/event")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

--[[
    Rolling is just like paging in page-based documents except that
    sometimes (in scroll mode) there is no concept of page number to indicate
    current progress.
    There are three kind of progress measurements for credocuments.
    1. page number (in page mode)
    2. progress percentage (in scroll mode)
    3. xpointer (in document dom structure)
    We found that the first two measurements are not suitable for keeping a
    record of the real progress. For example, when switching screen orientation
    from portrait to landscape, or switching view mode from page to scroll, the
    internal xpointer should not be used as the view dimen/mode is changed and
    crengine's pagination mechanism will find a closest xpointer for the new view.
    So if we change the screen orientation or view mode back, we cannot find the
    original place since the internal xpointer is changed, which is counter-
    intuitive as users didn't goto any other page.
    The solution is that we keep a record of the internal xpointer and only change
    it in explicit page turning. And use that xpointer for non-page-turning
    rendering.
--]]
local ReaderRolling = InputContainer:new{
    pan_rate = 30,  -- default 30 ops, will be adjusted in readerui
    old_doc_height = nil,
    old_page = nil,
    current_pos = 0,
    inverse_reading_order = false,
    -- only used for page view mode
    current_page= nil,
    doc_height = nil,
    xpointer = nil,
    panning_steps = ReaderPanning.panning_steps,
    show_overlap_enable = nil,
    -- nb of lines from previous page to show on next page (scroll mode only)
    overlap_lines = G_reader_settings:readSetting("copt_overlap_lines") or 1,
    cre_top_bar_enabled = false,
}

function ReaderRolling:init()
    if Device:hasKeyboard() or Device:hasKeys() then
        self.key_events = {
            GotoNextView = {
                { Input.group.PgFwd },
                doc = "go to next view",
                event = "GotoViewRel", args = 1
            },
            GotoPrevView = {
                { Input.group.PgBack },
                doc = "go to previous view",
                event = "GotoViewRel", args = -1
            },
            MoveUp = {
                { "Up" },
                doc = "move view up",
                event = "Panning", args = {0, -1}
            },
            MoveDown = {
                { "Down" },
                doc = "move view down",
                event = "Panning", args = {0,  1}
            },
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

    table.insert(self.ui.postInitCallback, function()
        self.doc_height = self.ui.document.info.doc_height
        self.old_doc_height = self.doc_height
        self.ui.document:_readMetadata()
        self.old_page = self.ui.document.info.number_of_pages
    end)
    table.insert(self.ui.postReaderCallback, function()
        self:updatePos()
        -- Disable crengine internal history, with required redraw
        self.ui.document:enableInternalHistory(false)
        self:onRedrawCurrentView()
    end)
    self.ui.menu:registerToMainMenu(self)
end

function ReaderRolling:onReadSettings(config)
    -- 20180503: some fix in crengine has changed the way the DOM is built
    -- for HTML documents and may make XPATHs obtained from previous version
    -- invalid.
    -- We may request the previous (buggy) behaviour though, which we do
    -- if we use a DocSetting previously made that may contain bookmarks
    -- and highlights with old XPATHs.
    -- (EPUB will use the same correct DOM code no matter what DOM version
    -- we request here.)
    if not config:readSetting("cre_dom_version") then
        -- Not previously set, guess which DOM version to use
        if config:readSetting("last_xpointer") then
            -- We have a last_xpointer: this book was previously opened
            -- with possibly a very old version: request the oldest
            config:saveSetting("cre_dom_version", self.ui.document:getOldestDomVersion())
        else
            -- No previous xpointer: book never opened (or sidecar file
            -- purged): we can use the latest DOM version
            config:saveSetting("cre_dom_version", self.ui.document:getLatestDomVersion())
        end
    end
    self.ui.document:requestDomVersion(config:readSetting("cre_dom_version"))

    local last_xp = config:readSetting("last_xpointer")
    local last_per = config:readSetting("last_percent")
    if last_xp then
        self.xpointer = last_xp
        self.setupXpointer = function()
            self:_gotoXPointer(self.xpointer)
            -- we have to do a real jump in self.ui.document._document to
            -- update status information in CREngine.
            self.ui.document:gotoXPointer(self.xpointer)
        end
    -- we read last_percent just for backward compatibility
    -- FIXME: remove this branch with migration script
    elseif last_per then
        self.setupXpointer = function()
            self:_gotoPercent(last_per)
            -- _gotoPercent calls _gotoPos, which only updates self.current_pos
            -- and self.view.
            -- we need to do a real pos change in self.ui.document._document
            -- to update status information in CREngine.
            self.ui.document:gotoPos(self.current_pos)
            -- _gotoPercent already calls gotoPos, so no need to emit
            -- PosUpdate event in scroll mode
            if self.view.view_mode == "page" then
                self.ui:handleEvent(
                    Event:new("PageUpdate", self.ui.document:getCurrentPage()))
            end
            self.xpointer = self.ui.document:getXPointer()
        end
    else
        self.setupXpointer = function()
            self.xpointer = self.ui.document:getXPointer()
            if self.view.view_mode == "page" then
                self.ui:handleEvent(Event:new("PageUpdate", 1))
            end
        end
    end
    self.show_overlap_enable = config:readSetting("show_overlap_enable")
    if self.show_overlap_enable == nil then
        self.show_overlap_enable = DSHOWOVERLAP
    end
    self.inverse_reading_order = config:readSetting("inverse_reading_order") or false

    self:onSetStatusLine(config:readSetting("copt_status_line") or DCREREADER_PROGRESS_BAR)
end

-- in scroll mode percent_finished must be save before close document
-- we cannot do it in onSaveSettings() because getLastPercent() uses self.ui.document
function ReaderRolling:onCloseDocument()
    self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())
end

function ReaderRolling:onSaveSettings()
    -- remove last_percent config since its deprecated
    self.ui.doc_settings:saveSetting("last_percent", nil)
    self.ui.doc_settings:saveSetting("last_xpointer", self.xpointer)
    -- in scrolling mode, the document may already be closed,
    -- so we have to check the condition to avoid crash function self:getLastPercent()
    -- that uses self.ui.document
    if self.ui.document then
        self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())
    end
    self.ui.doc_settings:saveSetting("show_overlap_enable", self.show_overlap_enable)
    self.ui.doc_settings:saveSetting("inverse_reading_order", self.inverse_reading_order)
end

function ReaderRolling:onReaderReady()
    self:setupTouchZones()
    self.setupXpointer()
end

function ReaderRolling:setupTouchZones()
    self.ges_events = {}
    self.onGesture = nil
    if not Device:isTouchDevice() then return end

    local forward_zone = {
        ratio_x = DTAP_ZONE_FORWARD.x, ratio_y = DTAP_ZONE_FORWARD.y,
        ratio_w = DTAP_ZONE_FORWARD.w, ratio_h = DTAP_ZONE_FORWARD.h,
    }
    local backward_zone = {
        ratio_x = DTAP_ZONE_BACKWARD.x, ratio_y = DTAP_ZONE_BACKWARD.y,
        ratio_w = DTAP_ZONE_BACKWARD.w, ratio_h = DTAP_ZONE_BACKWARD.h,
    }

    local forward_double_tap_zone = {
        ratio_x = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.x, ratio_y = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.y,
        ratio_w = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.w, ratio_h = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.h,
    }
    local backward_double_tap_zone = {
        ratio_x = DDOUBLE_TAP_ZONE_PREV_CHAPTER.x, ratio_y = DDOUBLE_TAP_ZONE_PREV_CHAPTER.y,
        ratio_w = DDOUBLE_TAP_ZONE_PREV_CHAPTER.w, ratio_h = DDOUBLE_TAP_ZONE_PREV_CHAPTER.h,
    }

    if self.inverse_reading_order then
        forward_zone.ratio_x = 1 - forward_zone.ratio_x - forward_zone.ratio_w
        backward_zone.ratio_x = 1 - backward_zone.ratio_x - backward_zone.ratio_w

        forward_double_tap_zone.ratio_x =
            1 - forward_double_tap_zone.ratio_x - forward_double_tap_zone.ratio_w
        backward_double_tap_zone.ratio_x =
            1 - backward_double_tap_zone.ratio_x - backward_double_tap_zone.ratio_w
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
        {
            id = "double_tap_forward",
            ges = "double_tap",
            screen_zone = forward_double_tap_zone,
            handler = function() return self:onDoubleTapForward() end
        },
        {
            id = "double_tap_backward",
            ges = "double_tap",
            screen_zone = backward_double_tap_zone,
            handler = function() return self:onDoubleTapBackward() end
        },
        {
            id = "rolling_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onSwipe(nil, ges) end
        },
        {
            id = "rolling_pan",
            ges = "pan",
            rate = self.pan_rate,
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPan(nil, ges) end
        },
    })
end

function ReaderRolling:getLastProgress()
    return self.xpointer
end

function ReaderRolling:addToMainMenu(menu_items)
    -- FIXME: repeated code with page overlap menu for readerpaging
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
        enabled_func = function() return self.view.view_mode ~= "page" end,
        sub_item_table = page_overlap_menu,
    }
end

function ReaderRolling:getLastPercent()
    if self.view.view_mode == "page" then
        return self.current_page / self.old_page
    else
        -- FIXME: the calculated percent is not accurate in "scroll" mode.
        return self.ui.document:getPosFromXPointer(
            self.ui.document:getXPointer()) / self.doc_height
    end
end

function ReaderRolling:onTapForward()
    self:onGotoViewRel(1)
    return true
end

function ReaderRolling:onTapBackward()
    self:onGotoViewRel(-1)
    return true
end

function ReaderRolling:onSwipe(_, ges)
    if ges.direction == "north" then
        self:onGotoViewRel(1)
    elseif ges.direction == "south" then
        self:onGotoViewRel(-1)
    elseif ges.direction == "west" then
        if self.inverse_reading_order then
            self:onGotoViewRel(-1)
        else
            self:onGotoViewRel(1)
        end
    elseif ges.direction == "east" then
        if self.inverse_reading_order then
            self:onGotoViewRel(1)
        else
            self:onGotoViewRel(-1)
        end
    else
        -- update footer (time & battery)
        self.view.footer:updateFooter()
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
    end
end

function ReaderRolling:onPan(_, ges)
    if self.view.view_mode == "scroll" then
        if ges.direction == "north" then
            self:_gotoPos(self.current_pos + ges.distance)
        elseif ges.direction == "south" then
            self:_gotoPos(self.current_pos - ges.distance)
        end
    end
    return true
end

function ReaderRolling:onPosUpdate(new_pos)
    self.current_pos = new_pos
    self:updateBatteryState()
end

function ReaderRolling:onPageUpdate(new_page)
    self.current_page = new_page
    self:updateBatteryState()
end

function ReaderRolling:onResume()
    self:updateBatteryState()
end

function ReaderRolling:onDoubleTapForward()
    local visible_page_count = self.ui.document:getVisiblePageCount()
    local pageno = self.current_page + (visible_page_count > 1 and 1 or 0)
    self:onGotoPage(self.ui.toc:getNextChapter(pageno, 0))
    return true
end

function ReaderRolling:onDoubleTapBackward()
    local pageno = self.current_page
    self:onGotoPage(self.ui.toc:getPreviousChapter(pageno, 0))
    return true
end

function ReaderRolling:onNotCharging()
    self:updateBatteryState()
end

function ReaderRolling:onGotoPercent(percent)
    logger.dbg("goto document offset in percent:", percent)
    self:_gotoPercent(percent)
    self.xpointer = self.ui.document:getXPointer()
    return true
end

function ReaderRolling:onGotoPage(number)
    if number then
        self:_gotoPage(number)
    end
    self.xpointer = self.ui.document:getXPointer()
    return true
end

function ReaderRolling:onGotoRelativePage(number)
    if number then
        self:_gotoPage(self.current_page + number)
    end
    self.xpointer = self.ui.document:getXPointer()
    return true
end

function ReaderRolling:onGotoXPointer(xp, marker_xp)
    if self.mark_func then
        -- unschedule previous marker as it's no more accurate
        UIManager:unschedule(self.mark_func)
        self.mark_func = nil
    end
    if self.unmark_func then
        -- execute scheduled unmark now to clean previous marker
        self.unmark_func()
        self.unmark_func = nil
    end
    self:_gotoXPointer(xp)
    self.xpointer = xp

    -- Allow tweaking this marker behaviour with a manual setting:
    --   followed_link_marker = false: no marker shown
    --   followed_link_marker = true: maker shown and not auto removed
    --   followed_link_marker = <number>: removed after <number> seconds
    -- (no real need for a menu item, the default is the finest)
    local marker_setting = G_reader_settings:readSetting("followed_link_marker")
    if marker_setting == nil then
        marker_setting = 1 -- default is: shown and removed after 1 second
    end

    if marker_xp and marker_setting then
        -- Show a mark on left side of screen to give a visual feedback of
        -- where xpointer target is (and remove if after 1s)
        local doc_y = self.ui.document:getPosFromXPointer(marker_xp)
        local top_y = self.ui.document:getCurrentPos()
        local screen_y = doc_y - top_y
        local doc_margins = self.ui.document._document:getPageMargins()
        if self.view.view_mode == "page" then
            screen_y = screen_y + doc_margins["top"]
        end
        local marker_h = Screen:scaleBySize(self.ui.font.font_size * 1.1 * self.ui.font.line_space_percent/100.0)
        -- Make it 4/5 of left margin wide (and bigger when huge margin)
        local marker_w = math.floor(math.max(doc_margins["left"] - Screen:scaleBySize(5), doc_margins["left"] * 4/5))

        self.mark_func = function()
            self.mark_func = nil
            Screen.bb:paintRect(0, screen_y, marker_w, marker_h, Blitbuffer.COLOR_BLACK)
            Screen["refreshUI"](Screen, 0, screen_y, marker_w, marker_h)
            if type(marker_setting) == "number" then -- hide it
                self.unmark_func = function()
                    self.unmark_func = nil
                    -- UIManager:setDirty(self.view.dialog, "ui", Geom:new({x=0, y=screen_y, w=marker_w, h=marker_h}))
                    -- No need to use setDirty (which would ask crengine to
                    -- re-render the page, which may take a few seconds on big
                    -- documents): we drew our black marker in the margin, we
                    -- can just draw a white one to make it disappear
                    Screen.bb:paintRect(0, screen_y, marker_w, marker_h, Blitbuffer.COLOR_WHITE)
                    Screen["refreshUI"](Screen, 0, screen_y, marker_w, marker_h)
                end
                UIManager:scheduleIn(marker_setting, self.unmark_func)
            end
        end
        UIManager:scheduleIn(0.5, self.mark_func)
    end
    return true
end

function ReaderRolling:getBookLocation()
    return self.xpointer
end

function ReaderRolling:onRestoreBookLocation(saved_location)
    return self:onGotoXPointer(saved_location.xpointer, saved_location.marker_xpointer)
end

function ReaderRolling:onGotoViewRel(diff)
    logger.dbg("goto relative screen:", diff, ", in mode: ", self.view.view_mode)
    if self.view.view_mode == "scroll" then
        local footer_height = (self.view.footer_visible and 1 or 0) * self.view.footer:getHeight()
        local page_visible_height = self.ui.dimen.h - footer_height
        local pan_diff = diff * page_visible_height
        if self.show_overlap_enable then
            local overlap_h = Screen:scaleBySize(self.ui.font.font_size * 1.1 * self.ui.font.line_space_percent/100.0) * self.overlap_lines
            if pan_diff > overlap_h then
                pan_diff = pan_diff - overlap_h
            elseif pan_diff < -overlap_h then
                pan_diff = pan_diff + overlap_h
            end
        end
        local old_pos = self.current_pos
        -- Only draw dim area when we moved a whole page (not when smaller scroll with Pan)
        local do_dim_area = math.abs(diff) == 1
        self:_gotoPos(self.current_pos + pan_diff, do_dim_area)
        if diff > 0 and old_pos == self.current_pos then
            self.ui:handleEvent(Event:new("EndOfBook"))
        end
    elseif self.view.view_mode == "page" then
        local page_count = self.ui.document:getVisiblePageCount()
        local old_page = self.current_page
        self:_gotoPage(self.current_page + diff*page_count)
        if diff > 0 and old_page == self.current_page then
            self.ui:handleEvent(Event:new("EndOfBook"))
        end
    end
    if self.ui.document ~= nil then
        self.xpointer = self.ui.document:getXPointer()
    end
    return true
end

function ReaderRolling:onPanning(args, _)
    --@TODO disable panning in page view_mode?  22.12 2012 (houqp)
    local _, dy = unpack(args)
    self:_gotoPos(self.current_pos + dy * self.panning_steps.normal)
    self.xpointer = self.ui.document:getXPointer()
    return true
end

function ReaderRolling:onZoom()
    --@TODO re-read doc_height info after font or lineheight changes  05.06 2012 (houqp)
    self:updatePos()
end

--[[
    remember to signal this event when the document has been zoomed,
    font has been changed, or line height has been changed.
    Note that xpointer should not be changed.
--]]
function ReaderRolling:onUpdatePos()
    if self.ui.postReaderCallback ~= nil then -- ReaderUI:init() not yet done
        -- Don't schedule any updatePos as long as ReaderUI:init() is
        -- not finished (one will be called in the ui.postReaderCallback
        -- we have set above) to avoid multiple refreshes.
        return true
    end
    UIManager:scheduleIn(0.1, function () self:updatePos() end)
    return true
end

function ReaderRolling:updatePos()
    -- reread document height
    self.ui.document:_readMetadata()
    -- update self.current_pos if the height of document has been changed.
    local new_height = self.ui.document.info.doc_height
    local new_page = self.ui.document.info.number_of_pages
    if self.old_doc_height ~= new_height or self.old_page ~= new_page then
        self:_gotoXPointer(self.xpointer)
        self.old_doc_height = new_height
        self.old_page = new_page
        self.ui:handleEvent(Event:new("UpdateToc"))
    end
    UIManager:setDirty(self.view.dialog, "partial")
end

--[[
    switching screen mode should not change current page number
--]]
function ReaderRolling:onChangeViewMode()
    self.ui.document:_readMetadata()
    self.old_doc_height = self.ui.document.info.doc_height
    self.old_page = self.ui.document.info.number_of_pages
    self.ui:handleEvent(Event:new("UpdateToc"))
    if self.xpointer then
        self:_gotoXPointer(self.xpointer)
    else
        table.insert(self.ui.postInitCallback, function()
            self:_gotoXPointer(self.xpointer)
        end)
    end
    return true
end

function ReaderRolling:onRedrawCurrentView()
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.current_page))
    else
        self.ui:handleEvent(Event:new("PosUpdate", self.current_pos))
    end
    return true
end

function ReaderRolling:onSetDimensions(dimen)
    self.ui.document:setViewDimen(Screen:getSize())
end

function ReaderRolling:onChangeScreenMode(mode)
    -- We need to temporarily re-enable internal history as crengine
    -- uses it to reposition after resize
    self.ui.document:enableInternalHistory(true)
    self.ui:handleEvent(Event:new("SetScreenMode", mode))
    self.ui.document:setViewDimen(Screen:getSize())
    self:onChangeViewMode()
    self:onUpdatePos()
    -- Re-disable internal history, with required redraw
    self.ui.document:enableInternalHistory(false)
    self:onRedrawCurrentView()
end

function ReaderRolling:onColorRenderingUpdate()
    self.ui.document:updateColorRendering()
end

--[[
    PosUpdate event is used to signal other widgets that pos has been changed.
--]]
function ReaderRolling:_gotoPos(new_pos, do_dim_area)
    if new_pos == self.current_pos then return end
    if new_pos < 0 then new_pos = 0 end
    if new_pos > self.doc_height then new_pos = self.doc_height end
    -- adjust dim_area according to new_pos
    if self.view.view_mode ~= "page" and self.show_overlap_enable and do_dim_area then
        local footer_height = (self.view.footer_visible and 1 or 0) * self.view.footer:getHeight()
        local page_visible_height = self.ui.dimen.h - footer_height
        local panned_step = new_pos - self.current_pos
        self.view.dim_area.x = 0
        self.view.dim_area.h = page_visible_height - math.abs(panned_step)
        self.view.dim_area.w = self.ui.dimen.w
        if panned_step < 0 then
            self.view.dim_area.y = page_visible_height - self.view.dim_area.h
        elseif panned_step > 0 then
            self.view.dim_area.y = 0
        end
    else
        self.view:resetDimArea()
    end
    self.ui.document:gotoPos(new_pos)
    -- The current page we get in scroll mode may be a bit innacurate,
    -- but we give it anyway to onPosUpdate so footer and statistics can
    -- keep up with page.
    self.ui:handleEvent(Event:new("PosUpdate", new_pos, self.ui.document:getCurrentPage()))
end

function ReaderRolling:_gotoPercent(new_percent)
    self:_gotoPos(new_percent * self.doc_height / 10000)
end

function ReaderRolling:_gotoPage(new_page)
    self.ui.document:gotoPage(new_page)
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getCurrentPage()))
    else
        self.ui:handleEvent(Event:new("PosUpdate", self.ui.document:getCurrentPos(), self.ui.document:getCurrentPage()))
    end
end

function ReaderRolling:_gotoXPointer(xpointer)
    if self.view.view_mode == "page" then
        self:_gotoPage(self.ui.document:getPageFromXPointer(xpointer))
    else
        self:_gotoPos(self.ui.document:getPosFromXPointer(xpointer))
    end
end

--[[
currently we don't need to get page links on each page/pos update
since we can check link on the fly when tapping on the screen
--]]
function ReaderRolling:updatePageLink()
    logger.dbg("update page link")
    local links = self.ui.document:getPageLinks()
    self.view.links = links
end

function ReaderRolling:onSetStatusLine(status_line)
    self.cre_top_bar_enabled = status_line == 0
end

function ReaderRolling:updateBatteryState()
    if self.view.view_mode == "page" and self.cre_top_bar_enabled then
        logger.dbg("update battery state")
        local powerd = Device:getPowerDevice()
        -- -1 is CR_BATTERY_STATE_CHARGING @ crengine/crengine/include/lvdocview.h
        local state = powerd:isCharging() and -1 or powerd:getCapacity()
        if state then
            self.ui.document:setBatteryState(state)
        end
    end
end

return ReaderRolling
