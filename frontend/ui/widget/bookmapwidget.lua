local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderText = require("ui/rendertext")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Input = Device.input
local Screen = Device.screen
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- BookMapRow (reused by PageBrowserWidget)
local BookMapRow = WidgetContainer:extend{
    width = nil,
    height = nil,
    pages_frame_border = Size.border.default,
    toc_span_border = Size.border.thin,
    -- pages_frame_border = 10, -- for debugging positioning
    -- toc_span_border = 5, -- for debugging positioning
    toc_items = nil, -- Arrays[levels] of arrays[items at this level to show as spans]
    -- Many other options not described here, see BookMapWidget:update()
    -- for the complete list.

    extended_marker = {
        SMALL = 1,
        MEDIUM = 2,
        LARGE = 3,
    }
}

function BookMapRow:getPageX(page, right_edge)
    local _mirroredUI = BD.mirroredUILayout()
    if right_edge then
        if (not _mirroredUI and page == self.end_page) or
               (_mirroredUI and page == self.start_page) then
            return self.pages_frame_inner_width
        else
            if _mirroredUI then
                return self:getPageX(page-1)
            else
                return self:getPageX(page+1)
            end
        end
    end
    local slot_idx
    if _mirroredUI then
        slot_idx = self.end_page - page
    else
        slot_idx = page - self.start_page
    end
    local x = slot_idx * self.page_slot_width
    x = x + math.floor(self.page_slot_extra * slot_idx / self.nb_page_slots)
    return x
end

function BookMapRow:getIndicatorXY(page, shift_down)
    local x = self:getPageX(page)
    local w = self:getPageX(page, true) - x
    x = x + math.ceil(w/2)
    local y = self.pages_frame_height + 1
    if shift_down then
        -- Shift it a bit down to keep bookmark glyph(s) readable
        y = y + math.floor(self.span_height * (1/3))
    end
    return x, y
end

function BookMapRow:getPageAtX(x, at_bounds_if_outside)
    x = x - self.pages_frame_offset_x
    if x < 0 then
        if not at_bounds_if_outside then return end
        x = 0
    end
    if x >= self.pages_frame_inner_width then
        if not at_bounds_if_outside then return end
        x = self.pages_frame_inner_width - 1
    end
    -- Reverse of the computation in :getPageX():
    local slot_idx = math.floor(x / (self.page_slot_width + self.page_slot_extra / self.nb_page_slots))
    if BD.mirroredUILayout() then
        return self.end_page - slot_idx
    else
        return self.start_page + slot_idx
    end
end

-- Helper function to be used before instantiating a BookMapRow instance,
-- to obtain the left_spacing equivalent to not showing nb_pages at start
-- of a row of pages_per_row items in a width of row_width
function BookMapRow:getLeftSpacingForNumberOfPageSlots(nb_pages, pages_per_row, row_width)
    -- Bits of the computation done in :init()
    local pages_frame_inner_width = row_width - 2*self.pages_frame_border
    local page_slot_width = math.floor(pages_frame_inner_width / pages_per_row)
    local page_slot_extra = pages_frame_inner_width - page_slot_width * pages_per_row
    -- Bits of the computation done in :getPageX()
    local x = nb_pages * page_slot_width
    x = x + math.floor(page_slot_extra * nb_pages / pages_per_row)
    return x - self.pages_frame_border
end

