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
}

local symbol_prefix = {
    letters = {
        time = nil,
        pages_left = "=>",
        battery = "B:",
        percentage = "R:",
        book_time_to_read = "TB:",
        chapter_time_to_read = "TC:",
        frontlight = "L:",
        mem_usage = "M:",
        wifi_status = "W:",
    },
    icons = {
        time = "⌚",
        pages_left = "⇒",
        battery = "⚡",
        percentage = "⤠",
        book_time_to_read = "⏳",
        chapter_time_to_read = "⤻",
        frontlight = "☼",
        mem_usage = "≡",
        wifi_status = "⚟",
    }
}

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
        return prefix .. " " .. (powerd:isCharging() and "+" or "") .. powerd:getCapacity() .. "%"
    end,
    time = function(footer)
        local symbol_type = footer.settings.item_prefix or "icons"
        local prefix = symbol_prefix[symbol_type].time
        local clock
        if footer.settings.time_format == "12" then
            clock = os.date("%I:%M%p")
        else
            clock = os.date("%H:%M")
        end
        if not prefix then
            return clock
        else
            return prefix .. " " .. clock
        end
    end,
    page_progress = function(footer)
        if footer.pageno then
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
        local current_page
        if footer.view.document.info.has_pages then
            current_page = footer.ui.paging.current_page
        else
            current_page = footer.view.document:getCurrentPage()
        end
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
}

local ReaderFooter = WidgetContainer:extend{
    mode = MODE.page_progress,
    pageno = nil,
    pages = nil,
    toc_level = 0,
    progress_percentage = 0.0,
    footer_text = nil,
    text_font_face = "ffont",
    text_font_size = DMINIBAR_FONT_SIZE,
    bar_height = Screen:scaleBySize(DMINIBAR_HEIGHT),
    height = Screen:scaleBySize(DMINIBAR_CONTAINER_HEIGHT),
    horizontal_margin = Screen:scaleBySize(10),
    text_left_margin = Screen:scaleBySize(10),
    bottom_padding = Screen:scaleBySize(1),
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
        battery = true,
        time = true,
        page_progress = true,
        pages_left = true,
        percentage = true,
        book_time_to_read = true,
        chapter_time_to_read = true,
        frontlight = false,
        mem_usage = false,
        wifi_status = false,
        item_prefix = "icons"
    }

    if not self.settings.order then
        self.mode_nb = 0
        self.mode_index = {}
        local mode_tbl = {}
        for k,v in pairs(MODE) do
            mode_tbl[v] = k
        end
        local mode_name
        for i = 0, #mode_tbl do
            mode_name = mode_tbl[i]
            if mode_name == "wifi_status" and not Device:isAndroid() then
                do end -- luacheck: ignore 541
            elseif mode_name == "frontlight" and not Device:hasFrontlight() then
                do end -- luacheck: ignore 541
            else
                self.mode_index[self.mode_nb] = mode_name
                self.mode_nb = self.mode_nb + 1
            end
        end
    else
        self.mode_index = self.settings.order
        self.mode_nb = #self.mode_index
    end
    self.mode_list = {}
    for i = 0, #self.mode_index do
        self.mode_list[self.mode_index[i]] = i
    end
    if self.settings.disabled then
        -- footer featuren disabled completely, stop initialization now
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

    self.footer_text = TextWidget:new{
        text = '',
        face = Font:getFace(self.text_font_face, self.text_font_size),
    }
    -- all width related values will be initialized in self:resetLayout()
    self.text_width = 0
    self.progress_bar = ProgressWidget:new{
        width = nil,
        height = self.bar_height,
        percentage = self.progress_percentage,
        tick_width = DMINIBAR_TOC_MARKER_WIDTH,
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }
    self.bottom_progress = LineWidget:new{
        progress_background = Blitbuffer.COLOR_DIM_GRAY,
        progress_percentage = self.progress_percentage,
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new{
            w = nil,
            h = Size.line.progress,
        }
    }
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
    end
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
        self:updateFooterTextGenerator()
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
        local vertical_span = VerticalSpan:new{width = self.bottom_padding *2}
        table.insert(self.vertical_frame, self.separator_line)
        table.insert(self.vertical_frame, vertical_span)
    end
    if self.settings.progress_bar_separate_line and not self.settings.disable_progress_bar then
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.text_container,
            margin_span,
        }
        local vertical_span = VerticalSpan:new{width = self.bottom_padding *2}
        table.insert(self.vertical_frame, self.progress_bar)
        table.insert(self.vertical_frame, vertical_span)
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

    table.insert(self.vertical_frame, self.footer_container)

    if self.settings.progress_bar_bottom and not self.settings.disable_progress_bar then
        table.insert(self.vertical_frame, self.bottom_progress)
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
            self:updateFooter(true)
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
        },
        {
            id = "readerfooter_hold",
            ges = "hold",
            screen_zone = footer_screen_zone,
            handler = function() return self:onHoldFooter() end,
            overrides = {
                "readerhighlight_hold",
            },
        },
    })
