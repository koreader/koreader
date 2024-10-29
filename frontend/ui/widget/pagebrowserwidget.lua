local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
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
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local logger = require("logger")
local util = require("util")
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
            Pan = { -- (for mousewheel scrolling support)
                GestureRange:new{
                    ges = "pan",
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
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        left_icon_hold_callback = function()
            -- Cycle nb of toc span levels shown in bottom row
            if self:updateNbTocSpans(-1, true, true) then
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

    -- For page numbers alongside thumbnails, use the same font size
    -- we use for them in the ribbon
    self.page_num_font_face = Font:getFace("infofont", 10)
    if not self.page_num_width then
        -- We'll be displaying the number vertically, so get the width we'd need
        -- to display some wide single char (this will influence side and inter
        -- thumbnails margins).
        test_w = TextWidget:new{
            text = "W",
            face = self.page_num_font_face,
        }
        self.page_num_width = test_w:getWidth()
        test_w:free()
    end

    self.min_nb_rows = 1
    self.max_nb_rows = 6
    self.min_nb_cols = 1
    self.max_nb_cols = 6

    -- Get some info that shouldn't change across calls to update() and updateLayout()
    self.nb_pages = self.ui.document:getPageCount()
    self.cur_page = self.ui.toc.pageno
    -- Get read page from the statistics plugin if enabled
    self.read_pages = self.ui.statistics and self.ui.statistics:getCurrentBookReadPages()
    self.current_session_duration = self.ui.statistics and (os.time() - self.ui.statistics.start_current_period)
    -- Reference page numbers, for first row page display
    self.page_labels = nil
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        self.page_labels = self.ui.document:getPageMap()
    end
    -- Location stack
    self.previous_locations = self.ui.link:getPreviousLocationPages()

    -- Update stuff that may be updated by the user while in PageBrowser
    self:updateEditableStuff()
    self.editable_stuff_edited = false -- reset this

    -- Compute settings-dependant sizes and options, and build the inner widgets
    -- (this will call self:update())
    self:updateLayout()
end

function PageBrowserWidget:updateEditableStuff(update_view)
    -- Toc, bookmarks and hidden flows may be edited
    -- Note: we update everything to keep things simpler, but we could provide flags to
    -- let us know what stuff has been updated and only do their related work.
    self.ui.toc:fillToc()
    self.max_toc_depth = self.ui.toc.toc_depth
    -- Get bookmarks and highlights from ReaderBookmark
    self.bookmarked_pages = self.ui.bookmark:getBookmarkedPages()
    -- Hidden flows, for first page display, and to draw them gray
    self.hidden_flows = nil
    self.has_hidden_flows = self.ui.document:hasHiddenFlows()
    if self.has_hidden_flows and #self.ui.document.flows > 0 then
        self.hidden_flows = {}
        -- Pick into credocument internal data to build a table
        -- of {first_page_number, last_page_number) for each flow
        for flow, tab in ipairs(self.ui.document.flows) do
            table.insert(self.hidden_flows, { tab[1], tab[1]+tab[2]-1 })
        end
    end
    -- Keep a flag so we can propagate the fact that editable stuff
    -- has been updated to our parent/launcher when we will close,
    -- so they can update themselves too.
    self.editable_stuff_edited = true
    if update_view then
        self:updateLayout()
    end
end

function PageBrowserWidget:updateLayout()
    -- We start with showing all toc levels (we could use book_map_toc_depth,
    -- but we might want to have it different here).
    self.nb_toc_spans = self.ui.doc_settings:readSetting("page_browser_toc_depth") or self.max_toc_depth
    if self.ui.handmade:isHandmadeTocEnabled() then
        -- We can switch from a custom TOC (max depth of 1) to the regular TOC
        -- (larger depth possible), so we'd rather not replace with 1 the depth
        -- set and saved for a regular TOC. So, use a dedicated setting for each.
        self.nb_toc_spans = self.ui.doc_settings:readSetting("page_browser_toc_depth_handmade_toc") or self.max_toc_depth
    end

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
    -- Have its top border noticeable above the BookMapRow top border
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

    self.thumbnails_pagenums = self.ui.doc_settings:readSetting("page_browser_thumbnails_pagenums")
                               or G_reader_settings:readSetting("page_browser_thumbnails_pagenums") or 2
    -- Set our items target size
    -- Borders may eat into the margin, and the horizontal margin should be able to contain the page number
    local grid_item_default_margin = Screen:scaleBySize(10)
    local grid_item_pagenum_margin = self.page_num_width + Size.padding.small + Size.border.thick + Size.border.thin
    local grid_item_inner_h_margin = grid_item_default_margin
    local grid_item_outer_h_margin = grid_item_default_margin
    if self.thumbnails_pagenums == 1 then
        grid_item_outer_h_margin = grid_item_pagenum_margin
    elseif self.thumbnails_pagenums == 2 then
        grid_item_outer_h_margin = grid_item_pagenum_margin
        grid_item_inner_h_margin = grid_item_pagenum_margin
    end
    self.grid_item_height = math.floor((self.grid_height - self.nb_rows*grid_item_default_margin) / self.nb_rows) -- no need for top margin, title bottom padding is enough
    self.grid_item_width = math.floor((self.grid_width - 2*grid_item_outer_h_margin - (self.nb_cols-1)*grid_item_inner_h_margin) / self.nb_cols)
    self.grid_item_dimen = Geom:new{
        w = self.grid_item_width,
        h = self.grid_item_height
    }
    -- Put any pixel left ouf by the flooring into grid_item_outer_h_margin, so everything looks balanced horizontally
    grid_item_outer_h_margin = math.floor((self.grid_width - self.nb_cols * self.grid_item_width - (self.nb_cols-1)*grid_item_inner_h_margin) / 2)

    self.grid:clear()

    for idx = 1, self.nb_grid_items do
        local row = math.floor((idx-1)/self.nb_cols) -- start from 0
        local col = (idx-1) % self.nb_cols
        local show_pagenum -- no page number shown on the left side of a thumbnail, unless:
        if self.thumbnails_pagenums == 1 then -- only for the first thumbnail of each row
            show_pagenum = col == 0
        elseif self.thumbnails_pagenums == 2 then -- for all thumnbnails
            show_pagenum = true
        end
        if BD.mirroredUILayout() then
            col = self.nb_cols - col - 1
        end
        local offset_x = grid_item_outer_h_margin + grid_item_inner_h_margin*col + self.grid_item_width*col
        local offset_y = grid_item_default_margin*row + self.grid_item_height*row -- no need for 1st margin
        local grid_item = CenterContainer:new{
            dimen = self.grid_item_dimen:copy(),
        }
        table.insert(self.grid, FrameContainer:new{
            show_pagenum = show_pagenum,
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

    for i=#self.grid, 1, -1 do
        if self.grid[i].is_page_num_widget then
            -- Remove page_num_widgets, as we'll be recreating them
            local widget = table.remove(self.grid, i)
            widget:free()
        end
    end

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

    -- Extended separators below the baseline for pages starting thumbnail rows
    -- No longer needed, as we now use view_finder_row_lines that will extend
    -- a bit below the baseline.
    --[[
    local extended_sep_pages = {}
    for p=grid_page_start+self.nb_cols, grid_page_end, self.nb_cols do
        extended_sep_pages[p] = BookMapRow.extended_marker.LARGE
    end
    ]]--

    -- Show the page number or label at the bottom page slot every N slots, with N
    -- the nb of thumbnails so we get at least one page label in our viewport.
    local page_texts_cycle = math.min(self.nb_grid_items, 10) -- but max 10
    local next_p = p_start
    local cur_page_label_idx = 1
    local page_texts = {} -- to be provided to the bottom ribbon BookMapRow
    self.pagenum_page_texts = {} -- to be displayed alongside thumbnails
    for p=p_start, p_end do
        -- This may be expensive, so compute only the ones we need for display
        local show_at_bottom
        if p >= next_p then
            -- Only show a page text if there is no indicator on that slot
            if p ~= self.cur_page and not self.bookmarked_pages[p] and not self.previous_locations[p] then
                show_at_bottom = true
            end
        end
        local show_near_thumbnail
        if p >= grid_page_start and p <= grid_page_end then
            show_near_thumbnail = self.grid[p - grid_page_start + 1].show_pagenum
        end
        if show_at_bottom or show_near_thumbnail then
            local page_text, thumbnail_page_text
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
                elseif show_near_thumbnail then
                    -- When reference pages may span multiple screen pages, the above may not get
                    -- a page_text for some pages, which is fine for the bottom ribbon: it will
                    -- display it for the next slot where a new reference page starts.
                    -- But for thumbnails, we want to show some page number text, so fetch
                    -- the previous one (that started on a previous screen page).
                    thumbnail_page_text = self.ui.pagemap:cleanPageLabel(self.page_labels[cur_page_label_idx].label)
                end
            elseif self.has_hidden_flows then
                local flow = self.ui.document:getPageFlow(p)
                if flow == 0 then
                    page_text = tostring(self.ui.document:getPageNumberInFlow(p))
                else
                    local page_number_in_flow = self.ui.document:getPageNumberInFlow(p)
                    local page_flow = self.ui.document:getPageFlow(p)
                    page_text = string.format("[%d]%d", page_number_in_flow, page_flow)
                    -- Use something that will feel alike brackets when vertically
                    -- (Harfbuzz will properly mirror these if the UI is RTL)
                    thumbnail_page_text = string.format("\u{2E1D}%d\u{2E0C}%d", page_number_in_flow, page_flow)
                end
            else
                page_text = tostring(p)
            end
            if page_text and show_at_bottom then
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
            if show_near_thumbnail then
                -- Dedicated thumbnail_page_text, or the default one
                self.pagenum_page_texts[p] = thumbnail_page_text or page_text
            end
        end
    end

    -- We need to rebuilt the full set of toc spans that will be shown
    -- Similar (but simplified) to what is done in BookMapWidget.
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
        if item.depth <= self.nb_toc_spans then -- ignore lower levels we won't show
            -- An item at level N closes all previous items at level >= N
            for lvl = item.depth, self.nb_toc_spans do
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
                seq_in_level = item.seq_in_level,
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
        alt_theme = G_reader_settings:isTrue("book_map_alt_theme"),
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
        -- extended_sep_pages = extended_sep_pages,
    }
    self.row[1] = row

    local bd_mirrored_left_spacing = 0
    if BD.mirroredUILayout() and blank_page_slots_after_end > 0 then
        bd_mirrored_left_spacing = BookMapRow:getLeftSpacingForNumberOfPageSlots(blank_page_slots_after_end,
                                                                        self.pages_per_row, self.row_width)
                                   + row.pages_frame_border -- (needed, but not sure why it is needed...)
    end

    if BD.mirroredUILayout() then
        self.view_finder_x = row:getPageX(grid_page_end)
        self.view_finder_w = row:getPageX(grid_page_start, true) - self.view_finder_x
        self.view_finder_x = self.view_finder_x + bd_mirrored_left_spacing
        -- No need to adjust anything, unlike when not mirrored
    else
        self.view_finder_x = row:getPageX(grid_page_start)
        self.view_finder_w = row:getPageX(grid_page_end, true) - self.view_finder_x
        self.view_finder_x = self.view_finder_x + left_spacing
        -- we requested with_page_sep, so leave these blank spaces between page slots outside the viewfinder
        self.view_finder_x = self.view_finder_x + 1
        self.view_finder_w = self.view_finder_w - 1
    end

    -- Have a thin gray vertical line in the view finder to separate each thumbnail row
    self.view_finder_row_lines = {}
    for i=1, self.nb_rows - 1 do
        local x
        if BD.mirroredUILayout() then
            x = row:getPageX(grid_page_end - i*self.nb_cols) + bd_mirrored_left_spacing - 1
        else
            x = row:getPageX(grid_page_start + i*self.nb_cols) + left_spacing
        end
        local h = self.row_height - self.span_height -- down to baseline
        h = h + math.ceil(self.span_height * 1/2) -- have it extend out below the baseline
        table.insert(self.view_finder_row_lines, {
            x = x,
            y = self.view_finder_y,
            w = 1, -- our with_page_sep makes a 1px space: let's be there
            h = h,
        })
    end

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
    if G_reader_settings:isTrue("page_browser_preload_thumbnails") then
        self:preloadNextPrevScreenThumbnails()
    end
end

function PageBrowserWidget:paintTo(bb, x, y)
    -- Paint regular sub widgets the classic way
    InputContainer.paintTo(self, bb, x, y)

    for _, r in ipairs(self.view_finder_row_lines) do
        -- If we would want them fully solid/opaque:
        -- bb:paintRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_GRAY_5)
        -- But we prefer them translucent, so we can draw them over chapter spans
        -- without getting bothered too much by them (alpha=0.3 feels fine).
        -- Only hatchRect() currently supports painting with alpha,
        -- so use it to fill our rectangle by using a larger stripe_width
        -- so it is fully filled.
        bb:hatchRect(r.x, r.y, r.w, r.h, r.h, Blitbuffer.COLOR_BLACK, 0.3)
    end

    -- If we would prefer to see the BookMapRow top border always take the full width
    -- so it acts as a separator from the thumbnail grid, add this:
    -- bb:paintRect(0, self.dimen.h - self.row_height, self.dimen.w, BookMapRow.pages_frame_border, Blitbuffer.COLOR_BLACK)
    -- And explicitly paint our viewfinder over the BookMapRow
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
            original_in_nightmode = false, -- we want our page thumbnail nightmode'd when in nighmtmode
        },
    }
    item_container[1] = thumb_frame
        -- thumb_frame will overflow its CenterContainer because of the added borders,
        -- but CenterContainer handles that well. We will refresh the outer dimensions.

    if self.has_hidden_flows and self.ui.document:getPageFlow(page) ~= 0 then
        -- We want to distinguish pages part of hidden flow.
        -- Using a uniform gray background may not be enough on scanned PDF
        -- gray pages non-dewatermarked, so we use diagonal gray stripes.
        -- We use a gray background similar to how it appears on hidden flows
        -- in the BookMapRow, where they are COLOR_LIGHT_GRAY (0xCC).
        -- To achieve the same color, we can use COLOR_BLACK with alpha = 0.2.
        thumb_frame.stripe_width = math.ceil(math.min(self.grid_item_width, self.grid_item_height) / 2)
        thumb_frame.stripe_color = Blitbuffer.COLOR_BLACK
        thumb_frame.stripe_over = true
        thumb_frame.stripe_over_alpha = 0.2
    end

    local page_num_widget
    if item_frame.show_pagenum and self.pagenum_page_texts[page] then
        local page_text = table.concat(util.splitToChars(self.pagenum_page_texts[page]), "\n")
        page_num_widget = TextBoxWidget:new{
            text = page_text,
            width = self.page_num_width,
            face = self.page_num_font_face,
            line_height = 0, -- no additional line height
            alignment = BD.mirroredUILayout() and "left" or "right",
            alignment_strict = true,
            is_page_num_widget = true, -- so we can clear them in :update()
        }
        -- Only now that we know the thumbnail size, we can position this vertical
        -- page number widget alongside and at the top of the thumbnail left edge
        local thumb_frame_dimen = thumb_frame:getSize()
        local dw = self.grid_item_width - thumb_frame_dimen.w
        local dh = self.grid_item_height - thumb_frame_dimen.h
        local dx = math.floor(dw/2)
        local dy = math.floor(dh/2)
        local offset_y = item_frame.overlap_offset[2] + dy
        local offset_x
        if BD.mirroredUILayout() then
            offset_x = item_frame.overlap_offset[1] + self.grid_item_width - dx + Size.padding.small
        else
            offset_x = item_frame.overlap_offset[1] + dx - page_num_widget:getSize().w - Size.padding.small
        end
        page_num_widget.overlap_offset = {offset_x, offset_y}
        table.insert(self.grid, page_num_widget)
    end

    if do_refresh then
        if self.wait_for_refresh_on_show_tile then
            self.wait_for_refresh_on_show_tile = nil
            -- Be sure the main view initial refresh has ended before refreshing
            -- this first thumbnail, to avoid papercut refresh glitches.
            UIManager:waitForVSync()
        end
        UIManager:setDirty(self, function()
            if not thumb_frame.dimen then
                -- No dimen if not painted, which may happen if we get covered
                -- by a BookMap launched from the ribbon: don't refresh.
                return
            end
            if page_num_widget then
                return "ui", thumb_frame.dimen:combine(page_num_widget.dimen)
            end
            return "ui", thumb_frame.dimen
        end)
    end
