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
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

local MODE = {
    off = 0,
    page_progress = 1,
    time = 2,
    pages_left = 3,
    battery = 4,
    percentage = 5,
    book_time_to_read = 6,
    chapter_time_to_read = 7,
    frontlight = 8,
    mem_usage = 9,
    wifi_status = 10,
    book_title = 11,
    book_chapter = 12,
}

local symbol_prefix = {
    letters = {
        time = nil,
        pages_left = "=>",
        -- @translators This is the footer letter prefix for battery % remaining.
        battery = C_("FooterLetterPrefix", "B:"),
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
        pages_left = BD.mirroredUILayout() and "⇐" or "⇒",
        battery = "",
        percentage = BD.mirroredUILayout() and "⤟" or "⤠",
        book_time_to_read = "⏳",
        chapter_time_to_read = BD.mirroredUILayout() and "⥖" or "⤻",
        frontlight = "☼",
        mem_usage = "",
        wifi_status = "",
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
local DMINIBAR_TOC_MARKER_WIDTH = 2
local DMINIBAR_FONT_SIZE = 14

-- android: guidelines for rounded corner margins
local material_pixels = 16 * math.floor(Screen:getDPI() / 160)

-- functions that generates footer text for each mode
local footerTextGeneratorMap = {
    empty = function() return "" end,
    frontlight = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].frontlight
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            if Device:isCervantes() or Device:isKobo() then
                return (prefix .. " %d%%"):format(powerd:frontlightIntensity())
            else
                return (prefix .. " %d"):format(powerd:frontlightIntensity())
            end
        else
            return T(_("%1 Off"), prefix)
        end
    end,
    battery = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].battery
        local powerd = Device:getPowerDevice()
        local batt_lvl = powerd:getCapacity()
        -- If we're using icons, use fancy variable icons
        if symbol_type == "icons" then
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
            return BD.wrap(prefix) .. batt_lvl .. "%"
        else
            return BD.wrap(prefix) .. " " .. (powerd:isCharging() and "+" or "") .. batt_lvl .. "%"
        end
    end,
    time = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].time
        local clock
        if footer.settings.time_format == "12" then
            if os.date("%p") == "AM" then
                -- @translators This is the time in the morning in the 12-hour clock (%I is the hour, %M the minute).
                clock = os.date(_("%I:%M AM"))
            else
                -- @translators This is the time in the afternoon in the 12-hour clock (%I is the hour, %M the minute).
                clock = os.date(_("%I:%M PM"))
            end
        else
            -- @translators This is the time in the 24-hour clock (%H is the hour, %M the minute).
            clock = os.date(_("%H:%M"))
        end
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
            return ("%d / %d"):format(footer.pageno, footer.pages)
        elseif footer.position then
            return ("%d / %d"):format(footer.position, footer.doc_height)
        end
    end,
    pages_left = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].pages_left
        local left = footer.ui.toc:getChapterPagesLeft(
            footer.pageno, footer.toc_level)
        return prefix .. " " .. (left and left or footer.pages - footer.pageno)
    end,
    percentage = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].percentage
        local digits = footer.settings.progress_pct_format or "0"
        local string_percentage
        if not prefix then
            string_percentage = "%." .. digits .. "f%%"
        else
            string_percentage = prefix .. " %." .. digits .. "f%%"
        end
        return string_percentage:format(footer.progress_bar.percentage * 100)
    end,
    book_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].book_time_to_read
        local current_page = footer.ui:getCurrentPage()
        return footer:getDataFromStatistics(prefix .. " ", footer.pages - current_page)
    end,
    chapter_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].chapter_time_to_read
        local left = footer.ui.toc:getChapterPagesLeft(
            footer.pageno, footer.toc_level)
        return footer:getDataFromStatistics(
            prefix .. " ", (left and left or footer.pages - footer.pageno))
    end,
    mem_usage = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].mem_usage
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local infos = statm:read("*all")
            statm:close()
            local rss = infos:match("^%S+ (%S+) ")
            -- we got the nb of 4Kb-pages used, that we convert to Mb
            rss = math.floor(tonumber(rss) * 4096 / 1024 / 1024)
            return (prefix .. " %d"):format(rss)
        end
        return ""
    end,
    wifi_status = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].wifi_status
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isWifiOn() then
            return T(_("%1 On"), prefix)
        else
            return T(_("%1 Off"), prefix)
        end
    end,
    book_title = function(footer)
        local doc_info = footer.ui.document:getProps()
        if doc_info and doc_info.title then
            local title_widget = TextWidget:new{
                text = doc_info.title,
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
            return
        end
    end,
    book_chapter = function(footer)
        local chapter_title = footer.ui.toc:getTocTitleByPage(footer.pageno)
        if chapter_title and chapter_title ~= "" then
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
            return
        end
    end
}

