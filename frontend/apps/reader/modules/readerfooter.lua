local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

local MODE = {
    off = 0,
    page_progress = 1,
    pages_left_book = 2,
    time = 3,
    pages_left = 4,
    battery = 5,
    percentage = 6,
    book_time_to_read = 7,
    chapter_time_to_read = 8,
    frontlight = 9,
    mem_usage = 10,
    wifi_status = 11,
    book_title = 12,
    book_chapter = 13,
    bookmark_count = 14,
    chapter_progress = 15,
}

local symbol_prefix = {
    letters = {
        time = nil,
        pages_left_book = "->",
        pages_left = "=>",
        -- @translators This is the footer letter prefix for battery % remaining.
        battery = C_("FooterLetterPrefix", "B:"),
        -- @translators This is the footer letter prefix for the number of bookmarks (bookmark count).
        bookmark_count = C_("FooterLetterPrefix", "BM:"),
        -- @translators This is the footer letter prefix for percentage read.
        percentage = C_("FooterLetterPrefix", "R:"),
        -- @translators This is the footer letter prefix for book time to read.
        book_time_to_read = C_("FooterLetterPrefix", "TB:"),
        -- @translators This is the footer letter prefix for chapter time to read.
        chapter_time_to_read = C_("FooterLetterPrefix", "TC:"),
        -- @translators This is the footer letter prefix for frontlight level.
        frontlight = C_("FooterLetterPrefix", "L:"),
        -- @translators This is the footer letter prefix for memory usage.
        mem_usage = C_("FooterLetterPrefix", "M:"),
        -- @translators This is the footer letter prefix for Wi-Fi status.
        wifi_status = C_("FooterLetterPrefix", "W:"),
    },
    icons = {
        time = "⌚",
        pages_left_book = BD.mirroredUILayout() and "↢" or "↣",
        pages_left = BD.mirroredUILayout() and "⇐" or "⇒",
        battery = "",
        bookmark_count = "☆",
        percentage = BD.mirroredUILayout() and "⤟" or "⤠",
        book_time_to_read = "⏳",
        chapter_time_to_read = BD.mirroredUILayout() and "⥖" or "⤻",
        frontlight = "☼",
        mem_usage = "",
        wifi_status = "",
        wifi_status_off = "",
    },
    compact_items = {
        time = nil,
        pages_left_book = BD.mirroredUILayout() and "‹" or "›",
        pages_left = BD.mirroredUILayout() and "‹" or "›",
        battery = "",
        -- @translators This is the footer compact item prefix for the number of bookmarks (bookmark count).
        bookmark_count = C_("FooterCompactItemsPrefix", "BM"),
        percentage = nil,
        book_time_to_read = nil,
        chapter_time_to_read = BD.mirroredUILayout() and "«" or "»",
        frontlight = "*",
        -- @translators This is the footer compact item prefix for memory usage.
        mem_usage = C_("FooterCompactItemsPrefix", "M"),
        wifi_status = "",
        wifi_status_off = "",
    }
}
if BD.mirroredUILayout() then
    -- We need to RTL-wrap these letters and symbols for proper layout
    for k, v in pairs(symbol_prefix.letters) do
        local colon = v:find(":")
        local wrapped
        if colon then
            local pre = v:sub(1, colon-1)
            local post = v:sub(colon)
            wrapped = BD.wrap(pre) .. BD.wrap(post)
        else
            wrapped = BD.wrap(v)
        end
        symbol_prefix.letters[k] = wrapped
    end
    for k, v in pairs(symbol_prefix.icons) do
        symbol_prefix.icons[k] = BD.wrap(v)
    end
end

local PROGRESS_BAR_STYLE_THICK_DEFAULT_HEIGHT = 7
local PROGRESS_BAR_STYLE_THIN_DEFAULT_HEIGHT = 3

-- android: guidelines for rounded corner margins
local material_pixels = 16 * math.floor(Screen:getDPI() / 160)

-- functions that generates footer text for each mode
local footerTextGeneratorMap = {
    empty = function() return "" end,
    frontlight = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].frontlight
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            if Device:isCervantes() or Device:isKobo() then
                return (prefix .. " %d%%"):format(powerd:frontlightIntensity())
            else
                return (prefix .. " %d"):format(powerd:frontlightIntensity())
            end
        else
            if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                return ""
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    battery = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].battery
        local powerd = Device:getPowerDevice()
        local batt_lvl = powerd:getCapacity()
        if footer.settings.all_at_once and batt_lvl > footer.settings.battery_hide_threshold then
            return ""
        end
        -- If we're using icons, use fancy variable icons
        if symbol_type == "icons" or symbol_type == "compact_items" then
            if powerd:isCharging() then
                prefix = ""
            else
                if batt_lvl >= 100 then
                    prefix = ""
                elseif batt_lvl >= 90 then
                    prefix = ""
                elseif batt_lvl >= 80 then
                    prefix = ""
                elseif batt_lvl >= 70 then
                    prefix = ""
                elseif batt_lvl >= 60 then
                    prefix = ""
                elseif batt_lvl >= 50 then
                    prefix = ""
                elseif batt_lvl >= 40 then
                    prefix = ""
                elseif batt_lvl >= 30 then
                    prefix = ""
                elseif batt_lvl >= 20 then
                    prefix = ""
                elseif batt_lvl >= 10 then
                    prefix = ""
                else
                    prefix = ""
                end
            end
            if symbol_type == "compact_items" then
                return BD.wrap(prefix)
            else
                return BD.wrap(prefix) .. batt_lvl .. "%"
            end
        else
            return BD.wrap(prefix) .. " " .. (powerd:isCharging() and "+" or "") .. batt_lvl .. "%"
        end
    end,
    bookmark_count = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].bookmark_count
        local bookmark_count = footer.ui.bookmark:getNumberOfBookmarks()
        if footer.settings.all_at_once and footer.settings.hide_empty_generators and bookmark_count == 0 then
            return ""
        end
        return prefix .. " " .. tostring(bookmark_count)
    end,
    time = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].time
        local clock = util.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        if not prefix then
            return clock
        else
            return prefix .. " " .. clock
        end
    end,
    page_progress = function(footer)
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                return ("%s / %s"):format(footer.ui.pagemap:getCurrentPageLabel(true),
                                          footer.ui.pagemap:getLastPageLabel(true))
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                if flow == 0 then
                    return ("%d // %d"):format(page, pages)
                else
                    return ("[%d / %d]%d"):format(page, pages, flow)
                end
            else
                return ("%d / %d"):format(footer.pageno, footer.pages)
            end
        elseif footer.position then
            return ("%d / %d"):format(footer.position, footer.doc_height)
        end
    end,
    pages_left_book = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].pages_left_book
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                return ("%s %s / %s"):format(prefix,
                                          footer.ui.pagemap:getCurrentPageLabel(true),
                                          footer.ui.pagemap:getLastPageLabel(true))
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                local remaining = pages - page;
                if flow == 0 then
                    return ("%s %d // %d"):format(prefix, remaining, pages)
                else
                    return ("%s [%d / %d]%d"):format(prefix, remaining, pages, flow)
                end
            else
                local remaining = footer.pages - footer.pageno
                return ("%s %d / %d"):format(prefix, remaining, footer.pages)
            end
        elseif footer.position then
            return ("%s %d / %d"):format(prefix, footer.doc_height - footer.position, footer.doc_height)
        end
    end,
    pages_left = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].pages_left
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        return prefix .. " " .. left
    end,
    chapter_progress = function(footer)
        local current = footer.ui.toc:getChapterPagesDone(footer.pageno)
        -- We want a page number, not a page read count
        if current then
            current = current + 1
        else
            current = footer.pageno
        end
        local total = footer.ui.toc:getChapterPageCount(footer.pageno) or footer.pages
        return current .. " ⁄⁄ " .. total
    end,
    percentage = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].percentage
        local digits = footer.settings.progress_pct_format
        local string_percentage = "%." .. digits .. "f%%"
        if footer.ui.document:hasHiddenFlows() then
            local flow = footer.ui.document:getPageFlow(footer.pageno)
            if flow ~= 0 then
                string_percentage = "[" .. string_percentage .. "]"
            end
        end
        if prefix then
            string_percentage = prefix .. " " .. string_percentage
        end
        return string_percentage:format(footer.progress_bar.percentage * 100)
    end,
    book_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].book_time_to_read
        local left = footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics(prefix and (prefix .. " ") or "", left)
    end,
    chapter_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].chapter_time_to_read
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics(
            prefix .. " ", left)
    end,
    mem_usage = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].mem_usage
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local dummy, rss = statm:read("*number", "*number")
            statm:close()
            -- we got the nb of 4Kb-pages used, that we convert to Mb
            rss = math.floor(rss * 4096 / 1024 / 1024)
            return (prefix .. " %d"):format(rss)
        end
        return ""
    end,
    wifi_status = function(footer)
        -- NOTE: This one deviates a bit from the mold because, in icons mode, we simply use two different icons and no text.
        local symbol_type = footer.settings.item_prefix
        local NetworkMgr = require("ui/network/manager")
        if symbol_type == "icons" or symbol_type == "compact_items" then
            if NetworkMgr:isWifiOn() then
                return symbol_prefix.icons.wifi_status
            else
                if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                    return ""
                else
                    return symbol_prefix.icons.wifi_status_off
                end
            end
        else
            local prefix = symbol_prefix[symbol_type].wifi_status
            if NetworkMgr:isWifiOn() then
                return T(_("%1 On"), prefix)
            else
                if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                    return ""
                else
                    return T(_("%1 Off"), prefix)
                end
            end
        end
    end,
    book_title = function(footer)
        local doc_info = footer.ui.document:getProps()
        if doc_info and doc_info.title then
            local title = doc_info.title:gsub(" ", "\xC2\xA0") -- replace space with no-break-space
            local title_widget = TextWidget:new{
                text = title,
                max_width = footer._saved_screen_width * footer.settings.book_title_max_width_pct / 100,
                face = Font:getFace(footer.text_font_face, footer.settings.text_font_size),
                bold = footer.settings.text_font_bold,
            }
            local fitted_title_text, add_ellipsis = title_widget:getFittedText()
            title_widget:free()
            if add_ellipsis then
                fitted_title_text = fitted_title_text .. "…"
            end
            return BD.auto(fitted_title_text)
        else
            return ""
        end
    end,
    book_chapter = function(footer)
        local chapter_title = footer.ui.toc:getTocTitleByPage(footer.pageno)
        if chapter_title and chapter_title ~= "" then
            chapter_title = chapter_title:gsub(" ", "\xC2\xA0") -- replace space with no-break-space
            local chapter_widget = TextWidget:new{
                text = chapter_title,
                max_width = footer._saved_screen_width * footer.settings.book_chapter_max_width_pct / 100,
                face = Font:getFace(footer.text_font_face, footer.settings.text_font_size),
                bold = footer.settings.text_font_bold,
            }
            local fitted_chapter_text, add_ellipsis = chapter_widget:getFittedText()
            chapter_widget:free()
            if add_ellipsis then
                fitted_chapter_text = fitted_chapter_text .. "…"
            end
            return BD.auto(fitted_chapter_text)
        else
            return ""
        end
    end
}

