local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
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

local MODE_NB = 0
local MODE_INDEX = {}
for k,v in pairs(MODE) do
    MODE_INDEX[v] = k
    MODE_NB = MODE_NB + 1
end

-- functions that generates footer text for each mode
local footerTextGeneratorMap = {
    empty = function() return "" end,
    frontlight = function()
        if not Device:hasFrontlight() then return "L: NA" end
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            if Device:isKobo() then
                return ("L: %d%%"):format(powerd:frontlightIntensity())
            else
                return ("L: %d"):format(powerd:frontlightIntensity())
            end
        else
            return "L: Off"
        end
    end,
    battery = function()
        local powerd = Device:getPowerDevice()
        return "B:" .. (powerd:isCharging() and "+" or "") .. powerd:getCapacity() .. "%"
    end,
    time = function()
        return os.date("%H:%M")
    end,
    page_progress = function(footer)
        if footer.pageno then
            return ("%d / %d"):format(footer.pageno, footer.pages)
        else
            return ("%d / %d"):format(footer.position, footer.doc_height)
        end
    end,
    pages_left = function(footer)
        local left = footer.ui.toc:getChapterPagesLeft(
            footer.pageno, footer.toc_level)
        return "=> " .. (left and left or footer.pages - footer.pageno)
    end,
    percentage = function(footer)
        return ("R:%1.f%%"):format(footer.progress_bar.percentage * 100)
    end,
    book_time_to_read = function(footer)
        local current_page
        if footer.view.document.info.has_pages then
            current_page = footer.ui.paging.current_page
        else
            current_page = footer.view.document:getCurrentPage()
        end
        return footer:getDataFromStatistics("TB: ", footer.pages - current_page)
    end,
    chapter_time_to_read = function(footer)
        local left = footer.ui.toc:getChapterPagesLeft(
            footer.pageno, footer.toc_level)
        return footer:getDataFromStatistics(
            "TC: ", (left and left or footer.pages - footer.pageno))
    end,
    mem_usage = function(footer)
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local infos = statm:read("*all")
            statm:close()
            local rss = infos:match("^%S+ (%S+) ")
            -- we got the nb of 4Kb-pages used, that we convert to Mb
            rss = math.floor(tonumber(rss) * 4096 / 1024 / 1024)
            return ("M:%d"):format(rss)
        end
        return ""
    end,
    wifi_status = function()
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isWifiOn() then
            return "W:On"
        else
            return "W:Off"
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
    }

    if self.settings.disabled then
        -- footer featuren disabled completely, stop initialization now
        self:disableFooter()
        return
    end

    self.pageno = self.view.state.page
    self.has_no_mode = true
    for _, m in ipairs(MODE_INDEX) do
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
    self.text_container = RightContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.footer_text,
    }

    local margin_span = HorizontalSpan:new{ width = self.horizontal_margin }
    self.horizontal_group = HorizontalGroup:new{
        margin_span,
        self.progress_bar,
        self.text_container,
        margin_span,
    }

    self.footer_content = FrameContainer:new{
        self.horizontal_group,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }
    self.footer_container = BottomContainer:new{
        dimen = Geom:new{ w = 0, h = self.height*2 },
        self.footer_content,
    }
    self.footer_positioner = BottomContainer:new{
        dimen = Geom:new{},
        self.footer_container,
    }
    self[1] = self.footer_positioner

    self.mode = G_reader_settings:readSetting("reader_footer_mode") or self.mode
    if self.has_no_mode then
        self.mode = MODE.off
        self.view.footer_visible = false
        self:resetLayout()
    end
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= MODE.off)
        self:updateFooterTextGenerator()
    else
        self:applyFooterMode()
    end
    if self.settings.auto_refresh_time then
        self:setupAutoRefreshTime()
    end
end

function ReaderFooter:setupAutoRefreshTime()
    if not self.autoRefreshTime then
        self.autoRefreshTime = function()
            self:updateFooter()
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
                'tap_forward', 'tap_backward', 'readerconfigmenu_tap',
            },
        },
        {
            id = "readerfooter_hold",
            ges = "hold",
            screen_zone = footer_screen_zone,
            handler = function() return self:onHoldFooter() end,
            overrides = {'readerhighlight_hold'},
        },
    })
end

-- call this method whenever the screen size changes
function ReaderFooter:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._saved_screen_width then return end
    local new_screen_height = Screen:getHeight()

    if self.settings.disable_progress_bar then
        self.progress_bar.width = 0
    else
        self.progress_bar.width = math.floor(
            new_screen_width - self.text_width - self.horizontal_margin*2)
    end
    self.horizontal_group:resetLayout()
    self.footer_positioner.dimen.w = new_screen_width
    self.footer_positioner.dimen.h = new_screen_height
    self.footer_container.dimen.w = new_screen_width
    self.dimen = self.footer_positioner:getSize()

    self._saved_screen_width = new_screen_width
end

function ReaderFooter:getHeight()
    return self.footer_text:getSize().h
end

function ReaderFooter:disableFooter()
    self.onReaderReady = function() end
    self.resetLayout = function() end
    self.onCloseDocument = nil
    self.onPageUpdate = function() end
    self.onPosUpdate = function() end
    self.onUpdatePos = function() end
    self.onSetStatusLine = function() end
    self.mode = MODE.off
    self.view.footer_visible = false
end

function ReaderFooter:updateFooterTextGenerator()
    local footerTextGenerators = {}
    for _, m in pairs(MODE_INDEX) do
        if self.settings[m] then
            table.insert(footerTextGenerators,
                         footerTextGeneratorMap[m])
            if not self.settings.all_at_once then
                -- if not show all at once, then one is enough
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

