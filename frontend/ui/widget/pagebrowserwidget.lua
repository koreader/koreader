local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local logger = require("logger")
local _ = require("gettext")

-- We use the BookMapRow widget, a local widget defined in bookmapwidget.lua,
-- that we made available via BookMapWidget itself
local BookMapWidget = require("ui/widget/bookmapwidget")
local BookMapRow = BookMapWidget.BookMapRow

-- PageBrowserWidget: shows thumbnails of pages
local PageBrowserWidget = InputContainer:extend{
    title = _("Page browser"),
    -- Focus page: will be put at the best place in the thumbnail grid
    -- (that is, the grid will pick thumbnails from pages before and
    -- after it, and more pages after than before)
    focus_page = nil,
    -- Should only be nil on the first launch via ReaderThumbnail
    launcher = nil,
}

function PageBrowserWidget:init()
    if self.ui.view:shouldInvertBiDiLayoutMirroring() then
        BD.invert()
    end

    -- Compute non-settings-dependant sizes and options
    self.dimen = Geom:new{
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true -- hint for UIManager:_repaint()

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            ScrollRowUp = { { "Up" } },
            ScrollRowDown = { { "Down" } },
            ScrollPageUp = { { Input.group.PgBack } },
            ScrollPageDown = { { Input.group.PgFwd } },
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = self.dimen,
                }
            },
            MultiSwipe = {
                GestureRange:new{
                    ges = "multiswipe",
                    range = self.dimen,
                }
            },
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                }
            },
            Hold = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                }
            },
            Pinch = {
                GestureRange:new{
                    ges = "pinch",
                    range = self.dimen,
                }
            },
            Spread = {
                GestureRange:new{
                    ges = "spread",
                    range = self.dimen,
                }
            },
        }
    end

    -- Put the BookMapRow left and right border outside of screen
    self.row_width = self.dimen.w + 2*BookMapRow.pages_frame_border

    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = self.title,
        left_icon = "info",
        left_icon_tap_callback = function() self:showHelp() end,
        left_icon_hold_callback = function()
            -- Cycle nb of toc span levels shown in bottom row
            if self:updateNbTocSpans(-1, true) then
                self:updateLayout()
            end
        end,
        close_callback = function() self:onClose() end,
        close_hold_callback = function() self:onClose(true) end,
        show_parent = self,
    }
    self.title_bar_h = self.title_bar:getHeight()

    -- Guess grid TOC span height from its font size
    -- (it feels this font size does not need to be configurable: too large and
    -- titles will be too easily truncated, too small and they will be unreadable)
    self.toc_span_font_name = "infofont"
    self.toc_span_font_size = 14
    self.toc_span_face = Font:getFace(self.toc_span_font_name, self.toc_span_font_size)
    local test_w = TextWidget:new{
        text = "z",
        face = self.toc_span_face,
    }
    self.span_height = test_w:getSize().h + BookMapRow.toc_span_border
    test_w:free()

    self.min_nb_rows = 1
    self.max_nb_rows = 6
    self.min_nb_cols = 1
    self.max_nb_cols = 6

    -- Get some info that shouldn't change across calls to update() and updateLayout()
    self.ui.toc:fillToc()
    self.max_toc_depth = self.ui.toc.toc_depth
    self.nb_pages = self.ui.document:getPageCount()
    self.cur_page = self.ui.toc.pageno
    -- Get bookmarks and highlights from ReaderBookmark
    self.bookmarked_pages = self.ui.bookmark:getBookmarkedPages()
    -- Get read page from the statistics plugin if enabled
    self.read_pages = self.ui.statistics and self.ui.statistics:getCurrentBookReadPages()
    self.current_session_duration = self.ui.statistics and (os.time() - self.ui.statistics.start_current_period)
    -- Hidden flows, for first page display, and to draw them gray
    self.has_hidden_flows = self.ui.document:hasHiddenFlows()
    if self.has_hidden_flows and #self.ui.document.flows > 0 then
        self.hidden_flows = {}
        -- Pick into credocument internal data to build a table
        -- of {first_page_number, last_page_number) for each flow
        for flow, tab in ipairs(self.ui.document.flows) do
            table.insert(self.hidden_flows, { tab[1], tab[1]+tab[2]-1 })
        end
    end
    -- Reference page numbers, for first row page display
    self.page_labels = nil
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        self.page_labels = self.ui.document:getPageMap()
    end
    -- Location stack
    self.previous_locations = self.ui.link:getPreviousLocationPages()

    -- Compute settings-dependant sizes and options, and build the inner widgets
    -- (this will call self:update())
    self:updateLayout()
