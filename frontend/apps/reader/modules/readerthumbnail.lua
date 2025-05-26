local Blitbuffer = require("ffi/blitbuffer")
local Cache = require("cache")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Persist = require("persist")
local RenderImage = require("ui/renderimage")
local TileCacheItem = require("document/tilecacheitem")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- This ReaderThumbnail module provides a service for generating thumbnails
-- of book pages.
-- It handles launching via the menu or Dispatcher/Gestures two fullscreen
-- widgets related to showing pages and thumbnails that will make use of
-- its services: BookMap and PageBrowser.
local ReaderThumbnail = InputContainer:extend{}

function ReaderThumbnail:init()
    self:registerKeyEvents()
    if not Device:isTouchDevice() and not Device:useDPadAsActionKeys() then
        -- The BookMap and PageBrowser widgets depend too much on gestures,
        -- making them work with not enough keys on Non-Touch would be hard and very limited, so
        -- just don't make them available.
        -- We will only let them run on useDPadAsActionKeys devices.
        return
    end

    self.ui.menu:registerToMainMenu(self)

    -- Use LuaJIT fast buffer.encode()/decode() when serializing BlitBuffer
    -- for exchange between subprocess and parent.
    self.codec = Persist.getCodec("luajit")

    self:setupColor()
    self.thumbnails_requests = {}
    self.current_target_size_tag = nil

    -- Ensure no multiple executions, and nextTick() the scheduleIn()
    -- so we get a chance to process events in-between refreshes and
    -- this can be interrupted (otherwise, something scheduleIn(0.1),
    -- if a screen refresh is then done and taking longer than 0.1s,
    -- would be executed immediately, without emptying any input event).
    local schedule_step = 0
    self._ensureTileGeneration_action = function(restart)
        if restart then
            UIManager:unschedule(self._ensureTileGeneration_action)
            schedule_step = 0
        end
        if schedule_step == 0 then
            schedule_step = 1
            UIManager:nextTick(self._ensureTileGeneration_action)
        elseif schedule_step == 1 then
            schedule_step = 2
            UIManager:scheduleIn(0.1, self._ensureTileGeneration_action)
        else
            schedule_step = 0
            self:ensureTileGeneration()
        end
    end
end

function ReaderThumbnail:registerKeyEvents()
    if Device:hasDPad() and Device:useDPadAsActionKeys() then
        if Device:hasKeyboard() then
            self.key_events.ShowBookMap = { { "Shift", "Down" } }
        else
            self.key_events.ShowBookMap = { { "ScreenKB", "Down" } }
        end
    end
end

function ReaderThumbnail:addToMainMenu(menu_items)
    menu_items.book_map = {
        text = _("Book map"),
        callback = function()
            self:onShowBookMap()
        end,
        -- Show the alternative overview mode (which is just a restricted
        -- variation of the main book map) with long-press (let's avoid
        -- adding another item in the crowded first menu).
        hold_keep_menu_open = false,
        hold_callback = function()
            self:onShowBookMap(true)
        end,
    }
    menu_items.page_browser = {
        text = _("Page browser"),
        callback = function()
            self:onShowPageBrowser()
        end,
    }
end

function ReaderThumbnail:onShowBookMap(overview_mode)
    local BookMapWidget = require("ui/widget/bookmapwidget")
    UIManager:show(BookMapWidget:new{
        ui = self.ui,
        overview_mode = overview_mode,
    })
    return true
end

function ReaderThumbnail:onShowPageBrowser()
    local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    UIManager:show(PageBrowserWidget:new{
        ui = self.ui,
    })
    return true
end

-- This is made a module local so we can keep track of pids
-- to collect across multiple Reader instantiations
local pids_to_collect = {}

function ReaderThumbnail:collectPids()
    if #pids_to_collect == 0 then
        return false
    end
    for i=#pids_to_collect, 1, -1 do
        if ffiutil.isSubProcessDone(pids_to_collect[i]) then
            table.remove(pids_to_collect, i)
        end
    end
    return #pids_to_collect > 0
end

function ReaderThumbnail:setupColor()
    self.bb_type = self.ui.document.render_color and self.ui.document.color_bb_type or Blitbuffer.TYPE_BB8
end

