local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local bit = require("bit")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template

local band = bit.band

-- We need a small mmap'ped segment to exchange states with forked
-- subproceses doing background rerenderings.
-- Used as:
--   shared_state[0] = pid of current subprocess
--   shared_state[1] = 0 or 1, set by subprocess when rendering done, waiting to save cache
--   shared_state[2] = 0 or 1, set by main process when subprocess can go on saving cache
local ffi = require("ffi")
local shared_state_data = ffi.C.mmap(nil, 3*ffi.sizeof("uint32_t"), bit.bor(ffi.C.PROT_READ, ffi.C.PROT_WRITE),
                                       bit.bor(ffi.C.MAP_SHARED, ffi.C.MAP_ANONYMOUS), -1, 0)
local shared_state = ffi.cast("uint32_t*", shared_state_data)
local koreader_pid = ffi.C.getpid()

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
local ReaderRolling = InputContainer:extend{
    pan_rate = 30,  -- default 30 ops, will be adjusted in readerui
    rendering_hash = 0,
    current_pos = 0,
    -- only used for page view mode
    current_page = nil,
    xpointer = nil,
    panning_steps = ReaderPanning.panning_steps,
    cre_top_bar_enabled = false,
    -- With visible_pages=2, in 2-pages mode, ensure the first
    -- page is always odd or even (odd is logical to avoid a
    -- same page when turning first 2-pages set of document)
    odd_or_even_first_page = 1, -- 1 = odd, 2 = even, nil or others = free
    hide_nonlinear_flows = nil,

    partial_rerendering = false,
    nb_partial_rerenderings = 0,
    rendering_state = nil,
    RENDERING_STATE = {
        FULLY_RENDERED = nil,
        PARTIALLY_RERENDERED = 1,
        FULL_RENDERING_IN_BACKGROUND = 2,
        FULL_RENDERING_READY = 3,
        RELOADING_DOCUMENT = 4,
        DO_RELOAD_DOCUMENT = 5,
    },

    mark_func = nil,
    unmark_func = nil,
    _stepRerenderingAutomation = nil,
}

function ReaderRolling:init()
    self:registerKeyEvents()
    self.pan_interval = time.s(1 / self.pan_rate)

    table.insert(self.ui.postInitCallback, function()
        self.rendering_hash = self.ui.document:getDocumentRenderingHash(true)
        self.ui.document:_readMetadata()
        if self.ui.document:hasCacheFile() and not self.ui.document:isCacheFileStale() then
            -- We loaded from a valid cache file: remember its hash. It may allow not
            -- having to do any background rerendering if the user somehow reverted
            -- some setting changes before any background rerendering had completed
            -- (ie. with autorotation, transitioning from portrait to landscape for
            -- a few seconds, to then end up back in portrait).
            self.valid_cache_rendering_hash = self.ui.document:getDocumentRenderingHash(false)
        end
    end)
    table.insert(self.ui.postReaderReadyCallback, function()
        self:updatePos()
        -- Disable crengine internal history, with required redraw
        self.ui.document:enableInternalHistory(false)
        self:onRedrawCurrentView()
    end)
    self.ui.menu:registerToMainMenu(self)
    self.batched_update_count = 0

    -- delegate gesture listener to readerui, NOP our own
    self.ges_events = nil
end

function ReaderRolling:onGesture() end

function ReaderRolling:registerKeyEvents()
    local nextKey = BD.mirroredUILayout() and "Left" or "Right"
    local prevKey = BD.mirroredUILayout() and "Right" or "Left"
    if Device:hasDPad() and Device:useDPadAsActionKeys() then
        if G_reader_settings:isTrue("left_right_keys_turn_pages") then
            self.key_events.GotoNextView = { { { "LPgFwd", nextKey } }, event = "GotoViewRel", args = 1, }
            self.key_events.GotoPrevView = { { { "LPgBack", prevKey } }, event = "GotoViewRel", args = -1, }
        elseif G_reader_settings:nilOrFalse("left_right_keys_turn_pages") then
            self.key_events.GotoNextChapter = { { nextKey }, event = "GotoNextChapter", args = 1, }
            self.key_events.GotoPrevChapter = { { prevKey }, event = "GotoPrevChapter", args = -1, }
            self.key_events.GotoNextView = { { "LPgFwd" }, event = "GotoViewRel", args = 1, }
            self.key_events.GotoPrevView = { { "LPgBack" }, event = "GotoViewRel", args = -1, }
        end
        self.key_events.MoveUp = { { "RPgBack" }, event = "Panning", args = {0, -1}, }
        self.key_events.MoveDown = { { { "RPgFwd", " " } }, event = "Panning", args = {0,  1}, }
    elseif Device:hasDPad() then
        self.key_events.MoveUp = { { "Up" }, event = "Panning", args = {0, -1}, }
        self.key_events.MoveDown = { { "Down" }, event = "Panning", args = {0,  1}, }
    end
    if (Device:hasDPad() and not Device:useDPadAsActionKeys()) or (Device:hasKeys() and not Device:useDPadAsActionKeys()) then
        self.key_events.GotoNextView = { { { "RPgFwd", "LPgFwd", nextKey } }, event = "GotoViewRel", args = 1, }
        self.key_events.GotoPrevView = { { { "RPgBack", "LPgBack", prevKey } }, event = "GotoViewRel", args = -1, }
    end
    if Device:hasKeyboard() and not Device.k3_alt_plus_key_kernel_translated then
        self.key_events.GotoFirst = { { "1" }, event = "GotoPercent", args = 0,   }
        self.key_events.Goto11    = { { "2" }, event = "GotoPercent", args = 11,  }
        self.key_events.Goto22    = { { "3" }, event = "GotoPercent", args = 22,  }
        self.key_events.Goto33    = { { "4" }, event = "GotoPercent", args = 33,  }
        self.key_events.Goto44    = { { "5" }, event = "GotoPercent", args = 44,  }
        self.key_events.Goto55    = { { "6" }, event = "GotoPercent", args = 55,  }
        self.key_events.Goto66    = { { "7" }, event = "GotoPercent", args = 66,  }
        self.key_events.Goto77    = { { "8" }, event = "GotoPercent", args = 77,  }
        self.key_events.Goto88    = { { "9" }, event = "GotoPercent", args = 88,  }
        self.key_events.Goto99    = { { "0" }, event = "GotoPercent", args = 100, }
    end
end

ReaderRolling.onPhysicalKeyboardConnected = ReaderRolling.registerKeyEvents

function ReaderRolling:onReadSettings(config)
    -- 20180503: some fix in crengine has changed the way the DOM is built
    -- for HTML documents and may make XPATHs obtained from previous version
    -- invalid.
    -- We may request the previous (buggy) behaviour though, which we do
    -- if we use a DocSetting previously made that may contain bookmarks
    -- and highlights with old XPATHs.
    -- (EPUB will use the same correct DOM code no matter what DOM version
    -- we request here.)
    if config:hasNot("cre_dom_version") then
        -- Not previously set, guess which DOM version to use
        if config:has("last_xpointer") then
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
    -- If we're using a DOM version without normalized XPointers, some stuff
    -- may need tweaking:
    local cre = require("document/credocument"):engineInit()
    if config:readSetting("cre_dom_version") < cre.getDomVersionWithNormalizedXPointers() then
        -- Show some warning when styles "display:" have changed that
        -- bookmarks may break
        self.using_non_normalized_xpointers = true
        -- Also tell ReaderTypeset, which ensures block rendering mode,
        -- that we'd rather have some of its BLOCK_RENDERING_FLAGS disabled
        -- if an old DOM version is requested, as some flags may "box"
        -- (into inserted internal elements) long fragment of text,
        -- which may break previous highlights.
        self.ui.typeset:ensureSanerBlockRenderingFlags()
        -- And check if we can migrate to a newest DOM version after
        -- the book is loaded (unless the user told us not to).
        if config:nilOrFalse("cre_keep_old_dom_version") then
            self.ui:registerPostReaderReadyCallback(function()
                self:checkXPointersAndProposeDOMVersionUpgrade()
            end)
        end
    end

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
            self:_gotoPercent(last_per * 100)
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
                self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getNextPage(0)))
            end
        end
    end

    -- self.configurable.visible_pages may not be the current nb of visible pages
    -- as crengine may decide to not ensure that in some conditions.
    -- It's the one we got from settings, the one the user has decided on
    -- with config toggle, and the one that we will save for next load.
    -- Use self.ui.document:getVisiblePageCount() to get the current
    -- crengine used value.
    self.ui.document:setVisiblePageCount(self.configurable.visible_pages)

    if config:has("hide_nonlinear_flows") then
        self.hide_nonlinear_flows = config:isTrue("hide_nonlinear_flows")
    else
        self.hide_nonlinear_flows = G_reader_settings:isTrue("hide_nonlinear_flows")
    end
    self.ui.document:setHideNonlinearFlows(self.hide_nonlinear_flows)

    -- Will be activated on ReaderReady
    if config:has("partial_rerendering") then
        self.partial_rerendering = config:isTrue("partial_rerendering")
    else
        self.partial_rerendering = G_reader_settings:nilOrTrue("cre_partial_rerendering")
    end

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