local ReaderFooter = WidgetContainer:extend{
    mode = MODE.page_progress,
    pageno = nil,
    pages = nil,
    progress_percentage = 0.0,
    footer_text = nil,
    text_font_face = "ffont",
    height = Screen:scaleBySize(DMINIBAR_CONTAINER_HEIGHT),
    horizontal_margin = Size.span.horizontal_default,
    bottom_padding = Size.padding.tiny,
    settings = {},
    -- added to expose them to unit tests
    textGeneratorMap = footerTextGeneratorMap,
}

-- NOTE: This is used in a migration script by ui/data/onetime_migration,
--       which is why it's public.
ReaderFooter.default_settings = {
    disable_progress_bar = false, -- enable progress bar by default
    disabled = false,
    all_at_once = false,
    reclaim_height = false,
    toc_markers = true,
    page_progress = true,
    pages_left_book = false,
    time = true,
    pages_left = true,
    battery = Device:hasBattery(),
    battery_hide_threshold = 100,
    percentage = true,
    book_time_to_read = true,
    chapter_time_to_read = true,
    frontlight = false,
    mem_usage = false,
    wifi_status = false,
    book_title = false,
    book_chapter = false,
    bookmark_count = false,
    chapter_progress = false,
    item_prefix = "icons",
    toc_markers_width = 2, -- unscaled_size_check: ignore
    text_font_size = 14, -- unscaled_size_check: ignore
    text_font_bold = false,
    container_height = DMINIBAR_CONTAINER_HEIGHT,
    container_bottom_padding = 1, -- unscaled_size_check: ignore
    progress_margin_width = Screen:scaleBySize(Device:isAndroid() and material_pixels or 10), -- default margin (like self.horizontal_margin)
    progress_bar_min_width_pct = 20,
    book_title_max_width_pct = 30,
    book_chapter_max_width_pct = 30,
    skim_widget_on_hold = false,
    progress_style_thin = false,
    progress_bar_position = "alongside",
    bottom_horizontal_separator = false,
    align = "center",
    auto_refresh_time = false,
    progress_style_thin_height = PROGRESS_BAR_STYLE_THIN_DEFAULT_HEIGHT,
    progress_style_thick_height = PROGRESS_BAR_STYLE_THICK_DEFAULT_HEIGHT,
    hide_empty_generators = false,
    lock_tap = false,
    items_separator = "bar",
    progress_pct_format = "0",
    progress_margin = false,
}

function ReaderFooter:init()
    self.settings = G_reader_settings:readSetting("footer", self.default_settings)

    -- Remove items not supported by the current device
    if not Device:hasFastWifiStatusQuery() then
        MODE.wifi_status = nil
    end
    if not Device:hasFrontlight() then
        MODE.frontlight = nil
    end
    if not Device:hasBattery() then
        MODE.battery = nil
    end

    -- self.mode_index will be an array of MODE names, with an additional element
    -- with key 0 for "off", which feels a bit strange but seems to work...
    -- (The same is true for self.settings.order which is saved in settings.)
    self.mode_index = {}
    self.mode_nb = 0

    local handled_modes = {}
    if self.settings.order then
        -- Start filling self.mode_index from what's been ordered by the user and saved
        for i=0, #self.settings.order do
            local name = self.settings.order[i]
            -- (if name has been removed from our supported MODEs: ignore it)
            if MODE[name] then -- this mode still exists
                self.mode_index[self.mode_nb] = name
                self.mode_nb = self.mode_nb + 1
                handled_modes[name] = true
            end
        end
        -- go on completing it with remaining new modes in MODE
    end
    -- If no previous self.settings.order, fill mode_index with what's in MODE
    -- in the original indices order
    local orig_indexes = {}
    local orig_indexes_to_name = {}
    for name, orig_index in pairs(MODE) do
        if not handled_modes[name] then
            table.insert(orig_indexes, orig_index)
            orig_indexes_to_name[orig_index] = name
        end
    end
    table.sort(orig_indexes)
    for i = 1, #orig_indexes do
        self.mode_index[self.mode_nb] = orig_indexes_to_name[orig_indexes[i]]
        self.mode_nb = self.mode_nb + 1
    end
    -- require("logger").dbg(self.mode_nb, self.mode_index)

    -- Container settings
    self.height = Screen:scaleBySize(self.settings.container_height)
    self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)

    self.mode_list = {}
    for i = 0, #self.mode_index do
        self.mode_list[self.mode_index[i]] = i
    end
    if self.settings.disabled then
        -- footer feature is completely disabled, stop initialization now
        self:disableFooter()
        return
    end

    self.pageno = self.view.state.page
    self.has_no_mode = true
    self.reclaim_height = self.settings.reclaim_height
    for _, m in ipairs(self.mode_index) do
        if self.settings[m] then
            self.has_no_mode = false
            break
        end
    end

    self.footer_text = TextWidget:new{
        text = '',
        face = Font:getFace(self.text_font_face, self.settings.text_font_size),
        bold = self.settings.text_font_bold,
    }
    -- all width related values will be initialized in self:resetLayout()
    self.text_width = 0
    self.footer_text.height = 0
    self.progress_bar = ProgressWidget:new{
        width = nil,
        height = nil,
        percentage = self.progress_percentage,
        tick_width = Screen:scaleBySize(self.settings.toc_markers_width),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }

    if self.settings.progress_style_thin then
        self.progress_bar:updateStyle(false, nil)
    end

    self.text_container = RightContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.footer_text,
    }
    self:updateFooterContainer()
    self.mode = G_reader_settings:readSetting("reader_footer_mode") or self.mode
    if self.has_no_mode and self.settings.disable_progress_bar then
        self.mode = self.mode_list.off
        self.view.footer_visible = false
        self:resetLayout()
        self.footer_text.height = 0
    end
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
        self:updateFooterTextGenerator()
        if self.settings.progress_bar_position ~= "alongside" and self.has_no_mode then
            self.footer_text.height = 0
        end
    else
        self:applyFooterMode()
    end

    self.visibility_change = nil