function ReaderThumbnail:setupCache()
    if not self.tile_cache then
        -- We want to allow browsing at least N pages worth of thumbnails
        -- without cache trashing. A little more than N pages (because inter
        -- thumbnail margins) will fit in N * screen size.
        -- With N=5, this should use from 5 to 15 Mb on a classic eInk device.
        local N = 5
        local max_bytes = math.ceil(N * Screen:getWidth() * Screen:getHeight() * Blitbuffer.TYPE_TO_BPP[self.bb_type] / 8)
        -- We don't really care about limiting any number of slots, so allow
        -- for at least 5 pages of 10x10 tiles
        local avg_itemsize = math.ceil(max_bytes * (1/500))
        self.tile_cache = Cache:new{
            size = max_bytes,
            avg_itemsize = avg_itemsize, -- will make slots=500
            enable_eviction_cb = true,
        }
    end
end

function ReaderThumbnail:logCacheSize()
    logger.info(string.format("Thumbnails cache: %d/%d (%s/%s)",
                    self.tile_cache.cache.used_slots(),
                    self.tile_cache.slots,
                    util.getFriendlySize(self.tile_cache.cache.used_size()),
                    util.getFriendlySize(self.tile_cache.size)))
end

function ReaderThumbnail:resetCache()
    if self.tile_cache then
        self.tile_cache:clear()
        self.tile_cache = nil
    end
end

function ReaderThumbnail:removeFromCache(hash_subs, remove_only_non_matching)
    -- Remove from cache all tiles matching any hash from hash_subs.
    -- IF only_non_matching=true, keep those matching and remove all others.
    if not self.tile_cache then
        return
    end
    if type(hash_subs) ~= "table" then
        hash_subs = { hash_subs }
    end
    local nb_removed, size_removed = 0, 0
    local to_remove = {}
    for thash, tile in self.tile_cache.cache:pairs() do
        local remove = remove_only_non_matching
        for _, h in ipairs(hash_subs) do
            if thash:find(h, 1, true) then -- plain text match (no pattern needed)
                remove = not remove
                break
            end
        end
        if remove then
            to_remove[thash] = true
            nb_removed = nb_removed + 1
            size_removed = size_removed + tile.size
        end
    end
    for thash, _ in pairs(to_remove) do
        self.tile_cache.cache:delete(thash)
        logger.dbg("removed cached thumbnail", thash)
    end
    return nb_removed, size_removed
end

function ReaderThumbnail:resetCachedPagesForBookmarks(annotations)
    -- Multiple bookmarks may be provided
    local start_page, end_page
    for i = 1, #annotations do
        local bm = annotations[i]
        if self.ui.rolling then
            -- Look at all properties that may be xpointers
            for _, k in ipairs({"page", "pos0", "pos1"}) do
                if bm[k] and type(bm[k]) == "string" then
                    local p = self.ui.document:getPageFromXPointer(bm[k])
                    if not start_page or p < start_page then
                        start_page = p
                    end
                    if not end_page or p > end_page then
                        end_page = p
                    end
                end
            end
        else
            if bm.page and type(bm.page) == "number" then
                local bm_page0 = (bm.pos0 and bm.pos0.page) or bm.page
                local bm_page1 = (bm.pos1 and bm.pos1.page) or bm.page
                for p = bm_page0, bm_page1 do
                    if not start_page or p < start_page then
                        start_page = p
                    end
                    if not end_page or p > end_page then
                        end_page = p
                    end
                end
            end
        end
    end
    if start_page and end_page then
        local hash_subs_to_remove = {}
        for p=start_page, end_page do
            table.insert(hash_subs_to_remove, string.format("p%d-", p))
        end
        self:removeFromCache(hash_subs_to_remove)
    end
end

function ReaderThumbnail:tidyCache()
    if self.current_target_size_tag then
        -- Remove all thumbnails generated for an older target size
        self:removeFromCache("-"..self.current_target_size_tag, true)
    end
end

function ReaderThumbnail:cancelPageThumbnailRequests(batch_id)
    if batch_id then
        self.thumbnails_requests[batch_id] = nil
    else
        self.thumbnails_requests = {}
    end
    if self.req_in_progress and (not batch_id or self.req_in_progress.batch_id == batch_id) then
        -- Kill any reference to the module cancelling it
        self.req_in_progress.when_generated_callback = nil
    end