function ReaderRolling:onCloseDocument()
    self:tearDownRerenderingAutomation()
    -- Unschedule anything that might still somehow be...
    if self.mark_func then
        UIManager:unschedule(self.mark_func)
    end
    if self.unmark_func then
        UIManager:unschedule(self.unmark_func)
    end
    UIManager:unschedule(self.onCheckDomStyleCoherence)
    UIManager:unschedule(self.onUpdatePos)

    self.current_header_height = nil -- show unload progress bar at top
    -- we cannot do it in onSaveSettings() because getLastPercent() uses self.ui.document
    self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())

    local cache_file_path = self.ui.document:getCacheFilePath() -- nil if no cache file
    self.ui.doc_settings:saveSetting("cache_file_path", cache_file_path)
    if self.ui.document:hasCacheFile() then
        -- also checks if DOM is coherent with styles; if not, invalidate the
        -- cache, so a new DOM is built on next opening
        -- Don't check if we are reloading from a cache built in background: if
        -- incoherent, the user will get the popup after the re-open, and can
        -- decide to reload, or just revert his changes and avoid the reload.
        if self.ui.document:isBuiltDomStale() and self.rendering_state ~= self.RENDERING_STATE.DO_RELOAD_DOCUMENT then
            logger.dbg("cre DOM may not be in sync with styles, invalidating cache file for a full reload at next opening")
            self.ui.document:invalidateCacheFile()
        end
    end
    logger.dbg("cre cache used:", cache_file_path or "none")
    -- Unknown elements and attributes, uncomment if needed for debugging:
    -- local elements, attributes, namespaces = self.ui.document:getUnknownEntities()
    -- if elements ~= "" then logger.info("cre unknown elements: ", elements) end
    -- if attributes ~= "" then logger.info("cre unknown attributes: ", attributes) end
    -- if namespaces ~= "" then logger.info("cre unknown namespaces: ", namespaces) end
end

function ReaderRolling:onCheckDomStyleCoherence()
    if self.ui.document and self.ui.document:isBuiltDomStale() then
        -- When using an older DOM version, bookmarks may break
        local bookmarks_warn_txt = self.using_non_normalized_xpointers and self.ui.annotation:hasAnnotations()
            and ("\n" .. _("Note that this change in styles may render your bookmarks or highlights invalid.\nIf some of them no longer appear, you can simply revert the change you just made to show them again.") .. "\n\n")
        self:showSuggestReloadConfirmBox(bookmarks_warn_txt)
    end
end

function ReaderRolling:showSuggestReloadConfirmBox(warn_txt)
    UIManager:show(ConfirmBox:new{
        text = T(_("Styles have changed in such a way that fully reloading the document may be needed for a correct rendering.\n%1Do you want to reload the document?"),
            warn_txt or ""),
        ok_callback = function()
            -- Allow for ConfirmBox to be closed before showing
            -- "Opening file" InfoMessage
            UIManager:scheduleIn(0.5, function()
                -- And check we haven't quit reader in these 0.5s
                if self.ui.document then
                    self.ui:reloadDocument()
                end
            end)
        end,
    })
end

function ReaderRolling:onSaveSettings()
    self.ui.doc_settings:delSetting("last_percent") -- deprecated
    self.ui.doc_settings:saveSetting("last_xpointer", self.xpointer)
    self.ui.doc_settings:saveSetting("hide_nonlinear_flows", self.hide_nonlinear_flows)
    self.ui.doc_settings:saveSetting("partial_rerendering", self.partial_rerendering)
end

function ReaderRolling:onReaderReady()
    self:setupTouchZones()
    if self.hide_nonlinear_flows then
        self.ui.document:cacheFlows()
    end
    self.setupXpointer()
    if self.partial_rerendering then
        UIManager:nextTick(function()
            if self.ui.document then -- (could have disappeared with unit tests)
                self.ui.document:enablePartialRerendering(true)
            end
        end)
    end
end

function ReaderRolling:setupTouchZones()
    if not Device:isTouchDevice() then return end

    local forward_zone, backward_zone = self.view:getTapZones()

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
        {
            id = "rolling_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onSwipe(nil, ges) end,
        },
        {
            id = "rolling_pan",
            ges = "pan",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPan(nil, ges) end,
        },
        {
            id = "rolling_pan_release",
            ges = "pan_release",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onPanRelease(nil, ges) end,
        },
    })
end

function ReaderRolling:getLastProgress()
    return self.xpointer
end