local ReaderFooter = WidgetContainer:extend{
    mode = MODE.page_progress,
    pageno = nil,
    pages = nil,
    toc_level = 0,
    progress_percentage = 0.0,
    footer_text = nil,
    text_font_face = "ffont",
    height = Screen:scaleBySize(DMINIBAR_CONTAINER_HEIGHT),
    horizontal_margin = Size.span.horizontal_default,
    text_left_margin = Size.span.horizontal_default,
    bottom_padding = Size.padding.tiny,
    settings = {},
    -- added to expose them to unit tests
    textGeneratorMap = footerTextGeneratorMap,
}

function ReaderFooter:init()
    self.settings = G_reader_settings:readSetting("footer") or {
        -- enable progress bar by default
        -- disable_progress_bar = true,
        disabled = false,
        all_at_once = false,
        reclaim_height = false,
        toc_markers = true,
        battery = Device:hasBattery(),
        time = true,
        page_progress = true,
        pages_left = true,
        percentage = true,
        book_time_to_read = true,
        chapter_time_to_read = true,
        frontlight = false,
        mem_usage = false,
        wifi_status = false,
        book_title = false,
        book_chapter = false,
        item_prefix = "icons",
        toc_markers_width = DMINIBAR_TOC_MARKER_WIDTH,
        text_font_size = DMINIBAR_FONT_SIZE,
        text_font_bold = false,
        container_height = DMINIBAR_CONTAINER_HEIGHT,
        container_bottom_padding = 1, -- unscaled_size_check: ignore
    }

    -- Remove items not supported by the current device
    if not Device:isAndroid() then
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
    if not self.settings.container_height then
        self.settings.container_height = DMINIBAR_CONTAINER_HEIGHT
    end
    self.height = Screen:scaleBySize(self.settings.container_height)
    if not self.settings.container_bottom_padding then
        self.settings.container_bottom_padding = 1 -- unscaled_size_check: ignore
    end
    self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)

    -- default margin (like self.horizontal_margin)
    if not self.settings.progress_margin_width  then
        local defaults = Device:isAndroid() and material_pixels or 10
        self.settings.progress_margin_width = Screen:scaleBySize(defaults)
    end
    if not self.settings.toc_markers_width then
        self.settings.toc_markers_width = DMINIBAR_TOC_MARKER_WIDTH
    end
    if not self.settings.progress_bar_min_width_pct then
        self.settings.progress_bar_min_width_pct = 20
    end
    if not self.settings.book_title_max_width_pct then
        self.settings.book_title_max_width_pct = 30
    end
    if not self.settings.book_chapter_max_width_pct then
        self.settings.book_chapter_max_width_pct = 30
    end
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
    self.reclaim_height = self.settings.reclaim_height or false
    for _, m in ipairs(self.mode_index) do
        if self.settings[m] then
            self.has_no_mode = false
            break
        end
    end

    if not self.settings.text_font_size then
        self.settings.text_font_size = DMINIBAR_FONT_SIZE
    end
    if not self.settings.text_font_bold then
        self.settings.text_font_bold = false
    end
    self.footer_text = TextWidget:new{
        text = '',
        face = Font:getFace(self.text_font_face, self.settings.text_font_size),
        bold = self.settings.text_font_bold,
    }
    -- all width related values will be initialized in self:resetLayout()
    self.text_width = 0
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
        self.footer_container.dimen.h = 0
        self.footer_text.height = 0
    end
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
        self:updateFooterTextGenerator()
        if self.settings.progress_bar_position and self.has_no_mode then
            self.footer_container.dimen.h = 0
            self.footer_text.height = 0
        end
    else
        self:applyFooterMode()
    end
    if self.settings.auto_refresh_time then
        self:setupAutoRefreshTime()
    end
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
    if self.settings.progress_bar_position and not self.settings.disable_progress_bar then
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