end

function PageBrowserWidget:updateLayout()
    -- We start with showing all toc levels (we could use book_map_toc_depth,
    -- but we might want to have it different here).
    self.nb_toc_spans = self.ui.doc_settings:readSetting("page_browser_toc_depth") or self.max_toc_depth

    -- Row will contain: nb_toc_spans + page slots + spacing (+ some borders)
    local statistics_enabled = self.ui.statistics and self.ui.statistics:isEnabled()
    local page_slots_height_ratio = 1 -- default to 1 * span_height
    if not statistics_enabled and self.nb_toc_spans > 0 then
        -- Just enough to show page separators below toc spans
        page_slots_height_ratio = 0.2
    end
    self.row_height = math.ceil((self.nb_toc_spans + page_slots_height_ratio + 1) * self.span_height + 2*BookMapRow.pages_frame_border)

    self.grid_width = self.dimen.w
    self.grid_height = self.dimen.h - self.title_bar_h - self.row_height

    -- We'll draw some kind of static transparent glass over the BookMapRow,
    -- which should span over the page slots that get their thumbnails shown.
    self.view_finder_r = Size.radius.window
    self.view_finder_bw = Size.border.default
    -- Have its top border noticable above the BookMapRow top border
    self.view_finder_y = self.dimen.h - self.row_height - 2*self.view_finder_bw
    -- And put its bottom rounded corner outside of screen
    self.view_finder_h = self.row_height + 2*self.view_finder_bw + Size.radius.window

    if self.grid then
        self.grid:free()
    end
    self.grid = OverlapGroup:new{
        dimen = Geom:new{
            w = self.grid_width,
            h = self.grid_height,
        },
        allow_mirroring = false,
    }
    if self.row then
        self.row:free()
    end
    self.row = CenterContainer:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.row_height,
        },
        -- Will contain a BookMapRow wider, with l/r borders outside screen
    }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            self.title_bar,
            self.grid,
            self.row,
        }
    }

    self.nb_rows = self.ui.doc_settings:readSetting("page_browser_nb_rows")
                   or G_reader_settings:readSetting("page_browser_nb_rows")
    self.nb_cols = self.ui.doc_settings:readSetting("page_browser_nb_cols")
                   or G_reader_settings:readSetting("page_browser_nb_cols")
    if not self.nb_rows or not self.nb_cols then
        -- 3 x 2 seems like a good default, in both portrait or landscape mode
        self.nb_cols = 3
        self.nb_rows = 2
    end
    self.nb_grid_items = self.nb_rows * self.nb_cols
    -- Set our items target size
    self.grid_item_margin = Screen:scaleBySize(10) -- borders will eat into this, it should be larger than borders thin+thick
    self.grid_item_height = math.floor((self.grid_height - (self.nb_rows)*self.grid_item_margin) / self.nb_rows) -- no need for top margin, title bottom padding is enough
    self.grid_item_width = math.floor((self.grid_width - (1+self.nb_cols)*self.grid_item_margin) / self.nb_cols)
    self.grid_item_dimen = Geom:new{
        w = self.grid_item_width,
        h = self.grid_item_height
    }

    self.grid:clear()

    for idx = 1, self.nb_grid_items do
        local row = math.floor((idx-1)/self.nb_cols) -- start from 0
        local col = (idx-1) % self.nb_cols
        if BD.mirroredUILayout() then
            col = self.nb_cols - col - 1
        end
        local offset_x = self.grid_item_margin*(col+1) + self.grid_item_width*col
        local offset_y = self.grid_item_margin*(row) + self.grid_item_height*row -- no need for 1st margin
        local grid_item = CenterContainer:new{
            dimen = self.grid_item_dimen:copy(),
        }
        table.insert(self.grid, FrameContainer:new{
            overlap_offset = {offset_x, offset_y},
            margin = 0,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            grid_item,
        })
    end

    -- Put the focused (requested) page at some appropriate place in the grid
    if self.nb_rows > 1 then -- Multiple rows
        -- Show the focus page at the rightmost position in the first row
        self.focus_page_shift = self.nb_cols - 1
    else -- Single row
        if self.nb_cols > 2 then -- 3+ columns: show one page behind only
            self.focus_page_shift = 1
        else -- 1 or 2 columns: show it first
            self.focus_page_shift = 0
        end
    end

    -- Don't go with too small page slots
    self.pages_per_row = math.max(self.nb_grid_items*3, 20)
    -- We want our view finder centered over the BookMapRow
    if self.pages_per_row % 2 ~= self.nb_grid_items % 2 then
        self.pages_per_row = self.pages_per_row + 1
    end

    -- Update the BookMapRow and page thumbnails for the current view
    self:update()