end

function PageBrowserWidget:preloadThumbnail(page, dbg_msg)
    if page < 1 or page > self.nb_pages then
        return
    end
    logger.dbg(dbg_msg, page)
    -- We provide a dummy callback as we don't care about the tile
    self.ui.thumbnail:getPageThumbnail(page, self.grid_item_width, self.grid_item_height, self.requests_batch_id, function() end)
end

function PageBrowserWidget:preloadNextPrevScreenThumbnails()
    -- We're here with the page painted - and possibly some thumbnails
    -- not yet there and being generated and going to be updated.
    -- self.ui.thumbnail takes care of serializing tile requests, and
    -- cancelling scheduled ones when new requests come.
    -- So, we can just launch many getPageThumbnail() for the next and
    -- previous PageBrowser views (which will be nearly no-op if the
    -- thumbnail is already cached).
    -- We first preload the next and prev rows, before preloading the
    -- remaining thumbnails of the next and prev pages - so users
    -- browsing per-row can have them before.

    -- Pre-generate the thumbnails for the next row
    local next_grid_page_start = self.focus_page - self.focus_page_shift + self.nb_grid_items
    for idx=1, self.nb_cols do
        self:preloadThumbnail(next_grid_page_start + idx - 1, "preload next line")
    end
    -- Pre-generate the thumbnails for the prev row
    local prev_line_page_start = self.focus_page - self.focus_page_shift - self.nb_cols
    for idx=1, self.nb_cols do
        self:preloadThumbnail(prev_line_page_start + idx - 1, "preload prev line")
    end
    -- Pre-generate the thumbnails for the next page (minus its top row, already done)
    for idx=self.nb_cols+1, self.nb_grid_items do
        self:preloadThumbnail(next_grid_page_start + idx - 1, "preload next page remainings")
    end
    -- Pre-generate the thumbnails for the prev page (minus its bottom row, already done)
    local prev_grid_page_start = self.focus_page - self.focus_page_shift - self.nb_grid_items
    for idx=self.nb_grid_items - self.nb_cols, 1, -1 do
        self:preloadThumbnail(prev_grid_page_start + idx - 1, "preload prev page remainings")
    end