function ReaderRolling:addToMainMenu(menu_items)
    if self.ui.document:hasNonLinearFlows() then
        local hide_nonlinear_text = _("When hide non-linear fragments is enabled, any non-linear fragments will be hidden from the normal page flow. Such fragments will always remain accessible through links, the table of contents and the 'Go to' dialog. This only works in single-page mode.")
        menu_items.hide_nonlinear_flows = {
            text = _("Hide non-linear fragments"),
            enabled_func = function()
                -- Custom hidden flows have precedence over publisher hidden non-linear fragments
                return self.view.view_mode == "page" and self.ui.document:getVisiblePageCount() == 1
                                                     and not self.ui.handmade:isHandmadeHiddenFlowsEnabled()
            end,
            checked_func = function() return self.hide_nonlinear_flows end,
            callback = function()
                self:onToggleHideNonlinear()
            end,
            hold_callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(
                        hide_nonlinear_text .. "\n\n" .. _("Set default hide non-linear fragments to %1?"),
                        self.hide_nonlinear_flows and _("enabled") or _("disabled")
                    ),
                    ok_callback = function()
                        G_reader_settings:saveSetting("hide_nonlinear_flows", self.hide_nonlinear_flows)
                    end,
                })
            end,
            help_text = hide_nonlinear_text,
        }
    end
    menu_items.partial_rerendering = {
        text = _("Enable partial renderings"),
        enabled_func = function()
            return self.ui.document:canBePartiallyRerendered() == true
        end,
        checked_func = function()
            return self.ui.document:isPartialRerenderingEnabled() == true
        end,
        callback = function()
            if self.ui.document:isPartialRerenderingEnabled() then
                -- (Don't disable it if we are currently in a rerendering automation)
                if not self.rendering_state then
                    self.partial_rerendering = false
                    if self.ui.document:enablePartialRerendering(false) then
                        -- Disabling returns true when some partial rerenderings had been done.
                        -- A full rerendering is needed to have a properly rendered document.
                        self:onUpdatePos()
                    end
                end
            else
                self.ui.document:enablePartialRerendering(true)
                self.partial_rerendering = self.ui.document:isPartialRerenderingEnabled()
            end
        end,
        hold_callback = function()
            local cre_partial_rerendering = G_reader_settings:nilOrTrue("cre_partial_rerendering")
            local text = _([[
With EPUB documents (having multiple fragments), text appearance adjustments can be made quicker by only rendering the current chapter.
After such partial renderings, the book and KOReader are in a degraded state: you can turn pages, but some info and features may be broken or disabled (ie. footer info, ToC, statistics…).
To get back to a sane state, a full rendering will happen in the background, get cached, and the document will be seamlessly reloaded after a brief period of inactivity.]])
            if cre_partial_rerendering then
                text = text .. "\n\n" .. _("The current default (★) is to enable partial renderings when possible.")
            else
                text = text .. "\n\n" .. _("The current default (★) is to always do a full rendering.")
            end
            local MultiConfirmBox = require("ui/widget/multiconfirmbox")
            UIManager:show(MultiConfirmBox:new{
                text = text,
                -- This text is a bit long, and MultiConfirmBox currently doesn't adjust the
                -- font size and may overflow the screen height: use a smaller font size
                face = require("ui/font"):getFace("infofont", 20),
                icon = "cre.render.partial",
                choice1_text_func =  function()
                    return cre_partial_rerendering and _("Disable") or _("Disable (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:makeFalse("cre_partial_rerendering")
                end,
                choice2_text_func = function()
                    return cre_partial_rerendering and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("cre_partial_rerendering")
                end,
            })
        end,
    }
end

function ReaderRolling:getLastPercent()
    if self.view.view_mode == "page" then
        return self.current_page / self.ui.document.info.number_of_pages
    else
        --- @fixme the calculated percent is not accurate in "scroll" mode.
        return self.ui.document:getPosFromXPointer(
            self.ui.document:getXPointer()) / self.ui.document.info.doc_height
    end
end

function ReaderRolling:onScrollSettingsUpdated(scroll_method, inertial_scroll_enabled, scroll_activation_delay_ms)
    self.scroll_method = scroll_method
    self.scroll_activation_delay = time.ms(scroll_activation_delay_ms)
    if inertial_scroll_enabled then
        self.ui.scrolling:setInertialScrollCallbacks(
            function(distance) -- do_scroll_callback
                if not self.ui.document then
                    return false
                end
                UIManager.currently_scrolling = true
                local prev_pos = self.current_pos
                self:_gotoPos(prev_pos + distance)
                return self.current_pos ~= prev_pos
            end,
            function() -- scroll_done_callback
                UIManager.currently_scrolling = false
                if self.ui.document then
                    self.xpointer = self.ui.document:getXPointer()
                end
                UIManager:setDirty(self.view.dialog, "partial")
            end
        )
    else
        self.ui.scrolling:setInertialScrollCallbacks(nil, nil)
    end
end

function ReaderRolling:onSwipe(_, ges)
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
    end
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        if G_reader_settings:nilOrFalse("page_turns_disable_swipe") then
            if self.view.inverse_reading_order then
                self:onGotoViewRel(-1)
            else
                self:onGotoViewRel(1)
            end
            return true
        end
    elseif direction == "east" then
        if G_reader_settings:nilOrFalse("page_turns_disable_swipe") then
            if self.view.inverse_reading_order then
                self:onGotoViewRel(1)
            else
                self:onGotoViewRel(-1)
            end
            return true
        end
    end
end

function ReaderRolling:onPan(_, ges)
    if ges.direction == "north" or ges.direction == "south" then
        if ges.mousewheel_direction and self.view.view_mode == "page" then
            -- Mouse wheel generates a Pan event: in page mode, move one
            -- page per event. Scroll mode is handled in the 'else' branch
            -- and use the wheeled distance.
            UIManager:broadcastEvent(Event:new("GotoViewRel", -1 * ges.mousewheel_direction))
        elseif self.view.view_mode == "scroll" then
            if not self._pan_started then
                self._pan_started = true
                -- Re-init state variables
                self._pan_has_scrolled = false
                self._pan_prev_relative_y = 0
                self._pan_to_scroll_later = 0
                self._pan_real_last_time = 0
                if ges.mousewheel_direction then
                    self._pan_activation_time = false
                else
                    self._pan_activation_time = ges.time + self.scroll_activation_delay
                end
                -- We will restore the previous position if this pan
                -- ends up being a swipe or a multiswipe
                self._pan_pos_at_pan_start = self.current_pos
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
                    self:_gotoPos(self.current_pos + dist)
                        -- (We'll update self.xpointer only when done moving, at
                        -- release/swipe time as it might be expensive)
                end
            else
                self._pan_to_scroll_later = self._pan_to_scroll_later + scroll_dist
            end
        end
    end
    return true
end

function ReaderRolling:onPanRelease(_, ges)
    if self._pan_has_scrolled and self._pan_to_scroll_later ~= 0 then
        self:_gotoPos(self.current_pos + self._pan_to_scroll_later)
    end
    self._pan_started = false
    UIManager.currently_scrolling = false
    if self._pan_has_scrolled then
        self._pan_has_scrolled = false
        self.xpointer = self.ui.document:getXPointer()
        -- Don't do any inertial scrolling if pan events come from
        -- a mousewheel (which may have itself some inertia)
        if (ges and ges.from_mousewheel) or not self.ui.scrolling:startInertialScroll() then
            UIManager:setDirty(self.view.dialog, "partial")
        end
    end
end

function ReaderRolling:onHandledAsSwipe()
    if self._pan_started then
        -- Restore original position as this pan we've started handling
        -- has ended up being a multiswipe or handled as a swipe to open
        -- top or bottom menus
        self:_gotoPos(self._pan_pos_at_pan_start)
        self._pan_started = false
        self._pan_has_scrolled = false
        UIManager.currently_scrolling = false
        -- No specific refresh: the swipe/multiswipe might show other stuff,
        -- and we'd want to avoid a flashing refresh
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
    local visible_page_count = self.ui.document:getVisiblePageNumberCount()
    local pageno = self.current_page + (visible_page_count > 1 and 1 or 0)
    local new_page
    if self.ui.document:hasHiddenFlows() then
        -- Find next chapter start
        new_page = self.ui.document:getNextPage(pageno)
        while new_page > 0 do
            if self.ui.toc:isChapterStart(new_page) then break end
            new_page = self.ui.document:getNextPage(new_page)
        end
    else
        new_page = self.ui.toc:getNextChapter(pageno) or 0
    end
    if new_page > 0 then
        self.ui.link:addCurrentLocationToStack()
        self:onGotoPage(new_page)
    end
    return true
end

function ReaderRolling:onGotoPrevChapter()
    local pageno = self.current_page
    local new_page
    if self.ui.document:hasHiddenFlows() then
        -- Find previous chapter start
        new_page = self.ui.document:getPrevPage(pageno)
        while new_page > 0 do
            if self.ui.toc:isChapterStart(new_page) then break end
            new_page = self.ui.document:getPrevPage(new_page)
        end
    else
        new_page = self.ui.toc:getPreviousChapter(pageno) or 0
    end
    if new_page > 0 then
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
        -- Unschedule previous marker as it's no longer accurate.
        UIManager:unschedule(self.mark_func)
        self.mark_func = nil
    end
    if self.unmark_func then
        -- execute scheduled unmark now to clean previous marker
        UIManager:unschedule(self.unmark_func)
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
    local marker_setting
    if G_reader_settings:has("followed_link_marker") then
        marker_setting = G_reader_settings:readSetting("followed_link_marker")
    else
        marker_setting = 1 -- default is: shown and removed after 1 second
    end

    if marker_xp and marker_setting then
        -- Show a mark on left side of screen to give a visual feedback of
        -- where xpointer target is (and remove if after 1s)
        local screen_y, screen_x = self.ui.document:getScreenPositionFromXPointer(marker_xp)
        local doc_margins = self.ui.document:getPageMargins()
        local marker_h = Screen:scaleBySize(self.configurable.font_size * 1.1 * self.configurable.line_spacing * (1/100))
        -- Make it 4/5 of left margin wide (and bigger when huge margin)
        local marker_w = math.floor(math.max(doc_margins["left"] - Screen:scaleBySize(5), doc_margins["left"] * 4/5))

        if self.ui.document:getVisiblePageCount() > 1 then -- 2-pages mode
            if screen_x < Screen:getWidth() / 2 then -- On left page
                if BD.mirroredUILayout() then
                    -- In the middle margin, on the right of text
                    -- Same trick as below, assuming page2_x is equal to page 1 right x
                    screen_x = math.floor(Screen:getWidth() * 0.5)
                    local page2_x = self.ui.document:getPageOffsetX(self.ui.document:getCurrentPage(true)+1)
                    marker_w = page2_x + marker_w - screen_x
                    screen_x = screen_x - marker_w
                else
                    screen_x = 0 -- In left page left margin
                end
            else -- On right page
                if BD.mirroredUILayout() then
                    screen_x = Screen:getWidth() - marker_w -- In right page right margin
                else
                    -- In the middle margin, on the left of text
                    -- This is a bit tricky with how the middle margin is sized
                    -- by crengine (see LVDocView::updateLayout() in lvdocview.cpp)
                    screen_x = math.floor(Screen:getWidth() * 0.5)
                    local page2_x = self.ui.document:getPageOffsetX(self.ui.document:getCurrentPage(true)+1)
                    marker_w = page2_x + marker_w - screen_x
                end
            end
        else -- 1-page mode
            if BD.mirroredUILayout() then
                screen_x = Screen:getWidth() - marker_w -- In right margin
            else
                screen_x = 0 -- In left margin
            end
        end

        self.mark_func = function()
            self.mark_func = nil
            local delayed_unmark = type(marker_setting) == "number"
            if delayed_unmark then -- we'll have to remove the marker
                -- We remember the original content that was where we are going
                -- to draw the marker.
                -- It's usually some white margin, so we could just draw a white
                -- rectangle to unmark it; but it might not always be just white
                -- margin: when we're in dual page mode and crengine has drawn a
                -- vertical pages separator - or if we have had crengine draw
                -- some background texture with credocument:setBackgroundImage().
                if self.mark_orig_content_bb then
                    -- be sure we don't leak memory if a previous one is still
                    -- hanging around
                    self.mark_orig_content_bb:free()
                    self.mark_orig_content_bb = nil
                end
                self.mark_orig_content_bb = Blitbuffer.new(marker_w, marker_h, Screen.bb:getType())
                self.mark_orig_content_bb:blitFrom(Screen.bb, 0, 0, screen_x, screen_y, marker_w, marker_h)
            end
            -- Paint directly to the screen and force a regional refresh
            Screen.bb:paintRect(screen_x, screen_y, marker_w, marker_h, Blitbuffer.COLOR_BLACK)
            Screen:refreshFast(screen_x, screen_y, marker_w, marker_h)
            if delayed_unmark then
                self.unmark_func = function()
                    self.unmark_func = nil
                    -- UIManager:setDirty(self.view.dialog, "ui", Geom:new({x=0, y=screen_y, w=marker_w, h=marker_h}))
                    -- No need to use setDirty (which would ask crengine to
                    -- re-render the page, which may take a few seconds on big
                    -- documents). We just restore what was there by painting
                    -- it directly to screen and triggering a regional refresh.
                    if self.mark_orig_content_bb then
                        Screen.bb:blitFrom(self.mark_orig_content_bb, screen_x, screen_y, 0, 0, marker_w, marker_h)
                        Screen:refreshUI(screen_x, screen_y, marker_w, marker_h)
                        self.mark_orig_content_bb:free()
                        self.mark_orig_content_bb = nil
                    end
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
    logger.dbg("goto relative screen:", diff, "in mode:", self.view.view_mode)
    if self.view.view_mode == "scroll" then
        local footer_height = ((self.view.footer_visible and not self.view.footer.settings.reclaim_height) and 1 or 0) * self.view.footer:getHeight()
        local page_visible_height = self.ui.dimen.h - footer_height
        local pan_diff = diff * page_visible_height
        if self.view.page_overlap_enable then
            local overlap_lines = G_reader_settings:readSetting("copt_overlap_lines") or 1
            local overlap_h = Screen:scaleBySize(self.configurable.font_size * 1.1 * self.configurable.line_spacing * (1/100)) * overlap_lines
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
        local page_count = self.ui.document:getVisiblePageNumberCount()
        local old_page = self.current_page
        -- we're in paged mode, so round up
        if diff > 0 then
            diff = math.ceil(diff)
        else
            diff = math.floor(diff)
        end
        local new_page = self.current_page
        if self.ui.document:hasHiddenFlows() then
            local test_page
            for i=1, math.abs(diff*page_count) do
                if diff > 0 then
                    test_page = self.ui.document:getNextPage(new_page)
                else
                    test_page = self.ui.document:getPrevPage(new_page)
                end
                if test_page > 0 then
                    new_page = test_page
                end
            end
        else
            new_page = new_page + diff*page_count
        end
        self:_gotoPage(new_page)
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
    self:updatePos()
end

function ReaderRolling:onBatchedUpdate()
    -- This is called by Dispatcher, and it may be possible to have re-entrant calls
    self.batched_update_count = self.batched_update_count + 1
end

function ReaderRolling:onBatchedUpdateDone()
    self.batched_update_count = self.batched_update_count - 1
    if self.batched_update_count <= 0 then
        self.batched_update_count = 0
        -- Be sure any Notification gets a chance to be painted before
        -- a blocking rerendering (:nextTick() is not enough)
        UIManager:tickAfterNext(self.onUpdatePos, self)
    end
end

--[[
    remember to signal this event when the document layout could
    have changed (ie. font, line height, margin... change)
    Note that xpointer should not be changed.
    The only handler of this event should be this one.
    A "DocumentRerendered" event will be then sent if it has changed.
    Provide force=true to get it emitted even if nothing has changed.
--]]
function ReaderRolling:onUpdatePos(force)
    if self.batched_update_count > 0 then
        return
    end
    if self.ui.postReaderReadyCallback ~= nil then -- ReaderUI:init() not yet done
        -- Don't schedule any updatePos as long as ReaderUI:init() is
        -- not finished (one will be called in the ui.postReaderReadyCallback
        -- we have set above) to avoid multiple refreshes.
        return true
    end

    Input:inhibitInput(true) -- Inhibit any past and upcoming input events.
    Device:setIgnoreInput(true) -- Avoid ANRs on Android with unprocessed events.

    -- Calling this now ensures the re-rendering is done by crengine
    -- so updatePos() has good info and can reposition
    -- the previous xpointer accurately:
    if self.ui.document then
        -- This can be racy with CloseDocument, as it's scheduled by onBatchedUpdateDone, guard it
        self.ui.document:getCurrentPos()
    end

    -- Otherwise, _readMetadata() would do that, but the positioning
    -- would not work as expected, for some reason (it worked
    -- previously because of some bad setDirty() in ConfigDialog widgets
    -- that were triggering a full repaint of crengine (so, the needed
    -- rerendering) before updatePos() is called.
    self:updatePos(force)

    Device:setIgnoreInput(false) -- Allow processing of events (on Android).
    Input:inhibitInputUntil(0.2) -- Discard input events, which might have occurred (double tap).
    -- We can use a smaller duration than the default (quite large to avoid accidental dismissals),
    -- to allow for quicker setting changes and rendering comparisons.
end

function ReaderRolling:updatePos(force)
    if not self.ui.document then
        -- document closed since we were scheduleIn'ed
        return
    end
    -- Check if the document has been re-rendered
    local new_rendering_hash = self.ui.document:getDocumentRenderingHash(true)
    if new_rendering_hash ~= self.rendering_hash or force then
        logger.dbg("rendering hash changed:", self.rendering_hash, ">", new_rendering_hash)
        self.rendering_hash = new_rendering_hash

        if self.ui.document:isRerenderingDelayed(true) then
            -- Partial rerendering is enabled, rerendering is delayed
            logger.dbg("  but rendering delayed, will do partial renderings on draw")
            -- annotation page numbers must be updated after self.ui:reloadDocument()
            self.ui.doc_settings:makeTrue("annotations_externally_modified")
            self:handleRenderingDelayed()
            return
        end

        -- Full rerendering done.
        -- A few things like page numbers may have changed
        self.ui.document:resetCallCache() -- be really sure this cache is reset
        self.ui.document:_readMetadata() -- get updated document height and nb of pages
        if self.hide_nonlinear_flows or force then
            self.ui.document:cacheFlows()
        end
        -- Note: ReaderStatistics needs to get these in this order
        -- ("PageUpdate" event first, and then "DocumentRerendered").
        self:_gotoXPointer(self.xpointer)
        self.ui:handleEvent(Event:new("DocumentRerendered"))
    end
    self:onUpdateTopStatusBarMarkers()
    UIManager:setDirty(self.view.dialog, "partial")
    self.current_header_height = self.view.view_mode == "page" and self.ui.document:getHeaderHeight() or 0
    -- Allow for the new rendering to be shown before possibly showing
    -- the "Styles have changed..." ConfirmBox so the user can decide
    -- if it is really needed
    UIManager:scheduleIn(0.1, self.onCheckDomStyleCoherence, self)
end

function ReaderRolling:onChangeViewMode()
    self.current_header_height = self.view.view_mode == "page" and self.ui.document:getHeaderHeight() or 0
    -- Restore current position when switching page/scroll mode
    if self.xpointer then
        if self.configurable.visible_pages == 2 then
            -- Switching from 2-pages page mode to scroll mode has crengine switch to 1-page,
            -- and we need to notice this re-rendering and keep things sane
            self:onUpdatePos()
        end
        self:_gotoXPointer(self.xpointer)
        -- Ensure a whole screen refresh is always enqueued
        UIManager:setDirty(self.view.dialog, "partial")
    else
        table.insert(self.ui.postInitCallback, function()
            self:_gotoXPointer(self.xpointer)
        end)
    end
end

function ReaderRolling:onRedrawCurrentView()
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.current_page))
    else
        self.current_page = self.ui.document:getCurrentPage()
        self.ui:handleEvent(Event:new("PosUpdate", self.current_pos, self.current_page))
    end
    return true
end

function ReaderRolling:onSetDimensions(dimen)
    if self.ui.postReaderReadyCallback ~= nil then
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
        -- Re-render document (and update TOC, re set position)
        self:onUpdatePos()
        -- Re-disable internal history, with required redraw
        self.ui.document:enableInternalHistory(false)
        self:onRedrawCurrentView()
    end
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
    if self.view.view_mode ~= "page" and self.view.page_overlap_enable and do_dim_area then
        local footer_height = ((self.view.footer_visible and not self.view.footer.settings.reclaim_height) and 1 or 0) * self.view.footer:getHeight()
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
            self.view.dim_area:clear()
        end
    else
        self.view.dim_area:clear()
    end
    if self.current_pos and not UIManager.currently_scrolling then
        self.ui:handleEvent(Event:new("PageChangeAnimation", new_pos > self.current_pos))
    end
    self.ui.document:gotoPos(new_pos)
    -- The current page we get in scroll mode may be a bit inaccurate,
    -- but we give it anyway to onPosUpdate so footer and statistics can
    -- keep up with page.
    self.current_page = self.ui.document:getCurrentPage()
    self.ui:handleEvent(Event:new("PosUpdate", new_pos, self.current_page))
end

function ReaderRolling:_gotoPercent(new_percent)
    if self.view.view_mode == "page" then
        self:_gotoPage(new_percent * self.ui.document:getPageCount() * (1/100))
    else
        self:_gotoPos(new_percent * self.ui.document.info.doc_height * (1/100))
    end
end

function ReaderRolling:_gotoPage(new_page, free_first_page, internal)
    if self.ui.document:getVisiblePageCount() > 1 and not free_first_page
            and (internal or self.ui.document:getVisiblePageNumberCount() == 2) then
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
    if self.current_page then
        self.ui:handleEvent(Event:new("PageChangeAnimation", new_page > self.current_page))
    end
    self.ui.document:gotoPage(new_page, internal)
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getCurrentPage()))
    else
        self.current_page = self.ui.document:getCurrentPage()
        self.ui:handleEvent(Event:new("PosUpdate", self.ui.document:getCurrentPos(), self.current_page))
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
    -- By default, crengine may decide to not ensure the value we request
    -- (for example, in 2-pages mode, it may stop being ensured when we
    -- increase the font size up to a point where a line would contain
    -- less that 20 glyphs).
    -- But we have CreDocument:setVisiblePageCount() provide only_if_sane=false
    -- so these checks are not done.
    -- We nevertheless update the setting (that will be saved) with what
    -- the user has requested - and not what crengine has enforced, and
    -- always query crengine for if it ends up ensuring it or not.
    self.configurable.visible_pages = visible_pages
    local prev_visible_pages = self.ui.document:getVisiblePageCount()
    self.ui.document:setVisiblePageCount(visible_pages)
    local cur_visible_pages = self.ui.document:getVisiblePageCount()
    if cur_visible_pages ~= prev_visible_pages then
        if self.ui.document:isPartialRerenderingEnabled() then
            -- Page numbers have gone *2 or /2, we don't want drawCurrentViewByPage()
            -- to ensure the current page as we know it, which would otherwise
            -- led us *2 or /2 away or back in the book.
            self.ui.document.no_page_sync = true
        end
        self:onUpdatePos()
    end