function ReaderFooter:setupAutoRefreshTime()
    if not self.autoRefreshTime then
        self.autoRefreshTime = function()
            self:onUpdateFooter(true)
            UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
        end
    end
    self.onCloseDocument = function()
        UIManager:unschedule(self.autoRefreshTime)
    end
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
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
                "tap_forward",
                "tap_backward",
                "readerconfigmenu_tap",
            },
            -- (Low priority: tap on existing highlights
            -- or links have priority)
        },
        {
            id = "readerfooter_hold",
            ges = "hold",
            screen_zone = footer_screen_zone,
            handler = function() return self:onHoldFooter() end,
            -- (Low priority: word lookup and text selection
            -- have priority - SkimTo widget can be more easily
            -- brought up via some other gestures)
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
    elseif self.settings.progress_bar_position then
        self.progress_bar.width = math.floor(new_screen_width - 2 * self.settings.progress_margin_width)
    else
        self.progress_bar.width = math.floor(
            new_screen_width - self.text_width - self.settings.progress_margin_width*2)
    end
    if self.separator_line then
        self.separator_line.dimen.w = new_screen_width - 2 * self.horizontal_margin
    end
    local bar_height
    if self.settings.progress_style_thin then
        bar_height = self.settings.progress_style_thin_height or PROGRESS_BAR_STYLE_THIN_DEFAULT_HEIGHT
    else
        bar_height = self.settings.progress_style_thick_height or PROGRESS_BAR_STYLE_THICK_DEFAULT_HEIGHT
    end
    self.progress_bar.height = Screen:scaleBySize(bar_height)

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
        return self.footer_content:getSize().h
    else
        return 0
    end
end

function ReaderFooter:disableFooter()
    self.onReaderReady = function() end
    self.resetLayout = function() end
    self.onCloseDocument = nil
    self.updateFooterPage = function() end
    self.updateFooterPos = function() end
    self.onUpdatePos = function() end
    self.onSetStatusLine = function() end
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
        self.footerTextGenerators = footerTextGenerators
        self.genFooterText = self.genAllFooterText
    end
    -- notify caller that UI needs update
    return true
end

function ReaderFooter:progressPercentage(digits)
    local symbol_type = self.settings.item_prefix or "icons"
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
    local symbol = self.settings.item_prefix or "icons"
    local option_titles = {
        all_at_once = _("Show all at once"),
        reclaim_height = _("Reclaim bar height from bottom margin"),
        page_progress = T(_("Current page (%1)"), "/"),
        time = symbol_prefix[symbol].time
            and T(_("Current time (%1)"), symbol_prefix[symbol].time) or _("Current time"),
        pages_left = T(_("Pages left in chapter (%1)"), symbol_prefix[symbol].pages_left),
        battery = T(_("Battery status (%1)"), symbol_prefix[symbol].battery),
        percentage = symbol_prefix[symbol].percentage
            and T(_("Progress percentage (%1)"), symbol_prefix[symbol].percentage) or ("Progress percentage"),
        book_time_to_read = T(_("Book time to read (%1)"),symbol_prefix[symbol].book_time_to_read),
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
                G_reader_settings:saveSetting("footer", self.settings)
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
                self.reclaim_height = self.settings.reclaim_height or false
                -- refresh margins position
                if self.has_no_mode then
                    self.footer_container.dimen.h = 0
                    self.footer_text.height = 0
                    should_signal = true
                    self.genFooterText = footerTextGeneratorMap.empty
                    self.mode = self.mode_list.off
                elseif prev_has_no_mode then
                    self.footer_container.dimen.h = self.height
                    self.footer_text.height = self.height
                    if self.settings.all_at_once then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                    end
                    should_signal = true
                    G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
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
                end
                if should_update or should_signal then
                    self:refreshFooter(should_update, should_signal)
                end
            end,
        }
    end
    table.insert(sub_items, {
        text = _("Settings"),
        sub_item_table = {
            {
                text = _("Sort items"),
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
                            G_reader_settings:saveSetting("footer", self.settings)
                            self:updateFooterTextGenerator()
                            self:onUpdateFooter()
                            UIManager:setDirty(nil, "ui")
                        end
                    }
                    UIManager:show(sort_item)
                end,
            },
            getMinibarOption("all_at_once", self.updateFooterTextGenerator),
            getMinibarOption("reclaim_height"),
            {
                text = _("Auto refresh time"),
                checked_func = function()
                    return self.settings.auto_refresh_time == true
                end,
                -- only enable auto refresh when time is shown
                enabled_func = function() return self.settings.time end,
                callback = function()
                    self.settings.auto_refresh_time = not self.settings.auto_refresh_time
                    G_reader_settings:saveSetting("footer", self.settings)
                    if self.settings.auto_refresh_time then
                        self:setupAutoRefreshTime()
                    else
                        UIManager:unschedule(self.autoRefreshTime)
                        self.onCloseDocument = nil
                    end
                end
            },
            {
                text = _("Show footer separator"),
                checked_func = function()
                    return self.settings.bottom_horizontal_separator
                end,
                callback = function()
                    self.settings.bottom_horizontal_separator = not self.settings.bottom_horizontal_separator
                    self:refreshFooter(true, true)
                end,
            },
            {
                text = _("Lock status bar"),
                checked_func = function()
                    return self.settings.lock_tap
                end,
                callback = function()
                    self.settings.lock_tap = not self.settings.lock_tap
                end,
            },
            {
                text = _("Font"),
                separator = true,
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
                    return self.settings.disable_progress_bar or self.settings.progress_bar_position ~= nil
                end,
                sub_item_table = {
                    {
                        text = _("Center"),
                        checked_func = function()
                            return self.settings.align == "center" or self.settings.align == nil
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
                            return self.settings.item_prefix == "icons" or self.settings.item_prefix == nil
                        end,
                        callback = function()
                            self.settings.item_prefix = "icons"
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
                            return self.settings.items_separator == "bar" or self.settings.items_separator == nil
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
                            return self.settings.progress_pct_format == "0" or self.settings.progress_pct_format == nil
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
            {
                text = _("Time format"),
                sub_item_table = {
                    {
                        text_func = function()
                            local footer = {}
                            footer.settings = {}
                            footer.settings.time_format = "24"
                            footer.settings.item_prefix = self.settings.item_prefix or "icons"
                            return T(_("24-hour (%1)"),footerTextGeneratorMap.time(footer))
                        end,
                        checked_func = function()
                            return self.settings.time_format == "24" or self.settings.time_format == nil
                        end,
                        callback = function()
                            self.settings.time_format = "24"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text_func = function()
                            local footer = {}
                            footer.settings = {}
                            footer.settings.time_format = "12"
                            footer.settings.item_prefix = self.settings.item_prefix or "icons"
                            return T(_("12-hour (%1)"),footerTextGeneratorMap.time(footer))
                        end,
                        checked_func = function()
                            return self.settings.time_format == "12"
                        end,
                        callback = function()
                            self.settings.time_format = "12"
                            self:refreshFooter(true)
                        end,
                    },
                }
            },
            {
                text = _("Duration format"),
                sub_item_table = {
                    {
                        text_func = function()
                            local current_duration_format = self.settings.duration_format
                            local return_text
                            self.settings.duration_format = "modern"
                            return_text = footerTextGeneratorMap.book_time_to_read(self)
                            self.settings.duration_format = current_duration_format
                            return T(_("Modern (%1)"), return_text)
                        end,
                        checked_func = function()
                            return self.settings.duration_format == "modern" or self.settings.duration_format == nil
                        end,
                        callback = function()
                            self.settings.duration_format = "modern"
                            self:refreshFooter(true)
                        end,
                    },
                    {
                        text_func = function()
                            local current_duration_format = self.settings.duration_format
                            local return_text
                            self.settings.duration_format = "classic"
                            return_text = footerTextGeneratorMap.book_time_to_read(self)
                            self.settings.duration_format = current_duration_format
                            return T(_("Classic (%1)"), return_text)
                        end,
                        checked_func = function()
                            return self.settings.duration_format == "classic"
                        end,
                        callback = function()
                            self.settings.duration_format = "classic"
                            self:refreshFooter(true)
                        end,
                    },
                }
            },
        }
    })
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
                        self.footer_container.dimen.h = self.height
                        self.footer_text.height = self.height
                        self:setTocMarkers()
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
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
                            return not self.settings.progress_bar_position
                        end,
                        callback = function()
                            if self.settings.progress_margin then
                                self.settings.progress_margin = false
                                self.settings.progress_margin_width = Size.span.horizontal_default
                            end
                            self.settings.progress_bar_position = nil
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
                            local bar_height = self.settings.progress_style_thick_height or PROGRESS_BAR_STYLE_THICK_DEFAULT_HEIGHT
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
                            local bar_height = self.settings.progress_style_thin_height or PROGRESS_BAR_STYLE_THIN_DEFAULT_HEIGHT
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
                            return self.settings.toc_markers
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
                                return not self.ui.document.info.has_pages and self.settings.progress_bar_position ~= nil
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
                    return not self.settings.progress_bar_position and not self.settings.disable_progress_bar
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
    table.insert(sub_items, getMinibarOption("time"))
    table.insert(sub_items, getMinibarOption("pages_left"))
    if Device:hasBattery() then
        table.insert(sub_items, getMinibarOption("battery"))
    end
    table.insert(sub_items, getMinibarOption("percentage"))
    table.insert(sub_items, getMinibarOption("book_time_to_read"))
    table.insert(sub_items, getMinibarOption("chapter_time_to_read"))
    if Device:hasFrontlight() then
        table.insert(sub_items, getMinibarOption("frontlight"))
    end
    table.insert(sub_items, getMinibarOption("mem_usage"))
    if Device:isAndroid() then
        table.insert(sub_items, getMinibarOption("wifi_status"))
    end
    table.insert(sub_items, getMinibarOption("book_title"))
    table.insert(sub_items, getMinibarOption("book_chapter"))
end

-- this method will be updated at runtime based on user setting
function ReaderFooter:genFooterText() end

function ReaderFooter:genAllFooterText()
    local info = {}
    local separator = "  "
    if self.settings.items_separator == "bar" or self.settings.items_separator == nil then
        separator = " | "
    elseif self.settings.items_separator == "bullet" then
        separator = " • "
    end
    -- We need to BD.wrap() all items and separators, so we're
    -- sure they are laid out in our order (reversed in RTL),
    -- without ordering by the RTL Bidi algorithm.
    for _, gen in ipairs(self.footerTextGenerators) do
        table.insert(info, BD.wrap(gen(self)))
    end
    return table.concat(info, BD.wrap(separator))
end

function ReaderFooter:setTocMarkers(reset)
    if self.settings.disable_progress_bar or self.settings.progress_style_thin then return end
    if reset then
        self.progress_bar.ticks = nil
        self.pages = self.view.document:getPageCount()
    end
    if self.settings.toc_markers then
        self.progress_bar.tick_width = Screen:scaleBySize(self.settings.toc_markers_width)
        if self.progress_bar.ticks ~= nil then -- already computed
            return
        end
        self.progress_bar.ticks = {}
        if self.ui.toc then
            self.progress_bar.ticks = self.ui.toc:getTocTicksForFooter()
        end
        self.progress_bar.last = self.pages or self.view.document:getPageCount()
    else
        self.progress_bar.ticks = nil
    end
    -- notify caller that UI needs update
    return true
end

function ReaderFooter:getAvgTimePerPage()
    return
end

function ReaderFooter:getDataFromStatistics(title, pages)
    local sec = 'na'
    local average_time_per_page = self:getAvgTimePerPage()
    if average_time_per_page then
        if self.settings.duration_format == "classic" then
            sec = util.secondsToClock(pages * average_time_per_page, true)
        else
            sec = util.secondsToHClock(pages * average_time_per_page, true)
        end
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
    self.progress_bar.percentage = self.pageno / self.pages
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
    self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.settings.progress_margin_width))
    if self.settings.disable_progress_bar then
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_container.dimen.h = 0
            self.footer_text.height = 0
        else
            self.text_width = self.footer_text:getSize().w
        end
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position then
        if text == "" then
            self.footer_container.dimen.h = 0
            self.footer_text.height = 0
        end
        self.progress_bar.width = math.floor(self._saved_screen_width - 2 * self.settings.progress_margin_width)
        self.text_width = self.footer_text:getSize().w
    else
        if self.has_no_mode or text == "" then
            self.text_width = 0
        else
            local text_max_available_ratio = (100 - self.settings.progress_bar_min_width_pct) / 100
            self.footer_text:setMaxWidth(math.floor(text_max_available_ratio * self._saved_screen_width - 2 * self.settings.progress_margin_width))
            self.text_width = self.footer_text:getSize().w + self.text_left_margin
        end
        self.progress_bar.width = math.floor(
            self._saved_screen_width - self.text_width - self.settings.progress_margin_width*2)
    end
    local bar_height
    if self.settings.progress_style_thin then
        bar_height = self.settings.progress_style_thin_height or PROGRESS_BAR_STYLE_THIN_DEFAULT_HEIGHT
    else
        bar_height = self.settings.progress_style_thick_height or PROGRESS_BAR_STYLE_THICK_DEFAULT_HEIGHT
    end
    self.progress_bar.height = Screen:scaleBySize(bar_height)

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
        -- NOTE: We need to repaint everything when toggling the progress bar, for some reason.
        UIManager:setDirty(self.view.dialog, function()
            return "ui", self.footer_content.dimen
        end)
    end
end

function ReaderFooter:onPageUpdate(pageno)
    self.pageno = pageno
    self.pages = self.view.document:getPageCount()
    self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    self:updateFooterPage()
end

function ReaderFooter:onPosUpdate(pos, pageno)
    self.position = pos
    self.doc_height = self.view.document.info.doc_height
    if pageno then
        self.pageno = pageno
        self.pages = self.view.document:getPageCount()
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
end

function ReaderFooter:onReadSettings(config)
    if not self.ui.document.info.has_pages then
        local h_margins = config:readSetting("copt_h_page_margins") or
            G_reader_settings:readSetting("copt_h_page_margins") or
            DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM
        self.book_margins_footer_width = math.floor((h_margins[1] + h_margins[2])/2)
    end
end

function ReaderFooter:applyFooterMode(mode)
    -- three modes switcher for reader footer
    -- 0 for footer off
    -- 1 for footer page info
    -- 2 for footer time info
    -- 3 for footer next_chapter info
    -- 4 for battery status
    -- 5 for progress percentage
    -- 6 for from statistics book time to read
    -- 7 for from statistics chapter time to read
    -- 8 for front light level
    -- 9 for memory usage
    -- 10 for Wi-Fi status
    -- 11 for book title
    -- 12 for current chapter

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
    end
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(self.mode_list.page_progress)
end

function ReaderFooter:onExitFlippingMode()
    self:applyFooterMode(self.orig_mode)
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
    return true
end

function ReaderFooter:onHoldFooter()
    if self.mode == self.mode_list.off then return end
    self.ui:handleEvent(Event:new("ShowSkimtoDialog"))
    return true
end

function ReaderFooter:setVisible(visible)
    if visible then
        -- If it was off, just do as if we tap'ed on it (so we don't
        -- duplicate onTapFooter() code)
        if self.mode == self.mode_list.off then
            self:onTapFooter(true) -- ignore tap lock
        end
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
    else
        self:applyFooterMode(self.mode_list.off)
    end
end

function ReaderFooter:refreshFooter(refresh, signal)
    self:updateFooterContainer()
    self:resetLayout(true)
    -- If we signal, the event we send will trigger a full repaint anyway, so we should be able to skip this one.
    -- We *do* need to ensure we at least re-compute the footer layout, though, especially when going from visible to invisible...
    self:onUpdateFooter(refresh and not signal, refresh and signal)
    if signal then
        self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
    end
end

function ReaderFooter:onResume()
    self:onUpdateFooter()
    if self.settings.auto_refresh_time then
        self:setupAutoRefreshTime()
    end
end

function ReaderFooter:onSuspend()
    if self.settings.auto_refresh_time then
        UIManager:unschedule(self.autoRefreshTime)
        self.onCloseDocument = nil
    end
end

function ReaderFooter:onFrontlightStateChanged()
    if self.settings.frontlight then
        self:onUpdateFooter(true)
    end
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