end

-- call this method whenever the screen size changes
function ReaderFooter:resetLayout(force_reset)
    local new_screen_width = Screen:getWidth()
    local new_screen_height = Screen:getHeight()
    if new_screen_width == self._saved_screen_width
        and new_screen_height == self._saved_screen_height and not force_reset then return end

    if self.settings.disable_progress_bar or self.settings.progress_bar_bottom then
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_separate_line then
        self.progress_bar.width = math.floor(new_screen_width - self.horizontal_margin*2)
    else
        self.progress_bar.width = math.floor(
            new_screen_width - self.text_width - self.horizontal_margin*2)
    end
    if self.separator_line then
        self.separator_line.dimen.w = new_screen_width - 2 * self.horizontal_margin
    end
    if self.settings.progress_bar_bottom then
        self.bottom_progress.dimen.w = new_screen_width - 2 * self.horizontal_margin
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
        return self.footer_content:getSize().h
    else
        return 0
    end
end

function ReaderFooter:disableFooter()
    self.onReaderReady = function() end
    self.resetLayout = function() end
    self.onCloseDocument = nil
    self.onPageUpdate = function() end
    self.onPosUpdate = function() end
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
            callback = function() self:onTapFooter() end,
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
                    self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
                    self.genFooterText = footerTextGeneratorMap.empty
                    self.mode = self.mode_list.off
                elseif prev_has_no_mode then
                    self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
                    G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
                elseif self.reclaim_height ~= prev_reclaim_height then
                    self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
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
                    end
                    should_update = true
                    self:applyFooterMode()
                end
                if should_update then
                    self:updateFooter()
                    UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
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
                separator = true,
                checked_func = function()
                    return self.settings.bottom_horizontal_separator
                end,
                callback = function()
                    self.settings.bottom_horizontal_separator = not self.settings.bottom_horizontal_separator
                    self:refreshFooter()
                    self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
                    UIManager:setDirty(nil, "ui")
                end,
            },
            {
                text = _("Alignment"),
                enabled_func = function()
                    return self.settings.disable_progress_bar or self.settings.progress_bar_separate_line or self.settings.progress_bar_bottom
                end,
                sub_item_table = {
                    {
                        text = _("Center"),
                        checked_func = function()
                            return self.settings.align == "center" or self.settings.align == nil
                        end,
                        callback = function()
                            self.settings.align = "center"
                            self:refreshFooter()
                            UIManager:setDirty(nil, "ui")
                        end,
                    },
                    {
                        text = _("Left"),
                        checked_func = function()
                            return self.settings.align == "left"
                        end,
                        callback = function()
                            self.settings.align = "left"
                            self:refreshFooter()
                            UIManager:setDirty(nil, "ui")
                        end,
                    },
                    {
                        text = _("Right"),
                        checked_func = function()
                            return self.settings.align == "right"
                        end,
                        callback = function()
                            self.settings.align = "right"
                            self:refreshFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
                        end,
                    },
                    {
                        text = _("Bullet (•)"),
                        checked_func = function()
                            return self.settings.items_separator == "bullet"
                        end,
                        callback = function()
                            self.settings.items_separator = "bullet"
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
                        end,
                    },
                    {
                        text = _("No separator"),
                        checked_func = function()
                            return self.settings.items_separator == "none"
                        end,
                        callback = function()
                            self.settings.items_separator = "none"
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                            self:updateFooter()
                            UIManager:setDirty(nil, "ui")
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
                    self:setTocMarkers()
                    self:refreshFooter()
                    if self.settings.progress_bar_separate_line or self.settings.progress_bar_bottom then
                        self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
                    end
                    UIManager:setDirty(nil, "ui")
                end,
            },
            {
                text = _("Show chapter markers"),
                checked_func = function()
                    return self.settings.toc_markers
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar and not self.settings.progress_bar_bottom
                end,
                callback = function()
                    self.settings.toc_markers = not self.settings.toc_markers
                    self:setTocMarkers()
                    self:updateFooter()
                    UIManager:setDirty(nil, "ui")
                end,
                separator = true,
            },
            {
                text = _("Progress bar on separate line"),
                checked_func = function()
                    return self.settings.progress_bar_separate_line
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.progress_bar_separate_line = not self.settings.progress_bar_separate_line
                    if self.settings.progress_bar_separate_line then
                        self.settings.progress_bar_bottom = nil
                    end
                    self:refreshFooter()
                    self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
                    UIManager:setDirty(nil, "ui")
                end,
            },
            {
                text = _("Progress bar on the bottom"),
                checked_func = function()
                    return self.settings.progress_bar_bottom
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.progress_bar_bottom = not self.settings.progress_bar_bottom
                    if self.settings.progress_bar_bottom then
                        self.settings.progress_bar_separate_line = nil
                    end
                    self:refreshFooter()
                    self.ui:handleEvent(Event:new("SetPageBottomMargin", self.view.document.configurable.b_page_margin))
                    UIManager:setDirty(nil, "ui")
                end,
            },
        }
    })
    table.insert(sub_items, getMinibarOption("page_progress"))
    table.insert(sub_items, getMinibarOption("time"))
    table.insert(sub_items, getMinibarOption("pages_left"))
    table.insert(sub_items, getMinibarOption("battery"))
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
    for _, gen in ipairs(self.footerTextGenerators) do
        table.insert(info, gen(self))
    end
    return table.concat(info, separator)