end

function ReaderFooter:updateFooterContainer()
    local margin_span = HorizontalSpan:new{ width = self.horizontal_margin }
    self.vertical_frame = VerticalGroup:new{}
    if self.settings.bottom_horizontal_separator then
        self.separator_line = LineWidget:new{
            dimen = Geom:new{
                w = 0,
                h = Size.line.medium,
            }
        }
        local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}
        table.insert(self.vertical_frame, self.separator_line)
        table.insert(self.vertical_frame, vertical_span)
    end
    if self.settings.progress_bar_position ~= "alongside" and not self.settings.disable_progress_bar then
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.text_container,
            margin_span,
        }
    else
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.progress_bar,
            self.text_container,
            margin_span,
        }
    end

    if self.settings.align == "left" then
        self.footer_container = LeftContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    elseif self.settings.align == "right" then
        self.footer_container = RightContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    else
        self.footer_container = CenterContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    end

    local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}

    if self.settings.progress_bar_position == "above" and not self.settings.disable_progress_bar then
        table.insert(self.vertical_frame, self.progress_bar)
        table.insert(self.vertical_frame, vertical_span)
        table.insert(self.vertical_frame, self.footer_container)
    elseif self.settings.progress_bar_position == "below" and not self.settings.disable_progress_bar then
        table.insert(self.vertical_frame, self.footer_container)
        table.insert(self.vertical_frame, vertical_span)
        table.insert(self.vertical_frame, self.progress_bar)
    else
        table.insert(self.vertical_frame, self.footer_container)
    end
    self.footer_content = FrameContainer:new{
        self.vertical_frame,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self.footer_positioner = BottomContainer:new{
        dimen = Geom:new{},
        self.footer_content,
    }
    self[1] = self.footer_positioner
end

function ReaderFooter:unscheduleFooterAutoRefresh()
    if not self.autoRefreshFooter then return end -- not yet set up
    UIManager:unschedule(self.autoRefreshFooter)
    logger.dbg("ReaderFooter.autoRefreshFooter unscheduled")
end

function ReaderFooter:rescheduleFooterAutoRefreshIfNeeded()
    if not self.autoRefreshFooter then
        -- Create this function the first time we're called
        self.autoRefreshFooter = function()
            -- Only actually repaint the footer if nothing's being shown over ReaderUI (#6616)
            -- (We want to avoid the footer to be painted over a widget covering it - we would
            -- be fine refreshing it if the widget is not covering it, but this is hard to
            -- guess from here.)
            if UIManager:getTopWidget() == "ReaderUI" then
                self:onUpdateFooter(self.view.footer_visible)
            else
                logger.dbg("Skipping ReaderFooter repaint, because ReaderUI is not the top-level widget")
                -- NOTE: We *do* keep its content up-to-date, though
                self:onUpdateFooter()
            end
            self:rescheduleFooterAutoRefreshIfNeeded() -- schedule (or not) next refresh
        end
    end
    local unscheduled = UIManager:unschedule(self.autoRefreshFooter) -- unschedule if already scheduled
    -- Only schedule an update if the footer has items that may change
    -- As self.view.footer_visible may be temporarily toggled off by other modules,
    -- we can't trust it for not scheduling auto refresh
    local schedule = false
    if self.settings.auto_refresh_time then
        if self.settings.all_at_once then
            if self.settings.time or self.settings.battery or self.settings.wifi_status or self.settings.mem_usage then
                schedule = true
            end
        else
            if self.mode == self.mode_list.time or self.mode == self.mode_list.battery
                    or self.mode == self.mode_list.wifi_status or self.mode == self.mode_list.mem_usage then
                schedule = true
            end
        end
    end
    if schedule then
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshFooter)
        if not unscheduled then
            logger.dbg("ReaderFooter.autoRefreshFooter scheduled")
        else
            logger.dbg("ReaderFooter.autoRefreshFooter rescheduled")
        end
    elseif unscheduled then
        logger.dbg("ReaderFooter.autoRefreshFooter unscheduled")
    end
end

