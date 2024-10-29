local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local Input = Device.input
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template

local HistogramWidget = Widget:extend{
    width = nil,
    height = nil,
    color = Blitbuffer.COLOR_BLACK,
    nb_items = nil,
    ratios = nil, -- table of 1...nb_items items, each with (0 <= value <= 1)
}

function HistogramWidget:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
    local item_width = math.floor(self.width / self.nb_items)
    local nb_item_width_add1 = self.width - self.nb_items * item_width
    local nb_item_width_add1_mod = math.floor(self.nb_items/nb_item_width_add1)
    self.item_widths = {}
    for n = 1, self.nb_items do
        local w = item_width
        if nb_item_width_add1 > 0 and n % nb_item_width_add1_mod == 0 then
            w = w + 1
            nb_item_width_add1 = nb_item_width_add1 - 1
        end
        table.insert(self.item_widths, w)
    end
    if BD.mirroredUILayout() then
        self.do_mirror = true
    end
end

function HistogramWidget:paintTo(bb, x, y)
    local i_x = 0
    for n = 1, self.nb_items do
        if self.do_mirror then
            n = self.nb_items - n + 1
        end
        local i_w = self.item_widths[n]
        local ratio = self.ratios and self.ratios[n] or 0
        local i_h = Math.round(ratio * self.height)
        if i_h == 0 and ratio > 0 then -- show at least 1px
            i_h = 1
        end
        local i_y = self.height - i_h
        if i_h > 0 then
            bb:paintRect(x + i_x, y + i_y, i_w, i_h, self.color)
        end
        i_x = i_x + i_w
    end
end


local CalendarDay = InputContainer:extend{
    daynum = nil,
    ratio_per_hour = nil,
    filler = false,
    width = nil,
    height = nil,
    border = 0,
    is_future = false,
    font_face = "xx_smallinfofont",
    font_size = nil,
    show_histo = true,
    histo_height = nil,
}

function CalendarDay:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
    if self.filler then
        return
    end
    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        }
    }
    self.ges_events.Hold = {
        GestureRange:new{
            ges = "hold",
            range = self.dimen,
        }
    }

    self.daynum_w = TextWidget:new{
        text = " " .. tostring(self.daynum),
        face = Font:getFace(self.font_face, self.font_size),
        fgcolor = self.is_future and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        padding = 0,
        bold = true,
    }
    self.nb_not_shown_w = TextWidget:new{
        text = "",
        face = Font:getFace(self.font_face, self.font_size - 1),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        overlap_align = "right",
    }
    local inner_w = self.width - 2*self.border
    local inner_h = self.height - 2*self.border
    if self.show_histo then
        if not self.histo_height then
            self.histo_height = inner_h * (1/3)
        end
        self.histo_w = BottomContainer:new{
            dimen = Geom:new{w = inner_w, h = inner_h},
            HistogramWidget:new{
                width = inner_w,
                height = self.histo_height,
                nb_items = 24,
                ratios = self.ratio_per_hour,
            }
        }
    end
    self[1] = FrameContainer:new{
        padding = 0,
        color = self.is_future and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        bordersize = self.border,
        width = self.width,
        height = self.height,
        focusable = true,
        focus_border_color = Blitbuffer.COLOR_GRAY,
        OverlapGroup:new{
            dimen = { w = inner_w },
            self.daynum_w,
            self.nb_not_shown_w,
            self.histo_w, -- nil if not show_histo
        }
    }
end

function CalendarDay:updateNbNotShown(nb)
    self.nb_not_shown_w:setText(string.format("+ %d ", nb))
end

function CalendarDay:onTap()
    if self.callback then
        self.callback()
    end
    return true
end

function CalendarDay:onHold()
    return self:onTap()
end


local CalendarWeek = InputContainer:extend{
    width = nil,
    height = nil,
    day_width = 0,
    day_padding = 0,
    day_border = 0,
    nb_book_spans = 0,
    histo_shown = nil,
    span_height = nil,
    font_size = 0,
    font_face = "xx_smallinfofont",
}

function CalendarWeek:init()
    self.calday_widgets = {}
    self.days_books = {}
end

function CalendarWeek:addDay(calday_widget)
    -- Add day widget to this week widget, and update the
    -- list of books read this week for later showing book
    -- spans, that may span multiple days.
    table.insert(self.calday_widgets, calday_widget)

    local prev_day_num = #self.days_books
    local prev_day_books = prev_day_num > 0 and self.days_books[#self.days_books]
    local this_day_num = prev_day_num + 1
    local this_day_books = {}
    table.insert(self.days_books, this_day_books)

    if not calday_widget.read_books then
        calday_widget.read_books = {}
    end
    local nb_books_read = #calday_widget.read_books
    if nb_books_read > self.nb_book_spans then
        calday_widget:updateNbNotShown(nb_books_read - self.nb_book_spans)
    end
    for i=1, self.nb_book_spans do
        if calday_widget.read_books[i] then
            this_day_books[i] = calday_widget.read_books[i] -- brings id & title keys
            this_day_books[i].span_days = 1
            this_day_books[i].start_day = this_day_num
            this_day_books[i].fixed = false
        else
            this_day_books[i] = false
        end
    end

    if prev_day_books then
        -- See if continuation from previous day, and re-order them if needed
        for pn=1, #prev_day_books do
            local prev_book = prev_day_books[pn]
            if prev_book then
                for tn=1, #this_day_books do
                    local this_book = this_day_books[tn]
                    if this_book and this_book.id == prev_book.id then
                        this_book.start_day = prev_book.start_day
                        this_book.fixed = true
                        this_book.span_days = prev_book.span_days + 1
                        -- Update span_days in all previous books
                        for bk = 1, prev_book.span_days do
                            self.days_books[this_day_num-bk][pn].span_days = this_book.span_days
                        end
                        if tn ~= pn then -- swap it with the one at previous day position
                            this_day_books[tn], this_day_books[pn] = this_day_books[pn], this_day_books[tn]
                        end
                        break
                    end
                end
            end
        end
    end
end

-- Set of { Font color, background color }
local SPAN_COLORS = {
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_E },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_D },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_B },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_9 },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_7 },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_5 },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_3 },
}