end

function ReaderFooter:setTocMarkers(reset)
    if self.settings.disable_progress_bar then return end
    if reset then
        self.progress_bar.ticks = nil
        self.pages = self.view.document:getPageCount()
    end
    if self.settings.toc_markers then
        if self.progress_bar.ticks ~= nil then return end
        local ticks_candidates = {}
        if self.ui.toc then
            local max_level = self.ui.toc:getMaxDepth()
            for i = 0, -max_level, -1 do
                local ticks = self.ui.toc:getTocTicks(i)
                table.insert(ticks_candidates, ticks)
            end
            -- find the finest toc ticks by sorting out the largest one
            table.sort(ticks_candidates, function(a, b) return #a > #b end)
        end

        if #ticks_candidates > 0 then
            self.progress_bar.ticks = ticks_candidates[1]
            self.progress_bar.last = self.pages or self.view.document:getPageCount()
        else
            -- we still set ticks here so self.progress_bar.ticks will not be
            -- initialized again if ticks_candidates is empty
            self.progress_bar.ticks = {}
        end
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

function ReaderFooter:updateFooter(force_repaint)
    if self.pageno then
        self:updateFooterPage(force_repaint)
    else
        self:updateFooterPos(force_repaint)
    end
end

function ReaderFooter:updateFooterPage(force_repaint)
    if type(self.pageno) ~= "number" then return end
    self.progress_bar.percentage = self.pageno / self.pages
    self.bottom_progress.progress_percentage = self.progress_bar.percentage
    self:updateFooterText(force_repaint)
end

function ReaderFooter:updateFooterPos(force_repaint)
    if type(self.position) ~= "number" then return end
    self.progress_bar.percentage = self.position / self.doc_height
    self.bottom_progress.progress_percentage = self.progress_bar.percentage
    self:updateFooterText(force_repaint)
end

-- updateFooterText will start as a noop. After onReaderReady event is
-- received, it will initialized as _updateFooterText below
function ReaderFooter:updateFooterText(force_repaint)
end

-- only call this function after document is fully loaded
function ReaderFooter:_updateFooterText(force_repaint)
    local text = self:genFooterText()
    if text then
        self.footer_text:setText(text)
    end
    if self.settings.disable_progress_bar or self.settings.progress_bar_bottom then
        if self.has_no_mode or not text then
            self.text_width = 0
        else
            self.text_width = self.footer_text:getSize().w
        end
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_separate_line then
        self.progress_bar.width = math.floor(self._saved_screen_width - self.horizontal_margin*2)
        self.text_width = self.footer_text:getSize().w
    else
        if self.has_no_mode or not text then
            self.text_width = 0
        else
            self.text_width = self.footer_text:getSize().w + self.text_left_margin
        end
        self.progress_bar.width = math.floor(
            self._saved_screen_width - self.text_width - self.horizontal_margin*2)
    end
    if self.separator_line then
        self.separator_line.dimen.w = self._saved_screen_width - 2 * self.horizontal_margin
    end
    if self.settings.progress_bar_bottom then
        self.bottom_progress.dimen.w = self._saved_screen_width - 2 * self.horizontal_margin
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
ReaderFooter.onUpdatePos = ReaderFooter.updateFooter

function ReaderFooter:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self:setupTouchZones()
    self:resetLayout()  -- set widget dimen
    self:setTocMarkers()
    self.updateFooterText = self._updateFooterText
    self:updateFooter()
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
    -- 10 for wifi status
    if mode ~= nil then self.mode = mode end
    self.view.footer_visible = (self.mode ~= self.mode_list.off)

    -- If all-at-once is enabled, just hide, but the text will keep being processed...
    if self.settings.all_at_once then
        return
    end
    -- We're not in all-at-once mode, disable text generation entirely when we're hidden
    if not self.view.footer_visible then
        self.genFooterText = footerTextGeneratorMap.empty
        return
    end

    local mode_name = self.mode_index[self.mode]
    if not self.settings[mode_name] or self.has_no_mode then
        -- all modes disabled, only show progress bar
        mode_name = "empty"
    end
    self.genFooterText = footerTextGeneratorMap[mode_name]
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(self.mode_list.page_progress)
end

function ReaderFooter:onExitFlippingMode()
    self:applyFooterMode(self.orig_mode)
end

function ReaderFooter:onTapFooter(ges)
    if self.has_no_mode then
        return
    end
    if self.view.flipping_visible then
        local pos = ges.pos
        local dimen = self.progress_bar.dimen
        -- if reader footer is not drawn before the dimen value should be nil
        if dimen then
            local percentage = (pos.x - dimen.x)/dimen.w
            self.ui:handleEvent(Event:new("GotoPercentage", percentage))
        end
    else
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
    end
    self:updateFooter(true)
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
        -- duplicate onTapFooter() code - not if flipping_visible as in
        -- this case, a ges.pos argument to onTapFooter(ges) is required)
        if self.mode == self.mode_list.off and not self.view.flipping_visible then
            self:onTapFooter()
        end
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
    else
        self:applyFooterMode(self.mode_list.off)
    end
end

function ReaderFooter:refreshFooter()
    self:updateFooterContainer()
    self:resetLayout(true)
    self:updateFooter()
end

function ReaderFooter:onResume()
    self:updateFooter()
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
        self:updateFooter(true)
    end
end

function ReaderFooter:onChangeScreenMode()
    self:updateFooterContainer()
    self:resetLayout(true)
end

return ReaderFooter