function ReaderFooter:setupTouchZones()
    if not Device:isTouchDevice() then return end
    local footer_screen_zone = {
        ratio_x = DTAP_ZONE_MINIBAR.x, ratio_y = DTAP_ZONE_MINIBAR.y,
        ratio_w = DTAP_ZONE_MINIBAR.w, ratio_h = DTAP_ZONE_MINIBAR.h,
    }
    self.ui:registerTouchZones({
        {
            id = "readerfooter_tap",
            ges = "tap",
            screen_zone = footer_screen_zone,
            handler = function(ges) return self:onTapFooter(ges) end,
            overrides = {
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "tap_forward",
                "tap_backward",
            },
            -- (Low priority: tap on existing highlights
            -- or links have priority)
        },
        {
            id = "readerfooter_hold",
            ges = "hold",
            screen_zone = footer_screen_zone,
            handler = function(ges) return self:onHoldFooter(ges) end,
            overrides = {
                "readerhighlight_hold",
            },
            -- (High priority: it's a fallthrough if we held outside the footer)
        },
    })
end

-- call this method whenever the screen size changes
function ReaderFooter:resetLayout(force_reset)
    local new_screen_width = Screen:getWidth()
    local new_screen_height = Screen:getHeight()
    if new_screen_width == self._saved_screen_width
        and new_screen_height == self._saved_screen_height and not force_reset then return end

    if self.settings.disable_progress_bar then
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position ~= "alongside" then
        self.progress_bar.width = math.floor(new_screen_width - 2 * self.settings.progress_margin_width)
    else
        self.progress_bar.width = math.floor(
            new_screen_width - 2 * self.settings.progress_margin_width - self.text_width)
    end
    if self.separator_line then
        self.separator_line.dimen.w = new_screen_width - 2 * self.horizontal_margin
    end
    if self.settings.disable_progress_bar then
        self.progress_bar.height = 0
    else
        local bar_height
        if self.settings.progress_style_thin then
            bar_height = self.settings.progress_style_thin_height
        else
            bar_height = self.settings.progress_style_thick_height
        end
        self.progress_bar:setHeight(bar_height)
    end

    self.horizontal_group:resetLayout()
    self.footer_positioner.dimen.w = new_screen_width
    self.footer_positioner.dimen.h = new_screen_height
    self.footer_container.dimen.w = new_screen_width
    self.dimen = self.footer_positioner:getSize()

    self._saved_screen_width = new_screen_width
    self._saved_screen_height = new_screen_height
end

function ReaderFooter:getHeight()
    if self.footer_content then
        -- NOTE: self.footer_content is self.vertical_frame + self.bottom_padding,
        --       self.vertical_frame includes self.text_container (which includes self.footer_text)
        return self.footer_content:getSize().h
    else
        return 0
    end
end

function ReaderFooter:disableFooter()
    self.onReaderReady = function() end
    self.resetLayout = function() end
    self.updateFooterPage = function() end
    self.updateFooterPos = function() end
    self.onUpdatePos = function() end
    self.mode = self.mode_list.off
    self.view.footer_visible = false
end

function ReaderFooter:updateFooterTextGenerator()
    local footerTextGenerators = {}
    for i, m in pairs(self.mode_index) do
        if self.settings[m] then
            table.insert(footerTextGenerators,
                         footerTextGeneratorMap[m])
            if not self.settings.all_at_once then
                -- if not show all at once, then one is enough
                self.mode = i
                break
            end
        end
    end
    if #footerTextGenerators == 0 then
        -- all modes are disabled
        self.genFooterText = footerTextGeneratorMap.empty
    elseif #footerTextGenerators == 1 then
        -- there is only one mode enabled, simplify the generator
        -- function to that one
        self.genFooterText = footerTextGenerators[1]
    else
        self.genFooterText = self.genAllFooterText
    end

    -- Even if there's no or a single mode enabled, all_at_once requires this to be set
     self.footerTextGenerators = footerTextGenerators

    -- notify caller that UI needs update
    return true
end

function ReaderFooter:progressPercentage(digits)
    local symbol_type = self.settings.item_prefix
    local prefix = symbol_prefix[symbol_type].percentage

    local string_percentage
    if not prefix then
        string_percentage = "%." .. digits .. "f%%"
    else
        string_percentage = prefix .. " %." .. digits .. "f%%"
    end
    return string_percentage:format(self.progress_bar.percentage * 100)
end

function ReaderFooter:textOptionTitles(option)
    local symbol = self.settings.item_prefix
    local option_titles = {
        all_at_once = _("Show all at once"),
        reclaim_height = _("Reclaim bar height from bottom margin"),
        bookmark_count = T(_("Bookmark count (%1)"), symbol_prefix[symbol].bookmark_count),
        page_progress = T(_("Current page (%1)"), "/"),
        pages_left_book = T(_("Pages left in book (%1)"), symbol_prefix[symbol].pages_left_book),
        time = symbol_prefix[symbol].time
            and T(_("Current time (%1)"), symbol_prefix[symbol].time) or _("Current time"),
        chapter_progress = T(_("Current page in chapter (%1)"), " ⁄⁄ "),
        pages_left = T(_("Pages left in chapter (%1)"), symbol_prefix[symbol].pages_left),
        battery = T(_("Battery status (%1)"), symbol_prefix[symbol].battery),
        percentage = symbol_prefix[symbol].percentage
            and T(_("Progress percentage (%1)"), symbol_prefix[symbol].percentage) or _("Progress percentage"),
        book_time_to_read = symbol_prefix[symbol].book_time_to_read
            and T(_("Book time to read (%1)"),symbol_prefix[symbol].book_time_to_read) or _("Book time to read"),
        chapter_time_to_read = T(_("Chapter time to read (%1)"), symbol_prefix[symbol].chapter_time_to_read),
        frontlight = T(_("Frontlight level (%1)"), symbol_prefix[symbol].frontlight),
        mem_usage = T(_("KOReader memory usage (%1)"), symbol_prefix[symbol].mem_usage),
        wifi_status = T(_("Wi-Fi status (%1)"), symbol_prefix[symbol].wifi_status),
        book_title = _("Book title"),
        book_chapter = _("Current chapter"),
    }
    return option_titles[option]
end

function ReaderFooter:addToMainMenu(menu_items)
    local sub_items = {}
    menu_items.status_bar = {
        text = _("Status bar"),
        sub_item_table = sub_items,
    }

    -- menu item to fake footer tapping when touch area is disabled
    local settings_submenu_num = 1
    if Geom:new{
           x = DTAP_ZONE_MINIBAR.x,
           y = DTAP_ZONE_MINIBAR.y,
           w = DTAP_ZONE_MINIBAR.w,
           h = DTAP_ZONE_MINIBAR.h
       }:area() == 0 then
        table.insert(sub_items, {
            text = _("Toggle mode"),
            enabled_func = function()
                return not self.view.flipping_visible
            end,
            callback = function() self:onTapFooter(true) end,
        })
        settings_submenu_num = 2
    end

    local getMinibarOption = function(option, callback)
        return {
            text_func = function()
                return self:textOptionTitles(option)
            end,
            checked_func = function()
                return self.settings[option] == true
            end,
            callback = function()
                self.settings[option] = not self.settings[option]
                -- We only need to send a SetPageBottomMargin event when we truly affect the margin
                local should_signal = false
                -- only case that we don't need a UI update is enable/disable
                -- non-current mode when all_at_once is disabled.
                local should_update = false
                local first_enabled_mode_num
                local prev_has_no_mode = self.has_no_mode
                local prev_reclaim_height = self.reclaim_height
                self.has_no_mode = true
                for mode_num, m in pairs(self.mode_index) do
                    if self.settings[m] then
                        first_enabled_mode_num = mode_num
                        self.has_no_mode = false
                        break
                    end
                end
                self.reclaim_height = self.settings.reclaim_height
                -- refresh margins position
                if self.has_no_mode then
                    self.footer_text.height = 0
                    should_signal = true
                    self.genFooterText = footerTextGeneratorMap.empty
                    self.mode = self.mode_list.off
                elseif prev_has_no_mode then
                    if self.settings.all_at_once then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                    else
                        G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
                    end
                    should_signal = true
                elseif self.reclaim_height ~= prev_reclaim_height then
                    should_signal = true
                    should_update = true
                end
                if callback then
                    should_update = callback(self)
                elseif self.settings.all_at_once then
                    should_update = self:updateFooterTextGenerator()
                elseif (self.mode_list[option] == self.mode and self.settings[option] == false)
                        or (prev_has_no_mode ~= self.has_no_mode) then
                    -- current mode got disabled, redraw footer with other
                    -- enabled modes. if all modes are disabled, then only show
                    -- progress bar
                    if not self.has_no_mode then
                        self.mode = first_enabled_mode_num
                    else
                        -- If we've just disabled our last mode, first_enabled_mode_num is nil
                        -- If the progress bar is enabled,
                        -- fake an innocuous mode so that we switch to showing the progress bar alone, instead of nothing,
                        -- This is exactly what the "Show progress bar" toggle does.
                        self.mode = self.settings.disable_progress_bar and self.mode_list.off or self.mode_list.page_progress
                    end
                    should_update = true
                    self:applyFooterMode()
                    G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                end
                if should_update or should_signal then
                    self:refreshFooter(should_update, should_signal)
                end
                -- The absence or presence of some items may change whether auto-refresh should be ensured
                self:rescheduleFooterAutoRefreshIfNeeded()
            end,
        }
    end
    table.insert(sub_items, {
        text = _("Settings"),
        sub_item_table = {
            {
                text = _("Sort items"),
                separator = true,
                callback = function()
                    local item_table = {}
                    for i=1, #self.mode_index do
                        table.insert(item_table, {text = self:textOptionTitles(self.mode_index[i]), label = self.mode_index[i]})
                    end
                    local SortWidget = require("ui/widget/sortwidget")
                    local sort_item
                    sort_item = SortWidget:new{
                        title = _("Sort footer items"),
                        item_table = item_table,
                        callback = function()
                            for i=1, #sort_item.item_table do
                                self.mode_index[i] = sort_item.item_table[i].label
                            end
                            self.settings.order = self.mode_index
                            self:updateFooterTextGenerator()
                            self:onUpdateFooter()
                            UIManager:setDirty(nil, "ui")
                        end
                    }
                    UIManager:show(sort_item)
                end,
            },
            getMinibarOption("all_at_once", self.updateFooterTextGenerator),
            {
                text = _("Hide empty items"),
                help_text = _([[This will hide values like 0 or off.]]),
                enabled_func = function()
                    return self.settings.all_at_once == true
                end,
                checked_func = function()
                    return self.settings.hide_empty_generators == true
                end,
                callback = function()
                    self.settings.hide_empty_generators = not self.settings.hide_empty_generators
                    self:refreshFooter(true, true)
                end,
            },
            getMinibarOption("reclaim_height"),
            {
                text = _("Auto refresh"),
                checked_func = function()
                    return self.settings.auto_refresh_time == true
                end,
                callback = function()
                    self.settings.auto_refresh_time = not self.settings.auto_refresh_time
                    self:rescheduleFooterAutoRefreshIfNeeded()
                end
            },
            {
                text = _("Show footer separator"),
                checked_func = function()
                    return self.settings.bottom_horizontal_separator == true
                end,
                callback = function()
                    self.settings.bottom_horizontal_separator = not self.settings.bottom_horizontal_separator
                    self:refreshFooter(true, true)
                end,
            },
            {
                text = _("Lock status bar"),
                checked_func = function()
                    return self.settings.lock_tap == true
                end,
                callback = function()
                    self.settings.lock_tap = not self.settings.lock_tap
                end,
            },
            {
                text = _("Hold footer to skim"),
                checked_func = function()
                    return self.settings.skim_widget_on_hold == true
                end,
                callback = function()
                    self.settings.skim_widget_on_hold = not self.settings.skim_widget_on_hold
                end,
            },
            {
                text = _("Font"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Font size (%1)"), self.settings.text_font_size)
                        end,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            local font_size = self.settings.text_font_size
                            local items_font = SpinWidget:new{
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = font_size,
                                value_min = 8,
                                value_max = 36,
                                default_value = 14,
                                ok_text = _("Set size"),
                                title_text =  _("Footer font size"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    self.settings.text_font_size = spin.value
                                    self.footer_text:free()
                                    self.footer_text = TextWidget:new{
                                        text = self.footer_text.text,
                                        face = Font:getFace(self.text_font_face, self.settings.text_font_size),
                                        bold = self.settings.text_font_bold,
                                    }
                                    self.text_container[1] = self.footer_text
                                    self:refreshFooter(true, true)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            }
                            UIManager:show(items_font)
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Use bold font"),
                        checked_func = function()
                            return self.settings.text_font_bold == true
                        end,
                        callback = function(touchmenu_instance)
                            self.settings.text_font_bold = not self.settings.text_font_bold
                            self.footer_text:free()
                            self.footer_text = TextWidget:new{
                                text = self.footer_text.text,
                                face = Font:getFace(self.text_font_face, self.settings.text_font_size),
                                bold = self.settings.text_font_bold,
                            }
                            self.text_container[1] = self.footer_text
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                        keep_menu_open = true,
                    },
                }
            },
            {
                text_func = function()
                    return T(_("Container height (%1)"), self.settings.container_height)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local container_height = self.settings.container_height
                    local items_font = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = container_height,
                        value_min = 7,
                        value_max = 98,
                        default_value = DMINIBAR_CONTAINER_HEIGHT,
                        ok_text = _("Set height"),
                        title_text =  _("Container height"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.container_height = spin.value
                            self.height = Screen:scaleBySize(self.settings.container_height)
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Container bottom margin (%1)"), self.settings.container_bottom_padding)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local container_bottom_padding = self.settings.container_bottom_padding
                    local items_font = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = container_bottom_padding,
                        value_min = 0,
                        value_max = 49,
                        default_value = 1,
                        ok_text = _("Set margin"),
                        title_text =  _("Container bottom margin"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.container_bottom_padding = spin.value
                            self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            },
            {
                text = _("Maximum width of items"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Book title (%1%)"), self.settings.book_title_max_width_pct)
                        end,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            local items = SpinWidget:new{
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = self.settings.book_title_max_width_pct,
                                value_min = 10,
                                value_step = 5,
                                value_hold_step = 20,
                                value_max = 100,
                                title_text =  _("Maximum width"),
                                info_text = _("Maximum book title width in percentage of screen width"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    self.settings.book_title_max_width_pct = spin.value
                                    self:refreshFooter(true, true)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end
                            }
                            UIManager:show(items)
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text_func = function()
                            return T(_("Current chapter (%1%)"), self.settings.book_chapter_max_width_pct)
                        end,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            local items = SpinWidget:new{
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = self.settings.book_chapter_max_width_pct,
                                value_min = 10,
                                value_step = 5,
                                value_hold_step = 20,
                                value_max = 100,
                                title_text =  _("Maximum width"),
                                info_text = _("Maximum chapter width in percentage of screen width"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    self.settings.book_chapter_max_width_pct = spin.value
                                    self:refreshFooter(true, true)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end
                            }
                            UIManager:show(items)
                        end,
                        keep_menu_open = true,
                    }
                },
            },
            {
                text = _("Alignment"),
                separator = true,
                enabled_func = function()
                    return self.settings.disable_progress_bar or self.settings.progress_bar_position ~= "alongside"
                end,
                sub_item_table = {
                    {
                        text = _("Center"),
                        checked_func = function()
                            return self.settings.align == "center"
                        end,
                        callback = function()
                            self.settings.align = "center"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text = _("Left"),
                        checked_func = function()
                            return self.settings.align == "left"
                        end,
                        callback = function()
                            self.settings.align = "left"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text = _("Right"),
                        checked_func = function()
                            return self.settings.align == "right"
                        end,
                        callback = function()
                            self.settings.align = "right"
                            self:refreshFooter(true)
                        end,
                    },
                }
            },
            {
                text = _("Prefix"),
                sub_item_table = {
                    {
                        text_func = function()
                            local sym_tbl = {}
                            for _, letter in pairs(symbol_prefix.icons) do
                                table.insert(sym_tbl, letter)
                            end
                            return T(_("Icons (%1)"), table.concat(sym_tbl, " "))
                        end,
                        checked_func = function()
                            return self.settings.item_prefix == "icons"
                        end,
                        callback = function()
                            self.settings.item_prefix = "icons"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text_func = function()
                            local sym_tbl = {}
                            for _, letter in pairs(symbol_prefix.compact_items) do
                                table.insert(sym_tbl, letter)
                            end
                            return T(_("Compact Items (%1)"), table.concat(sym_tbl, " "))
                        end,
                        checked_func = function()
                            return self.settings.item_prefix == "compact_items"
                        end,
                        callback = function()
                            self.settings.item_prefix = "compact_items"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text_func = function()
                            local sym_tbl = {}
                            for _, letter in pairs(symbol_prefix.letters) do
                                table.insert(sym_tbl, letter)
                            end
                            return T(_("Letters (%1)"), table.concat(sym_tbl, " "))
                        end,
                        checked_func = function()
                            return self.settings.item_prefix == "letters"
                        end,
                        callback = function()
                            self.settings.item_prefix = "letters"
                            self:refreshFooter(true)
                        end,
                    },
                },
            },
            {
                text = _("Item separator"),
                sub_item_table = {
                    {
                        text = _("Vertical line (|)"),
                        checked_func = function()
                            return self.settings.items_separator == "bar"
                        end,
                        callback = function()
                            self.settings.items_separator = "bar"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text = _("Bullet (•)"),
                        checked_func = function()
                            return self.settings.items_separator == "bullet"
                        end,
                        callback = function()
                            self.settings.items_separator = "bullet"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text = _("No separator"),
                        checked_func = function()
                            return self.settings.items_separator == "none"
                        end,
                        callback = function()
                            self.settings.items_separator = "none"
                            self:refreshFooter(true)
                        end,
                    },
                },
            },
            {
                text = _("Progress percentage format"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("No decimal point (%1)"), self:progressPercentage(0))
                        end,
                        checked_func = function()
                            return self.settings.progress_pct_format == "0"
                        end,
                        callback = function()
                            self.settings.progress_pct_format = "0"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("1 digit after decimal point (%1)"), self:progressPercentage(1))
                        end,
                        checked_func = function()
                            return self.settings.progress_pct_format == "1"
                        end,
                        callback = function()
                            self.settings.progress_pct_format = "1"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("2 digits after decimal point (%1)"), self:progressPercentage(2))
                        end,
                        checked_func = function()
                            return self.settings.progress_pct_format == "2"
                        end,
                        callback = function()
                            self.settings.progress_pct_format = "2"
                            self:refreshFooter(true)
                        end,
                    },
                },
            },
        }
    })
    if Device:hasBattery() then
        table.insert(sub_items[settings_submenu_num].sub_item_table, 4, {
            text_func = function()
                return T(_("Hide battery status if level higher than (%1%)"), self.settings.battery_hide_threshold)
            end,
            enabled_func = function()
                return self.settings.all_at_once == true
            end,
            separator = true,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                local battery_threshold = SpinWidget:new{
                    width = math.floor(Screen:getWidth() * 0.6),
                    value = self.settings.battery_hide_threshold,
                    value_min = 0,
                    value_max = 100,
                    default_value = 100,
                    value_hold_step = 10,
                    title_text =  _("Hide battery threshold"),
                    callback = function(spin)
                        self.settings.battery_hide_threshold = spin.value
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                }
                UIManager:show(battery_threshold)
            end,
            keep_menu_open = true,
        })
    end
    table.insert(sub_items, {
        text = _("Progress bar"),
        separator = true,
        sub_item_table = {
            {
                text = _("Show progress bar"),
                checked_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.disable_progress_bar = not self.settings.disable_progress_bar
                    if not self.settings.disable_progress_bar then
                        self:setTocMarkers()
                    end
                    -- If the status bar is currently disabled, switch to an innocuous mode to display it
                    if not self.view.footer_visible then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                    end
                    self:refreshFooter(true, true)
                end,
            },
            {
                text_func = function()
                    local text = _("alongside items")
                    if self.settings.progress_bar_position == "above" then
                        text = _("above items")
                    elseif self.settings.progress_bar_position == "below" then
                        text = _("below items")
                    end
                    return T(_("Position: %1"), text)
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    {
                        text = _("Above items"),
                        checked_func = function()
                            return self.settings.progress_bar_position == "above"
                        end,
                        callback = function()
                            self.settings.progress_bar_position = "above"
                            self:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Below items"),
                        checked_func = function()
                            return self.settings.progress_bar_position == "below"
                        end,
                        callback = function()
                            self.settings.progress_bar_position = "below"
                            self:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Alongside items"),
                        checked_func = function()
                            return self.settings.progress_bar_position == "alongside"
                        end,
                        callback = function()
                            -- "Same as book" is disabled in this mode, and we enforce the defaults.
                            if self.settings.progress_margin then
                                self.settings.progress_margin = false
                                self.settings.progress_margin_width = self.horizontal_margin
                            end
                            -- Text alignment is also disabled
                            self.settings.align = "center"

                            self.settings.progress_bar_position = "alongside"
                            self:refreshFooter(true, true)
                        end
                    },
                },
            },
            {
                text_func = function()
                    if self.settings.progress_style_thin then
                        return _("Style: thin")
                    else
                        return _("Style: thick")
                    end
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    {
                        text = _("Thick"),
                        checked_func = function()
                            return not self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.progress_style_thin = nil
                            local bar_height = self.settings.progress_style_thick_height
                            self.progress_bar:updateStyle(true, bar_height)
                            self:setTocMarkers()
                            self:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Thin"),
                        checked_func = function()
                            return self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.progress_style_thin = true
                            local bar_height = self.settings.progress_style_thin_height
                            self.progress_bar:updateStyle(false, bar_height)
                            self:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Set size"),
                        callback = function()
                            local value, value_min, value_max, default_value
                            if self.settings.progress_style_thin then
                                default_value = PROGRESS_BAR_STYLE_THIN_DEFAULT_HEIGHT
                                value = self.settings.progress_style_thin_height or default_value
                                value_min = 1
                                value_max = 12
                            else
                                default_value = PROGRESS_BAR_STYLE_THICK_DEFAULT_HEIGHT
                                value = self.settings.progress_style_thick_height or default_value
                                value_min = 5
                                value_max = 28
                            end
                            local SpinWidget = require("ui/widget/spinwidget")
                            local items = SpinWidget:new{
                                width = math.floor(Screen:getWidth() * 0.6),
                                value = value,
                                value_min = value_min,
                                value_step = 1,
                                value_hold_step = 2,
                                value_max = value_max,
                                default_value = default_value,
                                title_text =  _("Progress bar size"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    if self.settings.progress_style_thin then
                                        self.settings.progress_style_thin_height = spin.value
                                    else
                                        self.settings.progress_style_thick_height = spin.value
                                    end
                                    self:refreshFooter(true, true)
                                end
                            }
                            UIManager:show(items)
                        end,
                        separator = true,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Show chapter markers"),
                        checked_func = function()
                            return self.settings.toc_markers == true
                        end,
                        enabled_func = function()
                            return not self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.toc_markers = not self.settings.toc_markers
                            self:setTocMarkers()
                            self:refreshFooter(true)
                        end
                    },
                    {
                        text_func = function()
                            local markers_width_text = _("thick")
                            if self.settings.toc_markers_width == 1 then
                                markers_width_text = _("thin")
                            elseif self.settings.toc_markers_width == 2 then
                                markers_width_text = _("medium")
                            end
                            return T(_("Chapter marker width (%1)"), markers_width_text)
                        end,
                        enabled_func = function()
                            return not self.settings.progress_style_thin and self.settings.toc_markers
                        end,
                        sub_item_table = {
                            {
                                text = _("Thin"),
                                checked_func = function()
                                    return self.settings.toc_markers_width == 1
                                end,
                                callback = function()
                                    self.settings.toc_markers_width = 1  -- unscaled_size_check: ignore
                                    self:setTocMarkers()
                                    self:refreshFooter(true)
                                end,
                            },
                            {
                                text = _("Medium"),
                                checked_func = function()
                                    return self.settings.toc_markers_width == 2
                                end,
                                callback = function()
                                    self.settings.toc_markers_width = 2  -- unscaled_size_check: ignore
                                    self:setTocMarkers()
                                    self:refreshFooter(true)
                                end,
                            },
                            {
                                text = _("Thick"),
                                checked_func = function()
                                    return self.settings.toc_markers_width == 3
                                end,
                                callback = function()
                                    self.settings.toc_markers_width = 3  -- unscaled_size_check: ignore
                                    self:setTocMarkers()
                                    self:refreshFooter(true)
                                end
                            },
                        },
                    },
                },
            },
            {
                text_func = function()
                    local text = _("static margins (10)")
                    local cur_width = self.settings.progress_margin_width
                    if cur_width == 0 then
                        text = _("no margins (0)")
                    elseif cur_width == Screen:scaleBySize(material_pixels) then
                        text = T(_("static margins (%1)"), material_pixels)
                    end
                    if self.settings.progress_margin and not self.ui.document.info.has_pages then
                        text = T(_("same as book margins (%1)"), self.book_margins_footer_width)
                    end
                    return T(_("Margins: %1"), text)
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table_func = function()
                    local common = {
                        {
                            text = _("No margins (0)"),
                            checked_func = function()
                                return self.settings.progress_margin_width == 0
                                    and not self.settings.progress_margin
                            end,
                            callback = function()
                                self.settings.progress_margin_width = 0
                                self.settings.progress_margin = false
                                self:refreshFooter(true)
                            end,
                        },
                        {
                            text_func = function()
                                if self.ui.document.info.has_pages then
                                    return _("Same as book margins")
                                end
                                return T(_("Same as book margins (%1)"), self.book_margins_footer_width)
                            end,
                            checked_func = function()
                                return self.settings.progress_margin and not self.ui.document.info.has_pages
                            end,
                            enabled_func = function()
                                return not self.ui.document.info.has_pages and self.settings.progress_bar_position ~= "alongside"
                            end,
                            callback = function()
                                self.settings.progress_margin = true
                                self.settings.progress_margin_width = Screen:scaleBySize(self.book_margins_footer_width)
                                self:refreshFooter(true)
                            end
                        },
                    }
                    local function customMargin(px)
                        return {
                            text = T(_("Static margins (%1)"), px),
                            checked_func = function()
                                return self.settings.progress_margin_width == Screen:scaleBySize(px)
                                    and not self.settings.progress_margin
                                    -- if same as book margins is selected in document with pages (pdf) we enforce static margins
                                    or (self.ui.document.info.has_pages and self.settings.progress_margin)
                            end,
                            callback = function()
                                self.settings.progress_margin_width = Screen:scaleBySize(px)
                                self.settings.progress_margin = false
                                self:refreshFooter(true)
                            end,
                        }
                    end
                    local device_defaults
                    if Device:isAndroid() then
                        device_defaults = customMargin(material_pixels)
                    else
                        device_defaults = customMargin(10)
                    end
                    table.insert(common, 2, device_defaults)
                    return common
                end,
            },
            {
                text_func = function()
                    return T(_("Minimal width (%1%)"), self.settings.progress_bar_min_width_pct)
                end,
                enabled_func = function()
                    return self.settings.progress_bar_position == "alongside" and not self.settings.disable_progress_bar
                        and self.settings.all_at_once
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local items = SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = self.settings.progress_bar_min_width_pct,
                        value_min = 5,
                        value_step = 5,
                        value_hold_step = 20,
                        value_max = 50,
                        title_text =  _("Minimal width"),
                        text = _("Minimal progress bar width in percentage of screen width"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.progress_bar_min_width_pct = spin.value
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items)
                end,
                keep_menu_open = true,
            }
        }
    })
    table.insert(sub_items, getMinibarOption("page_progress"))
    table.insert(sub_items, getMinibarOption("pages_left_book"))
    table.insert(sub_items, getMinibarOption("time"))
    table.insert(sub_items, getMinibarOption("chapter_progress"))
    table.insert(sub_items, getMinibarOption("pages_left"))
    if Device:hasBattery() then
        table.insert(sub_items, getMinibarOption("battery"))
    end
    table.insert(sub_items, getMinibarOption("bookmark_count"))
    table.insert(sub_items, getMinibarOption("percentage"))
    table.insert(sub_items, getMinibarOption("book_time_to_read"))
    table.insert(sub_items, getMinibarOption("chapter_time_to_read"))
    if Device:hasFrontlight() then
        table.insert(sub_items, getMinibarOption("frontlight"))
    end
    table.insert(sub_items, getMinibarOption("mem_usage"))
    if Device:hasFastWifiStatusQuery() then
        table.insert(sub_items, getMinibarOption("wifi_status"))
    end
    table.insert(sub_items, getMinibarOption("book_title"))
    table.insert(sub_items, getMinibarOption("book_chapter"))

    -- Settings menu: keep the same parent page for going up from submenu
    for i = 1, #sub_items[settings_submenu_num].sub_item_table do
        sub_items[settings_submenu_num].sub_item_table[i].menu_item_id = i
    end

    -- If using crengine, add Alt status bar items at top
    if self.ui.crelistener then
        table.insert(sub_items, 1, self.ui.crelistener:getAltStatusBarMenu())
    end