end

function PageBrowserWidget:update()
    if self.requests_batch_id then
        self.ui.thumbnail:cancelPageThumbnailRequests(self.requests_batch_id)
    end
    self.requests_batch_id = "PageBrowserWidget"..tostring(os.time())

    if not self.focus_page then
        self.focus_page = self.cur_page or 1
    end

    local grid_page_start = self.focus_page - self.focus_page_shift
    local grid_page_end = grid_page_start + self.nb_grid_items - 1

    -- Get p_start so that our viewfinder is centered
    local p_start = math.ceil(grid_page_start + self.nb_grid_items/2 - self.pages_per_row/2)
    local p_end = p_start + self.pages_per_row - 1
    local blank_page_slots_before_start = 0
    local blank_page_slots_after_end = 0 -- used only when _mirroredUI
    if p_end > self.nb_pages then
        blank_page_slots_after_end = p_end - self.nb_pages
        p_end = self.nb_pages
    end
    if p_start < 1 then
        blank_page_slots_before_start = 1 - p_start
        p_start = 1
    end

    -- Show the page number or label at the bottom page slot every N slots, with N
    -- the nb of thumbnails so we get at least one page label in our viewport.
    local page_texts_cycle = math.min(self.nb_grid_items, 10) -- but max 10
    local next_p = p_start
    local cur_page_label_idx = 1
    local page_texts = {}
    for p=p_start, p_end do
        if p >= next_p then
            -- Only show a page text if there is no indicator on that slot
            if p ~= self.cur_page and not self.bookmarked_pages[p] and not self.previous_locations[p] then
                local page_text
                if self.page_labels then
                    local page_label
                    for idx=cur_page_label_idx, #self.page_labels do
                        local item = self.page_labels[idx]
                        if item.page >= p then
                            if item.page == p then
                                page_label = item.label
                            end
                            break
                        end
                        cur_page_label_idx = idx
                    end
                    if page_label then
                        page_text = self.ui.pagemap:cleanPageLabel(page_label)
                    end
                elseif self.has_hidden_flows then
                    local flow = self.ui.document:getPageFlow(p)
                    if flow == 0 then
                        page_text = tostring(self.ui.document:getPageNumberInFlow(p))
                    else
                        page_text = string.format("[%d]%d", self.ui.document:getPageNumberInFlow(p), self.ui.document:getPageFlow(p))
                    end
                else
                    page_text = tostring(p)
                end
                if page_text then
                    local page_block, page_block_dx -- centered by default
                    if p == p_start or p == grid_page_start or p == grid_page_end+1 then
                        page_block = "left"
                        page_block_dx = Size.padding.tiny
                        if p == grid_page_start then
                            page_block_dx = page_block_dx + self.view_finder_bw + 1
                        end
                    elseif p == p_end or p == grid_page_end or p == grid_page_start-1 then
                        page_block = "right"
                        page_block_dx = Size.padding.tiny
                        if p == grid_page_end then
                            page_block_dx = page_block_dx + self.view_finder_bw + 1
                        end
                    end
                    page_texts[p] = {
                        text = page_text,
                        block = page_block,
                        block_dx = page_block_dx,
                    }
                    next_p = p + page_texts_cycle
                end
            end
        end
    end

    -- We need to rebuilt the full set of toc spans that will be shown
    -- Similar (but simplified) to what is done in BookMapWidget.
    self.toc_depth = self.nb_toc_spans
    local toc = self.ui.toc.toc
    local cur_toc_items = {}
    local row_toc_items = {}
    local toc_idx = 1
    while toc_idx <= #toc do
        -- Find out the toc items that can be shown on this row
        local item = toc[toc_idx]
        if item.page > p_end then
            break
        end
        if item.depth <= self.toc_depth then -- ignore lower levels we won't show
            -- An item at level N closes all previous items at level >= N
            for lvl = item.depth, self.toc_depth do
                local done_toc_item = cur_toc_items[lvl]
                cur_toc_items[lvl] = nil
                if done_toc_item then
                    done_toc_item.p_end = math.max(item.page - 1, done_toc_item.p_start)
                    if done_toc_item.p_end >= p_start then
                        -- Can go into row_toc_items[lvl]
                        if done_toc_item.p_start < p_start then
                            done_toc_item.p_start = p_start
                            done_toc_item.started_before = true -- no left margin
                        end
                        if not row_toc_items[lvl] then
                            row_toc_items[lvl] = {}
                        end
                        -- We're done with it, we can just move it
                        table.insert(row_toc_items[lvl], done_toc_item)
                    end
                end
            end
            cur_toc_items[item.depth] = {
                title = item.title,
                p_start = item.page,
                p_end = nil,
            }
        end
        toc_idx = toc_idx + 1
    end
    local is_last_row = p_end >= self.nb_pages
    for lvl = 1, self.nb_toc_spans do -- (no-op/no-loop if flat_map)
        local active_toc_item = cur_toc_items[lvl]
        if active_toc_item then
            if active_toc_item.p_start < p_start then
                active_toc_item.p_start = p_start
                active_toc_item.started_before = true -- no left margin
            end
            active_toc_item.p_end = p_end
            active_toc_item.continues_after = not is_last_row -- no right margin (except if last row)
            -- Look at next TOC item to see if it would close this one
            local coming_up_toc_item = toc[toc_idx]
            if coming_up_toc_item and coming_up_toc_item.page == p_end+1 and coming_up_toc_item.depth <= lvl then
                active_toc_item.continues_after = false -- right margin
            end
            if not row_toc_items[lvl] then
                row_toc_items[lvl] = {}
            end
            table.insert(row_toc_items[lvl], active_toc_item)
        end
    end

    local left_spacing = 0
    if blank_page_slots_before_start > 0 then
        left_spacing = BookMapRow:getLeftSpacingForNumberOfPageSlots(blank_page_slots_before_start, self.pages_per_row, self.row_width)
    end
    local row = BookMapRow:new{
        height = self.row_height,
        width = self.row_width,
        show_parent = self,
        left_spacing = left_spacing,
        nb_toc_spans = self.nb_toc_spans,
        span_height = self.span_height,
        font_face = self.toc_span_face,
        start_page_text = "",
        start_page = p_start,
        end_page = p_end,
        pages_per_row = self.pages_per_row - blank_page_slots_before_start,
        cur_page = self.cur_page,
        with_page_sep = true,
        toc_items = row_toc_items,
        bookmarked_pages = self.bookmarked_pages,
        previous_locations = self.previous_locations,
        hidden_flows = self.hidden_flows,
        read_pages = self.read_pages,
        current_session_duration = self.current_session_duration,
        page_texts = page_texts,
    }
    self.row[1] = row

    if BD.mirroredUILayout() then
        self.view_finder_x = row:getPageX(grid_page_end)
        self.view_finder_w = row:getPageX(grid_page_start, true) - self.view_finder_x
        if blank_page_slots_after_end > 0 then
            self.view_finder_x = self.view_finder_x
                + BookMapRow:getLeftSpacingForNumberOfPageSlots(blank_page_slots_after_end, self.pages_per_row, self.row_width)
                + row.pages_frame_border -- (needed, but not sure why it is needed...)
        end
    else
        self.view_finder_x = row:getPageX(grid_page_start)
        self.view_finder_w = row:getPageX(grid_page_end, true) - self.view_finder_x
        self.view_finder_x = self.view_finder_x + left_spacing
    end
    -- we requested with_page_sep, so leave these blank spaces between page slots outside the viewfinder
    self.view_finder_x = self.view_finder_x + 1
    self.view_finder_w = self.view_finder_w - 1

    for idx=1, self.nb_grid_items do
        local p = grid_page_start + idx - 1
        if p < 1 or p > self.nb_pages then
            self.grid[idx].page_idx = nil -- no action on Tap
            self:clearTile(idx)
        else
            self.grid[idx].page_idx = p -- go there on Tap
            local delayed = self.ui.thumbnail:getPageThumbnail(p, self.grid_item_width, self.grid_item_height, self.requests_batch_id, function(tile, batch_id, async_response)
                if batch_id ~= self.requests_batch_id then
                    -- Response from an obsolete request
                    return
                end
                if not tile then -- failure notification
                    return
                end
                -- If tile was in the cache, we get this immediately called with async_response=false,
                -- and we don't need to do any setDirty as a full one will be done below.
                self:showTile(idx, p, tile, async_response)
            end)
            if delayed then
                self:clearTile(idx, true)
                self.wait_for_refresh_on_show_tile = true
            end
        end
    end
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function PageBrowserWidget:paintTo(bb, x, y)
    -- Paint regular sub widgets the classic way
    InputContainer.paintTo(self, bb, x, y)
    -- If we would prefer to see the BookMapRow top border always take the full width
    -- so it acts as a separator from the thumbnail grid, add this:
    -- bb:paintRect(0, self.dimen.h - self.row_height, self.dimen.w, BookMapRow.pages_frame_border, Blitbuffer.COLOR_BLACK)
    -- And explicitely paint our viewfinder over the BookMapRow
    bb:paintBorder(self.view_finder_x, self.view_finder_y, self.view_finder_w, self.view_finder_h,
                            self.view_finder_bw, Blitbuffer.COLOR_BLACK, self.view_finder_r)
