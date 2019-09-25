local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local bit = require("bit")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local band = bit.band

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
    inverse_reading_order = nil,
    -- only used for page view mode
    current_page= nil,
    xpointer = nil,
    panning_steps = ReaderPanning.panning_steps,
    show_overlap_enable = nil,
    cre_top_bar_enabled = false,
    visible_pages = 1,
    -- With visible_pages=2, in 2-pages mode, ensure the first
    -- page is always odd or even (odd is logical to avoid a
    -- same page when turning first 2-pages set of document)
    odd_or_even_first_page = 1 -- 1 = odd, 2 = even, nil or others = free
}

function ReaderRolling:init()
    self.key_events = {}
    if Device:hasKeys() then
        self.key_events.GotoNextView = {
            { {"RPgFwd", "LPgFwd", "Right" } },
            doc = "go to next view",
            event = "GotoViewRel", args = 1,
        }
        self.key_events.GotoPrevView = {
            { { "RPgBack", "LPgBack", "Left" } },
            doc = "go to previous view",
            event = "GotoViewRel", args = -1,
        }
    end
    if Device:hasDPad() then
        self.key_events.MoveUp = {
            { "Up" },
            doc = "move view up",
            event = "Panning", args = {0, -1},
        }
        self.key_events.MoveDown = {
            { "Down" },
            doc = "move view down",
            event = "Panning", args = {0,  1},
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

    table.insert(self.ui.postInitCallback, function()
        self.ui.document:_readMetadata()
        self.old_doc_height = self.ui.document.info.doc_height
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
    --- @fixme remove this branch with migration script
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

    self.inverse_reading_order = config:readSetting("inverse_reading_order")
    if self.inverse_reading_order == nil then
        self.inverse_reading_order = G_reader_settings:isTrue("inverse_reading_order")
    end

    -- This self.visible_pages may not be the current nb of visible pages
    -- as crengine may decide to not ensure that in some conditions.
    -- It's the one we got from settings, the one the user has decided on
    -- with config toggle, and the one that we will save for next load.
    -- Use self.ui.document:getVisiblePageCount() to get the current
    -- crengine used value.
    self.visible_pages = config:readSetting("visible_pages") or
        G_reader_settings:readSetting("copt_visible_pages") or 1
    self.ui.document:setVisiblePageCount(self.visible_pages)

    -- Set a callback to allow showing load and rendering progress
    -- (this callback will be cleaned up by cre.cpp closeDocument(),
    -- no need to handle it in :onCloseDocument() here.)
    self.ui.document:setCallback(function(...)
        -- Catch and log any error happening in handleCallback(),
        -- as otherwise it would just silently abort (but beware
        -- having errors, this may flood crash.log)
        local ok, err = xpcall(self.handleEngineCallback, debug.traceback, self, ...)
        if not ok then
            logger.warn("cre callback() error:", err)
        end
    end)
end

-- in scroll mode percent_finished must be save before close document
-- we cannot do it in onSaveSettings() because getLastPercent() uses self.ui.document
function ReaderRolling:onCloseDocument()
    self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())
    local cache_file_path = self.ui.document:getCacheFilePath() -- nil if no cache file
    self.ui.doc_settings:saveSetting("cache_file_path", cache_file_path)
    if self.ui.document:hasCacheFile() then
        -- also checks if DOM is coherent with styles; if not, invalidate the
        -- cache, so a new DOM is built on next opening
        if self.ui.document:isBuiltDomStale() then
            logger.dbg("cre DOM may not be in sync with styles, invalidating cache file for a full reload at next opening")
            self.ui.document:invalidateCacheFile()
        end
    end
    logger.dbg("cre cache used:", cache_file_path or "none")
end

function ReaderRolling:onCheckDomStyleCoherence()
    if self.ui.document and self.ui.document:isBuiltDomStale() then
        local has_bookmarks_warn_txt = ""
        if self.ui.bookmark:hasBookmarks() then
            has_bookmarks_warn_txt = _("\nNote that this change in styles may render your bookmarks or highlights no more valid.\nIf some of them do not show anymore, you can just revert the change you just made to have them shown again.\n\n")
        end
        UIManager:show(ConfirmBox:new{
            text = T(_("Styles have changed in such a way that fully reloading the document may be needed for a correct rendering.\n%1Do you want to reload the document?"), has_bookmarks_warn_txt),
            ok_callback = function()
                -- Allow for ConfirmBox to be closed before showing
                -- "Opening file" InfoMessage
                UIManager:scheduleIn(0.5, function ()
                    -- And check we haven't quit reader in these 0.5s
                    if self.ui.document then
                        self.ui:reloadDocument()
                    end
                end)
            end,
        })
    end
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
    self.ui.doc_settings:saveSetting("visible_pages", self.visible_pages)
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
            handler = function() return self:onGotoViewRel(1) end,
        },
        {
            id = "tap_backward",
            ges = "tap",
            screen_zone = backward_zone,
            handler = function() return self:onGotoViewRel(-1) end,
        },
        {
            id = "double_tap_forward",
            ges = "double_tap",
            screen_zone = forward_double_tap_zone,
            handler = function() return self:onGotoNextChapter() end
        },
        {
            id = "double_tap_backward",
            ges = "double_tap",
            screen_zone = backward_double_tap_zone,
            handler = function() return self:onGotoPrevChapter() end
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
    --- @fixme Repeated code with ReaderPaging read from left to right.
    menu_items.invert_page_turn_gestures = {
        text = _("Invert page turn taps and swipes"),
        checked_func = function() return self.inverse_reading_order end,
        callback = function()
            self.ui:handleEvent(Event:new("ToggleReadingOrder"))
        end,
        hold_callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = self.inverse_reading_order and _("Enable right to left reading by default?")
                    or _("Disable right to left reading by default?"),
                ok_text = self.inverse_reading_order and _("Enable")
                    or _("Disable"),
                ok_callback = function()
                    G_reader_settings:saveSetting("inverse_reading_order", self.inverse_reading_order)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    }
    --- @fixme repeated code with page overlap menu for readerpaging
    -- needs to keep only one copy of the logic as for the DRY principle.
    -- The difference between the two menus is only the enabled func.
    local overlap_lines_help_text = _([[
When page overlap is enabled, some lines from the previous page will be displayed on the next page.
You can set how many lines are shown.]])
    local page_overlap_menu = {
        {
            text = _("Page overlap"),
            checked_func = function()
                return self.show_overlap_enable
            end,
            callback = function()
                self.show_overlap_enable = not self.show_overlap_enable
                if not self.show_overlap_enable then
                    self.view:resetDimArea()
                end
            end
        },
        {
            text_func = function()
                return T(_("Number of lines: %1"), G_reader_settings:readSetting("copt_overlap_lines") or 1)
            end,
            enabled_func = function()
                return self.show_overlap_enable
            end,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    width = Screen:getWidth() * 0.75,
                    value = G_reader_settings:readSetting("copt_overlap_lines") or 1,
                    value_min = 1,
                    value_max = 10,
                    precision = "%d",
                    ok_text = _("Set"),
                    title_text =  _("Set overlapped lines"),
                    text = overlap_lines_help_text,
                    callback = function(spin)
                        G_reader_settings:saveSetting("copt_overlap_lines", spin.value)
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
            keep_menu_open = true,
            help_text = overlap_lines_help_text,
            separator = true,
        },
    }
    local overlap_enabled_func = function() return self.show_overlap_enable end
    for _, menu_entry in ipairs(self.view:genOverlapStyleMenu(overlap_enabled_func)) do
        table.insert(page_overlap_menu, menu_entry)
    end
    menu_items.page_overlap = {
        text = _("Page overlap"),
        enabled_func = function() return self.view.view_mode ~= "page" end,
        help_text = _([[When page overlap is enabled, some lines from the previous pages are shown on the next page.]]),
        sub_item_table = page_overlap_menu,
    }
end

function ReaderRolling:getLastPercent()
    if self.view.view_mode == "page" then
        return self.current_page / self.old_page
    else
        --- @fixme the calculated percent is not accurate in "scroll" mode.
        return self.ui.document:getPosFromXPointer(
            self.ui.document:getXPointer()) / self.ui.document.info.doc_height
    end
end

function ReaderRolling:onSwipe(_, ges)
    if ges.direction == "west" then
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
        local distance_type = "distance"
        if self.ui.gesture and self.ui.gesture.multiswipes_enabled then
            distance_type = "distance_delayed"
        end
        if ges.direction == "north" then
            self:_gotoPos(self.current_pos + ges[distance_type])
        elseif ges.direction == "south" then
            self:_gotoPos(self.current_pos - ges[distance_type])
        end
    --this is only use when mouse wheel is used
    elseif ges.mousewheel_direction and self.view.view_mode == "page" then
        UIManager:broadcastEvent(Event:new("GotoViewRel", -1 * ges.mousewheel_direction))
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

function ReaderRolling:onGotoNextChapter()
    local visible_page_count = self.ui.document:getVisiblePageCount()
    local pageno = self.current_page + (visible_page_count > 1 and 1 or 0)
    local new_page = self.ui.toc:getNextChapter(pageno, 0)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self:onGotoPage(new_page)
    end
    return true
end

function ReaderRolling:onGotoPrevChapter()
    local pageno = self.current_page
    local new_page = self.ui.toc:getPreviousChapter(pageno, 0)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self:onGotoPage(new_page)
    end
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
        local screen_y, screen_x = self.ui.document:getScreenPositionFromXPointer(marker_xp)
        local doc_margins = self.ui.document:getPageMargins()
        local marker_h = Screen:scaleBySize(self.ui.font.font_size * 1.1 * self.ui.font.line_space_percent/100.0)
        -- Make it 4/5 of left margin wide (and bigger when huge margin)
        local marker_w = math.floor(math.max(doc_margins["left"] - Screen:scaleBySize(5), doc_margins["left"] * 4/5))

        if self.ui.document:getVisiblePageCount() > 1 and screen_x > Screen:getWidth() / 2 then
            -- On right page in 2-pages mode
            -- We could show the marker on the right of the page with:
            --   screen_x = Screen:getWidth() - marker_w
            -- But it's best to show it on the left of text, so in
            -- the middle margin, so it still shows just left of a
            -- footnote number.
            -- This is a bit tricky with how the middle margin is sized
            -- by crengine (see LVDocView::updateLayout() in lvdocview.cpp)
            screen_x = Screen:getWidth() / 2
            local page2_x = self.ui.document:getPageOffsetX(self.ui.document:getCurrentPage()+1)
            marker_w = page2_x + marker_w - screen_x
        else
            screen_x = 0
        end

        self.mark_func = function()
            self.mark_func = nil
            Screen.bb:paintRect(screen_x, screen_y, marker_w, marker_h, Blitbuffer.COLOR_BLACK)
            Screen["refreshFast"](Screen, screen_x, screen_y, marker_w, marker_h)
            if type(marker_setting) == "number" then -- hide it
                self.unmark_func = function()
                    self.unmark_func = nil
                    -- UIManager:setDirty(self.view.dialog, "ui", Geom:new({x=0, y=screen_y, w=marker_w, h=marker_h}))
                    -- No need to use setDirty (which would ask crengine to
                    -- re-render the page, which may take a few seconds on big
                    -- documents): we drew our black marker in the margin, we
                    -- can just draw a white one to make it disappear
                    Screen.bb:paintRect(screen_x, screen_y, marker_w, marker_h, Blitbuffer.COLOR_WHITE)
                    Screen["refreshUI"](Screen, screen_x, screen_y, marker_w, marker_h)
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
            local overlap_lines = G_reader_settings:readSetting("copt_overlap_lines") or 1
            local overlap_h = Screen:scaleBySize(self.ui.font.font_size * 1.1 * self.ui.font.line_space_percent/100.0) * overlap_lines
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
        -- we're in paged mode, so round up
        if diff > 0 then
            diff = math.ceil(diff)
        else
            diff = math.floor(diff)
        end
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
    local _, dy = unpack(args)
    if self.view.view_mode ~= "scroll" then
        UIManager:broadcastEvent(Event:new("GotoViewRel", dy))
        return
    end
    self:_gotoPos(self.current_pos + dy * self.panning_steps.normal)
    self.xpointer = self.ui.document:getXPointer()
    return true
end

function ReaderRolling:onZoom()
    --- @todo Re-read doc_height info after font or lineheight changes.  05.06 2012 (houqp)
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
    -- Calling this now ensures the re-rendering is done by crengine
    -- so the delayed updatePos() has good info and can reposition
    -- the previous xpointer accurately:
    self.ui.document:getCurrentPos()
    -- Otherwise, _readMetadata() would do that, but the positionning
    -- would not work as expected, for some reason (it worked
    -- previously because of some bad setDirty() in ConfigDialog widgets
    -- that were triggering a full repaint of crengine (so, the needed
    -- rerendering) before updatePos() is called.
    UIManager:scheduleIn(0.1, function () self:updatePos() end)
    return true
end

function ReaderRolling:updatePos()
    if not self.ui.document then
        -- document closed since we were scheduleIn'ed
        return
    end
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
        self.view.footer:updateFooter()
    end
    UIManager:setDirty(self.view.dialog, "partial")
    -- Allow for the new rendering to be shown before possibly showing
    -- the "Styles have changes..." ConfirmBox so the user can decide
    -- if it is really needed
    UIManager:scheduleIn(0.1, function ()
        self:onCheckDomStyleCoherence()
    end)
end

--[[
    switching screen mode should not change current page number
--]]
function ReaderRolling:onChangeViewMode()
    self.ui.document:_readMetadata()
    self.old_doc_height = self.ui.document.info.doc_height
    self.old_page = self.ui.document.info.number_of_pages
    self.ui:handleEvent(Event:new("UpdateToc"))
    self.view.footer:setTocMarkers(true)
    if self.xpointer then
        self:_gotoXPointer(self.xpointer)
        -- Ensure a whole screen refresh is always enqueued
        UIManager:setDirty(self.view.dialog, "partial")
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
    if self.ui.postReaderCallback ~= nil then
        -- ReaderUI:init() not yet done: just set document dimensions
        self.ui.document:setViewDimen(Screen:getSize())
        -- (what's done in the following else is done elsewhere by
        -- the initialization code)
    else
        -- Initialization done: we are called on orientation change
        -- or on window resize (SDL, Android possibly).
        -- We need to temporarily re-enable internal history as crengine
        -- uses it to reposition after resize
        self.ui.document:enableInternalHistory(true)
        -- Set document dimensions
        self.ui.document:setViewDimen(Screen:getSize())
        -- Re-setup previous position
        self:onChangeViewMode()
        self:onUpdatePos()
        -- Re-disable internal history, with required redraw
        self.ui.document:enableInternalHistory(false)
        self:onRedrawCurrentView()
    end
end

function ReaderRolling:onChangeScreenMode(mode, rotation)
    -- Flag it as interactive so we can properly swap to Inverted orientations
    -- (we usurp the second argument, which usually means rotation)
    self.ui:handleEvent(Event:new("SetScreenMode", mode, rotation or true))
    -- (This had the above ReaderRolling:onSetDimensions() called to resize
    -- document dimensions and keep up with current position)
end

function ReaderRolling:onColorRenderingUpdate()
    self.ui.document:updateColorRendering()
    UIManager:setDirty(self.view.dialog, "partial")
end

--[[
    PosUpdate event is used to signal other widgets that pos has been changed.
--]]
function ReaderRolling:_gotoPos(new_pos, do_dim_area)
    if new_pos == self.current_pos then return end
    if new_pos < 0 then new_pos = 0 end
    -- Don't go past end of document, and ensure last line of the document
    -- is shown just above the footer, whether footer is visible or not
    local max_pos = self.ui.document.info.doc_height - self.ui.dimen.h + self.view.footer:getHeight()
    if new_pos > max_pos then new_pos = max_pos end
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
        if self.current_pos > max_pos - self.ui.dimen.h/2 then
            -- Avoid a fully dimmed page when reaching end of document
            -- (the scroll would bump and not be a full page long)
            self.view:resetDimArea()
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
    self:_gotoPos(new_percent * self.ui.document.info.doc_height / 10000)
end

function ReaderRolling:_gotoPage(new_page, free_first_page)
    if self.ui.document:getVisiblePageCount() > 1 and not free_first_page then
        -- Ensure we always have the first of the two pages odd
        if self.odd_or_even_first_page == 1 then -- odd
            if band(new_page, 1) == 0 then
                -- requested page will be shown as the right page
                new_page = new_page - 1
            end
        elseif self.odd_or_even_first_page == 2 then -- (or 'even' if requested)
            if band(new_page, 1) == 1 then
                -- requested page will be shown as the right page
                new_page = new_page - 1
            end
        end
    end
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
function ReaderRolling:updatePageLink()
    logger.dbg("update page link")
    local links = self.ui.document:getPageLinks()
    self.view.links = links
end
--]]