end

function ReaderThumbnail:getPageThumbnail(page, width, height, batch_id, when_generated_callback)
    self:setupCache()
    self.current_target_size_tag = string.format("w%d_h%d", width, height)
    if self.ui.rolling and Screen.night_mode and self.ui.document.configurable.nightmode_images == 1 then
        -- We'll get a different bb in this case: it needs its own cache hash
        self.current_target_size_tag = self.current_target_size_tag .. "_nm"
    end
    local hash = string.format("p%d-%s", page, self.current_target_size_tag)
    local tile = self.tile_cache and self.tile_cache:check(hash)
    if tile then
        -- Cached: call callback and we're done.
        when_generated_callback(tile, batch_id, false)
        return false -- not delayed
    end
    if not self.thumbnails_requests[batch_id] then
        self.thumbnails_requests[batch_id] = {}
    end
    table.insert(self.thumbnails_requests[batch_id], {
        batch_id = batch_id,
        hash = hash,
        page = page,
        width = width,
        height = height,
        when_generated_callback = when_generated_callback,
    })
    -- Start tile generation, avoid multiple ones
    self._ensureTileGeneration_action(true)
    return true -- delayed
end

function ReaderThumbnail:ensureTileGeneration()
    if not self._standby_prevented then
        self._standby_prevented = true
        UIManager:preventStandby()
    end
    local has_pids_still_to_collect = self:collectPids()

    local still_in_progress = false
    if self.req_in_progress then
        local pid_still_to_collect
        still_in_progress, pid_still_to_collect = self:checkTileGeneration(self.req_in_progress)
        if pid_still_to_collect then
            has_pids_still_to_collect = true
        end
    end
    if not still_in_progress then
        self.req_in_progress = nil
        while true do
            local req_id, requests = next(self.thumbnails_requests)
            if not req_id then -- no more requests
                break
            end
            local req = table.remove(requests, 1)
            if #requests == 0 then
                self.thumbnails_requests[req_id] = nil
            end
            if req.when_generated_callback then -- not cancelled since queued
                -- It might have been generated and cached by a previous batch
                local tile = self.tile_cache and self.tile_cache:check(req.hash)
                if tile then
                    req.when_generated_callback(tile, req.batch_id, true)
                else
                    if self:startTileGeneration(req) then
                        self.req_in_progress = req
                        break
                    else
                        -- Failure starting it: let requester know in case it cares, and forget it
                        req.when_generated_callback(nil, req.batch_id, true)
                    end
                end
            end
        end
    end
    if self.req_in_progress or has_pids_still_to_collect or next(self.thumbnails_requests) then
        self._ensureTileGeneration_action()
    else
        if self._standby_prevented then
            self._standby_prevented = false
            UIManager:allowStandby()
        end
    end
end

function ReaderThumbnail:startTileGeneration(request)
    local pid, parent_read_fd = ffiutil.runInSubProcess(function(pid, child_write_fd)
        -- Get page image as if drawn on the screen
        local bb = self:_getPageImage(request.page)
        -- Scale it to fit in the requested size
        local scale_factor = math.min(request.width / bb:getWidth(), request.height / bb:getHeight())
        local target_w = math.floor(bb:getWidth() * scale_factor)
        local target_h = math.floor(bb:getHeight() * scale_factor)
        -- local time = require("ui/time")
        -- local start_time = time.now()
        local tile = TileCacheItem:new{
            bb = RenderImage:scaleBlitBuffer(bb, target_w, target_h, true),
            pageno = request.page,
        }
        tile.size = tonumber(tile.bb.stride) * tile.bb.h
        -- logger.info("tile size", tile.bb.w, tile.bb.h, "=>", tile.size)
        -- logger.info(string.format("  scaling took %.3f seconds, %d bpp", time.to_s(time.since(start_time)), tile.bb:getBpp()))
        -- bb:free() -- no need to spend time freeing, we're dying soon anyway!

        ffiutil.writeToFD(child_write_fd, self.codec.serialize(tile:totable()), true)
    end, true) -- with_pipe = true
    if pid then
        -- Store these in the request object itself
        request.pid = pid
        request.parent_read_fd = parent_read_fd
        return true
    end
    logger.warn("PageBrowserWidget thumbnail start failure:", parent_read_fd)
    return false