function BookMapRow:init()
    self.focus_layout = {}
    local _mirroredUI = BD.mirroredUILayout()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    -- Keep one span_height under baseline (frame bottom border) for indicators (current page, bookmarks)
    self.pages_frame_height = self.height - self.span_height

    self.pages_frame_offset_x = self.left_spacing + self.pages_frame_border
    self.pages_frame_width = self.width - self.left_spacing
    self.pages_frame_inner_width = self.pages_frame_width - 2*self.pages_frame_border
    self.page_slot_width = math.floor(self.pages_frame_inner_width / self.pages_per_row)
    self.page_slot_extra = self.pages_frame_inner_width - self.page_slot_width * self.pages_per_row -- will be distributed

    -- Update the widths if this row contains fewer pages
    self.nb_page_slots = self.end_page - self.start_page + 1
    if self.nb_page_slots ~= self.pages_per_row then
        self.page_slot_extra = math.floor(self.page_slot_extra * self.nb_page_slots / self.pages_per_row)
        self.pages_frame_inner_width = self.page_slot_width * self.nb_page_slots + self.page_slot_extra
        self.pages_frame_width = self.pages_frame_inner_width + 2*self.pages_frame_border
    end

    if _mirroredUI then
        self.pages_frame_offset_x = self.width - self.pages_frame_width - self.left_spacing + self.pages_frame_border
    end

    -- We draw a frame container with borders for the book content, with
    -- some space on the left for the start page number, and some space
    -- below the bottom border as spacing before the next row (spacing
    -- that we can use to show current position and hanging bookmarks
    -- and highlights symbols)
    self.pages_frame = OverlapGroup:new{
        dimen = Geom:new{
            w = self.pages_frame_width,
            h = self.pages_frame_height,
        },
        allow_mirroring = false, -- we handle mirroring ourselves below
        FrameContainer:new{
            overlap_align = _mirroredUI and "right" or "left",
            margin = 0,
            padding = 0,
            bordersize = self.pages_frame_border,
            -- color = Blitbuffer.COLOR_GRAY, -- for debugging positioning
            Widget:new{ -- empty widget to give dimensions around which to draw borders
                dimen = Geom:new{
                    w = self.pages_frame_inner_width,
                    h = self.pages_frame_height - 2*self.pages_frame_border,
                }
            }
        },
    }

    -- We won't add this margin to the FrameContainer: to be able
    -- to tweak it on some sides, we'll just tweak its overlap
    -- offsets and width to ensure the margins
    local tspan_margin = Size.margin.tiny
    local tspan_padding_h = Size.padding.tiny
    local tspan_height = self.span_height - 2 * (tspan_margin + self.toc_span_border)
    local focus_row = nil
    local focus_row_offset_y = 0
    if self.toc_items then
        for lvl, items in pairs(self.toc_items) do
            local offset_y = self.pages_frame_border + self.span_height * (lvl - 1) + tspan_margin
            local prev_p_start, same_p_start_offset_dx
            for __, item in ipairs(items) do
                local text = item.title
                local p_start, p_end = item.p_start, item.p_end
                local started_before, continues_after = item.started_before, item.continues_after
                if _mirroredUI then
                    -- Just flip these (beware below, we need to use item.p_start to get
                    -- the real start page to account in prev_p_start)
                    p_start, p_end = p_end, p_start
                    started_before, continues_after = continues_after, started_before
                end
                local offset_x = self:getPageX(p_start)
                local width = self:getPageX(p_end, true) - offset_x
                offset_x = offset_x + self.pages_frame_border
                if prev_p_start == item.p_start then
                    -- Multiple TOC items starting on the same page slot:
                    -- shift and shorten 2nd++ ones so we see a bit of
                    -- the previous overwritten span and we can know this
                    -- page slot contains multiple chapters
                    if width > same_p_start_offset_dx then
                        if not _mirroredUI then
                            offset_x = offset_x + same_p_start_offset_dx
                        end
                        width = width - same_p_start_offset_dx
                        same_p_start_offset_dx = same_p_start_offset_dx + self.toc_span_border * 2
                    end
                else
                    prev_p_start = item.p_start
                    same_p_start_offset_dx = self.toc_span_border * 2
                end
                if started_before then
                    -- No left margin, have span border overlap with outer border
                    offset_x = offset_x - self.toc_span_border
                    width = width + self.toc_span_border
                else
                    -- Add some left margin
                    offset_x = offset_x + tspan_margin
                    width = width - tspan_margin
                end
                if continues_after then
                    -- No right margin, have span border overlap with outer border
                    width = width + self.toc_span_border
                else
                    -- Add some right margin
                    width = width - tspan_margin
                end
                local text_max_width = width - 2 * (self.toc_span_border + tspan_padding_h)
                local text_widget = nil
                if text_max_width > 0 then
                    text_widget = TextWidget:new{
                        text = BD.auto(text),
                        max_width = text_max_width,
                        face = self.font_face,
                        padding = 0,
                    }
                    if text_widget:getWidth() > text_max_width then
                        -- May happen with very small max_width when smaller
                        -- than the truncation ellipsis
                        text_widget:free()
                        text_widget = nil
                    end
                end
                -- Different style depending on alt_theme
                local bgcolor = Blitbuffer.COLOR_WHITE
                if self.alt_theme then
                    if item.seq_in_level % 2 == 0 then -- alternate background color
                        bgcolor = Blitbuffer.COLOR_GRAY_E
                    else
                        bgcolor = Blitbuffer.COLOR_GRAY_B
                    end
                end
                local span_w = FrameContainer:new{
                    overlap_offset = {offset_x, offset_y},
                    margin = 0,
                    padding = 0,
                    bordersize = self.toc_span_border,
                    background = bgcolor,
                    focusable = self.enable_focus_navigation,
                    focus_border_size = self.focus_nav_border,
                    focus_inner_border = true,
                    CenterContainer:new{
                        dimen = Geom:new{
                            w = width - 2 * self.toc_span_border,
                            h = tspan_height,
                        },
                        text_widget or VerticalSpan:new{ width = 0 },
                    }
                }
                table.insert(self.pages_frame, span_w)
                if self.enable_focus_navigation then
                    if not focus_row or focus_row_offset_y ~= offset_y then
                        focus_row = {}
                        focus_row_offset_y = offset_y
                        table.insert(self.focus_layout, focus_row)
                    end
                    table.insert(focus_row, span_w)
                end
            end
        end
    end

    -- For page numbers:
    self.smaller_font_face = Font:getFace(self.font_face.orig_font, self.font_face.orig_size - 4)
    -- For current page triangle
    self.larger_font_face = Font:getFace(self.font_face.orig_font, self.font_face.orig_size + 6)

    self.hgroup = HorizontalGroup:new{
        align = "top",
    }

    if self.left_spacing > 0 then
        local spacing = Size.padding.small
        local width = self.left_spacing - spacing
        local widget = TextBoxWidget:new{
            text = self.start_page_text,
            width = width,
            face = self.smaller_font_face,
            line_height = 0, -- no additional line height
            alignment = _mirroredUI and "left" or "right",
            alignment_strict = true,
        }
        local text_height = widget:getSize().h
        -- We want the bottom digit aligned on the pages frame baseline if the number is small,
        -- but the top digit at top and overflowing down if it is tall.
        -- (We get better visual alignment by tweaking a bit line_glyph_extra_height.)
        local shift_y = self.pages_frame_height - text_height + math.ceil(widget.line_glyph_extra_height*2/3)
        if shift_y > 0 then
            widget = VerticalGroup:new{
                VerticalSpan:new{ width = shift_y },
                widget,
            }
        end
        table.insert(self.hgroup, TopContainer:new{
            dimen = Geom:new{
                w = width,
                h = self.pages_frame_height,
            },
            widget,
        })
        table.insert(self.hgroup, HorizontalSpan:new{ width = spacing })
    end
    table.insert(self.hgroup, self.pages_frame)

    -- Get hidden flows rectangle ready to be painted gray first as background
    self.background_fillers = {}
    if self.hidden_flows then
        for _, flow_edges in ipairs(self.hidden_flows) do
            local f_start, f_end = flow_edges[1], flow_edges[2]
            if f_start <= self.end_page and f_end >= self.start_page then
                local r_start = math.max(f_start, self.start_page)
                local r_end = math.min(f_end, self.end_page)
                local x, w
                if _mirroredUI then
                    x = self:getPageX(r_end)
                    w = self:getPageX(r_start, true) - x
                else
                    x = self:getPageX(r_start)
                    w = self:getPageX(r_end, true) - x
                end
                table.insert(self.background_fillers, {
                    x = x, y = 0,
                    w = w, h = self.pages_frame_height,
                    -- Different style depending on alt_theme
                    color = self.alt_theme and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_LIGHT_GRAY,
                    stripe_width = self.alt_theme and math.ceil(self.span_height / 10) or nil,
                })
            end
        end
    end

    self[1] = LeftContainer:new{ -- needed only for auto UI mirroring
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.hgroup:getSize().h,
        },
        self.hgroup,
    }

    -- Get read pages markers and other indicators ready to be drawn
    self.pages_markers = {}
    self.indicators = {}
    self.bottom_texts = {}

    -- For focus navigation (with keys), we need empty widgets over page slots,
    -- that will only get a border when focused and lose it when unfocused.
    local invisible_focusable_page_slots = {}
    if self.enable_focus_navigation then
        table.insert(self.focus_layout, invisible_focusable_page_slots)
    end

    local prev_page_was_read = true -- avoid one at start of row
    local extended_marker_h = { -- maps to extended_marker.SMALL/MEDIUM/LARGE
        math.ceil(self.span_height * 0.12),
        math.ceil(self.span_height * 0.21),
        math.ceil(self.span_height * 0.3),
    }
    local unread_marker_h = math.ceil(self.span_height * 0.05)
    local read_min_h = math.max(math.ceil(self.span_height * 0.1), unread_marker_h+Size.line.thick)
    if self.page_slot_width >= 5 * unread_marker_h then
        -- If page slots are large enough, we can make unread markers a bit taller (so they
        -- are noticeable and won't be confused with read page slots)
        unread_marker_h = unread_marker_h * 2
    end
    for page = self.start_page, self.end_page do
        if self.read_pages and self.read_pages[page] then
            local x = self:getPageX(page)
            local w = self:getPageX(page, true) - x
            local h = math.ceil(self.read_pages[page][1] * self.span_height * 0.8)
            h = math.max(h, read_min_h) -- so it's noticeable
            local y = self.pages_frame_height - self.pages_frame_border - h + 1
            if self.with_page_sep then
                -- We put the blank at the start of a page slot
                x = x + 1
                w = w - 1
                if w > 2 then
                    if page == self.end_page and not _mirroredUI then
                        w = w - 1 -- some spacing before right border (like we had at start)
                    end
                    if page == self.start_page and _mirroredUI then
                        w = w - 1
                    end
                end
            end
            local color = Blitbuffer.COLOR_BLACK
            if self.current_session_duration and self.read_pages[page][2] < self.current_session_duration then
                color = Blitbuffer.COLOR_GRAY_5
            end
            table.insert(self.pages_markers, {
                x = x, y = y,
                w = w, h = h,
                color = color,
            })
            prev_page_was_read = true
        else
            if self.with_page_sep and not prev_page_was_read then
                local w = Size.line.thin
                local x
                if _mirroredUI then
                    x = self:getPageX(page, true) - w
                else
                    x = self:getPageX(page)
                end
                local y = self.pages_frame_height - self.pages_frame_border - unread_marker_h + 1
                table.insert(self.pages_markers, {
                    x = x, y = y,
                    w = w, h = unread_marker_h,
                    color = Blitbuffer.COLOR_BLACK,
                })
            end
            prev_page_was_read = false
        end
        if self.enable_focus_navigation then
            local x
            if _mirroredUI then
                x = self:getPageX(page, true)
            else
                x = self:getPageX(page)
            end
            local w = self:getPageX(page, true) - x
            -- This + 1 and the one below for overlap_offset seem to give the right
            -- appearance (but I can't really logically make out why...)
            if self.with_page_sep then
                w = w + 1
            end
            if (not _mirroredUI and page == self.end_page) or
                   (_mirroredUI and page == self.start_page) then
                w = w - 1 -- needed visual tweak, to match appearance at start and end
            end
            local invisible_focusable_page_slot = FrameContainer:new{
                overlap_offset = {x + 1 - self.focus_nav_border, self.pages_frame_height - self.span_height},
                margin = 0,
                padding = self.focus_nav_border,
                bordersize = 0,
                focusable = true,
                focus_border_size = self.focus_nav_border,
                focus_inner_border = true,
                Widget:new{
                    dimen = Geom:new{
                        w = w,
                        h = math.floor(1.2 * self.span_height) - 2*self.focus_nav_border,
                    }
                }
            }
            table.insert(self.pages_frame, invisible_focusable_page_slot)
            table.insert(invisible_focusable_page_slots, invisible_focusable_page_slot)
            if page == self.focus_nav_page then
                invisible_focusable_page_slots.focused_widget_idx = #invisible_focusable_page_slots
            end
        end
        -- Extended separators below the baseline if requested (by PageBrowser
        -- to show the start of thumbnail rows)
        if self.extended_sep_pages and self.extended_sep_pages[page] then
            local w = Size.line.thin
            local x
            if _mirroredUI then
                x = self:getPageX(page, true) - w
                if page == self.start_page then
                    x = x + w
                end
            else
                x = self:getPageX(page)
                if page == self.start_page then
                    -- if at 0, make it prolong the left border
                    x = -self.pages_frame_border
                end
            end
            local y = self.pages_frame_height - self.pages_frame_border
            table.insert(self.pages_markers, {
                x = x, y = y,
                w = w, h = extended_marker_h[self.extended_sep_pages[page]],
                color = Blitbuffer.COLOR_BLACK,
            })
        end
        -- Add a little spike below the baseline above each page number displayed, so we
        -- can more easily associate the (possibly wider) page number to its page slot.
        if self.page_texts and self.page_texts[page] then
            local w = Screen:scaleBySize(1.5)
            local x = math.floor((self:getPageX(page) + self:getPageX(page, true) + 0.5)/2 - w/2)
            local y = self.pages_frame_height - self.pages_frame_border + 2
            table.insert(self.pages_markers, {
                x = x, y = y,
                w = w, h = w, -- square
                color = Blitbuffer.COLOR_BLACK,
            })
        end
        -- Indicator for bookmark/highlight type
        if self.bookmarked_pages[page] then
            local page_bookmark_types = self.bookmarked_pages[page]
            local x, y = self:getIndicatorXY(page)
            -- These 3 icons overlap quite ok, so no need for any shift
            if page_bookmark_types["highlight"] then
                table.insert(self.indicators, {
                    x = x, y = y,
                    c = 0x2592, -- medium shade
                })
            end
            if page_bookmark_types["note"] then
                table.insert(self.indicators, {
                    x = x, y = y,
                    c = 0xF040, -- pencil
                    rotation = -90,
                    shift_x_pct = 0.2, -- 20% looks a bit better
                    -- This glyph is a pencil pointing to the bottom left,
                    -- so we make it point to the top left and align it so
                    -- it points to the page slot it is associated with
                })
            end
            if page_bookmark_types["bookmark"] then
                table.insert(self.indicators, {
                    x = x, y = y,
                    c = 0xF097, -- empty bookmark
                })
            end
        end
        -- Indicator for pinned page
        if page == self.pinned_page then
            local x, y = self:getIndicatorXY(page, self.bookmarked_pages[page])
            table.insert(self.indicators, {
                c = 0xF435, -- pin
                rotation = -90,
                shift_x_pct = 0.2,
                x = x, y = y,
            })
        end
        -- Indicator for previous locations
        if self.previous_locations[page] and page ~= self.cur_page then
            local x, y = self:getIndicatorXY(page, self.bookmarked_pages[page] or page == self.pinned_page)
            local num = self.previous_locations[page]
            table.insert(self.indicators, {
                c = 0x2775 + (num < 10 and num or 10), -- number in solid black circle
                -- c = 0x245F + (num < 20 and num or 20), -- number in white circle
                x = x, y = y,
            })
        end
        -- Extra indicator
        if self.extra_symbols_pages and self.extra_symbols_pages[page] then
            local x, y = self:getIndicatorXY(page, self.bookmarked_pages[page] or page == self.pinned_page)
            table.insert(self.indicators, {
                c = self.extra_symbols_pages[page],
                x = x, y = y,
            })
        end
        -- Current page indicator
        if page == self.cur_page then
            local x, y = self:getIndicatorXY(page, self.bookmarked_pages[page] or page == self.pinned_page)
            table.insert(self.indicators, {
                c = 0x25B2, -- black up-pointing triangle
                x = x, y = y,
                face = self.larger_font_face,
            })
        end
        if self.page_texts and self.page_texts[page] then
            -- These have been put on pages free from any other indicator, so
            -- we can show the page number at the very bottom
            local x = self:getPageX(page)
            local w = self:getPageX(page, true) - x - Size.padding.tiny
            table.insert(self.bottom_texts, {
                text = self.page_texts[page].text,
                x = x,
                slot_width = w,
                block = self.page_texts[page].block,
                block_dx = self.page_texts[page].block_dx,
            })
        end
    end
end

function BookMapRow:paintTo(bb, x, y)
    -- Paint background fillers (which are not subwidgets) first
    for _, filler in ipairs(self.background_fillers) do
        if filler.stripe_width then
            bb:hatchRect(x + self.pages_frame_offset_x + filler.x, y + filler.y, filler.w, filler.h, filler.stripe_width, filler.color)
        else
            bb:paintRect(x + self.pages_frame_offset_x + filler.x, y + filler.y, filler.w, filler.h, filler.color)
        end
    end
    -- Paint regular sub widgets the classic way
    InputContainer.paintTo(self, bb, x, y)
    -- And explicitly paint read pages markers (which are not subwidgets)
    for _, marker in ipairs(self.pages_markers) do
        bb:paintRect(x + self.pages_frame_offset_x + marker.x, y + marker.y, marker.w, marker.h, marker.color)
    end
    -- And explicitly paint indicators (which are not subwidgets)
    for _, indicator in ipairs(self.indicators) do
        local glyph = RenderText:getGlyph(indicator.face or self.font_face, indicator.c)
        local alt_bb
        if indicator.rotation then
            alt_bb = glyph.bb:rotatedCopy(indicator.rotation)
        end
        -- Glyph's bb fit the blackbox of the glyph, so there's no cropping
        -- or complicated positioning to do
        -- By default, just center the glyph at x
        local d_x_pct = indicator.shift_x_pct or 0.5
        local d_x = math.floor(glyph.bb:getWidth() * d_x_pct)
        bb:colorblitFrom(
            alt_bb or glyph.bb,
            x + self.pages_frame_offset_x + indicator.x - d_x,
            y + indicator.y,
            0, 0,
            glyph.bb:getWidth(), glyph.bb:getHeight(),
            Blitbuffer.COLOR_BLACK)
        if alt_bb then
            alt_bb:free()
        end
    end
    -- And explicitly paint bottom texts (which are not subwidgets)
    for _, btext in ipairs(self.bottom_texts) do
        local text_w = TextWidget:new{
            text = btext.text,
            face = self.smaller_font_face,
            padding = 0,
        }
        local d_y = self.height - math.ceil(text_w:getSize().h)
        local d_x
        local text_width = text_w:getWidth()
        local d_width = btext.slot_width - text_width
        if not btext.block then
            -- no block constraint: can be centered
            d_x = math.ceil(d_width / 2)
        else
            if d_width >= 2 * btext.block_dx then
                -- small enough: can be centered
                d_x = math.ceil(d_width / 2)
            elseif btext.block == "left" then
                d_x = btext.block_dx
            else -- "right"
                d_x = d_width - btext.block_dx
            end
        end
        text_w:paintTo(bb, x + self.pages_frame_offset_x + btext.x + d_x, y + d_y)
        text_w:free()
    end
end

-- BookMapWidget: shows a map of content, including TOC, bookmarks, read pages, non-linear flows...
local BookMapWidget = FocusManager:extend{
    -- Focus page: show the BookMapRow containing this page
    -- in the middle of screen (despite its name, this has
    -- nothing to do with FocusManager and focus navigation)
    focus_page = nil,
    -- Should only be nil on the first launch via ReaderThumbnail
    launcher = nil,
    -- Extra symbols to show below pages
    extra_symbols_pages = nil,
    -- Restricted mode, as initial view (all on one screen), but allowing chapter levels changes
    overview_mode = false,

    -- Border around focused items (page slots, chapter titles) on non-touch devices
    -- (this needs to be wider than BookMapRow.toc_span_border or they won't show)
    focus_nav_border = Size.border.thick,

    -- Make this local subwidget available for reuse by PageBrowser
    BookMapRow = BookMapRow,
}

function BookMapWidget:init()
    -- On touch devices (with keys), we don't really need to navigate focus with keys,
    -- so we should avoid allocating memory to huge data structures.
    self.enable_focus_navigation = not Device:isTouchDevice() and Device:hasDPad() and Device:useDPadAsActionKeys()

    if self.ui.view:shouldInvertBiDiLayoutMirroring() then
        BD.invert()
    end

    -- Compute non-settings-dependant sizes and options
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true -- hint for UIManager:_repaint()

    self:registerKeyEvents()
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
        -- No need for any long-press handler: page slots may be small and we can't
        -- really target a precise page slot with our fat finger above it...
        -- Tap will zoom the zone in a PageBrowserWidget where things will be clearer
        -- and allow us to get where we want.
        -- (Also, handling "hold" is a bit more complicated when we have our
        -- ScrollableContainer that would also like to handle it.)
    else
        -- NT: needed for selection
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                }
            }
        }
    end

    -- No real need for any explicit edge and inter-row padding:
    -- we use the scrollbar width on both sides for balance (we may put a start
    -- page number on the left space), and each BookMapRow will have itself some
    -- blank space at bottom below page slots (where we may put hanging markers
    -- for current page and bookmark/highlights)
    self.scrollbar_width = ScrollableContainer:getScrollbarWidth()
    self.row_width = self.dimen.w - self.scrollbar_width
    self.row_left_spacing = self.scrollbar_width
    self.swipe_hint_bar_width = Screen:scaleBySize(6)

    local title = self.overview_mode and _("Book map (overview)") or _("Book map")
    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = title,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:onShowBookMapMenu() end,
        left_icon_hold_callback = not self.overview_mode and function()
            self:toggleDefaultSettings() -- toggle between user settings and default view
        end,
        close_callback = function() self:onClose() end,
        close_hold_callback = function() self:onClose(true) end,
        show_parent = self,
    }
    self.title_bar_h = self.title_bar:getHeight()
    self.crop_height = self.dimen.h - self.title_bar_h - Size.margin.small - self.swipe_hint_bar_width

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

    -- Reference font size for flat TOC items, as set (or default) in ReaderToc
    self.reader_toc_font_size = G_reader_settings:readSetting("toc_items_font_size")
            or Menu.getItemFontSize(G_reader_settings:readSetting("toc_items_per_page") or self.ui.toc.toc_items_per_page_default)

    self.ten_pages_markers = G_reader_settings:readSetting("book_map_ten_pages_markers", 0)

    -- Our container of stacked BookMapRows (and TOC titles in flat map mode)
    self.vgroup = VerticalGroup:new{
        align = "left",
    }
    -- We'll handle all events in this main BookMapWidget: none of the vgroup
    -- children have any handler. Hack into vgroup so it doesn't propagate
    -- events needlessly to its children (the slowness gets noticeable when
    -- we have many TOC items in flat map mode - the also needless :paintTo()
    -- don't seen to cause such a noticeable slowness)
    self.vgroup.propagateEvent = function() return false end

    -- Our scrollable container needs to be known as widget.cropping_widget in
    -- the widget that is passed to UIManager:show() for UIManager to ensure
    -- proper interception of inner widget self repainting/invert (mostly used
    -- when flashing for UI feedback that we want to limit to the cropped area).
    self.cropping_widget = ScrollableContainer:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.crop_height,
        },
        show_parent = self,
        ignore_events = {"swipe"},
        self.vgroup,
    }
    -- Our event handlers are similarly named as those in ScrollableContainer, so even
    -- if we add the key event to ignore_events above, registering them here with the
    -- same names means they'll still be handled by ScrollableContainer's own handlers.
    -- Therefore, we override its handlers to make them pass-through.
    self.cropping_widget.onScrollPageUp = function() return false end
    self.cropping_widget.onScrollPageDown = function() return false end

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
            self.cropping_widget,
        }
    }

    -- Note: some of these could be cached in ReaderThumbnail, and discarded/updated
    -- on some events (ie. TocUpdated, PageUpdate, AddHhighlight...)
    -- Get some info that shouldn't change across calls to update()
    self.nb_pages = self.ui.document:getPageCount()
    self.cur_page = self.ui.toc.pageno
    -- Get read page from the statistics plugin if enabled
    self.statistics_enabled = self.ui.statistics and self.ui.statistics:isEnabled()
    self.read_pages = self.ui.statistics and self.ui.statistics:getCurrentBookReadPages()
    self.current_session_duration = self.ui.statistics and (os.time() - self.ui.statistics.start_current_period)
    -- Reference page numbers, for first row page display
    self.page_labels = nil
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        self.page_labels = self.ui.document:getPageMap()
    end
    -- Location stack
    self.previous_locations = self.ui.link:getPreviousLocationPages()
    self.pinned_page = self.ui.gotopage:getPinnedPageNumber()

    -- Update stuff that may be updated by the user while in PageBrowser
    self:updateEditableStuff()
    self.editable_stuff_edited = false -- reset this

    -- Compute settings-dependant sizes and options, and build the inner widgets
    self:update()