local option_titles = {
    all_at_once = _("Show all at once"),
    toc_markers = _("Show chapter markers"),
    page_progress = _("Current page"),
    time = _("Current time"),
    pages_left = _("Pages left in chapter"),
    battery = _("Battery status"),
    percentage = _("Progress percentage"),
    book_time_to_read = _("Book time to read"),
    chapter_time_to_read = _("Chapter time to read"),
    frontlight = _("Frontlight level"),
    mem_usage = _("KOReader memory usage"),
    wifi_status = _("Wi-Fi status"),
}

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
            text = option_titles[option],
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
                self.has_no_mode = true
                for mode_num, m in pairs(MODE_INDEX) do
                    if self.settings[m] then
                        first_enabled_mode_num = mode_num
                        self.has_no_mode = false
                        break
                    end
                end
                -- refresh margins position
                if self.has_no_mode then
                    self.ui:handleEvent(Event:new("SetPageMargins", self.view.document.configurable.page_margins))
                    self.genFooterText = footerTextGeneratorMap.empty
                    self.mode = MODE.off
                elseif prev_has_no_mode then
                    self.ui:handleEvent(Event:new("SetPageMargins", self.view.document.configurable.page_margins))
                    G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
                end
                if callback then
                    should_update = callback(self)
                elseif self.settings.all_at_once then
                    should_update = self:updateFooterTextGenerator()
                elseif (MODE[option] == self.mode and self.settings[option] == false)
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
                    UIManager:setDirty("all", "partial")
                end
            end,
        }
    end

    table.insert(sub_items,
                 getMinibarOption("all_at_once", self.updateFooterTextGenerator))
    table.insert(sub_items, {
        text = _("Progress bar"),
        sub_item_table = {
            {
                text = _("Show progress bar"),
                checked_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.disable_progress_bar = not self.settings.disable_progress_bar
                    self:updateFooter()
                    UIManager:setDirty("all", "partial")
                end,
            },
            getMinibarOption("toc_markers", self.setTocMarkers),
        }
    })
    table.insert(sub_items, {
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
    for _, gen in ipairs(self.footerTextGenerators) do
        table.insert(info, gen(self))
    end
    return table.concat(info, " | ")
end

-- this method should never get called when footer is disabled
function ReaderFooter:setTocMarkers()
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
        sec = util.secondsToClock(pages * average_time_per_page, true)
    end
    return title .. sec
end

function ReaderFooter:updateFooter()
    if self.pageno then
        self:updateFooterPage()
    else
        self:updateFooterPos()
    end
end

function ReaderFooter:updateFooterPage()
    if type(self.pageno) ~= "number" then return end
    self.progress_bar.percentage = self.pageno / self.pages
    self:updateFooterText()
end

function ReaderFooter:updateFooterPos()
    if type(self.position) ~= "number" then return end
    self.progress_bar.percentage = self.position / self.doc_height
    self:updateFooterText()
end

-- updateFooterText will start as a noop. After onReaderReady event is
-- received, it will initialized as _updateFooterText below
function ReaderFooter:updateFooterText()
end

-- only call this function after document is fully loaded
function ReaderFooter:_updateFooterText()
    self.footer_text:setText(self:genFooterText())
    if self.settings.disable_progress_bar then
        if self.has_no_mode then
            self.text_width = 0
        else
            self.text_width = self.footer_text:getSize().w
        end
        self.progress_bar.width = 0
    else
        if self.has_no_mode then
            self.text_width = 0
        else
            self.text_width = self.footer_text:getSize().w + self.text_left_margin
        end
        self.progress_bar.width = math.floor(
            self._saved_screen_width - self.text_width - self.horizontal_margin*2)
    end
    self.text_container.dimen.w = self.text_width
    self.horizontal_group:resetLayout()
    UIManager:setDirty(self.view.dialog, "ui", self.footer_content.dimen)
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
    self.view.footer_visible = (self.mode ~= MODE.off)
    if not self.view.footer_visible or self.settings.all_at_once then return end

    local mode_name = MODE_INDEX[self.mode]
    if not self.settings[mode_name] or self.has_no_mode then
        -- all modes disabled, only show progress bar
        mode_name = "empty"
    end
    self.genFooterText = footerTextGeneratorMap[mode_name]
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(MODE.page_progress)
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
                self.mode = MODE.off
            else
                self.mode = MODE.page_progress
            end
        else
            self.mode = (self.mode + 1) % MODE_NB
            for i, m in ipairs(MODE_INDEX) do
                if self.mode == MODE.off then break end
                if self.mode == i then
                    if self.settings[m] then
                        break
                    else
                        self.mode = (self.mode + 1) % MODE_NB
                    end
                end
            end
        end
        self:applyFooterMode()
        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
    end
    self:updateFooter()
    return true
end

function ReaderFooter:onHoldFooter()
    if self.mode == MODE.off then return end
    self.ui:handleEvent(Event:new("ShowGotoDialog"))
    return true
end

function ReaderFooter:onSetStatusLine(status_line)
    -- 1 is min progress bar while 0 is full cre header progress bar
    if status_line == 1 then
        self.view.footer_visible = (self.mode ~= MODE.off)
    else
        self:applyFooterMode(MODE.off)
    end
    self.ui.document:setStatusLineProp(status_line)
    self.ui:handleEvent(Event:new("UpdatePos"))
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
        self:updateFooter()
    end
end

return ReaderFooter
