local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Font = require("ui/font")
local _ = require("gettext")
local util  = require("util")


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
}

local MODE_INDEX = {}
for k,v in pairs(MODE) do
    MODE_INDEX[v] = k
end

-- functions that generates footer text for each mode
local footerTextGeneratorMap = {
    empty = function() return "" end,
    frontlight = function()
        if not Device:hasFrontlight() then return "L: NA" end
        local powerd = Device:getPowerDevice()
        if powerd.is_fl_on ~= nil and powerd.is_fl_on == true then
            if powerd.fl_intensity ~= nil then
                return string.format("L: %d%%", powerd.fl_intensity)
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
            return string.format("%d / %d", footer.pageno, footer.pages)
        else
            return string.format("%d / %d", footer.position, footer.doc_height)
        end
    end,
    pages_left = function(footer)
        local left = footer.ui.toc:getChapterPagesLeft(
            footer.pageno, footer.toc_level)
        return "=> " .. (left and left or footer.pages - footer.pageno)
    end,
    percentage = function(footer)
        return string.format("R:%1.f%%", footer.progress_bar.percentage * 100)
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
}

local ReaderFooter = InputContainer:new{
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
    settings = {},
    -- added to expose them to unit tests
    textGeneratorMap = footerTextGeneratorMap,
}

function ReaderFooter:init()
    self.pageno = self.view.state.page

    self.settings = G_reader_settings:readSetting("footer") or {
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
    }

    if self.settings.disabled then
        -- footer featuren disabled completely, stop initialization now
        self:disableFooter()
        return
    end

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

    local margin_span = HorizontalSpan:new{width = self.horizontal_margin}
    self.horizontal_group = HorizontalGroup:new{margin_span}
    self.text_container = RightContainer:new{
        dimen = Geom:new{w = 0, h = self.height},
        self.footer_text,
    }
    table.insert(self.horizontal_group, self.progress_bar)
    table.insert(self.horizontal_group, self.text_container)
    table.insert(self.horizontal_group, margin_span)
    self[1] = BottomContainer:new{
        dimen = Geom:new{},
        BottomContainer:new{
            dimen = Geom:new{w = 0, h = self.height*2},
            FrameContainer:new{
                self.horizontal_group,
                background = Blitbuffer.COLOR_WHITE,
                bordersize = 0,
                padding = 0,
            }
        }
    }

    self.mode = G_reader_settings:readSetting("reader_footer_mode") or self.mode
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= MODE.off)
        self:updateFooterTextGenerator()
    else
        self:applyFooterMode()
    end
    self:resetLayout()

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

-- call this method whenever the screen size changed
function ReaderFooter:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._saved_screen_width then return end
    local new_screen_height = Screen:getHeight()

    self.progress_bar.width = math.floor(new_screen_width - self.text_width - self.horizontal_margin*2)
    self.horizontal_group:resetLayout()
    self[1].dimen.w = new_screen_width
    self[1].dimen.h = new_screen_height
    self[1][1].dimen.w = new_screen_width
    self.dimen = self[1]:getSize()

    self._saved_screen_width = new_screen_width
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = new_screen_width*DTAP_ZONE_MINIBAR.x,
            y = new_screen_height*DTAP_ZONE_MINIBAR.y,
            w = new_screen_width*DTAP_ZONE_MINIBAR.w,
            h = new_screen_height*DTAP_ZONE_MINIBAR.h
        }
        self.ges_events = {
            TapFooter = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                },
            },
            HoldFooter = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
        }
    end
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
    toc_markers = _("Show table of content markers"),
    auto_refresh_time = _("Auto refresh time"),
    page_progress = _("Current page"),
    time = _("Current time"),
    pages_left = _("Pages left in this chapter"),
    battery = _("Battery status"),
    percentage = _("Progress percentage"),
    book_time_to_read = _("Book time to read"),
    chapter_time_to_read = _("Chapter time to read"),
    frontlight = _("Frontlight level"),
}