end

-- this method will be updated at runtime based on user setting
function ReaderFooter:genFooterText() end

function ReaderFooter:genAllFooterText()
    local info = {}
    local separator = "  "
    if self.settings.item_prefix == "compact_items" then
        separator = " "
    end
    if self.settings.items_separator == "bar" then
        separator = " | "
    elseif self.settings.items_separator == "bullet" then
        separator = " • "
    end
    -- We need to BD.wrap() all items and separators, so we're
    -- sure they are laid out in our order (reversed in RTL),
    -- without ordering by the RTL Bidi algorithm.
    for _, gen in ipairs(self.footerTextGenerators) do
        -- Skip empty generators, so they don't generate bogus separators
        local text = gen(self)
        if text and text ~= "" then
            if self.settings.item_prefix == "compact_items" then
                -- remove whitespace from footer items if symbol_type is compact_items
                -- use a hair-space to avoid issues with RTL display
                text = text:gsub("%s", "\xE2\x80\x8A")
            end
            table.insert(info, BD.wrap(text))
        end
    end
    return table.concat(info, BD.wrap(separator))
end

function ReaderFooter:setTocMarkers(reset)
    if self.settings.disable_progress_bar or self.settings.progress_style_thin then return end
    if reset then
        self.progress_bar.ticks = nil
        self.pages = self.ui.document:getPageCount()
    end
    if self.settings.toc_markers then
        self.progress_bar.tick_width = Screen:scaleBySize(self.settings.toc_markers_width)
        if self.progress_bar.ticks ~= nil then -- already computed
            return
        end
        if self.ui.document:hasHiddenFlows() and self.pageno then
            local flow = self.ui.document:getPageFlow(self.pageno)
            self.progress_bar.ticks = {}
            if self.ui.toc then
                -- filter the ticks to show only those in the current flow
                for n, pageno in ipairs(self.ui.toc:getTocTicksFlattened()) do
                    if self.ui.document:getPageFlow(pageno) == flow then
                        table.insert(self.progress_bar.ticks, self.ui.document:getPageNumberInFlow(pageno))
                    end
                end
            end
            self.progress_bar.last = self.ui.document:getTotalPagesInFlow(flow)
        else
            if self.ui.toc then
                self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
            end
            if self.view.view_mode == "page" then
                self.progress_bar.last = self.pages or self.ui.document:getPageCount()
            else
                -- in scroll mode, convert pages to positions
                if self.ui.toc then
                    self.progress_bar.ticks = {}
                    for n, pageno in ipairs(self.ui.toc:getTocTicksFlattened()) do
                        local idx = self.ui.toc:getTocIndexByPage(pageno)
                        local pos = self.ui.document:getPosFromXPointer(self.ui.toc.toc[idx].xpointer)
                        table.insert(self.progress_bar.ticks, pos)
                    end
                end
                self.progress_bar.last = self.doc_height or self.ui.document.info.doc_height
            end
        end
    else
        self.progress_bar.ticks = nil
    end
    -- notify caller that UI needs update
    return true