end

function ReaderThumbnail:checkTileGeneration(request)
    local pid, parent_read_fd = request.pid, request.parent_read_fd
    local stuff_to_read = ffiutil.getNonBlockingReadSize(parent_read_fd) ~= 0
    local subprocess_done = ffiutil.isSubProcessDone(pid)
    logger.dbg("subprocess_done:", subprocess_done, " stuff_to_read:", stuff_to_read)
    if stuff_to_read then
        -- local time = require("ui/time")
        -- local start_time = time.now()
        local result, err = self.codec.deserialize(ffiutil.readAllFromFD(parent_read_fd))
        if result then
            local tile = TileCacheItem:new{}
            tile:fromtable(result)
            if self.tile_cache then
                self.tile_cache:insert(request.hash, tile)
            end
            if request.when_generated_callback then -- not cancelled
                request.when_generated_callback(tile, request.batch_id, true)
            end
        else
            logger.warn("PageBrowserWidget thumbnail deserialize() failed:", err)
            if request.when_generated_callback then -- not cancelled
                request.when_generated_callback(nil, request.batch_id, true)
            end
        end
        -- logger.info(string.format("  parsing result from subprocess took %.3f seconds", time.to_s(time.since(start_time))))
        if not subprocess_done then
            table.insert(pids_to_collect, pid)
            return false, true
        end
        return false
    elseif subprocess_done then
        -- subprocess_done: process exited with no output
        ffiutil.readAllFromFD(parent_read_fd) -- close our fd
        return false
    end
    logger.dbg("process not yet done, will check again soon")
    return true
end