end

function PageBrowserWidget:clearTile(grid_idx, in_progress, do_refresh)
    local item_frame = self.grid[grid_idx] -- FrameContainer
    local item_container = item_frame[1] -- CenterContainer
    local dimen = item_frame.dimen
    if item_container[1] then -- TextWidget or FrameContainer
        if item_container[1].dimen then
            dimen = item_container[1].dimen:copy()
        end
        if item_container[1].free then
            item_container[1]:free()
        end
    end
    -- Quickly showing the first tile while the whole page is still being refreshed
    -- can cause some papercut-like refresh glitch on this first tile, with even more
    -- chances if we put gray things in the initial page (as gray is painted black
    -- and then becomes gray, making it 2 steps and longer).
    -- This seems to be mitigated with our self.wait_for_refresh_on_show_tile trick.
    if in_progress then
        item_container[1] = TextWidget:new{
            text = "♲", -- gray symbol (which initially caused refresh glitches)
            -- Alternatives (mostly from Nerdfont):
            -- text = "\u{26F6}", -- square with four corners
            -- text = "\u{ED36}",
            -- text = "\u{F196}", -- square with plus inside
            -- text = "\u{ED5F}", -- square with plus at top right
            -- text = "\u{F141}",
            -- text = "\u{EB52}",
            -- text = "\u{EB4F}",
            -- text = "\u{F021}",
            face = Font:getFace("cfont", 20),
        }
    else
        item_container[1] = VerticalSpan:new{ width = 0, }
    end
    if do_refresh then
        UIManager:setDirty(self, function()
            return "ui", dimen
        end)
    end