end

function BookMapWidget:registerKeyEvents()
    if Device:hasKeys() then
        if Device:isTouchDevice() then
            -- Remove key handling by FocusManager (there is no ordering/priority
            -- handling for key_events, unlike with touch zones)
            self.key_events = {}
            self.key_events.ScrollRowUp = { { "Up" } }
            self.key_events.ScrollRowDown = { { "Down" } }
        elseif Device:hasScreenKB() or Device:hasKeyboard() then
            local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
            self.key_events.ScrollRowUp = { { modifier, "Up" } }
            self.key_events.ScrollRowDown = { { modifier, "Down" } }
            self.key_events.GoToFocusedPage = { { modifier, "Press" } }
            self.key_events.CloseAll = { { modifier, "Back" }, event = "Close", args = true }
        end
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.ShowBookMapMenu = { { "Menu" } }
        self.key_events.ScrollPageUp = { { Input.group.PgBack } }
        self.key_events.ScrollPageDown = { { Input.group.PgFwd } }
    end
end
BookMapWidget.onPhysicalKeyboardConnected = BookMapWidget.registerKeyEvents

function BookMapWidget:updateEditableStuff(update_view)
    -- Toc, bookmarks and hidden flows may be edited
    self.ui.toc:fillToc()
    self.max_toc_depth = self.ui.toc.toc_depth
    -- Get bookmarks and highlights from ReaderBookmark
    self.bookmarked_pages = self.ui.bookmark:getBookmarkedPages()
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
        self:update()
    end