function ReaderThumbnail:_getPageImage(page)
    -- This is run in a subprocess: we can tweak all document settings
    -- to get an adequate image of the page.
    -- No need to worry about the final state of things: this subprocess
    -- will die just after drawing the page, and all will be forgotten,
    -- without impact on the parent process.

    -- Be sure to limit our impact on the disk-saved book state
    self.ui.saveSettings = function() end -- Be sure nothing is flushed
    self.ui.statistics = nil -- Don't update statistics for pages we visit

    -- By default, our target page size is the current screen size
    local target_w, target_h = Screen:getWidth(), Screen:getHeight()

    -- This was all mostly chosen by experimenting.
    -- Be sure to call the innermost methods enough to get what we want, and
    -- not upper event handlers that may trigger other unneeded events and stuff.
    -- Especially, be sure to not trigger any paint on the screen buffer, or
    -- any processing of input events.
    -- No need to worry about UIManager:scheduleIn() or :nextTick(), as
    -- we will die before the callback gets a chance to be run.

    -- Common to ReaderRolling and ReaderPaging
    self.ui.view.footer_visible = false -- We want no footer on page image
    if self.ui.view.highlight.lighten_factor < 0.3 then
        self.ui.view.highlight.lighten_factor = 0.3 -- make lighten highlight a bit darker
    end
    self.ui.highlight.select_mode = false -- Remove any select mode icon

    if self.ui.rolling then
        -- CRE documents: pages all have the aspect ratio of our screen (alt top status bar
        -- will be croped out after drawing), we will show them just as rendered.
        self.ui.rolling.rendering_state = nil -- Remove any partial rerendering icon
        if self.ui.view.view_mode == "scroll" then
            -- Get out of scroll mode, and be sure we'll be in one-page mode as that
            -- is what is shown in scroll mode (needs to do the following in that
            -- order to avoid rendering hash change)
            self.ui.rolling:onSetVisiblePages(1)
            self.ui.view:onSetViewMode("page")
        end
        if self.ui.document.configurable.font_gamma < 30 then  -- Increase font gamma (if not already increased),
            self.ui.document:setGammaIndex(30) -- as downscaling will make text grayer
        end
        self.ui.document:setImageScaling(false) -- No need for smooth scaling as all will be downscaled
        -- (We keep "nighmode_images" as it was set: we may get and cache a different bb whether nightmode is on or off)
        self.ui.view.state.page = page -- Be on requested page
        self.ui.document:gotoPage(page) -- Current xpointer needs to be updated for some of what follows
        self.ui.bookmark:onPageUpdate(page) -- Update dogear state for this page
        self.ui.pagemap:onPageUpdate(page) -- Update pagemap labels for this page
    end

    if self.ui.paging then
        -- With PDF/DJVU/Pics, we will show the native page (no reflow, no crop, no zoom
        -- to columns...). This makes thumbnail generation faster, and will allow the user
        -- to get an overview of the book native pages to better decide which option will
        -- be best to use for the book.
        -- We also want to get a thumbnail with the aspect ratio of the native page
        -- (so we don't get a native landscape page smallish and centered with blank above
        -- and below in a portrait thumbnail, if the screen is in portrait mode).

        self.ui.view.hinting = false -- Disable hinting
        self.ui.view.page_scroll = false -- Get out of scroll mode
        self.ui.view.flipping_visible = false -- No page flipping icon
        self.ui.document.configurable.text_wrap = false -- Get out of reflow mode
        self.ui.document.configurable.trim_page = 3 -- Page crop: none
        -- self.ui.document.configurable.trim_page = 1 -- Page crop: auto (very slower)
        self.ui.document.configurable.auto_straighten = 0 -- No auto straighten
        -- We can let dewatermark if the user has enabled it, it helps
        -- limiting annoying eInk refreshes of light gray areas
        -- self.ui.document.configurable.page_opt = 0 -- No dewatermark
        -- We won't touch the contrast (to try making text less gray), as it applies on
        -- images that could get too dark.

        -- Get native page dimensions, and update our target bb dimensions so it gets the
        -- same aspect ratio (we don't use native dimensions as is, as they may get huge)
        local dimen = self.ui.document:getPageDimensions(page, 1, 0)
        local scale_factor = math.min(target_w / dimen.w, target_h / dimen.h)
        target_w = math.floor(dimen.w * scale_factor)
        target_h = math.floor(dimen.h * scale_factor)
        dimen = Geom:new{ w=target_w, h=target_h }
        -- logger.info("getPageImage", page, dimen, "=>", target_w, target_h, scale_factor)

        -- This seems to do it all well:
        --   local Event = require("ui/event")
        --   self.ui:handleEvent(Event:new("SetDimensions", dimen))
        --   self.ui.view.dogear[1].dimen.w = dimen.w -- (hack... its code uses the Screen width)
        --   self.ui:handleEvent(Event:new("PageUpdate", page))
        --   self.ui:handleEvent(Event:new("SetZoomMode", "page"))

        -- Trying to do as little as needed, knowing the internals:
        self.ui.view:onSetDimensions(dimen)
        self.ui.view:onBBoxUpdate(nil) -- drop any bbox, draw native page
        self.ui.view.state.page = page
        self.ui.view.state.zoom = scale_factor
        self.ui.view.state.rotation = 0
        self.ui.view:recalculate()
        self.ui.view.dogear[1].dimen.w = dimen.w -- (hack... its code uses the Screen width)
        self.ui.bookmark:onPageUpdate(page) -- Update dogear state for this page
    end

    -- Draw the page on a new BB with the targeted size
    local bb = Blitbuffer.new(target_w, target_h, self.bb_type)
    self.ui.view:paintTo(bb, 0, 0)

    if self.ui.rolling then
        -- Crop out the top alt status bar if enabled
        local header_height = self.ui.document:getHeaderHeight()
        if header_height > 0 then
            bb = bb:viewport(0, header_height, bb.w, bb.h - header_height)
        end
    end

    return bb
end

function ReaderThumbnail:onCloseDocument()
    self:cancelPageThumbnailRequests()
    if self.tile_cache then
        self:logCacheSize()
        self.tile_cache:clear()
        self.tile_cache = nil
    end
    if self._standby_prevented then
        self._standby_prevented = false
        UIManager:allowStandby()
    end
end

function ReaderThumbnail:onRenderingModeUpdate()
    self:resetCache()
end

function ReaderThumbnail:onColorRenderingUpdate()
    self:setupColor()
    self:resetCache()
end

-- CRE: emitted after a re-rendering
ReaderThumbnail.onDocumentRerendered = ReaderThumbnail.resetCache
ReaderThumbnail.onDocumentPartiallyRerendered = ReaderThumbnail.resetCache
-- Emitted When adding/removing/updating bookmarks and highlights
ReaderThumbnail.onAnnotationsModified = ReaderThumbnail.resetCachedPagesForBookmarks

return ReaderThumbnail