end

function PageBrowserWidget:showTile(grid_idx, page, tile, do_refresh)
    local item_frame = self.grid[grid_idx] -- FrameContainer
    local item_container = item_frame[1] -- CenterContainer
    if item_container[1] and item_container[1].free then -- TextWidget
        item_container[1]:free()
    end
    local border = page == self.cur_page and Size.border.thick or Size.border.thin
    local thumb_frame = FrameContainer:new{
        is_page_thumbnail = true, -- for tap handler
        margin = 0,
        padding = 0,
        bordersize = border,
        background = Blitbuffer.COLOR_WHITE,
        ImageWidget:new{
            image = tile.bb,
            image_disposable = false,
        },
    }
    item_container[1] = thumb_frame
        -- thumb_frame will overflow its CenterContainer because of the added borders,
        -- but CenterContainer handles that well. We will refresh the outer dimensions.

    if do_refresh then
        if self.wait_for_refresh_on_show_tile then
            self.wait_for_refresh_on_show_tile = nil
            -- Be sure the main view initial refresh has ended before refreshing
            -- this first thumbnail, to avoid papercut refresh glitches.
            UIManager:waitForVSync()
        end
        UIManager:setDirty(self, function()
            return "ui", thumb_frame.dimen
        end)
    end
end

function PageBrowserWidget:showHelp()
    UIManager:show(InfoMessage:new{
        text = _([[
Page browser shows thumbnails of pages.

The bottom ribbon displays an extract of the book map around the shown pages: see the book map help for details.

Swipe along the top or left screen edge to change the number of columns or rows of thumbnails.
Swipe vertically to move one row, horizontally to move one page.
Swipe horizontally in the bottom ribbon to move by the full stripe.
Tap in the bottom ribbon on a page to focus thumbnails on this page.
Tap on a thumbnail to read this page.
Long-press on ⓘ to decrease or reset the number of chapter levels shown in the bottom ribbon.
Any multiswipe will close the page browser.]]),
    })