end

function ReaderRolling:onSetStatusLine(status_line)
    -- Enable or disable crengine header status line
    -- Note that for crengine, 0=header enabled, 1=header disabled
    self.ui.document:setStatusLineProp(status_line)
    self.cre_top_bar_enabled = status_line == 0
    -- (We used to toggle the footer when toggling the top status bar,
    -- but people seem to like having them both, and it feels more
    -- practicable to have the independent.)
    self:onUpdatePos()
end

function ReaderRolling:onUpdateTopStatusBarMarkers()
    if not self.cre_top_bar_enabled then
        return
    end
    local pages = self.ui.document:getPageCount()
    local ticks = self.ui.toc:getTocTicksFlattened()
    self.ui.document:setHeaderProgressMarks(pages, ticks)
end

function ReaderRolling:updateBatteryState()
    if self.view.view_mode == "page" and self.cre_top_bar_enabled then
        logger.dbg("update battery state")
        local powerd = Device:getPowerDevice()
        local main_batt_lvl = powerd:getCapacity()
        -- -1 is CR_BATTERY_STATE_CHARGING @ crengine/crengine/include/lvdocview.h
        local state = powerd:isCharging() and -1 or main_batt_lvl
        if powerd.device:hasAuxBattery() and powerd:isAuxBatteryConnected() and
            not powerd:isAuxCharging() then
            -- The first few reads after connecting to the PowerCover may fail, so default to zero
            local aux_batt_lvl = powerd:getAuxCapacity()
            -- If aux_battery not charging, but present -> don't show '[ + ]' in header
            -- but show the average (as both battery have the same maximum capacity).
            if G_reader_settings:readSetting("cre_header_battery_percent") ~= 0 then
                -- if percentage is wanted, show the total capacity of reader plus power-cover
                state = main_batt_lvl + aux_batt_lvl
            else
                -- if icon is wanted, show the total average capacity of reader and power-cover
                -- (as this is the shows graphically what capacity is left in total)
                state = math.floor((main_batt_lvl + aux_batt_lvl) / 2)
            end
        end
        if state then
            self.ui.document:setBatteryState(state)
        end
        return state
    end
    return 0