end

function PageBrowserWidget:showMenu()
    local button_dialog
    -- Width of our -/+ buttons, so it looks fine with Button's default font size of 20
    local plus_minus_width = Screen:scaleBySize(60)
    local buttons = {
        {{
            text = _("About page browser"),
            align = "left",
            callback = function()
                self:showAbout()
            end,
        }},
        {{
            text = _("Available gestures"),
            align = "left",
            callback = function()
                self:showGestures()
            end,
        }},
        {{
            text = _("Preload next/prev thumbnails"),
            checked_func = function()
                return G_reader_settings:isTrue("page_browser_preload_thumbnails")
            end,
            align = "left",
            callback = function()
                G_reader_settings:flipTrue("page_browser_preload_thumbnails")
                if G_reader_settings:isTrue("page_browser_preload_thumbnails") then
                    self:preloadNextPrevScreenThumbnails()
                end
            end,
        }},
        {
            {
                text = _("Thumbnail columns"),
                callback = function() end,
                align = "left",
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.nb_cols > self.min_nb_cols end,
                callback = function()
                    if self:updateNbCols(-1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.nb_cols < self.max_nb_cols end,
                callback = function()
                    if self:updateNbCols(1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            }
        },
        {
            {
                text = _("Thumbnail rows"),
                callback = function() end,
                align = "left",
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.nb_rows > self.min_nb_rows end,
                callback = function()
                    if self:updateNbRows(-1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.nb_rows < self.max_nb_rows end,
                callback = function()
                    if self:updateNbRows(1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            }
        },
        {
            {
                text = _("Thumbnail page numbers"),
                callback = function() end,
                align = "left",
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.thumbnails_pagenums > 0 end,
                callback = function()
                    if self:updateThumbnailPageNumsDisplayType(-1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.thumbnails_pagenums < 2 end,
                callback = function()
                    if self:updateThumbnailPageNumsDisplayType(1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            }
        },
        {
            {
                text = _("Chapters in bottom ribbon"),
                callback = function() end,
                align = "left",
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.nb_toc_spans > 0 end,
                callback = function()
                    if self:updateNbTocSpans(-1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.nb_toc_spans < self.max_toc_depth end,
                callback = function()
                    if self:updateNbTocSpans(1, true) then
                        self:updateLayout()
                    end
                end,
                width = plus_minus_width,
            }
        },
    }
    button_dialog = ButtonDialog:new{
        -- width = math.floor(Screen:getWidth() / 2),
        width = math.floor(Screen:getWidth() * 0.9), -- max width, will get smaller
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(button_dialog)
end

function PageBrowserWidget:showAbout()
    UIManager:show(InfoMessage:new{
        text = _([[
Page browser shows thumbnails of pages.

The bottom ribbon displays an extract of the book map around the pages displayed:

If statistics are enabled, black bars are shown for already read pages (gray for pages read in the current reading session). Their heights vary depending on the time spent reading the page.
Chapters are shown above the pages they encompass.
Under the pages, these indicators may be shown:
▲ current page
❶ ❷ … previous locations
▒ highlighted text
 highlighted text with notes
 bookmarked page]]),
    })
end

function PageBrowserWidget:showGestures()
    UIManager:show(InfoMessage:new{
        text = _([[
Swipe along the top or left screen edge to change the number of columns or rows of thumbnails.

Swipe vertically to move one row, horizontally to move one screen.

Swipe horizontally in the bottom ribbon to move by the full stripe.

Tap in the bottom ribbon on a page to focus thumbnails on this page.

Tap on a thumbnail to read this page.

Long-press on ≡ to decrease or reset the number of chapter levels shown in the bottom ribbon.

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
            if self.editable_stuff_edited then
                self.launcher:updateEditableStuff(true)
            end
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
        -- (delay it a bit so this pause is less noticeable)
        UIManager:scheduleIn(0.5, function()
            collectgarbage()
            collectgarbage()
        end)
        -- As we're getting back to Reader, update the footer and the dogear state
        -- (we may have toggled bookmark for current page) and do a full flashing
        -- refresh to remove any ghost trace of thumbnails or black page slots
        UIManager:broadcastEvent(Event:new("UpdateFooter"))
        self.ui.bookmark:onPageUpdate(self.ui:getCurrentPage())
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
    if self.ui.handmade:isHandmadeTocEnabled() then
        self.ui.doc_settings:saveSetting("page_browser_toc_depth_handmade_toc", self.nb_toc_spans)
    else
        self.ui.doc_settings:saveSetting("page_browser_toc_depth", self.nb_toc_spans)
    end
    self.ui.doc_settings:saveSetting("page_browser_nb_rows", self.nb_rows)
    self.ui.doc_settings:saveSetting("page_browser_nb_cols", self.nb_cols)
    self.ui.doc_settings:saveSetting("page_browser_thumbnails_pagenums", self.thumbnails_pagenums)
    -- We also save nb_rows/nb_cols as global settings, so they will apply on other books
    -- where they were not already set
    G_reader_settings:saveSetting("page_browser_nb_rows", self.nb_rows)
    G_reader_settings:saveSetting("page_browser_nb_cols", self.nb_cols)
    G_reader_settings:saveSetting("page_browser_thumbnails_pagenums", self.thumbnails_pagenums)
end

function PageBrowserWidget:updateNbTocSpans(value, relative, rollover)
    local new_nb_toc_spans
    if relative then
        new_nb_toc_spans = self.nb_toc_spans + value
    else
        new_nb_toc_spans = value
    end
    if new_nb_toc_spans < 0 then
        if rollover then
            new_nb_toc_spans = self.max_toc_depth
        else
            new_nb_toc_spans = 0
        end
    end
    if new_nb_toc_spans > self.max_toc_depth then
        if rollover then
            new_nb_toc_spans = 0
        else
            new_nb_toc_spans = self.max_toc_depth
        end
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

function PageBrowserWidget:updateThumbnailPageNumsDisplayType(value, relative)
    local new_thumbnails_pagenums
    if relative then
        new_thumbnails_pagenums = self.thumbnails_pagenums + value
    else
        new_thumbnails_pagenums = value
    end
    if new_thumbnails_pagenums < 0 then
        new_thumbnails_pagenums = 0
    end
    if new_thumbnails_pagenums > 2 then
        new_thumbnails_pagenums = 2
    end
    if new_thumbnails_pagenums == self.thumbnails_pagenums then
        return false
    end
    self.thumbnails_pagenums = new_thumbnails_pagenums
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
    -- Handle scroll by row or page a bit differently, so we dont constrain and
    -- readjust the focus page: when later scrolling in the other direction,
    -- we'll find exactly the view as it was (this means that we allow a single
    -- thumbnail in the view, but it's less confusing this way).
    if relative and (value == -self.nb_grid_items or value == -self.nb_cols) then
        -- Going back one page or row. If first thumbnail is page 1 (or less if
        -- blank), don't move. Otherwise, go ahead without any check as we'll
        -- have something to display.
        if self.focus_page - self.focus_page_shift <= 1 then
            return
        end
    elseif relative and (value == self.nb_grid_items or value == self.nb_cols) then
        -- Going forward one page or row. If last thumbnail is last page (or more if
        -- blank), don't move. Otherwise, go ahead without any check as we'll
        -- have something to display.
        if self.focus_page - self.focus_page_shift + self.nb_grid_items - 1 >= self.nb_pages then
            return
        end
    else
        if new_focus_page < 1 then
            new_focus_page = 1
        end
        if new_focus_page > self.nb_pages then
            new_focus_page = self.nb_pages
        end
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

function PageBrowserWidget:onPan(arg, ges)
    if ges.mousewheel_direction then
        if ges.direction == "north" then
            self:onScrollRowDown()
        elseif ges.direction == "south" then
            self:onScrollRowUp()
        end
    end
    return true
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
            if page then
                if self.grid[idx][1][1].is_page_thumbnail then
                    -- If the thumbnail for this page is displayed, show some
                    -- visual feedback for the tap (on PDF documents, jumping
                    -- to a page may block for a few seconds while the page
                    -- is rendered): make the border bigger so the user knows
                    -- his tap is being processed).
                    local thumb_frame = self.grid[idx][1][1]
                    local orig_bordersize = thumb_frame.bordersize
                    thumb_frame.bordersize = Size.border.thick * 2
                    local b_inc = thumb_frame.bordersize - orig_bordersize
                    thumb_frame.dimen.x = thumb_frame.dimen.x - b_inc
                    thumb_frame.dimen.y = thumb_frame.dimen.y - b_inc
                    thumb_frame.dimen.w = thumb_frame.dimen.w + 2*b_inc
                    thumb_frame.dimen.h = thumb_frame.dimen.h + 2*b_inc
                    UIManager:widgetRepaint(thumb_frame, thumb_frame.dimen.x, thumb_frame.dimen.y)
                    Screen:refreshFast(thumb_frame.dimen.x, thumb_frame.dimen.y, thumb_frame.dimen.w, thumb_frame.dimen.h)
                        -- (refresh "fast" will make gray drawn black and may make the
                        -- thumbnail a little uglier - but this enhances the effect
                        -- of "being processed"!)
                end
                -- (If no thumbnail yet displayed, go on directly: the user
                -- must be in a hurry if he can't wait for the thumbnail!)
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
    -- may be split onto multiple BookMapRows...)
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
    -- Hold on title: do nothing
    if ges.pos.y < self.title_bar_h then
        return true
    end
    -- If hold on a thumbnail, toggle bookmark on that page
    for idx=1, self.nb_grid_items do
        if ges.pos:intersectWith(self.grid[idx].dimen) then
            local page = self.grid[idx].page_idx
            if page then
                -- We allow that even if the thumbnail is not yet displayed.
                -- Note: there could be some race condition when toggling
                -- bookmark for a page while its thumbnail is being generated:
                -- we may get (and cache) a thumbnail showing the wrong
                -- bookmark state...
                self:onThumbnailHold(page, ges)
                return true
            end
            break
        end
    end
    return true
end

function PageBrowserWidget:onThumbnailHold(page, ges)
    local handmade_toc_edit_enabled = self.ui.handmade:isHandmadeTocEnabled() and self.ui.handmade:isHandmadeTocEditEnabled()
    local handmade_hidden_flows_edit_enabled = self.ui.handmade:isHandmadeHiddenFlowsEnabled() and self.ui.handmade:isHandmadeHiddenFlowsEditEnabled()
    if not handmade_toc_edit_enabled and not handmade_hidden_flows_edit_enabled then
        -- No other feature enabled: we can toggle bookmark directly
        self.ui.bookmark:toggleBookmark(page)
        self:updateEditableStuff(true)
        return
    end
    local button_dialog
    local buttons = {
        {{
            text = _("Toggle page bookmark"),
            align = "left",
            callback = function()
                UIManager:close(button_dialog)
                self.ui.bookmark:toggleBookmark(page)
                self:updateEditableStuff(true)
            end,
        }},
    }
    if handmade_toc_edit_enabled then
        local has_toc_item = self.ui.handmade:hasPageTocItem(page)
        table.insert(buttons, {{
            -- Note: we may have multiple chapters on a same page: we will show the first, which
            -- would need to be removed to access the second... We may want to show as many
            -- buttons as there are chapters, with the start of the chapter title as its text.
            text = (has_toc_item and _("Edit or remove TOC chapter")
                                  or _("Start TOC chapter here")) .. " " .. self.ui.handmade.custom_toc_symbol,
            align = "left",
            callback = function()
                UIManager:close(button_dialog)
                self.ui.handmade:addOrEditPageTocItem(page, function()
                    self:updateEditableStuff(true)
                end)
            end,
        }})
    end
    if handmade_hidden_flows_edit_enabled then
        local is_in_hidden_flow = self.ui.handmade:isInHiddenFlow(page)
        table.insert(buttons, {{
            text = is_in_hidden_flow and _("Restart regular flow here")
                                      or _("Start hidden flow here"),
            align = "left",
            callback = function()
                UIManager:close(button_dialog)
                self.ui.handmade:toggleHiddenFlow(page)
                self:updateEditableStuff(true)
            end,
        }})
    end
    button_dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return ges.pos, true
        end
    }
    UIManager:show(button_dialog)
end

return PageBrowserWidget