end

function BookMapWidget:update()
    self.layout = {}
    self.cur_focused_widget = nil

    if not self.focus_page then -- Initial display
        -- Focus (show at the middle of screen) on the BookMapRow that contains
        -- current page
        self.focus_page = self.cur_page
    else
        -- We have a previous focus page: if we have not scrolled around, keep
        -- focusing on this one. Otherwise, use the start_page of the BookMapRow
        -- at the middle of screen as the new focus page.
        if self.initial_scroll_offset_y ~= self.cropping_widget._scroll_offset_y then
            local h = math.min(self.vgroup:getSize().h, self.crop_height)
            local row = self:getBookMapRowNearY(h/2)
            if row then
                self.focus_page = row.start_page
            end
        end
    end

    -- Reset main widgets
    self.vgroup:clear()
    self.cropping_widget:reset()

    self.alt_theme = G_reader_settings:isTrue("book_map_alt_theme")

    -- Flat book map has each TOC item on a new line, and pages graph underneath.
    -- Non-flat book map shows a grid with TOC items following each others.
    self.flat_map = self.ui.doc_settings:readSetting("book_map_flat", false)
    if self.ui.handmade:isHandmadeTocEnabled() then
        -- We can switch from a custom TOC (max depth of 1) to the regular TOC
        -- (larger depth possible), so we'd rather not replace with 1 the depth
        -- set and saved for a regular TOC. So, use a dedicated setting for each.
        self.toc_depth = self.ui.doc_settings:readSetting("book_map_toc_depth_handmade_toc") or self.max_toc_depth
    else
        self.toc_depth = self.ui.doc_settings:readSetting("book_map_toc_depth", self.max_toc_depth)
    end
    if self.overview_mode then
        -- Restricted to grid mode, fitting on the screen. Only toc depth can be adjusted.
        self.flat_map = false
        if self.ui.handmade:isHandmadeTocEnabled() then
            self.toc_depth = self.ui.doc_settings:readSetting("book_map_overview_toc_depth_handmade_toc") or self.max_toc_depth
        else
            self.toc_depth = self.ui.doc_settings:readSetting("book_map_overview_toc_depth", self.max_toc_depth)
        end
    end
    if self.flat_map then
        self.nb_toc_spans = 0 -- no span shown in grid
    else
        self.nb_toc_spans = self.toc_depth
    end

    self.flat_toc_depth_faces = nil
    if self.flat_map then
        self.flat_toc_depth_faces = {}
        -- Use ReaderToc setting font size for items at the lowest depth
        self.flat_toc_depth_faces[self.toc_depth] = Font:getFace(self.toc_span_font_name, self.reader_toc_font_size)
        for lvl=self.toc_depth-1, 1, -1 do
            -- But increase font size for each upper level
            local inc = 2 * (self.toc_depth - lvl)
            self.flat_toc_depth_faces[lvl] = Font:getFace(self.toc_span_font_name, self.reader_toc_font_size + inc)
        end
        -- Use 1.5em with the reference font size for indenting chapters and their BookMapRow
        self.flat_toc_level_indent = Screen:scaleBySize(self.reader_toc_font_size * 1.5)
    end

    -- Row will contain: nb_toc_spans + page slots + spacing (+ some borders)
    local page_slots_height_ratio = 1 -- default to 1 * span_height
    if not self.statistics_enabled then
        -- If statistics are disabled, we won't show black page slots for read pages.
        -- We can gain a bit of height by reducing the height reserved for these
        -- (don't go too low: we need some height to show the page number on the left).
        if self.flat_map or self.nb_toc_spans == 0 then
            -- Enough to show 4 digits page numbers
            page_slots_height_ratio = 0.7
        elseif self.nb_toc_spans > 0 then
            -- Just enough to show page separators below toc spans
            page_slots_height_ratio = 0.2
        end
    end
    self.row_height = math.ceil((self.nb_toc_spans + page_slots_height_ratio + 1) * self.span_height + 2*BookMapRow.pages_frame_border)

    if self.flat_map then
        -- Max pages per row, when each page slots takes 1px
        self.max_pages_per_row = math.floor(self.row_width - self.row_left_spacing - 2*Size.border.default
                                                - Size.span.horizontal_default*self.toc_depth)
        -- Find out the length of the largest chapter that we may show
        local len
        local max_len = 0
        local p = 1
        for _, item in ipairs(self.ui.toc.toc) do
            if item.depth <= self.toc_depth then
                len = item.page - p + 1
                if len > max_len then max_len = len end
                p = item.page
            end
        end
        len = self.nb_pages - p + 1 -- last chapter
        if len > max_len then max_len = len end
        self.fit_pages_per_row = max_len
    else
        -- Max pages per row, when each page slots takes 1px
        self.max_pages_per_row = math.floor(self.row_width - self.row_left_spacing - 2*Size.border.default)
        -- What can fit without scrollbar
        local fit_nb_rows = math.floor(self.crop_height / self.row_height)
        self.fit_pages_per_row = math.ceil(self.nb_pages / fit_nb_rows)
    end
    self.min_pages_per_row = 10
    -- If page slots are at least 4 pixels wide, we can steal one to act as a 1px blank separator
    self.max_pages_per_row_with_sep = math.floor(self.max_pages_per_row / 4)
    if self.fit_pages_per_row < self.min_pages_per_row then
        self.fit_pages_per_row = self.min_pages_per_row
    end
    if self.fit_pages_per_row > self.max_pages_per_row then
        self.fit_pages_per_row = self.max_pages_per_row
    end

    -- Show the whole book without scrollbar initially
    self.pages_per_row = self.ui.doc_settings:readSetting("book_map_pages_per_row", self.fit_pages_per_row)
    if self.overview_mode then
        self.pages_per_row = self.fit_pages_per_row
    end
    self.page_slot_width = nil -- will be fetched from the first BookMapRow

    -- Build BookMapRows as we walk the ToC
    local toc = self.ui.toc.toc
    local toc_idx = 1
    local cur_toc_items = {}
    local p_start = 1
    local cur_left_spacing = self.row_left_spacing -- updated when flat_map with previous TOC item indentation
    local cur_page_label_idx = 1
    while true do
        local p_max = p_start + self.pages_per_row - 1 -- max page number in this row
        local p_end = math.min(p_max, self.nb_pages) -- last book page in this row
        -- Find out the toc items that can be shown on this row
        local row_toc_items = {}
        while toc_idx <= #toc do
            local item = toc[toc_idx]
            if item.page > p_max then
                -- This TOC item will close previous items and start on the next row
                break
            end
            if item.depth <= self.toc_depth then -- ignore lower levels we won't show
                if self.flat_map then
                    if item.page == p_start then
                        cur_left_spacing = self.row_left_spacing + self.flat_toc_level_indent * (item.depth-1)
                        -- We'll display focus with inner borders, possibly drawn over the text.
                        -- Adding top and bottom padding does not seem needed, but we need
                        -- some left and right padding (for the border, and some thin one before the text)
                        local h_padding = self.enable_focus_navigation and Size.border.default + Size.border.thin or 0
                        local txt_max_width = self.row_width - cur_left_spacing - 2*h_padding
                        local toc_title = FrameContainer:new{
                            margin = 0,
                            padding = 0,
                            padding_left = h_padding,
                            padding_right = h_padding,
                            bordersize = 0,
                            focusable = self.enable_focus_navigation,
                            focus_border_size = self.focus_nav_border,
                            focus_inner_border = true,
                            TextBoxWidget:new{
                                text = self.ui.toc:cleanUpTocTitle(item.title, true),
                                width = txt_max_width,
                                face = self.flat_toc_depth_faces[item.depth],
                            }
                        }
                        if self.enable_focus_navigation then
                            table.insert(self.layout, {toc_title})
                        end
                        table.insert(self.vgroup, HorizontalGroup:new{
                            HorizontalSpan:new{
                                width = cur_left_spacing,
                            },
                            toc_title,
                            -- Store this TOC item page, so we can tap on it to launch PageBrowser on its page
                            toc_item_page = item.page,
                        })
                        -- Add a bit more spacing for the BookMapRow(s) underneath this Toc item title
                        -- (so the page number painted in this spacing feels included in the indentation)
                        cur_left_spacing = cur_left_spacing + Size.span.horizontal_default + toc_title.padding_left
                        -- Note: this variable indentation may make the page slot widths variable across
                        -- rows from different levels (and self.fit_pages_per_row not really accurate) :/
                        -- Hopefully, it won't be noticeable.
                    else
                        p_max = item.page - 1
                        p_end = p_max
                        -- Will be reprocessed on a new row
                        break
                    end
                else
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
                        seq_in_level = item.seq_in_level,
                    }
                end
            end
            toc_idx = toc_idx + 1
        end
        local is_last_row = p_end == self.nb_pages
        -- We may have current toc_items that are active and may continue on next row
        -- Add a slightly adjusted copy of the current ones to row_toc_items
        for lvl = 1, self.nb_toc_spans do -- (no-op/no-loop if flat_map)
            local active_toc_item = cur_toc_items[lvl]
            if active_toc_item then
                local copied_toc_item = {}
                for k,v in next, active_toc_item, nil do copied_toc_item[k] = v end
                if copied_toc_item.p_start < p_start then
                    copied_toc_item.p_start = p_start
                    copied_toc_item.started_before = true -- no left margin
                end
                copied_toc_item.p_end = p_end
                copied_toc_item.continues_after = not is_last_row -- no right margin (except if last row)
                -- Look at next TOC item to see if it would close this one
                local coming_up_toc_item = toc[toc_idx]
                if coming_up_toc_item and coming_up_toc_item.page == p_max+1 and coming_up_toc_item.depth <= lvl then
                    copied_toc_item.continues_after = false -- right margin
                end
                if not row_toc_items[lvl] then
                    row_toc_items[lvl] = {}
                end
                table.insert(row_toc_items[lvl], copied_toc_item)
            end
        end

        -- Get the page number to display at start of row
        local start_page_text
        if self.page_labels then
            local label
            for idx=cur_page_label_idx, #self.page_labels do
                local item = self.page_labels[idx]
                if item.page > p_start then
                    break
                end
                label = item.label
                cur_page_label_idx = idx
            end
            if label then
                start_page_text = self.ui.pagemap:cleanPageLabel(label)
            end
        elseif self.has_hidden_flows then
            local flow = self.ui.document:getPageFlow(p_start)
            if flow == 0 then
                start_page_text = tostring(self.ui.document:getPageNumberInFlow(p_start))
            else
                -- start_page_text = string.format("[%d]%d", self.ui.document:getPageNumberInFlow(p_start), self.ui.document:getPageFlow(p_start))
                -- start_page_text = string.format("/%d\\", self.ui.document:getPageFlow(p_start))
                -- Just don't display anything
                start_page_text = nil
            end
        else
            start_page_text = tostring(p_start)
        end
        if start_page_text then
            start_page_text = table.concat(util.splitToChars(start_page_text), "\n")
        else
            start_page_text = ""
        end

        local extended_sep_pages
        if self.ten_pages_markers > 0 then
            -- 0: no marker
            -- 1: show small marker every 10 pages
            -- 2: show medium marker every 10 pages
            -- 3: show medium marker every 10 pages + small every 5 pages
            local show_5 = self.ten_pages_markers == 3
            local extended_sep_pages_every = show_5 and 5 or 10
            local marker_10 = self.ten_pages_markers == 1 and BookMapRow.extended_marker.SMALL or BookMapRow.extended_marker.MEDIUM
            local marker_5 = BookMapRow.extended_marker.SMALL
            local start, is_5
            extended_sep_pages = {}
            if self.flat_map then
                -- We start counting at the start of each row (markers won't coincide with pages nn0)
                start = p_start
                is_5 = false
            else
                -- For simplicity, we show the markers every 10 screen pages (this may look odd though,
                -- if hidden flows or page labels are at play, as markers may not happen on pages nn0)
                start = p_start - (p_start % extended_sep_pages_every)
                is_5 = show_5 and start % 10 == 5 or false
            end
            for p = start, p_end, extended_sep_pages_every do
                extended_sep_pages[p] = is_5 and marker_5 or marker_10
                if show_5 then
                    is_5 = not is_5
                end
            end
        end

        local row = BookMapRow:new{
            height = self.row_height,
            width = self.row_width,
            show_parent = self,
            left_spacing = cur_left_spacing,
            nb_toc_spans = self.nb_toc_spans,
            span_height = self.span_height,
            font_face = self.toc_span_face,
            alt_theme = self.alt_theme,
            start_page_text = start_page_text,
            start_page = p_start,
            end_page = p_end,
            pages_per_row = self.pages_per_row,
            cur_page = self.cur_page,
            with_page_sep = self.pages_per_row < self.max_pages_per_row_with_sep,
            toc_items = row_toc_items,
            bookmarked_pages = self.bookmarked_pages,
            pinned_page = self.pinned_page,
            previous_locations = self.previous_locations,
            extra_symbols_pages = self.extra_symbols_pages,
            hidden_flows = self.hidden_flows,
            read_pages = self.read_pages,
            current_session_duration = self.current_session_duration,
            extended_sep_pages = extended_sep_pages,
            enable_focus_navigation = self.enable_focus_navigation,
            focus_nav_page = self.focus_page,
            focus_nav_border = self.focus_nav_border,
        }
        table.insert(self.vgroup, row)
        if self.enable_focus_navigation then
            for _, focus_row in ipairs(row.focus_layout) do
                table.insert(self.layout, focus_row)
            end
        end
        if not self.page_slot_width then
            self.page_slot_width = row.page_slot_width
        end
        if is_last_row then
            break
        end
        p_start = p_max + 1
    end

    -- Have main VerticalGroup size and subwidgets' offsets computed
    self.vgroup:getSize()

    -- Scroll so we get the focus page at the middle of screen
    local row, row_idx, row_y, row_h = self:getMatchingVGroupRow(function(r, r_y, r_h) -- luacheck: no unused
        return r.start_page and self.focus_page >= r.start_page and self.focus_page <= r.end_page
    end)
    if row_y then
        local top_y = row_y + row_h/2 - self.crop_height/2
        -- Align it so that we don't see any truncated BookMapRow at top
        row, row_idx, row_y, row_h = self:getMatchingVGroupRow(function(r, r_y, r_h)
            return r_y < top_y and r_y + r_h > top_y
        end)
        if row then
            if top_y - row_y > row_y + row_h - top_y then
                -- Less adjustment if we scroll to align the next row
                top_y = row_y + row_h
            else
                top_y = row_y
            end
        end
        if top_y > 0 then
            self.cropping_widget:initState() -- anticipate this (otherwise delayed and done at :paintTo() time)
            if self.cropping_widget._is_scrollable then
                self.cropping_widget:_scrollBy(0, top_y)
            end
        end
    end
    self.initial_scroll_offset_y = self.cropping_widget._scroll_offset_y

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end


function BookMapWidget:onShowBookMapMenu()
    local button_dialog
    -- Width of our -/+ buttons, so it looks fine with Button's default font size of 20
    local plus_minus_width = Screen:scaleBySize(60)
    local buttons = {
        {{
            text = self.overview_mode and _("About book map (overview)") or _("About book map"),
            align = "left",
            callback = function()
                self:showAbout()
            end,
        }},
        {{
            text = Device:isTouchDevice() and _("Available gestures") or _("Controls"),
            align = "left",
            callback = function()
                self:showGestures()
            end,
        }},
        {{
            text = Device:isTouchDevice() and _("Page browser on tap") or _("Page browser on key press"),
            checked_func = function()
                if self.overview_mode then
                    return G_reader_settings:nilOrTrue("book_map_overview_tap_to_page_browser")
                else
                    return G_reader_settings:nilOrTrue("book_map_tap_to_page_browser")
                end
            end,
            align = "left",
            callback = function()
                if self.overview_mode then
                    return G_reader_settings:flipNilOrTrue("book_map_overview_tap_to_page_browser")
                else
                    return G_reader_settings:flipNilOrTrue("book_map_tap_to_page_browser")
                end
            end,
        }},
        {{
            text = _("Alternative theme"),
            checked_func = function()
                return G_reader_settings:isTrue("book_map_alt_theme")
            end,
            align = "left",
            callback = function()
                G_reader_settings:flipTrue("book_map_alt_theme")
                self.editable_stuff_edited = true -- have this change reflected on any lower bookmap & pagebrowser
                self:update()
            end,
        }},
        not self.overview_mode and {{
            text = _("Switch current/initial view"),
            align = "left",
            enabled_func = function() return self.toc_depth > 0 end,
            callback = function()
                self:toggleDefaultSettings()
            end,
        }},
        not self.overview_mode and {{
            text = _("Switch grid/flat views"),
            align = "left",
            enabled_func = function() return self.toc_depth > 0 end,
            callback = function()
                self.flat_map = not self.flat_map
                self:saveSettings()
                self:update()
            end,
        }},
        {
            {
                text = _("Chapter levels"),
                callback = function() end,
                align = "left",
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.toc_depth > 0 end,
                callback = function()
                    if self:updateTocDepth(self.flat_map and 1 or -1, nil) then
                        self:update()
                    end
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.toc_depth < self.max_toc_depth end,
                callback = function()
                    if self:updateTocDepth(self.flat_map and -1 or 1, nil) then
                        self:update()
                    end
                end,
                width = plus_minus_width,
            }
        },
        not self.overview_mode and {
            {
                text = _("Page-slot width"),
                callback = function() end,
                align = "left",
                -- Below, minus increases page per row and plus decreases it.
                -- It feels more natural this way: + will make everything (page slots and the grid) bigger.
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.pages_per_row < self.max_pages_per_row end,
                callback = function()
                    if self:updatePagesPerRow(10, true) then
                        self:update()
                    end
                end,
                hold_callback = function()
                    if self:updatePagesPerRow(50, true) then
                        self:update()
                    end
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.pages_per_row > self.min_pages_per_row end,
                callback = function()
                    if self:updatePagesPerRow(-10, true) then
                        self:update()
                    end
                end,
                hold_callback = function()
                    if self:updatePagesPerRow(-50, true) then
                        self:update()
                    end
                end,
                width = plus_minus_width,
            }
        },
        {
            {
                text = _("10-page markers"),
                callback = function() end,
                align = "left",
            },
            {
                text = "\u{2796}", -- Heavy minus sign
                enabled_func = function() return self.ten_pages_markers > 0 end,
                callback = function()
                    self.ten_pages_markers = self.ten_pages_markers - 1
                    G_reader_settings:saveSetting("book_map_ten_pages_markers", self.ten_pages_markers)
                    self:update()
                end,
                width = plus_minus_width,
            },
            {
                text = "\u{2795}", -- Heavy plus sign
                enabled_func = function() return self.ten_pages_markers < 3 end,
                callback = function()
                    self.ten_pages_markers = self.ten_pages_markers + 1
                    G_reader_settings:saveSetting("book_map_ten_pages_markers", self.ten_pages_markers)
                    self:update()
                end,
                width = plus_minus_width,
            }
        },
    }
    -- Remove false buttons from the list if overview_mode
    for i = #buttons, 1, -1 do
        if not buttons[i] then
            table.remove(buttons, i)
        end
    end
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

function BookMapWidget:showAbout()
    local text = _([[
Book map provides a summary of a book's content, showing chapters and pages visually. If statistics are enabled, black bars represent pages already read (gray for pages read in the current session), with varying heights based on reading time.

Map legend:
▲ current page
❶ ❷ … previous locations
▒ highlighted text
 highlighted text with notes
 bookmarked page
 pinned page
▢ focused page when coming from Pages browser]])

    if self.overview_mode then
        text = text .. "\n\n" .. _([[
When in overview mode, the book map is always displayed in grid mode to fit on one screen. The chapter levels can be easily adjusted for the most convenient overview experience.]])
    else
        text = text .. "\n\n" .. _([[
When you first open a book, the book map will begin in grid mode, displaying all chapter levels on one screen for a comprehensive overview of the book's content.]])
    end
    UIManager:show(InfoMessage:new{ text = text })
end

function BookMapWidget:showGestures()
    local text
    if not Device:isTouchDevice() then
        text = _([[
Use settings in this menu to change the level of chapters to include in the book map, the view type (grid or flat) and the width of page slots.

Use "ScreenKB/Shift" + "Up/Down" to scroll or use the page turn buttons to move at a faster rate.

Press back to exit the book map.]])
    elseif self.overview_mode then
        text = _([[
Tap on a location in the book to browse thumbnails of the pages there.

Swipe along the left screen edge to change the level of chapters to include in the book map.

Any multiswipe will close the book map.]])
    else
        text = _([[
Tap on a location in the book to browse thumbnails of the pages there.

Swipe along the left screen edge to change the level of chapters to include in the book map, and the type of book map (grid or flat) when crossing the level 0.

Swipe along the bottom screen edge to change the width of page slots.

Swipe or pan vertically on content to scroll.

Long-press on ≡ to switch between current and initial views.

Any multiswipe will close the book map.]])
    end
    UIManager:show(InfoMessage:new{ text = text })
end

function BookMapWidget:onClose(close_all_parents)
    -- Close this widget
    logger.dbg("closing BookMapWidget")
    UIManager:close(self)
    if self.launcher then
        -- We were launched by a PageBrowserWidget, don't do any cleanup.
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

function BookMapWidget:getMatchingVGroupRow(check_func)
    -- Generic Vertical subwidget search function.
    -- We use some of VerticalGroup's internal data, no need
    -- to keep public copies of these data in here
    for i=1, #self.vgroup do
        local row = self.vgroup[i]
        local y = self.vgroup._offsets[i].y
        local h = (i < #self.vgroup and self.vgroup._offsets[i+1].y or self.vgroup._size.h) - y
        if check_func(row, y, h) then
            return row, i, y, h
        end
    end
end

function BookMapWidget:getVGroupRowAtY(y)
    -- y is expected relative to the ScrollableContainer crop top
    -- (if y is from a screen coordinate, subtract 'self.title_bar_h' before calling this)
    y = y + self.cropping_widget._scroll_offset_y
    return self:getMatchingVGroupRow(function(r, r_y, r_h)
        return y >= r_y and y < r_y + r_h
    end)
end

function BookMapWidget:getBookMapRowNearY(y)
    -- y is expected relative to the ScrollableContainer crop top
    -- (if y is from a screen coordinate, subtract 'self.title_bar_h' before calling this)
    y = y + self.cropping_widget._scroll_offset_y
    -- Return the BookMapRow at y, or if the vgroup element is a ToC
    -- title (in flat_map mode), return the follow up BookMapRow
    return self:getMatchingVGroupRow(function(r, r_y, r_h)
        return y < r_y + r_h and r.start_page
    end)
end

function BookMapWidget:onScrollPageUp()
    -- Show previous content, ensuring any truncated widget at top is now full at bottom
    local scroll_offset_y = self.cropping_widget._scroll_offset_y
    local row, row_idx, row_y, row_h = self:getVGroupRowAtY(-1) -- luacheck: no unused
    local to_keep = 0
    if row then
        to_keep = row_h - (scroll_offset_y - row_y)
    end
    self.cropping_widget:_scrollBy(0, -(self.crop_height - to_keep))
    self:updateFocusAfterScroll()
    return true
end

function BookMapWidget:onScrollPageDown()
    -- Show next content, ensuring any truncated widget at bottom is now full at top
    local scroll_offset_y = self.cropping_widget._scroll_offset_y
    local row, row_idx, row_y, row_h = self:getVGroupRowAtY(self.crop_height) -- luacheck: no unused
    if row then
        self.cropping_widget:_scrollBy(0, row_y - scroll_offset_y)
    else
        self.cropping_widget:_scrollBy(0, self.crop_height)
    end
    self:updateFocusAfterScroll()
    return true
end

function BookMapWidget:onScrollRowUp()
    local scroll_offset_y = self.cropping_widget._scroll_offset_y
    local row, row_idx, row_y, row_h = self:getVGroupRowAtY(-1) -- luacheck: no unused
    if row then
        self.cropping_widget:_scrollBy(0, row_y - scroll_offset_y)
        self:updateFocusAfterScroll()
    end
    return true
end

function BookMapWidget:onScrollRowDown()
    local scroll_offset_y = self.cropping_widget._scroll_offset_y
    local row, row_idx, row_y, row_h = self:getVGroupRowAtY(0) -- luacheck: no unused
    if row then
        self.cropping_widget:_scrollBy(0, row_y + row_h - scroll_offset_y)
        self:updateFocusAfterScroll()
    end
    return true
end

function BookMapWidget:saveSettings(reset)
    if reset then
        self.flat_map = nil
        self.toc_depth = nil
        self.pages_per_row = nil
    end
    if self.overview_mode then
        if self.ui.handmade:isHandmadeTocEnabled() then
            self.ui.doc_settings:saveSetting("book_map_overview_toc_depth_handmade_toc", self.toc_depth)
        else
            self.ui.doc_settings:saveSetting("book_map_overview_toc_depth", self.toc_depth)
        end
        return
    end
    if self.ui.handmade:isHandmadeTocEnabled() then
        self.ui.doc_settings:saveSetting("book_map_toc_depth_handmade_toc", self.toc_depth)
    else
        self.ui.doc_settings:saveSetting("book_map_toc_depth", self.toc_depth)
    end
    self.ui.doc_settings:saveSetting("book_map_flat", self.flat_map)
    self.ui.doc_settings:saveSetting("book_map_pages_per_row", self.pages_per_row)
end

function BookMapWidget:toggleDefaultSettings()
    if not self.flat_map and self.toc_depth == self.max_toc_depth
            and self.pages_per_row == self.fit_pages_per_row then
        -- Still in default/initial view: restore previous settings (if any)
        self.flat_map = self.ui.doc_settings:readSetting("book_map_previous_flat")
        self.toc_depth = self.ui.doc_settings:readSetting("book_map_previous_toc_depth")
        self.pages_per_row = self.ui.doc_settings:readSetting("book_map_previous_pages_per_row")
        self:saveSettings()
    else
        -- Save previous settings and switch to defaults
        self.ui.doc_settings:saveSetting("book_map_previous_flat", self.flat_map)
        self.ui.doc_settings:saveSetting("book_map_previous_toc_depth", self.toc_depth)
        self.ui.doc_settings:saveSetting("book_map_previous_pages_per_row", self.pages_per_row)
        self:saveSettings(true)
    end
    self:update()
end

function BookMapWidget:updateTocDepth(depth, flat)
    -- if flat == nil, consider value relative, and allow toggling
    -- flatness when crossing 0
    local new_toc_depth = self.toc_depth
    local new_flat_map = self.flat_map
    if flat == nil then
        if self.flat_map then
            -- Reverse increment if flat_map
            new_toc_depth = new_toc_depth - depth
        else
            new_toc_depth = new_toc_depth + depth
        end
        if new_toc_depth < 0 and not self.overview_mode then
            new_toc_depth = - new_toc_depth
            new_flat_map = not new_flat_map
        end
    else
        new_toc_depth = depth
        new_flat_map = flat
    end
    if new_toc_depth < 0 then
        new_toc_depth = 0
    end
    if new_toc_depth > self.max_toc_depth then
        new_toc_depth = self.max_toc_depth
    end
    if new_toc_depth == self.toc_depth and new_flat_map == self.flat_map then
        return false
    end
    self.toc_depth = new_toc_depth
    self.flat_map = new_flat_map
    self:saveSettings()
    return true
end

function BookMapWidget:updatePagesPerRow(value, relative)
    local new_pages_per_row
    if relative then
        new_pages_per_row = self.pages_per_row + value
    else
        new_pages_per_row = value
    end
    if new_pages_per_row < self.min_pages_per_row then
        new_pages_per_row = self.min_pages_per_row
    end
    if new_pages_per_row > self.max_pages_per_row then
        new_pages_per_row = self.max_pages_per_row
    end
    if new_pages_per_row == self.pages_per_row then
        return false
    end
    self.pages_per_row = new_pages_per_row
    self:saveSettings()
    return true
end

function BookMapWidget:onSwipe(arg, ges)
    local _mirroredUI = BD.mirroredUILayout()
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if (not _mirroredUI and ges.pos.x < Screen:getWidth() * 1/8) or
           (_mirroredUI and ges.pos.x > Screen:getWidth() * 7/8) then
        -- Swipe along the left screen edge: increase/decrease toc levels shown
        if direction == "north" or direction == "south" then
            local rel = direction == "south" and 1 or -1
            if self:updateTocDepth(rel, nil) then
                self:update()
            end
            return true
        end
    end
    if ges.pos.y > Screen:getHeight() * 7/8 then
        if self.overview_mode then
            return true
        end
        -- Swipe along the bottom screen edge: increase/decrease pages per row
        if direction == "west" or direction == "east" then
            -- Have a swipe distance 0.8 x screen width do *2 or *1/2
            local ratio = ges.distance / Screen:getWidth()
            local new_pages_per_row
            if direction == "west" then -- increase pages per row
                new_pages_per_row = math.ceil(self.pages_per_row * (1 + ratio))
            else
                new_pages_per_row = math.floor(self.pages_per_row / (1 + ratio))
            end
            -- If we are crossing the ideal fit_pages_per_row, stop on it
            if (self.pages_per_row < self.fit_pages_per_row and new_pages_per_row > self.fit_pages_per_row)
                    or (self.pages_per_row > self.fit_pages_per_row and new_pages_per_row < self.fit_pages_per_row) then
                new_pages_per_row = self.fit_pages_per_row
            end
            if self:updatePagesPerRow(new_pages_per_row) then
                self:update()
            end
            return true
        end
    end
    if self.overview_mode and not self.cropping_widget._is_scrollable and direction == "south" then
        -- Swipe south won't have any effect in overview mode as we fit on the page (except on
        -- really big books, where we can still be scrollable), so allow swipe south to close
        -- as on some other fullscreen widgets.
        self:onClose()
        return true
    end
    -- Let our MovableContainer handle other swipes:
    -- return self.cropping_widget:onScrollableSwipe(arg, ges)
    -- No, we prefer not to, and have swipe north/south do full prev/next page
    -- rather than based on the swipe distance
    if direction == "north" then
        return self:onScrollPageDown()
    elseif direction == "south" then
        return self:onScrollPageUp()
    elseif direction == "west" or direction == "east" then
        return true
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function BookMapWidget:onPan(arg, ges)
    if ges.mousewheel_direction then
        if ges.direction == "north" then
            return self:onScrollRowDown()
        elseif ges.direction == "south" then
            return self:onScrollRowUp()
        end
    end
end

function BookMapWidget:onPinch(arg, ges)
    if self.overview_mode then
        return true
    end
    local updated = false
    if ges.direction == "horizontal" or ges.direction == "diagonal" then
        local new_pages_per_row = math.ceil(self.pages_per_row * 1.5)
        if (self.pages_per_row < self.fit_pages_per_row and new_pages_per_row > self.fit_pages_per_row)
                or (self.pages_per_row > self.fit_pages_per_row and new_pages_per_row < self.fit_pages_per_row) then
            new_pages_per_row = self.fit_pages_per_row
        end
        if self:updatePagesPerRow(new_pages_per_row) then
            updated = true
        end
    end
    if ges.direction == "vertical" or ges.direction == "diagonal" then
        -- Keep current flat map mode
        if self:updateTocDepth(self.toc_depth-1, self.flat_map) then
            updated = true
        else
            -- Already at 0: toggle flat mode, stay at 0 (no visual feedback though...)
            if self:updateTocDepth(0, not self.flat_map) then
                updated = true
            end
        end
    end
    if updated then
        self:update()
    end
    return true
end

function BookMapWidget:onSpread(arg, ges)
    if self.overview_mode then
        return true
    end
    local updated = false
    if ges.direction == "horizontal" or ges.direction == "diagonal" then
        local new_pages_per_row = math.floor(self.pages_per_row * (2/3))
        if (self.pages_per_row < self.fit_pages_per_row and new_pages_per_row > self.fit_pages_per_row)
                or (self.pages_per_row > self.fit_pages_per_row and new_pages_per_row < self.fit_pages_per_row) then
            new_pages_per_row = self.fit_pages_per_row
        end
        if self:updatePagesPerRow(new_pages_per_row) then
            updated = true
        end
    end
    if ges.direction == "vertical" or ges.direction == "diagonal" then
        if self:updateTocDepth(self.toc_depth+1, self.flat_map) then
            updated = true
        end
    end
    if updated then
        self:update()
    end
    return true
end

function BookMapWidget:onMultiSwipe(arg, ges)
    -- Swipe south (the usual shortcut for closing a full screen window)
    -- is used for navigation. Swipe left/right are free, but a little
    -- unusual for the purpose of closing.
    -- So, allow for quick closing with any multiswipe.
    self:onClose()
    return true
end

function BookMapWidget:onTap(arg, ges)
    if ges.pos:notIntersectWith(self.cropping_widget.dimen) then
        return true
    end
    local x, y = ges.pos.x, ges.pos.y
    local row, row_idx, row_y, row_h = self:getVGroupRowAtY(y-self.title_bar_h) -- luacheck: no unused
    if not row then
        return true
    end
    local page = row.toc_item_page      -- it might be a TOC title
    if not page and row.start_page then -- or a BookMapRow
        if BD.mirroredUILayout() then
            x = x - self.scrollbar_width
        end
        page = row:getPageAtX(x, true)
    end
    if page then
        if (self.overview_mode and G_reader_settings:isFalse("book_map_overview_tap_to_page_browser")) or (not self.overview_mode and G_reader_settings:isFalse("book_map_tap_to_page_browser")) then
            self:onClose(true)
            self.ui.link:addCurrentLocationToStack()
            self.ui:handleEvent(Event:new("GotoPage", page))
            return true
        end
        local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
        UIManager:show(PageBrowserWidget:new{
            launcher = self,
            ui = self.ui,
            focus_page = page,
        })
    end
    return true
end

function BookMapWidget:onGoToFocusedPage()
    if not self.enable_focus_navigation or not self.cur_focused_widget then
        return true
    end

    local target_page = nil
    -- Find the row containing the focused widget.
    local row = self:getVGroupRowAtY(self.cur_focused_widget.dimen.y - self.title_bar_h)
    if row and row.start_page then
        -- Find the focused widget in the row's layout.
        local invisible_page_slots = row.focus_layout[#row.focus_layout] -- last row in focus_layout contains page slots
        if invisible_page_slots then
            for i, widget in ipairs(invisible_page_slots) do
                if widget == self.cur_focused_widget then
                    target_page = row.start_page + i - 1
                    break
                end
            end
        end
    end
    if target_page then
        local should_go_to_page_browser
        if self.overview_mode then
            should_go_to_page_browser = G_reader_settings:isFalse("book_map_overview_tap_to_page_browser")
        else
            should_go_to_page_browser = G_reader_settings:isFalse("book_map_tap_to_page_browser")
        end
        if should_go_to_page_browser then
            local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
            UIManager:show(PageBrowserWidget:new{
                launcher = self,
                ui = self.ui,
                focus_page = target_page,
            })
        else
            -- Navigate directly to the target page
            self:onClose(true)
            self.ui.link:addCurrentLocationToStack()
            self.ui:handleEvent(Event:new("GotoPage", target_page))
        end
    end
    return true
end

function BookMapWidget:updateFocusAfterScroll()
    if not self.enable_focus_navigation then
        return
    end
    -- Set this flag so the next call to updateFocus() from paintTo() will know
    -- we've just scrolled and we don't have to force the current focused item
    -- into view, but possibly change what is the current focus item.
    self.update_focus_after_scroll = true
end

function BookMapWidget:updateFocus()
    -- To work with up to date widget positions, this must be called after paintTo()
    -- has done its job as it is it that updates all widget coordinates

    if not self.enable_focus_navigation then return end

    if not self.cur_focused_widget then -- first call after first paintTo()
        for y, r in ipairs(self.layout) do
            if r.focused_widget_idx then -- this row contains the focused widget
                self:moveFocusTo(r.focused_widget_idx, y)
                break
            end
        end
        self.cur_focused_widget = self:getFocusItem()
        -- This will cause a repaint and have the focus border appear
        self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK, FocusManager.FORCED_FOCUS)
        return
    end

    if not self.update_focus_after_scroll then -- regular painTo() not caused by scrolling
        local cur_focused_widget = self:getFocusItem()
        if cur_focused_widget ~= self.cur_focused_widget then
            -- The focused widget has changed; this is expected to happen only
            -- from the paintTo after the user has used keys to move the
            -- focused item.
            self.cur_focused_widget = cur_focused_widget
        else
            -- Nothing to do, this is a regular repaint without any move
            return
        end
    end

    local focused_widget_dimen = self.cur_focused_widget.dimen

    if self.update_focus_after_scroll then
        if focused_widget_dimen.y < self.cropping_widget.dimen.y
                or focused_widget_dimen.y + focused_widget_dimen.h >= self.cropping_widget.dimen.y + self.crop_height then
            -- The current focused widget is not fully in the viewport
            -- The user has scrolled one page or one row, and the focused widget moved out
            -- of the updated view: forget that focused widget and change it to a widget
            -- in the middle of the new view.
            for y, focus_row in ipairs(self.layout) do
                if #focus_row > 0 then
                    local dimen = focus_row[1].dimen
                    if dimen.y + dimen.h > self.cropping_widget.dimen.y + self.crop_height/2 then
                        self:moveFocusTo(1, y)
                        break
                    end
                end
            end
            self.cur_focused_widget = self:getFocusItem()
            -- This will trigger a repaint and cause us to be called again (at which point we should do nothing).
            self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK, FocusManager.FORCED_FOCUS)
        end
    else
        -- The focused widget was changed by the user (with keys), it may have moved out of view.
        -- For a smooth experience, we can't move just the focused page slot into view and have
        -- parts of its BookMapRow (chapter titles above in grid mode) truncated (borders, icons
        -- below baseline): we need to move this BookMapRow fully into view.
        local row, row_idx, row_y, row_h = self:getVGroupRowAtY(focused_widget_dimen.y - self.title_bar_h) -- luacheck: no unused
        if row then
            row_y = row_y - self.cropping_widget._scroll_offset_y
            if row_y < 0 then
                self.cropping_widget:_scrollBy(0, row_y)
                -- This will trigger a repaint and cause us to be called again (at which point we should do nothing).
                -- (We shouldn't need to refocus, but somehow, this works while a classic setDirty doesn't)
                self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK, FocusManager.FORCED_FOCUS)
            elseif row_y + row_h > self.crop_height then
                self.cropping_widget:_scrollBy(0, row_y + row_h - self.crop_height)
                self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK, FocusManager.FORCED_FOCUS)
            end
        end
    end
    self.update_focus_after_scroll = false
end

function BookMapWidget:paintTo(bb, x, y)
    -- Paint regular sub widgets the classic way
    InputContainer.paintTo(self, bb, x, y)
    -- And explicitly paint "swipe" hints along the left and bottom borders
    self:paintLeftVerticalSwipeHint(bb, x, y)
    if not self.overview_mode then
        self:paintBottomHorizontalSwipeHint(bb, x, y)
    end
    self:updateFocus()
end

function BookMapWidget:paintLeftVerticalSwipeHint(bb, x, y)
    -- Vertical bar with a part of it darker, as a scale showing
    -- selected flat_map and toc_depth. In gray so it's visible
    -- when you look at it, but not distracting when you don't.
    local v = self.vs_hint_info
    if not v then
        -- Compute and remember sizes, positions and info
        v = {}
        v.width = self.swipe_hint_bar_width
        if BD.mirroredUILayout() then
            v.left = Screen:getWidth() - v.width
        else
            v.left = 0
        end
        v.top = self.title_bar_h + math.floor(self.crop_height * 1/6)
        v.height = math.floor(self.crop_height * 4/6)
        v.nb_units = self.max_toc_depth * 2 + 1
        if self.overview_mode then
            v.nb_units = self.max_toc_depth + 1
        end
        v.unit_h = math.floor(v.height / v.nb_units)
        self.vs_hint_info = v
    end
    -- Paint a vertical light gray bar
    bb:paintRect(v.left, v.top, v.width, v.height, Blitbuffer.COLOR_LIGHT_GRAY)
    -- And paint a part of it in a darker gray
    local unit_idx -- starts from 0
    if self.flat_map then -- upper part of the vertical bar
        unit_idx = self.max_toc_depth - self.toc_depth
    else -- lower part of the vertical bar
        unit_idx = self.max_toc_depth + self.toc_depth
    end
    if self.overview_mode then
        unit_idx = self.toc_depth
    end
    local dy = unit_idx * v.unit_h
    if unit_idx == v.nb_units - 1 then
        -- avoid possible rounding error for last unit
        dy = v.height - v.unit_h
    end
    bb:paintRect(v.left, v.top + dy, v.width, v.unit_h, Blitbuffer.COLOR_DARK_GRAY)
end

function BookMapWidget:paintBottomHorizontalSwipeHint(bb, x, y)
    -- Horizontal bar with a part of it darker, as a scale showing
    -- selected pages_per_row.
    local h = self.hs_hint_info
    if not h then
        -- Compute and remember sizes, positions and info
        h = {}
        h.height = self.swipe_hint_bar_width
        h.top = Screen:getHeight() - h.height
        h.width = math.floor(Screen:getWidth() * 4/6)
        h.left = math.floor(Screen:getWidth() * 1/6)
        -- We show a fixed width handle with a granular dx
        h.hint_w = math.floor(h.width / 8)
        h.max_dx = h.width - h.hint_w
        self.hs_hint_info = h
    end
    -- Paint a horizontal light gray bar
    bb:paintRect(h.left, h.top, h.width, h.height, Blitbuffer.COLOR_LIGHT_GRAY)
    -- And paint a part of it in a darker gray
    -- (Somebody good at maths could probably do better than this... which
    -- could be related to the increment/ratio we use in onSwipe)
    local cur = self.pages_per_row - self.min_pages_per_row
    local max = self.max_pages_per_row - self.min_pages_per_row
    local dx = math.floor(h.max_dx*(1-math.log(1+cur)/math.log(1+max)))
    if BD.mirroredUILayout() then
        dx = h.max_dx - dx
    end
    bb:paintRect(h.left + dx, h.top, h.hint_w, h.height, Blitbuffer.COLOR_DARK_GRAY)
end

return BookMapWidget