end

function PageBrowserWidget:onClose(close_all_parents)
    if self.requests_batch_id then
        self.ui.thumbnail:cancelPageThumbnailRequests(self.requests_batch_id)
    end
    -- Close this widget
    logger.dbg("closing PageBrowserWidget")
    UIManager:close(self)
    if self.launcher then
        -- We were launched by a BookMapWidget, don't do any cleanup.
        if close_all_parents then
            -- The last one of these (which has no launcher attribute)
            -- will do the cleanup below.
            self.launcher:onClose(true)
        else
            UIManager:setDirty(self.launcher, "ui")
        end
    else
        BD.resetInvert()
        -- Remove all thumbnails generated for a different target size than
        -- the last one used (no need to keep old sizes if the user played
        -- with nb_cols/nb_rows, as on next opening, we just need the ones
        -- with the current size to be available)
        self.ui.thumbnail:tidyCache()
        -- Force a GC to free the memory used by the widgets and tiles
        -- (delay it a bit so this pause is less noticable)
        UIManager:scheduleIn(0.5, function()
            collectgarbage()
            collectgarbage()
        end)
        -- As we're getting back to Reader, do a full flashing refresh to remove
        -- any ghost trace of thumbnails or black page slots
        UIManager:setDirty(self.ui.dialog, "full")
    end
    return true
end

function PageBrowserWidget:saveSettings(reset)
    if reset then
        self.nb_toc_spans = nil
        self.nb_rows = nil
        self.nb_cols = nil
    end
    self.ui.doc_settings:saveSetting("page_browser_toc_depth", self.nb_toc_spans)
    self.ui.doc_settings:saveSetting("page_browser_nb_rows", self.nb_rows)
    self.ui.doc_settings:saveSetting("page_browser_nb_cols", self.nb_cols)
    -- We also save nb_rows/nb_cols as global settings, so they will apply on other books
    -- where they were not already set
    G_reader_settings:saveSetting("page_browser_nb_rows", self.nb_rows)
    G_reader_settings:saveSetting("page_browser_nb_cols", self.nb_cols)
end

function PageBrowserWidget:updateNbTocSpans(value, relative)
    local new_nb_toc_spans
    if relative then
        new_nb_toc_spans = self.nb_toc_spans + value
    else
        new_nb_toc_spans = value
    end
    -- We don't cap, we cycle
    if new_nb_toc_spans < 0 then
        new_nb_toc_spans = self.max_toc_depth
    end
    if new_nb_toc_spans > self.max_toc_depth then
        new_nb_toc_spans = 0
    end
    if new_nb_toc_spans == self.nb_toc_spans then
        return false
    end
    self.nb_toc_spans = new_nb_toc_spans
    self:saveSettings()
    return true
end

function PageBrowserWidget:updateNbCols(value, relative)
    local new_nb_cols
    if relative then
        new_nb_cols = self.nb_cols + value
    else
        new_nb_cols = value
    end
    if new_nb_cols < self.min_nb_cols then
        new_nb_cols = self.min_nb_cols
    end
    if new_nb_cols > self.max_nb_cols then
        new_nb_cols = self.max_nb_cols
    end
    if new_nb_cols == self.nb_cols then
        return false
    end
    self.nb_cols = new_nb_cols
    self:saveSettings()
    return true
end