function CalendarWeek:update()
    self.dimen = Geom:new{w = self.width, h = self.height}
    self.day_container = HorizontalGroup:new{
        dimen = self.dimen:copy(),
    }
    for num, calday in ipairs(self.calday_widgets) do
        table.insert(self.day_container, calday)
        if num < #self.calday_widgets then
            table.insert(self.day_container, HorizontalSpan:new{ width = self.day_padding, })
        end
    end

    local overlaps = OverlapGroup:new{
        self.day_container,
    }
    -- Create and add BookSpans
    local bspan_margin_h = Size.margin.tiny + self.day_border
    local bspan_margin_v = Size.margin.tiny
    local bspan_padding_h = Size.padding.tiny
    local bspan_border = Size.border.thin

    -- We need a smaller font size than the one provided
    local text_height = self.span_height - 2 * (bspan_margin_v + bspan_border)
    -- We don't use any bspan_padding_v, we let that be handled by CenterContainer
    -- and choosing an appropriate font size.
    -- We use TextBoxWidget:getFontSizeToFitHeight() to get a fitting
    -- font size. It's less precise than the TextWidget equivalent,
    -- but it handles padding as 'em'.
    -- Use a 1.3em line height
    local inner_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.3)
    -- If font size gets really small, get a larger one by using a smaller
    -- line height: tall glyphs may bleed on the border, but we won't notice
    -- at such small size, and we'll appreciate the readability.
    -- (threshold values decided from visual testing)
    if inner_font_size <= 12 then
        inner_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.1)
    elseif inner_font_size <= 15 then
        inner_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.2)
    end
    -- But cap it to the day num font size
    inner_font_size = math.min(inner_font_size, self.font_size)

    local offset_y_fixup
    if self.histo_shown then
        -- No real y positioning needed, but push it a bit down
        -- over histogram, as histograms rarely reach 100%, and
        -- will be drawn last, so possibly over last book span if
        -- really near 100%
        offset_y_fixup = Size.margin.small
    else
        -- No histogram: ensure last book span bottom margin
        -- is equal to bspan_margin_v for a nice fit
        offset_y_fixup = self.height - self.span_height * (self.nb_book_spans + 1) - bspan_margin_v
    end

    for col, day_books in ipairs(self.days_books) do
        for row, book in ipairs(day_books) do
            if book and book.start_day == col then
                local fgcolor, bgcolor = unpack(SPAN_COLORS[(book.id % #SPAN_COLORS)+1])
                local offset_x = (col-1) * (self.day_width + self.day_padding)
                local offset_y = row * self.span_height -- 1st real row used by day num
                offset_y = offset_y + offset_y_fixup
                local width = book.span_days * self.day_width + self.day_padding * (book.span_days-1)
                -- We use two FrameContainers, as (unlike HTML) a FrameContainer
                -- draws the background color outside its borders, in the margins
                local span_w = FrameContainer:new{
                    width = width,
                    height = self.span_height,
                    margin = 0,
                    bordersize = 0,
                    padding_top = bspan_margin_v,
                    padding_bottom = bspan_margin_v,
                    padding_left = bspan_margin_h,
                    padding_right = bspan_margin_h,
                    overlap_offset = {offset_x, offset_y},
                    FrameContainer:new{
                        width = width - 2 * bspan_margin_h,
                        height = self.span_height - 2 * bspan_margin_v,
                        margin = 0,
                        padding = 0,
                        bordersize = bspan_border,
                        background = bgcolor,
                        CenterContainer:new{
                            dimen = Geom:new{
                                w = width - 2 * (bspan_margin_h + bspan_border),
                                h = self.span_height - 2 * (bspan_margin_v + bspan_border),
                            },
                            TextWidget:new{
                                text = BD.auto(book.title),
                                max_width = width - 2 * (bspan_margin_h + bspan_border + bspan_padding_h),
                                face = Font:getFace(self.font_face, inner_font_size),
                                padding = 0,
                                fgcolor = fgcolor,
                            }
                        }
                    }
                }
                table.insert(overlaps, span_w)
            end
        end
    end

    self[1] = LeftContainer:new{
        dimen = self.dimen:copy(),
        overlaps,
    }
end

local BookDailyItem = InputContainer:extend{
    item = nil,
    face = Font:getFace("smallinfofont", 20),
    value_width = nil,
    width = nil,
    height = nil,
    padding = Size.padding.default,
}

function BookDailyItem:init()
    self.dimen = Geom:new{x = 0, y = 0, w = self.width, h = self.height}
    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        }
    }
    self.ges_events.Hold = {
        GestureRange:new{
            ges = "hold",
            range = self.dimen,
        }
    }
    self.checkmark_widget = CheckMark:new{
        checked = self.item.checked,
    }
    local checked_widget = CheckMark:new{
        checked = true
    }

    local title_max_width = self.dimen.w - 2 * Size.padding.default - checked_widget:getSize().w  - self.value_width
    local fgcolor, bgcolor = unpack(SPAN_COLORS[(self.item.book_id % #SPAN_COLORS)+1])
    self.check_container = CenterContainer:new{
        dimen = Geom:new{ w = checked_widget:getSize().w },
        self.checkmark_widget,
    }
    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        focusable = true,
        focus_border_size = Size.border.thin,
        LeftContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = self.height,
            },
            HorizontalGroup:new{
                align = "center",
                self.check_container,
                CenterContainer:new{
                    dimen = Geom:new{ w = Size.padding.default, h = self.height },
                    HorizontalSpan:new{ w = Size.padding.default },
                },
                OverlapGroup:new{
                    dimen = Geom:new{ w = title_max_width, h = self.height},
                    allow_mirroring = false,
                    FrameContainer:new{
                        width = title_max_width,
                        height = self.height - 2 * Size.padding.small,
                        padding = 0,
                        padding_left = self.padding,
                        padding_right = self.padding,
                        background = bgcolor,
                        bordersize = Size.border.thin,
                        overlap_offset = { 0, Size.padding.small },
                        LeftContainer:new{
                            dimen = Geom:new{
                                w = title_max_width,
                                h = self.height - 2 * Size.padding.small,
                            },
                            TextWidget:new{
                                text = self.item[1],
                                max_width = title_max_width - 2 * self.padding,
                                face = self.face,
                                bgcolor = bgcolor,
                                fgcolor = fgcolor,
                                padding = 0,
                                bordersize = Size.border.thin,
                            }
                        }
                    }
                },
                FrameContainer:new{
                    width = self.value_width,
                    padding = 0,
                    padding_left = Size.padding.default,
                    bordersize = 0,
                    LeftContainer:new{
                        dimen = Geom:new{ w = self.value_width, h = self.height},
                        padding = 0,
                        TextWidget:new{
                            text = self.item[2],
                            max_width = self.value_width,
                            face = self.face
                        }
                    }
                }
            }
        }
    }
    checked_widget:free()
    self[1].invert = self.invert
end

function BookDailyItem:onTap(_, ges)
    local x_intersect = function()
        local dimen = self.checkmark_widget.dimen
        return ges.pos.x >= dimen.x - dimen.w and ges.pos.x <= dimen.x + 2 * dimen.w
    end
    if self.item.check_cb and x_intersect() then
        self.item:check_cb()
        self.checkmark_widget = CheckMark:new{
            checked = self.item.checked,
        }
        self.check_container[1] = self.checkmark_widget
        UIManager:setDirty(self, function()
            return "ui", self.check_container.dimen
        end)
    elseif self.item.callback then
        self.item:callback()
    end
    return true
end

function BookDailyItem:onHold()
    if self.item.hold_callback then
        self.item.hold_callback(self.show_parent, self.item)
    end
    return true
end

local CalendarDayView = FocusManager:extend{
    day_ts = nil,
    show_page = 1,
    kv_pairs = {},
    NB_VERTICAL_SEPARATORS_PER_HOUR = 6 -- one vertical line every 10 minutes
}

function CalendarDayView:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end
    self.ges_events.MultiSwipe = {
        GestureRange:new{
            ges = "multiswipe",
            range = self.dimen,
        }
    }
    self.outer_padding = Size.padding.large
    self.inner_padding = Size.padding.small
    local min_month = self.min_month or os.date("%Y-%m", self.reader_statistics:getFirstTimestamp() or os.time())
    self.min_ts = os.time({
        year = min_month:sub(1, 4),
        month = min_month:sub(6),
        day = 0
    })

    self.title_bar = TitleBar:new{
        fullscreen = true,
        width = self.dimen.w,
        align = "left",
        title = self.title or "Title",
        title_face = Font:getFace("smalltfont", 22),
        title_h_padding = self.outer_padding,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    self.titlebar_height = self.title_bar:getHeight()

    local padding = Size.padding.large
    local footer_width = self.dimen.w - 2 * padding
    self.footer_center_width = math.floor(footer_width * 0.32)
    self.footer_button_width = math.floor(footer_width * 0.10)

    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"

    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end

    self.footer_left = Button:new{
        icon = chevron_left,
        width = self.footer_button_width,
        callback = function() self:prevPage() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_right = Button:new{
        icon = chevron_right,
        width = self.footer_button_width,
        callback = function() self:nextPage() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_first_up = Button:new{
        icon = chevron_first,
        width = self.footer_button_width,
        callback = function()
            self:goToPage(1)
        end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_last_down = Button:new{
        icon = chevron_last,
        width = self.footer_button_width,
        callback = function()
            self:goToPage(self.pages)
        end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_page = Button:new{
        text = "",
        hold_input = {
            title = _("Enter page number"),
            input_type = "number",
            hint_func = function()
                return string.format("(1 - %s)", self.pages)
            end,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.pages then
                    self:goToPage(page)
                end
            end,
            ok_text = _("Go to page"),
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        margin = 0,
        text_font_face = "pgfont",
        text_font_bold = false,
        width = self.footer_center_width,
        show_parent = self,
    }
    self.page_info = HorizontalGroup:new{
        self.footer_first_up,
        self.footer_left,
        self.footer_page,
        self.footer_right,
        self.footer_last_down,
    }
    self.footer_height = self.page_info:getSize().h

    self.items_per_page = 5

    local temp_text = TextWidget:new{
        text = " ",
        face = BookDailyItem.face
    }
    self.book_item_height = temp_text:getSize().h + 2 * Size.padding.small
    temp_text:free()

    self.book_items = VerticalGroup:new{}
    self.timeline = OverlapGroup:new{
        dimen = self.dimen:copy(),
    }
    self.footer_container = BottomContainer:new{
        dimen = self.dimen:copy()
    }
    self:setupView()

    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = self.dimen:copy(),
            FrameContainer:new{
                height = self.dimen.h,
                padding = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                VerticalGroup:new{
                    self.title_bar,
                    self.book_items
                }
            },
            self.timeline,
            self.footer_container,
        }
    }
end

function CalendarDayView:setupView()
    local now = os.time()
    self.is_current_day = now >= self.day_ts and now < self.day_ts + 86400
    if self.is_current_day then
        local date = os.date("*t", now)
        self.current_day_hour = date.hour - (self.reader_statistics.settings.calendar_day_start_hour or 0)
        self.current_hour_second = date.min * 60 + date.sec - (self.reader_statistics.settings.calendar_day_start_minute or 0) * 60
        if self.current_hour_second < 0 then
            self.current_day_hour = self.current_day_hour - 1
            self.current_hour_second = 3600 + self.current_hour_second
        end
        if self.current_day_hour < 0 then
            -- showing previous day
            self.current_day_hour = self.current_day_hour + 24
        end
    end

    self.kv_pairs = self.reader_statistics:getBooksFromPeriod(self.day_ts, self.day_ts + 86400)
    local seconds_books = self.reader_statistics:getReadingDurationBySecond(self.day_ts)
    for _, kv in ipairs(self.kv_pairs) do
        if seconds_books[kv.book_id] then
            kv.periods = seconds_books[kv.book_id].periods
        end
        kv.checked = true
    end
    table.sort(self.kv_pairs, function(a,b) return a.duration > b.duration end) --sort by value
    self.title = self:getTitle()

    self.show_page = 1
    self.title_bar:setTitle(self.title)

    for _, kv in ipairs(self.kv_pairs) do
        kv.check_cb = function(this)
            this.checked = not this.checked
            self:refreshTimeline()
        end
    end

    local temp_check = CheckMark:new{ checked = true }
    self.time_text_width = temp_check:getSize().w + self.outer_padding + Size.padding.default
    temp_check:free()

    local font_size = TextWidget:getFontSizeToFitHeight("cfont", self.time_text_width, Size.padding.small)
    self.time_text_face = Font:getFace("cfont", font_size)
    local temp_text = TextWidget:new{
        text = "00:00",
        face = self.time_text_face
    }
    local time_text_width = temp_text:getSize().w
    while time_text_width > self.time_text_width * 0.8 do
        font_size = font_size * 0.8
        self.time_text_face = Font:getFace("cfont", font_size)
        temp_text:free()
        temp_text = TextWidget:new{
            text = "00:00",
            face = self.time_text_face
        }
        time_text_width = temp_text:getWidth()
    end
    temp_text:free()

    self.pages = #self.kv_pairs <= self.items_per_page+1 and 1 or math.ceil(#self.kv_pairs / self.items_per_page)
    self.footer_container[1] = self.pages > 1 and self.page_info or VerticalSpan:new{ w = 0 }

    self:_populateBooks()
end

function CalendarDayView:nextPage()
    local new_page = math.min(self.show_page+1, self.pages)
    if new_page > self.show_page then
        self.show_page = new_page
        self:_populateBooks()
        return true
    end
end

function CalendarDayView:prevPage()
    local new_page = math.max(self.show_page-1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        self:_populateBooks()
        return true
    end
end

function CalendarDayView:goToPage(page)
    self.show_page = page
    self:_populateBooks()
end

function CalendarDayView:onNextPage()
    if not self:nextPage() and self.day_ts + 82800 < os.time() then
        local current_day_ts = self.day_ts - (self.reader_statistics.settings.calendar_day_start_hour or 0) * 3600
                                           - (self.reader_statistics.settings.calendar_day_start_minute or 0) * 60
        local next_day_ts = current_day_ts + 86400 + 10800 -- make sure it's the next day
        local next_day_date = os.date("*t", next_day_ts)
        next_day_ts = os.time({
            year = next_day_date.year,
            month = next_day_date.month,
            day = next_day_date.day,
            hour = 0,
            min = 0,
        })
        local current_day_length = next_day_ts - current_day_ts
        if self.day_ts + current_day_length < os.time() then
            -- go to next day
            self.day_ts = self.day_ts + current_day_length
            self:setupView()
        end
    end
    return true
end

function CalendarDayView:onPrevPage()
    if not self:prevPage() and self.day_ts - 82800 >= self.min_ts then
        local current_day_ts = self.day_ts - (self.reader_statistics.settings.calendar_day_start_hour or 0) * 3600
                                           - (self.reader_statistics.settings.calendar_day_start_minute or 0) * 60
        local previous_day_ts = current_day_ts - 86400 + 10800 -- make sure it's the previous day
        local previous_day_date = os.date("*t", previous_day_ts)
        previous_day_ts = os.time({
            year = previous_day_date.year,
            month = previous_day_date.month,
            day = previous_day_date.day,
            hour = 0,
            min = 0,
        })
        local previous_day_length = current_day_ts - previous_day_ts
        if self.day_ts - previous_day_length >= self.min_ts then
            -- go to previous day
            self.day_ts = self.day_ts - previous_day_length
            self:setupView()
        end
    end
    return true
end

function CalendarDayView:_populateBooks()
    self.book_items:clear()
    self.layout = {}
    local idx_offset = (self.show_page - 1) * self.items_per_page
    local page_last = #self.kv_pairs
    if self.pages > 1 and idx_offset + self.items_per_page < #self.kv_pairs then
        page_last = idx_offset + self.items_per_page
    end

    local value_width = 0
    local value_text = TextWidget:new{
        text = "",
        face = BookDailyItem.face
    }
    for idx = idx_offset+1, page_last do
        value_text:setText( self.kv_pairs[idx][2] )
        value_width = math.max(value_width, value_text:getSize().w)
    end
    value_text:free()

    for idx = idx_offset+1, page_last do
        local item = BookDailyItem:new{
            item = self.kv_pairs[idx],
            width = self.dimen.w - 2 * self.outer_padding,
            value_width = value_width,
            height = self.book_item_height,
            show_parent = self,
        }
        table.insert(self.layout, { item })
        table.insert(self.book_items, item)
    end
    self.timeline_offset = self.titlebar_height + #self.book_items * self.book_item_height + Size.padding.default
    self.timeline_height = self.dimen.h - self.timeline_offset
    if self.pages > 1 then
        self.footer_page:setText(T(_("Page %1 of %2"), self.show_page, self.pages), self.footer_center_width)
        self.footer_page:enable()

        self.footer_left:enableDisable(self.show_page > 1)
        self.footer_right:enableDisable(self.show_page < self.pages)
        self.footer_first_up:enableDisable(self.show_page > 1)
        self.footer_last_down:enableDisable(self.show_page < self.pages)

        self.timeline_height = self.timeline_height - self.footer_height
    else
        self.timeline_height = self.timeline_height - Size.padding.default
    end
    self.hour_height = math.floor(self.timeline_height / 24)
    self.timeline_width = self.dimen.w - self.outer_padding - self.time_text_width

    if #self.kv_pairs == 0 then
        -- Needed when the first opened day has no data, then move to another day with data
        table.insert(self.book_items, CenterContainer:new{
            dimen = Geom:new { w = self.dimen.w - 2 * self.outer_padding, h = 0},
            VerticalSpan:new{ w = 0 }
        })
    end
    self:refreshTimeline()
end

function CalendarDayView:refreshTimeline()
    self.timeline:clear()

    -- Draw decorations first, so read spans can be drawn over them
    -- Vertical lines (first, so horizontal lines can override them if we use another color)
    for i=0, self.NB_VERTICAL_SEPARATORS_PER_HOUR do
        local offset_x = self.time_text_width + self.timeline_width * i / self.NB_VERTICAL_SEPARATORS_PER_HOUR
        table.insert(self.timeline, FrameContainer:new{
            width = Size.border.thin,
            height = 24 * self.hour_height, -- unscaled_size_check: ignore
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            bordersize = 0,
            padding = 0,
            overlap_offset = { offset_x, self.timeline_offset },
            VerticalSpan:new{ w = 0 }
        })
    end
    -- Hour indicator
    for i=0, 23 do
        local offset_y = self.timeline_offset + self.hour_height * i
        table.insert(self.timeline, FrameContainer:new{
            width = self.time_text_width,
            height = self.hour_height,
            margin = 0,
            padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            overlap_offset = {0, offset_y},
            CenterContainer:new{
                dimen = Geom:new{ w = self.time_text_width, h = self.hour_height},
                TextWidget:new{
                    text = string.format("%02d:%02d",
                        (i + (self.reader_statistics.settings.calendar_day_start_hour or 0)) % 24,
                        self.reader_statistics.settings.calendar_day_start_minute or 0
                    ),
                    face = self.time_text_face,
                    padding = Size.padding.small
                }
            }
        })
    end
    -- Horizontal lines
    local idx_00h00
    if self.reader_statistics.settings.calendar_day_start_hour and self.reader_statistics.settings.calendar_day_start_hour ~= 0 then
        idx_00h00 = 24 - self.reader_statistics.settings.calendar_day_start_hour
    end
    for i=0, 24 do
        local offset_y = self.timeline_offset + self.hour_height * i
        local height = Size.border.default
        if idx_00h00 and i == idx_00h00 then
            -- Thicker separator between 23:00 and 00:00
            offset_y = offset_y - math.floor(height/2) -- shift it a bit up
            height = height * 2
        end
        table.insert(self.timeline, FrameContainer:new{
            width = self.timeline_width,
            height = height,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            bordersize = 0,
            padding = 0,
            overlap_offset = { self.time_text_width, offset_y - Size.border.thin },
            CenterContainer:new{
                dimen = Geom:new{ w = self.timeline_width, h = Size.border.default },
                VerticalSpan:new{ w = 0 }
            }
        })
    end
    -- Current time arrow indicator
    if self.is_current_day then
        -- Get the arrow glyph a bit bigger than what it is with the hour indicator font
        local font_size = TextWidget:getFontSizeToFitHeight("cfont", self.hour_height*1.1, 0)
        local current_time_icon = TextWidget:new{
            text = "\u{25B2}", -- black up-pointing triangle
            face = Font:getFace("cfont", font_size),
            padding = 0,
        }
        local offset_x = self.time_text_width + math.floor( self.timeline_width * self.current_hour_second / 3600 - current_time_icon:getWidth()/2)
        local offset_y = self.timeline_offset + self.hour_height * (self.current_day_hour + 1)
        offset_y = offset_y - math.floor(self.hour_height*0.3) -- move it up so it sits over the horizontal line
        current_time_icon.overlap_offset = { offset_x, offset_y }
        table.insert(self.timeline, current_time_icon)
    end
    -- Finally, the read books spans
    for _, v in ipairs(self.kv_pairs) do
        if v.checked and v.periods then
            local fgcolor, bgcolor = unpack(SPAN_COLORS[(v.book_id % #SPAN_COLORS)+1])
            for _, period in ipairs(v.periods) do
                local start_hour = math.floor(period.start / 3600)
                local finish_hour = math.floor(period.finish / 3600)
                for i=0, finish_hour-start_hour do
                    local start = i==0 and period.start or (start_hour+i) * 3600
                    if start >= 24 * 3600 then
                        break
                    end
                    local finish = i==finish_hour-start_hour and period.finish or (start_hour+i+1) * 3600 - 1
                    local span = self:generateSpan(start, finish, bgcolor, fgcolor, v[1])
                    if span then table.insert(self.timeline, span) end
                end
            end
        end
    end
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function CalendarDayView:generateSpan(start, finish, bgcolor, fgcolor, title)
    local width = math.floor((finish - start)/3600*self.timeline_width)
    if width <= 0 then return end
    local start_hour = math.floor(start / 3600)
    local offset_y = start_hour * self.hour_height + self.inner_padding + self.timeline_offset
    local offset_x = self.time_text_width + math.floor((start % 3600) / 3600 * self.timeline_width)

    local font_size = TextWidget:getFontSizeToFitHeight("cfont", self.hour_height - 2 * self.inner_padding, 0.3)
    local min_width = TextWidget:new{
        text = "…",
        face = Font:getFace("cfont", font_size),
        padding = 0.3
    }:getWidth()
    return FrameContainer:new{
        width = width,
        height = self.hour_height - 2 * self.inner_padding,
        bordersize = Size.border.thin,
        overlap_offset = {offset_x, offset_y},
        background = bgcolor,
        padding = 0.3,
        CenterContainer:new{
            dimen = Geom:new{ h = self.hour_height - 2 * self.inner_padding, w = width },
            width > min_width and TextWidget:new{
                text = title,
                face = Font:getFace("cfont", font_size),
                padding = 0,
                fgcolor = fgcolor,
                max_width = width
            } or HorizontalSpan:new{ w = 0 },
        }
    }
end

function CalendarDayView:removeKeyValueItem(item)
    for i, v in ipairs(self.kv_pairs) do
        if v.book_id == item.book_id then
            table.remove(self.kv_pairs, i)
            self:_populateBooks()
            break
        end
    end
end

function CalendarDayView:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
    elseif direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function CalendarDayView:onMultiSwipe(arg, ges_ev)
    self:onClose()
    return true
end

function CalendarDayView:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
    if self.close_callback then
        self:close_callback()
    end
    return true
end

-- Fetched from db, cached as local as it might be expensive
local MIN_MONTH = nil

local CalendarView = FocusManager:extend{
    reader_statistics = nil,
    start_day_of_week = 2, -- 2 = Monday, 1-7 = Sunday-Saturday
    show_hourly_histogram = true,
    browse_future_months = false,
    nb_book_spans = 3,
    font_face = "xx_smallinfofont",
    title = "",
    width = nil,
    height = nil,
    cur_month = nil,
    weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" } -- in Lua wday order
        -- (These do not need translations: they are the keys into the datetime module translations)
}

function CalendarDayView:getTitle()
    local day_ts = self.day_ts - (self.reader_statistics.settings.calendar_day_start_hour or 0) * 3600
                               - (self.reader_statistics.settings.calendar_day_start_minute or 0) * 60
    local day = os.date("%Y-%m-%d", day_ts + 10800) -- use 03:00 to determine date (summer time change)
    local date = os.date("*t", day_ts + 10800)
    return string.format("%s (%s)", day, datetime.shortDayOfWeekToLongTranslation[CalendarView.weekdays[date.wday]])

end

function CalendarView:init()
    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }
    if self.dimen.w == Screen:getWidth() and self.dimen.h == Screen:getHeight() then
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.NextMonth = { { Input.group.PgFwd } }
        self.key_events.PrevMonth = { { Input.group.PgBack } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = self.dimen,
            }
        }
    end

    self.outer_padding = Size.padding.large
    self.inner_padding = Size.padding.small

    -- 7 days in a week
    self.day_width = math.floor((self.dimen.w - 2*self.outer_padding - 6*self.inner_padding) * (1/7))
    -- Put back the possible 7px lost in rounding into outer_padding
    self.outer_padding = math.floor((self.dimen.w - 7*self.day_width - 6*self.inner_padding) * (1/2))

    self.content_width = self.dimen.w - 2*self.outer_padding

    local now_ts = os.time()
    if not MIN_MONTH then
        local min_ts = self.reader_statistics:getFirstTimestamp()
        if not min_ts then min_ts = now_ts end
        MIN_MONTH = os.date("%Y-%m", min_ts)
    end
    self.min_month = MIN_MONTH
    self.max_month = os.date("%Y-%m", now_ts)
    if not self.cur_month then
        self.cur_month = self.max_month
    end

    -- group for page info
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.page_info_left_chev = Button:new{
        icon = chevron_left,
        callback = function() self:prevMonth() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_right_chev = Button:new{
        icon = chevron_right,
        callback = function() self:nextMonth() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_first_chev = Button:new{
        icon = chevron_first,
        callback = function() self:goToMonth(self.min_month) end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_last_chev = Button:new{
        icon = chevron_last,
        callback = function() self:goToMonth(self.max_month) end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(32),
    }

    self.page_info_text = Button:new{
        text = "",
        hold_input = {
            title = _("Enter month"),
            input_func = function() return self.cur_month end,
            callback = function(input)
                local year, month = input:match("^(%d%d%d%d)-(%d%d)$")
                if year and month then
                    if tonumber(month) >= 1 and tonumber(month) <= 12 and tonumber(year) >= 1000 then
                        -- Allow seeing arbitrary year-month in the past or future by
                        -- not constraining to self.min_month/max_month.
                        -- (year >= 1000 to ensure %Y keeps returning 4 digits)
                        self:goToMonth(input)
                        return
                    end
                end
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("Invalid year-month string (YYYY-MM)"),
                })
            end,
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        text_font_face = "pgfont",
        text_font_bold = false,
    }
    self.page_info = HorizontalGroup:new{
        self.page_info_first_chev,
        self.page_info_spacer,
        self.page_info_left_chev,
        self.page_info_spacer,
        self.page_info_text,
        self.page_info_spacer,
        self.page_info_right_chev,
        self.page_info_spacer,
        self.page_info_last_chev,
    }

    local footer = BottomContainer:new{
        -- (BottomContainer does horizontal centering)
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.dimen.h,
        },
        self.page_info,
    }

    self.title_bar = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        width = self.dimen.w,
        align = "left",
        title = self.title,
        title_h_padding = self.outer_padding, -- have month name aligned with calendar left edge
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    -- week days names header
    self.day_names = HorizontalGroup:new{}
    table.insert(self.day_names, HorizontalSpan:new{ width = self.outer_padding })
    for i = 0, 6 do
        local dayname = TextWidget:new{
            text = datetime.shortDayOfWeekTranslation[self.weekdays[(self.start_day_of_week-1+i)%7 + 1]],
            face = Font:getFace("xx_smallinfofont"),
            bold = true,
        }
        table.insert(self.day_names, FrameContainer:new{
            padding = 0,
            bordersize = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = self.day_width, h = dayname:getSize().h },
                dayname,
            }
        })
        if i < 6 then
            table.insert(self.day_names, HorizontalSpan:new{ width = self.inner_padding, })
        end
    end

    -- At most 6 weeks in a month
    local available_height = self.dimen.h - self.title_bar:getHeight()
                            - self.page_info:getSize().h - self.day_names:getSize().h
    self.week_height = math.floor((available_height - 7*self.inner_padding) * (1/6))
    self.day_border = Size.border.default
    if self.show_hourly_histogram then
        -- day num + nb_book_spans + histogram: ceil() as histogram rarely
        -- reaches 100% and is stuck to bottom
        self.span_height = math.ceil((self.week_height - 2*self.day_border) / (self.nb_book_spans+2))
    else
        -- day num + nb_book_span: floor() to get some room for bottom padding
        self.span_height = math.floor((self.week_height - 2*self.day_border) / (self.nb_book_spans+1))
    end
    -- Limit font size to 1/3 of available height, and so that
    -- the day number and the +nb-not-shown do not overlap
    local text_height = math.min(self.span_height, self.week_height/3)
    self.span_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.3)
    local day_inner_width = self.day_width - 2*self.day_border -2*self.inner_padding
    while true do
        local test_w = TextWidget:new{
            text = " 30 + 99 ", -- we want this to be displayed in the available width
            face = Font:getFace(self.font_face, self.span_font_size),
            bold = true,
        }
        if test_w:getWidth() <= day_inner_width then
            test_w:free()
            break
        end
        self.span_font_size = self.span_font_size - 1
        test_w:free()
    end

    self.main_content = VerticalGroup:new{}
    self:_populateItems()

    local content = OverlapGroup:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.dimen.h,
        },
        allow_mirroring = false,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            self.day_names,
            HorizontalGroup:new{
                HorizontalSpan:new{ width = self.outer_padding },
                self.main_content,
            },
        },
        footer,
    }
    -- assemble page
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content
    }
end

function CalendarView:_populateItems()
    self.layout = {}
    self.page_info:resetLayout()
    self.main_content:clear()

    -- See https://www.lua.org/pil/22.1.html for info about os.time() and os.date()
    local month_start_ts = os.time({
        year = self.cur_month:sub(1,4),
        month = self.cur_month:sub(6),
        day = 1,
        -- When hour is unspecified, Lua defaults to noon 12h00
    })
    -- Update title
    local month_text = datetime.longMonthTranslation[os.date("%B", month_start_ts)] .. os.date(" %Y", month_start_ts)
    self.title_bar:setTitle(month_text)
    -- Update footer
    self.page_info_text:setText(self.cur_month)
    self.page_info_left_chev:enableDisable(self.cur_month > self.min_month)
    self.page_info_right_chev:enableDisable(self.cur_month < self.max_month or self.browse_future_months)
    self.page_info_first_chev:enableDisable(self.cur_month > self.min_month)
    self.page_info_last_chev:enableDisable(self.cur_month < self.max_month or self.browse_future_months)

    local ratio_per_hour_by_day = self.reader_statistics:getReadingRatioPerHourByDay(self.cur_month)
    local books_by_day = self.reader_statistics:getReadBookByDay(self.cur_month)

    table.insert(self.main_content, VerticalSpan:new{ width = self.inner_padding })
    self.weeks = {}
    local today_s = os.date("%Y-%m-%d", os.time())
    local cur_ts = month_start_ts
    local cur_date = os.date("*t", cur_ts)
    local this_month = cur_date.month
    local cur_week
    local layout_row
    while true do
        cur_date = os.date("*t", cur_ts)
        if cur_date.month ~= this_month then
            break
        end
        if not cur_week or cur_date.wday == self.start_day_of_week then
            if cur_week then
                table.insert(self.main_content, VerticalSpan:new{ width = self.inner_padding })
            end
            cur_week = CalendarWeek:new{
                height = self.week_height,
                width = self.content_width,
                day_width = self.day_width,
                day_padding = self.inner_padding,
                day_border = self.day_border,
                nb_book_spans = self.nb_book_spans,
                histo_shown = self.show_hourly_histogram,
                span_height = self.span_height,
                font_face = self.font_face,
                font_size = self.span_font_size,
                show_parent = self,
            }
            layout_row = {}
            table.insert(self.layout, layout_row)
            table.insert(self.weeks, cur_week)
            table.insert(self.main_content, cur_week)
            if cur_date.wday ~= self.start_day_of_week then
                -- Add fake days to fill week
                local day = self.start_day_of_week
                while day ~= cur_date.wday do
                    cur_week:addDay(CalendarDay:new{
                        filler = true,
                        height = self.week_height,
                        width = self.day_width,
                        border = self.day_border,
                        show_parent = self,
                    })
                    day = day + 1
                    if day == 8 then
                        day = 1
                    end
                end
            end
        end
        local day_s = os.date("%Y-%m-%d", cur_ts)
        local day_ts = os.time({
            year = cur_date.year,
            month = cur_date.month,
            day = cur_date.day,
            hour = 0,
        })
        local is_future = day_s > today_s
        local calendar_day = CalendarDay:new{
            show_histo = self.show_hourly_histogram,
            histo_height = self.span_height,
            font_face = self.font_face,
            font_size = self.span_font_size,
            border = self.day_border,
            is_future = is_future,
            daynum = cur_date.day,
            height = self.week_height,
            width = self.day_width,
            ratio_per_hour = ratio_per_hour_by_day[day_s],
            read_books = books_by_day[day_s],
            show_parent = self,
            callback = not is_future and function()
                UIManager:show(CalendarDayView:new{
                    day_ts = day_ts + (self.reader_statistics.settings.calendar_day_start_hour or 0) * 3600
                                    + (self.reader_statistics.settings.calendar_day_start_minute or 0) * 60,
                    reader_statistics = self.reader_statistics,
                    close_callback = function(this)
                        -- Refresh calendar in case some day stats were reset for some books
                        -- (we don't know if some reset were done... so we refresh the current
                        -- display always - at tickAfterNext so there is no noticeable slowness
                        -- when closing, and the re-painting happening after is not noticeable;
                        -- but if some stat reset were done, this will make a nice noticeable
                        -- repainting showing dynamically reset books disappearing :)
                        UIManager:tickAfterNext(function()
                            self:goToMonth(os.date("%Y-%m", this.day_ts + 10800))
                        end)
                    end,
                    min_month = self.min_month
                })
            end
        }
        cur_week:addDay(calendar_day)
        table.insert(layout_row, calendar_day)
        cur_ts = cur_ts + 86400 -- add one day
    end
    for _, week in ipairs(self.weeks) do
        week:update()
    end
    self:moveFocusTo(1, 1, bit.bor(FocusManager.FOCUS_ONLY_ON_NT, FocusManager.NOT_UNFOCUS))
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function CalendarView:showCalendarDayView(reader_statistics)
    local date = os.date("*t", os.time())
    if date.hour * 3600 + date.min * 60 + date.sec < (reader_statistics.settings.calendar_day_start_hour or 0) * 3600
                                                  + (reader_statistics.settings.calendar_day_start_minute or 0) * 60 then
        -- Should still be in previous day's timeline
        date = os.date("*t", os.time() - 86400 + 10800) -- make sure it's the previous day
    end
    UIManager:show(CalendarDayView:new{
        day_ts = os.time({ year = date.year, month = date.month, day = date.day, hour = reader_statistics.settings.calendar_day_start_hour or 0, min = reader_statistics.settings.calendar_day_start_minute or 0 }),
        reader_statistics = reader_statistics,
        min_month = self.min_month
    })
end

function CalendarView:nextMonth()
    local t = os.time({
        year = self.cur_month:sub(1,4),
        month = self.cur_month:sub(6),
        day = 15,
    })
    t = t + 86400 * 30 -- 30 days later
    local next_month = os.date("%Y-%m", t)
    if self.browse_future_months or next_month <= self.max_month then
        self.cur_month = next_month
        self:_populateItems()
    end
end

function CalendarView:prevMonth()
    local t = os.time({
        year = self.cur_month:sub(1,4),
        month = self.cur_month:sub(6),
        day = 15,
    })
    t = t - 86400 * 30 -- 30 days before
    local prev_month = os.date("%Y-%m", t)
    if prev_month >= self.min_month then
        self.cur_month = prev_month
        self:_populateItems()
    end
end

function CalendarView:goToMonth(month)
    self.cur_month = month
    self:_populateItems()
end

function CalendarView:onNextMonth()
    self:nextMonth()
    return true
end

function CalendarView:onPrevMonth()
    self:prevMonth()
    return true
end

function CalendarView:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:nextMonth()
        return true
    elseif direction == "east" then
        self:prevMonth()
        return true
    elseif direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function CalendarView:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function CalendarView:onClose()
    UIManager:close(self)
    -- Remove ghosting
    UIManager:setDirty(nil, "full")
    return true
end

return CalendarView