end

-- This is implemented by the Statistics plugin
function ReaderFooter:getAvgTimePerPage()
    return
end

function ReaderFooter:getDataFromStatistics(title, pages)
    local sec = _("N/A")
    local average_time_per_page = self:getAvgTimePerPage()
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    if average_time_per_page then
        sec = util.secondsToClockDuration(user_duration_format, pages * average_time_per_page, true)
    end
    return title .. sec
end

function ReaderFooter:onUpdateFooter(force_repaint, force_recompute)
    if self.pageno then
        self:updateFooterPage(force_repaint, force_recompute)
    else
        self:updateFooterPos(force_repaint, force_recompute)
    end
end

function ReaderFooter:updateFooterPage(force_repaint, force_recompute)
    if type(self.pageno) ~= "number" then return end
    if self.ui.document:hasHiddenFlows() then
        local flow = self.ui.document:getPageFlow(self.pageno)
        local page = self.ui.document:getPageNumberInFlow(self.pageno)
        local pages = self.ui.document:getTotalPagesInFlow(flow)
        self.progress_bar.percentage = page / pages
    else
        self.progress_bar.percentage = self.pageno / self.pages
    end
    self:updateFooterText(force_repaint, force_recompute)
end

function ReaderFooter:updateFooterPos(force_repaint, force_recompute)
    if type(self.position) ~= "number" then return end
    self.progress_bar.percentage = self.position / self.doc_height
    self:updateFooterText(force_repaint, force_recompute)