end

function ReaderRolling:handleEngineCallback(ev, ...)
    local argc = select("#", ...)
    local arg = argc > 0 and select(1, ...)
    -- logger.info("handleCallback: got", ev, ...)
    if ev == "OnLoadFileStart" then -- Start of book loading
        self:showEngineProgress(0) -- Start initial delay countdown
    elseif ev == "OnLoadFileProgress" then
        -- Initial load from file (step 1/2) or from cache (step 1/1)
        self:showEngineProgress(arg*(1/100/2))
    elseif ev == "OnNodeStylesUpdateStart" then -- Start of re-rendering
        self:showEngineProgress(0) -- Start initial delay countdown
    elseif ev == "OnNodeStylesUpdateProgress" then
        -- Update node styles (step 1/2 on re-rendering)
        self:showEngineProgress(arg*(1/100/2))
    elseif ev == "OnFormatStart" then -- Start of step 2/2
        self:showEngineProgress(1/2) -- 50%, in case of no OnFormatProgress
    elseif ev == "OnFormatProgress" then
        -- Paragraph formatting and page splitting (step 2/2 after load
        -- from file, step 2/2 on re-rendering)
        self:showEngineProgress(1/2 + arg*(1/100/2))
    elseif ev == "OnSaveCacheFileStart" then -- Start of cache file save
        self:showEngineProgress(1) -- Start initial delay countdown, fully filled
    elseif ev == "OnSaveCacheFileProgress" then
        -- Cache file save (when closing book after initial load from
        -- file or re-rendering)
        self:showEngineProgress(1 - arg*(1/100)) -- unfill progress
    elseif ev == "OnDocumentReady" or ev == "OnSaveCacheFileEnd" then
        self:showEngineProgress() -- cleanup
    elseif ev == "OnLoadFileError" then
        logger.warn("Cre error loading file:", arg)
    end
    -- ignore other events
end

local ENGINE_PROGRESS_INITIAL_DELAY = time.s(2)
local ENGINE_PROGRESS_UPDATE_DELAY = time.ms(500)