function ReaderRolling:onSetVisiblePages(visible_pages)
    -- crengine may decide to not ensure the value we request
    -- (for example, in 2-pages mode, it may stop being ensured
    -- when we increase the font size up to a point where a line
    -- would contain less that 20 glyphs).
    -- crengine may enforce visible_page=1 when:
    --   - not in page mode but in scroll mode
    --   - screen w/h < 6/5
    --   - w < 20*em
    -- We nevertheless update the setting (that will saved) with what
    -- the user has requested - and not what crengine has enforced.
    self.visible_pages = visible_pages
    local prev_visible_pages = self.ui.document:getVisiblePageCount()
    self.ui.document:setVisiblePageCount(visible_pages)
    local cur_visible_pages = self.ui.document:getVisiblePageCount()
    if cur_visible_pages ~= prev_visible_pages then
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderRolling:onSetStatusLine(status_line, on_read_settings)
    -- status_line values:
    -- in crengine: 0=header enabled, 1=disabled
    -- in koreader: 0=top status bar, 1=bottom mini bar
    self.ui.document:setStatusLineProp(status_line)
    self.cre_top_bar_enabled = status_line == 0
    if not on_read_settings then
        -- Ignore this event when it is first sent by ReaderCoptListener
        -- on book loading, so we stay with the saved footer settings
        self.view.footer:setVisible(status_line == 1)
    end
    self.ui:handleEvent(Event:new("UpdatePos"))
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