end

-- updateFooterText will start as a noop. After onReaderReady event is
-- received, it will initialized as _updateFooterText below
function ReaderFooter:updateFooterText(force_repaint, force_recompute)
end

-- only call this function after document is fully loaded
function ReaderFooter:_updateFooterText(force_repaint, force_recompute)
    -- footer is invisible, we need neither a repaint nor a recompute, go away.
    if not self.view.footer_visible and not force_repaint and not force_recompute then
        return
    end
    local text = self:genFooterText()
    if not text then text = "" end
    self.footer_text:setText(text)
    if self.settings.disable_progress_bar then
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- No progress bar, we're only constrained to fit inside self.footer_container
            self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.horizontal_margin))
            self.text_width = self.footer_text:getSize().w
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.height = 0
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position ~= "alongside" then
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- With a progress bar above or below us, we want to align ourselves to the bar's margins... iff text is centered.
            if self.settings.align == "center" then
                self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.settings.progress_margin_width))
            else
                -- Otherwise, we have to constrain ourselves to the container, or weird shit happens.
                self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.horizontal_margin))
            end
            self.text_width = self.footer_text:getSize().w
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.width = math.floor(self._saved_screen_width - 2 * self.settings.progress_margin_width)
    else
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- Alongside a progress bar, it's the bar's width plus whatever's left.
            local text_max_available_ratio = (100 - self.settings.progress_bar_min_width_pct) / 100
            self.footer_text:setMaxWidth(math.floor(text_max_available_ratio * self._saved_screen_width - 2 * self.settings.progress_margin_width - self.horizontal_margin))
            -- Add some spacing between the text and the bar
            self.text_width = self.footer_text:getSize().w + self.horizontal_margin
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.width = math.floor(
            self._saved_screen_width - 2 * self.settings.progress_margin_width - self.text_width)
    end

    if self.separator_line then
        self.separator_line.dimen.w = self._saved_screen_width - 2 * self.horizontal_margin
    end
    self.text_container.dimen.w = self.text_width
    self.horizontal_group:resetLayout()
    -- NOTE: This is essentially preventing us from truly using "fast" for panning,
    --       since it'll get coalesced in the "fast" panning update, upgrading it to "ui".
    -- NOTE: That's assuming using "fast" for pans was a good idea, which, it turned out, not so much ;).
    -- NOTE: We skip repaints on page turns/pos update, as that's redundant (and slow).
    if force_repaint then
        -- If there was a visibility change, notify ReaderView
        if self.visibility_change then
            self.ui:handleEvent(Event:new("ReaderFooterVisibilityChange"))
            self.visibility_change = nil
        end

        -- NOTE: Getting the dimensions of the widget is impossible without having drawn it first,
        --       so, we'll fudge it if need be...
        --       i.e., when it's no longer visible, because there's nothing to draw ;).
        local refresh_dim = self.footer_content.dimen
        -- No more content...
        if not self.view.footer_visible and not refresh_dim then
            -- So, instead, rely on self:getHeight to compute self.footer_content's height early...
            refresh_dim = self.dimen
            refresh_dim.h = self:getHeight()
            refresh_dim.y = self._saved_screen_height - refresh_dim.h
        end
        -- If we're making the footer visible (or it already is), we don't need to repaint ReaderUI behind it
        if self.view.footer_visible then
            -- Unfortunately, it's not a modal (we never show() it), so it's not in the window stack,
            -- instead, it's baked inside ReaderUI, so it gets slightly trickier...
            -- NOTE: self.view.footer -> self ;).

            -- c.f., ReaderView:paintTo()
            UIManager:widgetRepaint(self.view.footer, 0, 0)
            -- We've painted it first to ensure self.footer_content.dimen is sane
            UIManager:setDirty(self.view.footer, function()
                return self.view.currently_scrolling and "fast" or "ui", self.footer_content.dimen
            end)
        else
            UIManager:setDirty(self.view.dialog, function()
                return self.view.currently_scrolling and "fast" or "ui", refresh_dim
            end)
        end
    end
end