function ReaderRolling:showEngineProgress(percent)
    if G_reader_settings and G_reader_settings:isFalse("cre_show_progress") then
        -- (G_reader_settings might not be available when this is called
        -- in the context of unit tests.)
        -- This may slow things down too much with SDL over SSH,
        -- so allow disabling it.
        return
    end

    if percent then
        local now = time.now()
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
        local y = Size.margin.small
        -- On the first rendering the progress indicator should be on top.
        -- On further renderings the progress indicator should be on top,
        --    or if the top status bar is enabled, just below that.
        -- On toggling the top status bar, the location of the progress indicator
        --    should be on the location it would be expected in respect of the (old) drawn text.
        if self.ui.document.been_rendered and self.current_header_height then
            y = y + self.current_header_height
        end

        local w = math.floor(Screen:getWidth() * (1/3))
        local h = Size.line.progress
        if self.engine_progress_widget then
            self.engine_progress_widget:setPercentage(percent)
        else
            self.engine_progress_widget = ProgressWidget:new{
                width = w,
                height = h,
                fillcolor = Blitbuffer.COLOR_BLACK, -- we need pure B&W for refreshFast
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
        Screen:refreshFast(x, y, w, h)
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

function ReaderRolling:checkXPointersAndProposeDOMVersionUpgrade()
    if self.ui.document and self.ui.document:isBuiltDomStale() then
        -- DOM is not in sync, and some message "Styles have changed
        -- in such a way" is going to be displayed.
        -- Wait for things to be saner to migrate.
        return
    end

    -- Loop thru all known xpointers holders, and apply
    -- func(object, key, info_text) to each of them
    local applyFuncToXPointersSlots = function(func)
        -- Last position
        func(self, "xpointer", "last position in book")
        -- Annotations
        if self.ui.annotation and self.ui.annotation.annotations and #self.ui.annotation.annotations > 0 then
            local slots = { "page", "pos0", "pos1" }
            for _, item in ipairs(self.ui.annotation.annotations) do
                for _, slot in ipairs(slots) do
                    func(item, slot, item.text or "annotation")
                end
            end
        end
    end

    -- Cache and counters
    local normalized_xpointers = {}
    local lost_xpointer_info = {}
    local nb_xpointers = 0
    local nb_xpointers_found = 0
    local nb_xpointers_changed = 0
    local nb_xpointers_lost = 0

    -- To be provided to applyFuncToXPointersSlots()
    local checkAndCount = function(obj, slot, info)
        local xp = obj[slot]
        if not xp then
            return
        end
        if normalized_xpointers[xp] ~= nil then -- already seen
            return
        end
        nb_xpointers = nb_xpointers + 1
        local nxp = self.ui.document:getNormalizedXPointer(xp)
        normalized_xpointers[xp] = nxp -- cache it
        if nxp then
            nb_xpointers_found = nb_xpointers_found + 1
            if nxp ~= xp then
                nb_xpointers_changed = nb_xpointers_changed + 1
            end
        else
            nb_xpointers_lost = nb_xpointers_lost + 1
            lost_xpointer_info[xp] = info
        end
    end

    -- To be provided to applyFuncToXPointersSlots()
    local migrateXPointer = function(obj, slot, info)
        local xp = obj[slot]
        if not xp then
            return
        end
        local new_xp = normalized_xpointers[xp]
        if new_xp then
            obj[slot] = new_xp
            if slot == "page" then
                self.ui.annotation:updateItemByXPointer(obj)
            end
        else
            -- Let lost/not-found XPointer be. There is a small chance that
            -- it will be found (it it was made before the boxing code moved
            -- it into a box, it might be a normalized xpointer) but there is
            -- also a smaller chance that it will map to something completely
            -- different...
            -- Flag it, so one can investigate and fix it manually
            if slot ~= "xpointer" then -- (not for last_xpointer)
                obj["not_found_not_migrated"] = true
            end
        end
    end

    -- Do the actual xpointers migration, and related changes
    local upgradeToLatestDOMVersion = function()
        logger.info("Upgrading book to latest DOM version:")

        -- Backup metadata.lua
        local cur_dom_version = self.ui.doc_settings:readSetting("cre_dom_version") or "unknown"
        if self.ui.doc_settings.filepath then
            local backup_filepath = self.ui.doc_settings.filepath .. ".old_dom" .. tostring(cur_dom_version)
            if not lfs.attributes(backup_filepath) then -- backup does not yet exist
                os.rename(self.ui.doc_settings.filepath, backup_filepath)
                logger.info("  previous docsetting file saved as", backup_filepath)
            end
        end

        -- Migrate all XPointers
        applyFuncToXPointersSlots(migrateXPointer)
        logger.info(T("  xpointers updated: %1 unchanged, %2 modified, %3 not found let as-is",
            nb_xpointers_found - nb_xpointers_changed, nb_xpointers_changed, nb_xpointers_lost))

        -- Set latest DOM version, to be used at next load
        local latest_dom_version = self.ui.document:getLatestDomVersion()
        -- For some formats, DOM version 20200824 uses a new HTML parser that may build
        -- a different DOM tree. So, migrate these to a lower version
        local doc_format = self.ui.document:getDocumentFormat()
        if doc_format == "HTML" or doc_format == "CHM" or doc_format == "PDB" then
            latest_dom_version = self.ui.document:getDomVersionWithNormalizedXPointers()
        end
        self.ui.doc_settings:saveSetting("cre_dom_version", latest_dom_version)
        logger.info("  cre_dom_version updated to", latest_dom_version)

        -- Switch to default block rendering mode if this book has it set to "legacy",
        -- unless the user had set the global mode to be "legacy".
        -- (see ReaderTypeset:onReadSettings() for the logic of block_rendering_mode)
        local g_block_rendering_mode
        if G_reader_settings:has("copt_block_rendering_mode") then
            g_block_rendering_mode = G_reader_settings:readSetting("copt_block_rendering_mode")
        else
            -- nil means: use default
            g_block_rendering_mode = 3 -- default in ReaderTypeset:onReadSettings()
        end
        if g_block_rendering_mode ~= 0 then -- default is not "legacy"
            local block_rendering_mode = self.configurable.block_rendering_mode
            if block_rendering_mode == 0 then
                self.configurable.block_rendering_mode = g_block_rendering_mode
                logger.info("  block_rendering_mode switched to", g_block_rendering_mode)
            end
        end

        -- No need for "if doc:hasCacheFile() then doc:invalidateCacheFile()", as
        -- a change in gDOMVersionRequested has crengine trash previous cache file.
    end

    -- Check all xpointers
    applyFuncToXPointersSlots(checkAndCount)
    logger.info(T("%1 xpointers checked: %2 found (%3 changed) - %4 lost",
                nb_xpointers, nb_xpointers_found, nb_xpointers_changed, nb_xpointers_lost))
    if nb_xpointers_lost > 0 then
        logger.warn("Lost xpointers:")
        for k, v in pairs(lost_xpointer_info) do
            logger.warn("  ", k, ":", v)
        end
    end

    local text = _([[
This book was first opened, and has been handled since, by an older version of the rendering code.
Bookmarks and highlights can be upgraded to the latest version of the code.

%1

Proceed with this upgrade and reload the book?]])
    local details = {}
    if nb_xpointers_lost == 0 then
        table.insert(details, _([[All your bookmarks and highlights are valid and will be available after the migration.]]))
    else
        table.insert(details, T(_([[
Note that %1 (out of %2) xpaths from your bookmarks and highlights aren't currently found in the book, and may have been lost. You might want to toggle Rendering mode between 'legacy' and 'flat', and re-open this book, and see if they are found again, before proceeding.]]),
            nb_xpointers_lost, nb_xpointers))
    end
    if nb_xpointers_changed > 0 then
        table.insert(details, T(_([[
Note that %1 (out of %2) xpaths from your bookmarks and highlights have been normalized, and may not work on previous KOReader versions (if you're synchronizing your reading between multiple devices, you'll need to update KOReader on all of them).]]),
            nb_xpointers_changed, nb_xpointers))
    end
    text = T(text, table.concat(details, "\n\n"))

    UIManager:show(ConfirmBox:new{
        text = text,
        -- Given the layout of the buttons (Cancel|OK, and a big other button below
        -- with "Not now"), we don't want cancel_callback to be called when dismissing
        -- this ConfirmBox by taping outside. So, make it non dismissable.
        dismissable = false,
        other_buttons = {{
            {
                -- this is the real cancel/do nothing
                text = _("Not now"),
            }
        }},
        cancel_text = _("Not for this book"),
        cancel_callback = function()
            self.ui.doc_settings:makeTrue("cre_keep_old_dom_version")
        end,
        ok_text = _("Upgrade now"),
        ok_callback = function()
            -- Allow for ConfirmBox to be closed before migrating
            UIManager:scheduleIn(0.5, function()
                -- And check we haven't quit reader in these 0.5s
                if self.ui.document then
                    -- We'd rather not have any painting between the upgrade
                    -- and the document reloading (readerview might draw
                    -- highlights from the migrated xpointers, that would
                    -- not be found in the document...
                    local InfoMessage = require("ui/widget/infomessage")
                    local infomsg = InfoMessage:new{
                        text = _("Upgrading and reloading book…"),
                    }
                    UIManager:show(infomsg)
                    -- Let this message be shown
                    UIManager:scheduleIn(2, function ()
                        UIManager:close(infomsg)
                        if self.ui.document then
                            upgradeToLatestDOMVersion()
                            self.ui:reloadDocument()
                        end
                    end)
                end
            end)
        end,
    })
end

function ReaderRolling:onToggleHideNonlinear()
    self.hide_nonlinear_flows = not self.hide_nonlinear_flows
    self.ui.document:setHideNonlinearFlows(self.hide_nonlinear_flows)
    -- The document may change due to forced pagebreaks between flows being
    -- added or removed, so we need to find our location
    -- Even if the document doesn't change, we must ensure that the
    -- flow and call caches are cleared, to get the right page numbers,
    -- which may have changed, and the correct flow structure. Also,
    -- the footer needs updating, and TOC markers may come or go.
    -- So, provide force=true.
    self:onUpdatePos(true)
end


-- Partial rerendering handling methods and automation.
-- This is a one way path: we start from normal, and on a setting
-- change, we are and stay in a degraded partial rendering mode,
-- that we only exit with reloadDocument(), which makes everything
-- sane by restarting with fresh Reader and crengine instances.

function ReaderRolling:handleRenderingDelayed()
    -- Partial rendering will happen on next drawing: let it be known.
    -- Pages and ToC will be invalid, some modules may want to disable
    -- some features (ie. reading statistics should stop accounting
    -- pages read/total pages, as there are invalid, and bogus data
    -- would stick in the stats db).
    -- We don't send it on each partial rendering (which can happen as
    -- we turn pages, only on setting changes (if this would be needed,
    -- send this or another event in :handlePartialRerendering()).
    local first_partial_rerender = self.rendering_state == nil
    self.ui:handleEvent(Event:new("DocumentPartiallyRerendered", first_partial_rerender))
    -- Start the automation, ensuring we'll soon be rendering in background
    self:setupRerenderingAutomation()
    self._stepRerenderingAutomation(self.RENDERING_STATE.PARTIALLY_RERENDERED)
    -- Have ReaderView draw the current page, which will provoke the partial rerendering
    -- of the DocFragement the current page is from.
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderRolling:handlePartialRerendering()
    -- Called by ReaderView after crengine drawing, so we can notice if a partial
    -- rerendering did happen or not
    local nb_partial_rerenderings = self.ui.document:getPartialRerenderingsCount()
    if nb_partial_rerenderings == self.nb_partial_rerenderings then
        return -- no partial rerendering
    end
    logger.dbg("partial rerenderings done", self.nb_partial_rerenderings, ">", nb_partial_rerenderings)
    self.nb_partial_rerenderings = nb_partial_rerenderings

    self.ui.document:resetCallCache() -- trash invalid cached info

    -- crengine should have handled repositionning to the initial page xpointer,
    -- and redraw the page if needed.
    -- But when tweaking settings multiple times (without changing page), crengine
    -- will ensure this for each new displayed page top xpointer, and, the shifts
    -- accumulating, we may end up a few pages behind the original page.
    -- This is avoided with full rerendering by ensuring _gotoXPointer(self.xpointer)
    -- in :updatePos() above. So, do the same if we notice it is needed.
    local cur_page = self.ui.document:getCurrentPage()
    local cur_xpointer_page = self.ui.document:getPageFromXPointer(self.xpointer)
    if cur_page ~= cur_xpointer_page then
        logger.dbg("not on the expected page: repositionning and redrawing")
        self:_gotoXPointer(self.xpointer)
        return true -- ReaderView will repaint
    end

    -- Current page numbers, total pages and many other have changed.
    -- Some may be gathered next time from crengine as we reset the cache,
    -- but some are stored in Reader modules (ie. ToC) and won't be updated
    -- (some updates may be costly, but mostly, we don't want to hunt them all).
    -- At least, be sure everything knows about the current page, so we can
    -- turn pages and scroll.
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getCurrentPage()))
    else
        self.current_page = self.ui.document:getCurrentPage()
        self.ui:handleEvent(Event:new("PosUpdate", self.ui.document:getCurrentPos(), self.current_page))
    end
end

function ReaderRolling:_waitOrKillCurrentRerenderingSubprocess(wait, kill)
    -- No need for an asynchronous collector: we'll explicitly call this and wait
    -- before going on, even when reloading, to avoid having multiple possibly huge
    -- subprocesses at the same time.
    -- Returns true if the process is no longer running.
    -- We should only return false when wait=false provided (to know if still running).
    -- If wait=true, don't return until process is done.
    -- If kill=true, kill it, and wait for it to be gone.
    if not self._current_rerendering_pid then
        return true
    end
    if ffiutil.isSubProcessDone(self._current_rerendering_pid) then
        self._current_rerendering_pid = nil
        return true
    end
    if kill then
        wait = true -- we want to be sure it is collected
        ffiutil.terminateSubProcess(self._current_rerendering_pid)
    end
    if wait then
        if ffiutil.isSubProcessDone(self._current_rerendering_pid, true) then
            self._current_rerendering_pid = nil
            return true
        end
    end
    return false
end

function ReaderRolling:setupRerenderingAutomation()
    if self._stepRerenderingAutomation then
        return
    end

    -- Once this is created and called, we shouldn't stay long on the current document,
    -- we will reload it soon. So, disable standby during the whole steps.
    UIManager:preventStandby()

    -- Some states will step only when the user is idle
    local last_input_event_time = UIManager:getTime() -- (we got here because of some input)
    self._watchInputEvent = function()
        -- :getTime(), although not accurate, should be good enough, see:
        -- https://github.com/koreader/koreader/issues/9087#issuecomment-1419852952
        last_input_event_time = UIManager:getTime()
    end
    UIManager.event_hook:register("InputEvent", self._watchInputEvent)

    local next_step_not_before
    self._stepRerenderingAutomation = function(next_step)
        -- Ensure transitions between partial rerendering steps
        logger.dbg("_stepRerenderingAutomation(", next_step, "), currently ", self.rendering_state)
        UIManager:unschedule(self._stepRerenderingAutomation)
        local reschedule = true
        local prev_state = self.rendering_state

        if next_step == self.RENDERING_STATE.PARTIALLY_RERENDERED then
            -- rendering changed: may be the first, or some setting were changed
            -- before we ended all the steps and reload: cancel anything ongoing
            self:_waitOrKillCurrentRerenderingSubprocess(true, true)
            self.rendering_state = self.RENDERING_STATE.PARTIALLY_RERENDERED
            -- Avoid setDirty("ui"), a "partial" has been issued by our caller:
            prev_state = self.RENDERING_STATE.PARTIALLY_RERENDERED
            next_step_not_before = false

        elseif next_step == self.RENDERING_STATE.FULL_RENDERING_IN_BACKGROUND then
            self.rendering_state = self.RENDERING_STATE.FULL_RENDERING_IN_BACKGROUND
            if self.valid_cache_rendering_hash
                    and self.valid_cache_rendering_hash == self.ui.document:getDocumentRenderingHash(false) then
                -- No need to rerender, the current cache is valid, and we can just reload from it!
                -- We'll still show the rendering icon to keep the icon workflow consistent,
                -- it will just not display for long
                logger.dbg("background rerendering not needed, current cache is usable")
                self._current_rerendering_pid = nil -- have this mean no rerendering was needed
            else
                self._current_rerendering_pid = self:_rerenderInBackground()
            end

        elseif next_step == self.RENDERING_STATE.FULL_RENDERING_READY then
            -- Just show the new icon, work will happen at next schedule
            self.rendering_state = self.RENDERING_STATE.FULL_RENDERING_READY

        elseif next_step == self.RENDERING_STATE.RELOADING_DOCUMENT then
            -- Just show the new icon, work will happen at next schedule
            self.rendering_state = self.RENDERING_STATE.RELOADING_DOCUMENT

        else -- (from reschedule, next_step=nil)

            if self.rendering_state == self.RENDERING_STATE.PARTIALLY_RERENDERED then
                -- We want to launch a background rendering, but not before
                -- the user has closed all menus, meaning he might be satisfied
                -- enough with the partial result; as it may close them to see
                -- more of the book; allow for a small delay, assuming that
                -- if ReaderUI is still/again at the top, the user is done
                -- tweaking settings (if he changes a setting before a reload
                -- is triggered, we'll be go at step 1).
                -- Let's go with a delay of 3s.
                local top_widget = UIManager:getTopmostVisibleWidget() or {}
                if top_widget.name == "ReaderUI" then
                    if not next_step_not_before then -- start counting from now
                        next_step_not_before = UIManager:getTime() + time.s(3)
                    else
                        if UIManager:getTime() >= next_step_not_before then
                            self._stepRerenderingAutomation(self.RENDERING_STATE.FULL_RENDERING_IN_BACKGROUND)
                            return
                        end
                        -- otherwise, recheck at next schedule
                    end
                end

            elseif self.rendering_state == self.RENDERING_STATE.FULL_RENDERING_IN_BACKGROUND then
                if self._current_rerendering_pid then
                    -- Be sure the subprocess is still running
                    if self:_waitOrKillCurrentRerenderingSubprocess(false) then
                        -- subprocess died... (self._current_rerendering_pid has then be reset to nil)
                        -- Step forward, as if no background rendering needed
                        self._stepRerenderingAutomation(self.RENDERING_STATE.FULL_RENDERING_READY)
                        return
                    else -- still running
                        if shared_state[1] ~= 0 then -- done rendering
                            self._stepRerenderingAutomation(self.RENDERING_STATE.FULL_RENDERING_READY)
                            return
                        end
                        -- otherwise, recheck at next schedule
                    end
                else -- no background rendering needed, step forward
                    self._stepRerenderingAutomation(self.RENDERING_STATE.FULL_RENDERING_READY)
                    return
                end

            elseif self.rendering_state == self.RENDERING_STATE.FULL_RENDERING_READY
                or self.rendering_state == self.RENDERING_STATE.RELOADING_DOCUMENT then
                -- We'll have to reload the document: we prefer doing it when the user is
                -- idle "reading" (that is, ReaderUI is at top, and no input for some time)
                -- to not surprise and interrupt him if he is turning pages, reading a dict
                -- lookup result, or busy in some other widget or menu.
                -- Let's go with 5s of idle time
                local do_reload = false
                local top_widget = UIManager:getTopmostVisibleWidget() or {}
                if top_widget.name == "ReaderUI" then
                    do_reload = true
                    if self.ui.highlight.hold_pos or self.ui.highlight.select_mode then
                        -- Not if text selection in progress (to not reload while the user
                        -- is selecting, even if idle)
                        do_reload = false
                    elseif UIManager:getTime() < last_input_event_time + time.s(5) then
                        -- Not idle long enough
                        do_reload = false
                    end
                end
                if self.rendering_state == self.RENDERING_STATE.FULL_RENDERING_READY then
                    if do_reload then
                        -- Transition to show the reload icon for at least 1s if the
                        -- book reloads really fast. We'll redo the above conditions checks
                        -- in case things happened in the meantime.
                        self._stepRerenderingAutomation(self.RENDERING_STATE.RELOADING_DOCUMENT)
                        return
                    end
                    -- Otherwise, conditions not yet met
                else -- self.RENDERING_STATE.RELOADING_DOCUMENT
                    if not do_reload then
                        -- Stuff happened: transition back to previous state
                        self._stepRerenderingAutomation(self.RENDERING_STATE.FULL_RENDERING_READY)
                    else
                        -- reload icon shown, ready to reload
                        if self._current_rerendering_pid and not self:_waitOrKillCurrentRerenderingSubprocess(false) then
                            -- Rendering subproces still alive, waiting for our signal to save its cache
                            -- We need to let the subprocess save the cache, and only then reloadDocument.
                            -- We need to block the UI so no other setting get changed, and the cache
                            -- is sane to reload from.
                            -- Let subprocess know it can save cache
                            shared_state[2] = 1
                            -- And wait for it to end (successfully or not)
                            self:_waitOrKillCurrentRerenderingSubprocess(true)
                        end
                        -- Otherwise, no background rerendering needed, or the subprocess died: go on with the reload.
                        -- We're done with background stuff and icon animations: reallow standby
                        self.rendering_state = self.RENDERING_STATE.DO_RELOAD_DOCUMENT
                        self.ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
                    end
                    return
                end
            end
        end
        if self.rendering_state ~= prev_state then
            logger.dbg("_stepRerenderingAutomation", prev_state, ">", self.rendering_state)
            -- Have ReaderView redraw and refresh ReaderFlipping and our state icon, avoiding flashes
            UIManager:setDirty(self.view.dialog, "ui", self.view.flipping:getRefreshRegion())
        end
        if reschedule then
            UIManager:scheduleIn(1, self._stepRerenderingAutomation)
        end
    end
end

function ReaderRolling:tearDownRerenderingAutomation()
    if self._stepRerenderingAutomation then
        UIManager:unschedule(self._stepRerenderingAutomation)
        self._stepRerenderingAutomation = nil
        UIManager:allowStandby()
    end
    if self._watchInputEvent then
        UIManager.event_hook:unregister("InputEvent", self._watchInputEvent)
        self._watchInputEvent = nil
    end
    -- Be sure we don't let any zombie
    self:_waitOrKillCurrentRerenderingSubprocess(true, true)
    Device:enableCPUCores(1)
end

function ReaderRolling:_rerenderInBackground()
    Device:enableCPUCores(2)

    -- Set up mmap segment to exchange signals between main and sub processes
    shared_state[0] = 0
    shared_state[1] = 0
    shared_state[2] = 0

    -- If the fork failed, self._current_rerendering_pid will be false, and the above
    -- automation should do as if no rendering needed, and go on with the reload,
    -- provoking a full rerendering on load
    local child_pid = ffiutil.runInSubProcess(function(my_pid)
        logger.dbg("background rerendering started for hash", self.rendering_hash)
        -- Disable top left cre progress bar (not really needed, and may cause
        -- a crash on SDL "XInitThreads not called")
        self.ui.document:setCallback()
        self.ui.document:enablePartialRerendering(false) -- we want a full render

        -- Rerender: this will take some time
        self.ui.document._document:renderDocument()

        -- We could check if we would get "Styles have changed...fully reloading the document may be needed"
        -- (which happens when CSS properties "display:" and "white-space:" have changed for some nodes, which
        -- is rather rare with our style tweaks) here, and do the reload and rerendering in this same background
        -- subprocess, and doing this would hide this whole thing from the user, making the UX seamless.
        -- But this would need a lot more memory, as we would then have 2 independent DOM in memory.
        -- Ie. with a big book and KOReader taking 120 MB, the subprocess would additionally use:
        -- - 60 MB when doing a simple rerendering
        -- - 130 MB when doing a full load+render
        -- So, let's not, and let the user handle that after the coming up reload.
        if false and self.ui.document:isBuiltDomStale() then
            logger.info("background cre DOM may not be in sync with styles, doing a full reload")
            self.ui.document:invalidateCacheFile()
            -- Just doing this seems to work, we can keep the same LVDocView, no need for any
            -- tedious cleanup:
            self.ui.document._document:loadDocument(self.ui.document.file)
            self.ui.document._document:renderDocument()
        end

        -- Rebuild ToC and PageMap data (these are done when needed when requested by frontend,
        -- but doing that now in the background will save that time on the next reload).
        self.ui.document._document:updateTocAndPageMap()

        -- crengine is quite optimized regarding cache updates writes: it will compute hashes
        -- of each block and avoid writing them to disk if not changed from its vision of
        -- the existing cache at load time. Because of this, we don't want this background
        -- subprocess to update the cache until we are sure we'll reload from it.
        -- So, let the main process know we are done rendering and waiting for its
        -- signal that we can write the cache.

        -- We take some precautions to avoid staying alive if nothing is waiting for us
        if shared_state[0] ~= 0 and shared_state[0] ~= my_pid then
            -- Parent process is no longer waiting for this child
            os.exit(0)
        end
        shared_state[1] = 1 -- done rendering, let parent know, and wait before saving cache
        shared_state[2] = 0 -- we're going to wait for this to become non-0
        while true do
            ffiutil.usleep(250000)
            if shared_state[0] ~= 0 and shared_state[0] ~= my_pid then
                logger.info("rerendering subprocess: no longer waited, exiting")
                os.exit(0)
            end
            if ffi.C.getppid() ~= koreader_pid then
                -- new parent pid: main process exited/crashed
                logger.info("rerendering subprocess: parent gone, exiting")
                os.exit(0)
            end
            if shared_state[2] ~= 0 then
                break -- we can go on
            end
        end
        logger.dbg("rerendering subprocess: going on saving cache")
        self.ui.document._document:close() -- should save the cache and clean things properly
        -- ffiutil.sleep(1)
        logger.dbg("rerendering subprocess done")
    end)
    -- If the fork failed, or in _stepRerenderingAutomation() when we notice the subprocess has died
    -- (probably because of out of memory), should we disable partial rendering for this book?
    shared_state[0] = child_pid or 0
    return child_pid
end

return ReaderRolling