function PageBrowserWidget:updateNbRows(value, relative)
    local new_nb_rows
    if relative then
        new_nb_rows = self.nb_rows + value
    else
        new_nb_rows = value
    end
    if new_nb_rows < self.min_nb_rows then
        new_nb_rows = self.min_nb_rows
    end
    if new_nb_rows > self.max_nb_rows then
        new_nb_rows = self.max_nb_rows
    end
    if new_nb_rows == self.nb_rows then
        return false
    end
    self.nb_rows = new_nb_rows
    self:saveSettings()
    return true
end

function PageBrowserWidget:updateFocusPage(value, relative)
    local new_focus_page
    if relative then
        new_focus_page = self.focus_page + value
    else
        new_focus_page = value
    end
    if new_focus_page < 1 then
        new_focus_page = 1
    end
    if new_focus_page > self.nb_pages then
        new_focus_page = self.nb_pages
    end
    if new_focus_page == self.focus_page then
        return false
    end
    self.focus_page = new_focus_page
    return true
end

function PageBrowserWidget:onScrollPageUp()
    if self:updateFocusPage(-self.nb_grid_items, true) then
        self:update()
    end
    return true
end

function PageBrowserWidget:onScrollPageDown()
    if self:updateFocusPage(self.nb_grid_items, true) then
        self:update()
    end
    return true
end

function PageBrowserWidget:onScrollRowUp()
    if self:updateFocusPage(-self.nb_cols, true) then
        self:update()
    end
    return true
end

function PageBrowserWidget:onScrollRowDown()
    if self:updateFocusPage(self.nb_cols, true) then
        self:update()
    end
    return true
end

function PageBrowserWidget:onSwipe(arg, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)

    if direction == "north" or direction == "south" then
        -- Swipe along the screen left edge: increase/decrease nb of thumbnail rows
        -- (Should this be mirrored if RTL UI? It would be consistent with how it
        -- happens in BookMapWidget - but here, having it on the left is to have it
        -- less accessible to right handed people so they can scroll up/down more
        -- easily.)
        if ges.pos.x < Screen:getWidth() * 1/8 then
            local rel = direction == "north" and 1 or -1
            if self:updateNbRows(rel, true) then
                self:updateLayout()
            end
            return true
        else
            -- As onScrollRowUp/Down()
            local rel = direction == "north" and 1 or -1
            if self:updateFocusPage(rel*self.nb_cols, true) then
                self:update()
            end
            return true
        end
    elseif direction == "west" or direction == "east" then
        if ges.pos.y < Screen:getHeight() * 1/8 then
            -- Swipe along the screen top edge: increase/decrease nb of thumbnail cols
            local rel = direction == "west" and 1 or -1
            if self:updateNbCols(rel, true) then
                self:updateLayout()
            end
            return true
        elseif ges.pos.y > Screen:getHeight() - self.row_height then
            -- Inside BookMapRow at bottom: scroll by a full pages_per_row
            -- (Handling pan and hold/pan/release when started on view finder
            -- would be nice, as it might be an intuitive naive action on
            -- this area... but well...)
            local rel = direction == "west" and 1 or -1
            if self:updateFocusPage(rel*self.pages_per_row, true) then
                self:update()
            end
            return true
        else
            -- As onScrollPageUp/Down()
            local rel = direction == "west" and 1 or -1
            if self:updateFocusPage(rel*self.nb_grid_items, true) then
                self:update()
            end
            return true
        end
    else
        -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function PageBrowserWidget:onPinch(arg, ges)
    if ges.direction == "horizontal" then
        if self:updateNbCols(1, true) then
            self:updateLayout()
        end
    elseif ges.direction == "vertical" then
        if self:updateNbRows(1, true) then
            self:updateLayout()
        end
    elseif ges.direction == "diagonal" then
        local updated = self:updateNbCols(1, true)
        updated = self:updateNbRows(1, true) or updated
        if updated then
            self:updateLayout()
        end
    end
    return true
end

function PageBrowserWidget:onSpread(arg, ges)
    if ges.direction == "horizontal" then
        if self:updateNbCols(-1, true) then
            self:updateLayout()
        end
    elseif ges.direction == "vertical" then
        if self:updateNbRows(-1, true) then
            self:updateLayout()
        end
    elseif ges.direction == "diagonal" then
        local updated = self:updateNbCols(-1, true)
        updated = self:updateNbRows(-1, true) or updated
        if updated then
            self:updateLayout()
        end
    end
    return true