function ReaderFooter:addToMainMenu(tab_item_table)
    local sub_items = {}
    table.insert(tab_item_table.setting, {
        text = _("Status bar"),
        sub_item_table = sub_items,
    })

    -- menu item to fake footer tapping when touch area is disabled
    if Geom:new{
           x = DTAP_ZONE_MINIBAR.x,
           y = DTAP_ZONE_MINIBAR.y,
           w = DTAP_ZONE_MINIBAR.w,
           h = DTAP_ZONE_MINIBAR.h
       }:sizeof() == 0 then
        table.insert(sub_items, {
            text = _("Toggle mode"),
            enabled_func = function()
                return not self.view.flipping_visible
            end,
            callback = function() self:onTapFooter() end,
        })
    end

    -- footer is enabled, build the full status bar menu
    local isEnabled = function()
        return not self.settings.disabled
    end

    local getMinibarOption = function(option, callback)
        return {
            text = option_titles[option],
            checked_func = function()
                return self.settings[option] == true
            end,
            enabled_func = isEnabled,
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
    table.insert(sub_items, getMinibarOption("toc_markers", self.setTocMarkers))
    -- TODO: only enable auto refresh when time is shown
    table.insert(sub_items, getMinibarOption("auto_refresh_time", function()
        if self.settings.auto_refresh_time then
            self:setupAutoRefreshTime()
        else
            UIManager:unschedule(self.autoRefreshTime)
            self.onCloseDocument = nil
        end
    end))
    table.insert(sub_items, getMinibarOption("page_progress"))
    table.insert(sub_items, getMinibarOption("time"))
    table.insert(sub_items, getMinibarOption("pages_left"))
    table.insert(sub_items, getMinibarOption("battery"))
    table.insert(sub_items, getMinibarOption("percentage"))
    table.insert(sub_items, getMinibarOption("book_time_to_read"))
    table.insert(sub_items, getMinibarOption("chapter_time_to_read"))
    table.insert(sub_items, getMinibarOption("frontlight"))
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

-- this function should never be called with footer is disabled
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
end

function ReaderFooter:getDataFromStatistics(title, pages)
    local statistics_data = self.ui.doc_settings:readSetting("stats")
    local sec = 'na'
    if statistics_data and statistics_data.performance_in_pages then
        local read_pages = util.tableSize(statistics_data.performance_in_pages)
        local average_time_per_page = statistics_data.total_time_in_sec / read_pages
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
    if self.has_no_mode then
        self.text_width = 0
    else
        self.text_width = self.footer_text:getSize().w + self.text_left_margin
    end
    self.progress_bar.width = math.floor(
        self._saved_screen_width - self.text_width - self.horizontal_margin*2)
    self.text_container.dimen.w = self.text_width
    self.horizontal_group:resetLayout()
    UIManager:setDirty(self.view.dialog, "ui", self[1][1][1].dimen)
end

function ReaderFooter:onPageUpdate(pageno)
    self.pageno = pageno
    self.pages = self.view.document:getPageCount()
    self:updateFooterPage()
end

function ReaderFooter:onPosUpdate(pos)
    self.position = pos
    self.doc_height = self.view.document.info.doc_height
    self:updateFooterPos()
end

-- recalculate footer sizes when document page count is updated
-- see documentation for more info about this event.
ReaderFooter.onUpdatePos = ReaderFooter.updateFooter

function ReaderFooter:onReaderReady()
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

function ReaderFooter:onTapFooter(arg, ges)
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
            self.mode = (self.mode + 1) % 9
            for i, m in ipairs(MODE_INDEX) do
                if self.mode == MODE.off then break end
                if self.mode == i then
                    if self.settings[m] then
                        break
                    else
                        self.mode = (self.mode + 1) % 9
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

function ReaderFooter:onHoldFooter(arg, ges)
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

return ReaderFooter