function ReaderRolling:handleEngineCallback(ev, ...)
    local args = {...}
    -- logger.info("handleCallback: got", ev, args and #args > 0 and args[1] or nil)
    if ev == "OnLoadFileStart" then -- Start of book loading
        self:showEngineProgress(0) -- Start initial delay countdown
    elseif ev == "OnLoadFileProgress" then
        -- Initial load from file (step 1/2) or from cache (step 1/1)
        self:showEngineProgress(args[1]/100/2)
    elseif ev == "OnNodeStylesUpdateStart" then -- Start of re-rendering
        self:showEngineProgress(0) -- Start initial delay countdown
    elseif ev == "OnNodeStylesUpdateProgress" then
        -- Update node styles (step 1/2 on re-rendering)
        self:showEngineProgress(args[1]/100/2)
    elseif ev == "OnFormatStart" then -- Start of step 2/2
        self:showEngineProgress(1/2) -- 50%, in case of no OnFormatProgress
    elseif ev == "OnFormatProgress" then
        -- Paragraph formatting and page splitting (step 2/2 after load
        -- from file, step 2/2 on re-rendering)
        self:showEngineProgress(1/2 + args[1]/100/2)
    elseif ev == "OnSaveCacheFileStart" then -- Start of cache file save
        self:showEngineProgress(1) -- Start initial delay countdown, fully filled
    elseif ev == "OnSaveCacheFileProgress" then
        -- Cache file save (when closing book after initial load from
        -- file or re-rendering)
        self:showEngineProgress(1 - args[1]/100) -- unfill progress
    elseif ev == "OnDocumentReady" or ev == "OnSaveCacheFileEnd" then
        self:showEngineProgress() -- cleanup
    elseif ev == "OnLoadFileError" then
        logger.warn("Cre error loading file:", args[1])
    end
    -- ignore other events
end

local ENGINE_PROGRESS_INITIAL_DELAY = TimeVal:new{ sec = 2 }
local ENGINE_PROGRESS_UPDATE_DELAY = TimeVal:new{ usec = 500000 }

function ReaderRolling:showEngineProgress(percent)
    if G_reader_settings:isFalse("cre_show_progress") then
        -- This may slow things down too much with SDL over SSH,
        -- so allow disabling it.
        return
    end
    if percent then
        local now = TimeVal:now()
        if self.engine_progress_update_not_before and now < self.engine_progress_update_not_before then
            return
        end
        if not self.engine_progress_update_not_before then
            -- Start showing the progress widget only if load or re-rendering
            -- have not yet finished after 2 seconds
            self.engine_progress_update_not_before = now + ENGINE_PROGRESS_INITIAL_DELAY
            return
        end
        -- Widget size and position: best to anchor it at top left,
        -- so it does not override the footer or a bookmark dogear
        local x = 0
        local y = 0
        local w = Screen:getWidth() / 3
        local h = Screen:scaleBySize(5)
        if self.engine_progress_widget then
            self.engine_progress_widget:setPercentage(percent)
        else
            self.engine_progress_widget = ProgressWidget:new{
                width = w,
                height = h,
                percentage = percent,
                margin_h = 0,
                margin_v = 0,
                radius = 0,
                -- Show a tick at 50% (below is loading, after is rendering)
                tick_width = Screen:scaleBySize(1),
                ticks = {1,2},
                last = 2,
            }
        end
        -- Paint directly to the screen and force a regional refresh
        -- as UIManager won't get a change to run until loading/rendering
        -- is finished.
        self.engine_progress_widget:paintTo(Screen.bb, x, y)
        Screen["refreshFast"](Screen, x, y, w, h)
        self.engine_progress_update_not_before = now + ENGINE_PROGRESS_UPDATE_DELAY
    else
        -- Done: cleanup
        self.engine_progress_widget = nil
        self.engine_progress_update_not_before = nil
        -- No need for any paint/refresh: any action we got
        -- some progress callback for will generate a full
        -- screen refresh.
    end
end

return ReaderRolling