end

function PageBrowserWidget:onMultiSwipe(arg, ges)
    -- All swipes gestures are used for navigation.
    -- Allow for quick closing with any multiswipe.
    self:onClose()
    return true
end

function PageBrowserWidget:onTap(arg, ges)
    -- If tap in the bottom BookMapRow, put page at tap position
    -- as focus page, so it goes into our viewfinder
    if ges.pos.y > Screen:getHeight() - self.row_height then
        local page = self.row[1]:getPageAtX(ges.pos.x)
        if page then
            -- Have it in the middle of viewfinder, and not where
            -- the self.focus_page_shift would put it
            page = page - math.floor(self.nb_grid_items/2) + self.focus_page_shift
            if self:updateFocusPage(page, false) then
                self:update()
            end
        end
        return true
    end
    -- Tap on title: do nothing
    if ges.pos.y < self.title_bar_h then
        return true
    end
    -- If tap on a thumbnail, close widget and go to that page
    for idx=1, self.nb_grid_items do
        if ges.pos:intersectWith(self.grid[idx].dimen) then
            local page = self.grid[idx].page_idx
            if page and self.grid[idx][1][1].is_page_thumbnail then
                -- Only allow tap on fully displayed thumbnails.
                -- Also, a thumbnail might be smaller than the original grid
                -- item dimension. Be sure the tap is on it (otherwise, it's
                -- a tap in the inter thumbnail margin, that we'd rather not
                -- handle)
                local thumb_frame = self.grid[idx][1][1]
                if ges.pos:intersectWith(thumb_frame.dimen) then
                    -- On PDF documents, jumping to a page may block for a few
                    -- seconds while the page is rendered. So, make the border
                    -- bigger so the user knows his tap is being processed.
                    local orig_bordersize = thumb_frame.bordersize
                    thumb_frame.bordersize = Size.border.thick * 2
                    local b_inc = thumb_frame.bordersize - orig_bordersize
                    UIManager:widgetRepaint(thumb_frame, thumb_frame.dimen.x-b_inc, thumb_frame.dimen.y-b_inc)
                    Screen:refreshFast(thumb_frame.dimen.x, thumb_frame.dimen.y, thumb_frame.dimen.w, thumb_frame.dimen.h)
                        -- (refresh "fast" will make gray drawn black and may make the
                        -- thumbnail a little uglier - but this enhances the effect
                        -- of "being processed"!)
                    -- Close the BookMapWidget that launched this PageBrowser
                    -- and all their ancestors up to Reader
                    self:onClose(true)
                    self.ui.link:addCurrentLocationToStack()
                    self.ui:handleEvent(Event:new("GotoPage", page))
                        -- Note: with ReaderPaging, if we tap on the thumbnail for the current
                        -- page, nothing would be refreshed. Our :onClose(true) will have the
                        -- last ancestor issue a full refresh that will ensure it is painted.
                    return true
                end
            end
            break
        end
    end
    -- If tap on a blank area, handle as prev/next page, so people
    -- not friend with swipe can still move around
    if BD.flipIfMirroredUILayout(ges.pos.x < Screen:getWidth()/2) then
        self:onScrollPageUp()
    else
        self:onScrollPageDown()
    end
    return true
end

function PageBrowserWidget:onHold(arg, ges)
    -- If hold in the bottom BookMapRow, open a new BookMapWidget
    -- and focus on this page. We'll show a rounded square below
    -- our current focus_page to help locating where we were (it's
    -- quite more complicated to draw a rounded rectangle around
    -- multiple pages to figure our view finder, as these pages
    -- may be splitted onto multiple BookMapRows...)
    if ges.pos.y > Screen:getHeight() - self.row_height then
        local page = self.row[1]:getPageAtX(ges.pos.x)
        if page then
            local extra_symbols_pages = {}
            extra_symbols_pages[self.focus_page] = 0x25A2 -- white square with rounder corners
            UIManager:show(BookMapWidget:new{
                launcher = self,
                ui = self.ui,
                focus_page = page,
                extra_symbols_pages = extra_symbols_pages,
            })
        end
        return true
    end
    return true
end

return PageBrowserWidget