function ReaderFooter:onTocReset()
    self:setTocMarkers(true)
    if self.view.view_mode == "page" then
        self:updateFooterPage()
    else
        self:updateFooterPos()
    end
end

function ReaderFooter:onPageUpdate(pageno)
    local toc_markers_update = false
    if self.ui.document:hasHiddenFlows() then
        local flow = self.pageno and self.ui.document:getPageFlow(self.pageno)
        local new_flow = pageno and self.ui.document:getPageFlow(pageno)
        if pageno and new_flow ~= flow then
            toc_markers_update = true
        end
    end
    self.pageno = pageno
    self.pages = self.ui.document:getPageCount()
    if toc_markers_update then
        self:setTocMarkers(true)
    end
    self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    self:updateFooterPage()
end

function ReaderFooter:onPosUpdate(pos, pageno)
    self.position = pos
    self.doc_height = self.ui.document.info.doc_height
    if pageno then
        self.pageno = pageno
        self.pages = self.ui.document:getPageCount()
        self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    end
    self:updateFooterPos()
end

-- recalculate footer sizes when document page count is updated
-- see documentation for more info about this event.
ReaderFooter.onUpdatePos = ReaderFooter.onUpdateFooter

function ReaderFooter:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self:setupTouchZones()
    -- if same as book margins is selected in document with pages (pdf) we enforce static margins
    if self.ui.document.info.has_pages and self.settings.progress_margin then
        self.settings.progress_margin_width = Size.span.horizontal_default
        self:updateFooterContainer()
    -- set progress bar margins for current book
    elseif self.settings.progress_margin then
        local margins = self.ui.document:getPageMargins()
        self.settings.progress_margin_width = math.floor((margins.left + margins.right)/2)
        self:updateFooterContainer()
    end
    self:resetLayout(self.settings.progress_margin_width)  -- set widget dimen
    self:setTocMarkers()
    self.updateFooterText = self._updateFooterText
    self:onUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onReadSettings(config)
    if not self.ui.document.info.has_pages then
        local h_margins = config:readSetting("copt_h_page_margins")
                       or G_reader_settings:readSetting("copt_h_page_margins")
                       or DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM
        self.book_margins_footer_width = math.floor((h_margins[1] + h_margins[2])/2)
    end
end

function ReaderFooter:applyFooterMode(mode)
    if mode ~= nil then self.mode = mode end
    local prev_visible_state = self.view.footer_visible
    self.view.footer_visible = (self.mode ~= self.mode_list.off)

    -- NOTE: _updateFooterText won't actually run the text generator(s) when hidden ;).

    -- We're hidden, disable text generation entirely
    if not self.view.footer_visible then
        self.genFooterText = footerTextGeneratorMap.empty
    else
        if self.settings.all_at_once then
            -- If all-at-once is enabled, we only have toggle from empty to All.
            self.genFooterText = self.genAllFooterText
        else
            -- Otherwise, switch to the right text generator for the new mode
            local mode_name = self.mode_index[self.mode]
            if not self.settings[mode_name] or self.has_no_mode then
                -- all modes disabled, only show progress bar
                mode_name = "empty"
            end
            self.genFooterText = footerTextGeneratorMap[mode_name]
        end
    end

    -- If we changed visibility state at runtime (as opposed to during init), better make sure the layout has been reset...
    if prev_visible_state ~= nil and self.view.footer_visible ~= prev_visible_state then
        self:updateFooterContainer()
        -- NOTE: _updateFooterText does a resetLayout, but not a forced one!
        self:resetLayout(true)
        -- Flag _updateFooterText to notify ReaderView to recalculate the visible_area!
        self.visibility_change = true
    end
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(self.mode_list.page_progress)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onExitFlippingMode()
    self:applyFooterMode(self.orig_mode)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onTapFooter(ges)
    local ignore_lock = false
    if ges == true then
        ignore_lock = true
        ges = nil
    end
    if self.view.flipping_visible and ges then
        local pos = ges.pos
        local dimen = self.progress_bar.dimen
        -- if reader footer is not drawn before the dimen value should be nil
        if dimen then
            local percentage = (pos.x - dimen.x)/dimen.w
            self.ui:handleEvent(Event:new("GotoPercentage", percentage))
        end
        self:onUpdateFooter(true)
        return true
    end
    if self.has_no_mode or (self.settings.lock_tap and not ignore_lock) then
        return
    end
    if self.settings.all_at_once or self.has_no_mode then
        if self.mode >= 1 then
            self.mode = self.mode_list.off
        else
            self.mode = self.mode_list.page_progress
        end
    else
        self.mode = (self.mode + 1) % self.mode_nb
        for i, m in ipairs(self.mode_index) do
            if self.mode == self.mode_list.off then break end
            if self.mode == i then
                if self.settings[m] then
                    break
                else
                    self.mode = (self.mode + 1) % self.mode_nb
                end
            end
        end
    end
    self:applyFooterMode()
    G_reader_settings:saveSetting("reader_footer_mode", self.mode)
    self:onUpdateFooter(true)
    self:rescheduleFooterAutoRefreshIfNeeded()
    return true
end

function ReaderFooter:onHoldFooter(ges)
    -- We're higher priority than readerhighlight_hold, so, make sure we fall through properly...
    if not self.settings.skim_widget_on_hold then
        return
    end
    if not self.view.footer_visible then
        return
    end
    if not self.footer_content.dimen or not self.footer_content.dimen:contains(ges.pos) then
        -- We held outside the footer: meep!
        return
    end

    -- We're good, make sure we stop the event from going to readerhighlight_hold
    self.ui:handleEvent(Event:new("ShowSkimtoDialog"))
    return true
end

function ReaderFooter:refreshFooter(refresh, signal)
    self:updateFooterContainer()
    self:resetLayout(true)
    -- If we signal, the event we send will trigger a full repaint anyway, so we should be able to skip this one.
    -- We *do* need to ensure we at least re-compute the footer layout, though, especially when going from visible to invisible...
    self:onUpdateFooter(refresh and not signal, refresh and signal)
    if signal then
        if self.ui.document.provider == "crengine" then
            -- This will ultimately trigger an UpdatePos, hence a ReaderUI repaint.
            self.ui:handleEvent(Event:new("SetPageBottomMargin", self.ui.document.configurable.b_page_margin))
        else
            -- No fancy chain of events outside of CRe, just ask for a ReaderUI repaint ourselves ;).
            UIManager:setDirty(self.view.dialog, "partial")
        end
    end
end

function ReaderFooter:onResume()
    -- Don't repaint the footer until OutOfScreenSaver if screensaver_delay is enabled...
    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    if screensaver_delay and screensaver_delay ~= "disable" then
        self._delayed_screensaver = true
        return
    end

    -- Force a footer repaint on resume if it was visible
    self:onUpdateFooter(self.view.footer_visible)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onOutOfScreenSaver()
    if not self._delayed_screensaver then
        return
    end

    self._delayed_screensaver = nil
    -- Force a footer repaint on resume if it was visible
    self:onUpdateFooter(self.view.footer_visible)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onSuspend()
    self:unscheduleFooterAutoRefresh()
end

function ReaderFooter:onCloseDocument()
    self:unscheduleFooterAutoRefresh()
end

-- Used by event handlers that can trip without direct UI interaction...
function ReaderFooter:maybeUpdateFooter()
    -- ...so we need to avoid stomping over unsuspecting widgets (usually, ScreenSaver).
    if UIManager:getTopWidget() == "ReaderUI" then
        self:onUpdateFooter(self.view.footer_visible)
    else
        self:onUpdateFooter()
    end
end

function ReaderFooter:onFrontlightStateChanged()
    if self.settings.frontlight then
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onNetworkConnected()
    if self.settings.wifi_status then
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onNetworkDisconnected()
    if self.settings.wifi_status then
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onCharging()
    self:maybeUpdateFooter()
end

function ReaderFooter:onNotCharging()
    self:maybeUpdateFooter()
end

function ReaderFooter:onSetRotationMode()
    self:updateFooterContainer()
    self:resetLayout(true)
end

function ReaderFooter:onSetPageHorizMargins(h_margins)
    self.book_margins_footer_width = math.floor((h_margins[1] + h_margins[2])/2)
    if self.settings.progress_margin then
        self.settings.progress_margin_width = Screen:scaleBySize(self.book_margins_footer_width)
        self:refreshFooter(true)
    end
end

function ReaderFooter:onScreenResize()
    self:updateFooterContainer()
    self:resetLayout(true)
end

return ReaderFooter
