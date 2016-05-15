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
}
local MODE_INDEX = {}
for k,v in pairs(MODE) do
    MODE_INDEX[v] = k
end

local ReaderFooter = InputContainer:new{
    mode = MODE.page_progress,
    pageno = nil,
    pages = nil,
    toc_level = 0,
    max_ticks = 100,
    progress_percentage = 0.0,
    progress_text = nil,
    text_font_face = "ffont",
    text_font_size = DMINIBAR_FONT_SIZE,
    bar_height = Screen:scaleBySize(DMINIBAR_HEIGHT),
    height = Screen:scaleBySize(DMINIBAR_CONTAINER_HEIGHT),
    horizontal_margin = Screen:scaleBySize(10),
    text_left_margin = Screen:scaleBySize(10),
    settings = {},
}

function ReaderFooter:init()
    self.pageno = self.view.state.page

    self.settings = G_reader_settings:readSetting("footer") or {
        disabled = false,
        all_at_once = false,
        progress_bar = true,
        toc_markers = true,
        battery = true,
        time = true,
        page_progress = true,
        pages_left = true,
        percentage = true,
        book_time_to_read = true,
        chapter_time_to_read = true,
    }
    if self.settings.disabled then
        self.resetLayout = function() end
        self.onCloseDocument = function() end
        self.onPageUpdate = function() end
        self.onPosUpdate = function() end
        self.onUpdatePos = function() end
        self.onSetStatusLine = function() end
        return
    end

    self.progress_text = TextWidget:new{
        text = '',
        face = Font:getFace(self.text_font_face, self.text_font_size),
    }
    self.text_width = self.progress_text:getSize().w + self.text_left_margin
    self.progress_bar = ProgressWidget:new{
        width = nil,  -- width will be updated in self:resetLayout()
        height = self.bar_height,
        percentage = self.progress_percentage,
        tick_width = DMINIBAR_TOC_MARKER_WIDTH,
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }
    local margin_span = HorizontalSpan:new{width=self.horizontal_margin}
    local screen_width = Screen:getWidth()
    self.horizontal_group = HorizontalGroup:new{margin_span}
    self.text_container = RightContainer:new{
        dimen = Geom:new{w = self.text_width, h = self.height},
        self.progress_text,
    }
    if self.settings.progress_bar then
        table.insert(self.horizontal_group, self.progress_bar)
    end
    table.insert(self.horizontal_group, self.text_container)
    table.insert(self.horizontal_group, margin_span)
    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        BottomContainer:new{
            dimen = Geom:new{w = screen_width, h = self.height*2},
            FrameContainer:new{
                self.horizontal_group,
                background = Blitbuffer.COLOR_WHITE,
                bordersize = 0,
                padding = 0,
            }
        }
    }

    self:applyFooterMode(
        G_reader_settings:readSetting("reader_footer_mode") or self.mode)
    self:resetLayout()

    if self.settings.auto_refresh_time then
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
    local range = Geom:new{
        x = new_screen_width*DTAP_ZONE_MINIBAR.x,
        y = new_screen_height*DTAP_ZONE_MINIBAR.y,
        w = new_screen_width*DTAP_ZONE_MINIBAR.w,
        h = new_screen_height*DTAP_ZONE_MINIBAR.h
    }
    if Device:isTouchDevice() then
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

local options = {
    all_at_once = _("Show all at once"),
    auto_refresh_time = _("Auto refresh time"),
    progress_bar = _("Progress bar"),
    toc_markers = _("Chapter markers"),
    battery = _("Battery status"),
    time = _("Current time"),
    page_progress = _("Current page"),
    pages_left = _("Pages left in this chapter"),
    percentage = _("Progress percentage"),
    book_time_to_read = _("Book time to read"),
    chapter_time_to_read = _("Chapter time to read"),
}

function ReaderFooter:addToMainMenu(tab_item_table)
    local get_minibar_option = function(option)
        return {
            text = options[option],
            checked_func = function()
                return self.settings[option] == true
            end,
            enabled_func = function()
                return not self.settings.disabled
            end,
            callback = function()
                self.settings[option] = not self.settings[option]
                G_reader_settings:saveSetting("footer", self.settings)
                self:updateFooter()
                UIManager:setDirty("all", "partial")
            end,
        }
    end
    table.insert(tab_item_table.setting, {
        text = _("Status bar"),
        sub_item_table = {
            get_minibar_option("all_at_once"),
            get_minibar_option("auto_refresh_time"),
            get_minibar_option("progress_bar"),
            get_minibar_option("toc_markers"),
            get_minibar_option("battery"),
            get_minibar_option("time"),
            get_minibar_option("page_progress"),
            get_minibar_option("pages_left"),
            get_minibar_option("percentage"),
            get_minibar_option("book_time_to_read"),
            get_minibar_option("chapter_time_to_read"),
        }
    })
end

function ReaderFooter:getBatteryInfo()
    local powerd = Device:getPowerDevice()
    return "B:" .. (powerd:isCharging() and "+" or "") .. powerd:getCapacity() .. "%"
end

function ReaderFooter:getTimeInfo()
    return os.date("%H:%M")
end

function ReaderFooter:getProgressInfo()
    if self.pageno then
        return string.format("%d / %d", self.pageno, self.pages)
    else
        return string.format("%d / %d", self.position, self.doc_height)
    end
end

function ReaderFooter:getNextChapterInfo()
    local left = self.ui.toc:getChapterPagesLeft(self.pageno, self.toc_level)
    return "=> " .. (left and left or self.pages - self.pageno)
end

function ReaderFooter:getProgressPercentage()
    return string.format("R:%1.f%%", self.progress_bar.percentage * 100)
end

function ReaderFooter:getBookTimeToRead()
    local current_page
    if self.view.document.info.has_pages then
        current_page = self.ui.paging.current_page
    else
        current_page = self.view.document:getCurrentPage()
    end
    return self:getDataFromStatistics("TB: ", self.pages - current_page)
end

function ReaderFooter:getChapterTimeToRead()
    local left = self.ui.toc:getChapterPagesLeft(self.pageno, self.toc_level)
    return self:getDataFromStatistics("TC: ", (left and left or self.pages - self.pageno))
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

function ReaderFooter:updateFooterText()
    if self.settings.toc_markers and self.progress_bar.ticks == nil then
        local ticks_candidates = {}
        if self.ui.toc then
            local max_level = self.ui.toc:getMaxDepth()
            for i = 0, -max_level, -1 do
                local ticks = self.ui.toc:getTocTicks(i)
                if #ticks < self.max_ticks then
                    table.insert(ticks_candidates, ticks)
                end
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
    end

    if self.settings.all_at_once then
        local info = {}
        if self.settings.battery then
            table.insert(info, self:getBatteryInfo())
        end
        if self.settings.time then
            table.insert(info, self:getTimeInfo())
        end
        if self.settings.page_progress then
            table.insert(info, self:getProgressInfo())
        end
        if self.settings.pages_left then
            table.insert(info, self:getNextChapterInfo())
        end
        if self.settings.percentage then
            table.insert(info, self:getProgressPercentage())
        end
        if self.settings.book_time_to_read then
            table.insert(info, self:getBookTimeToRead())
        end
        if self.settings.chapter_time_to_read then
            table.insert(info, self:getChapterTimeToRead())
        end
        self.progress_text:setText(table.concat(info, " | "))
    else
        local info
        if self.mode == MODE.page_progress then
            info = self:getProgressInfo()
        elseif self.mode == MODE.time then
            info = self:getTimeInfo()
        elseif self.mode == MODE.pages_left then
            info = self:getNextChapterInfo()
        elseif self.mode == MODE.battery then
            info = self:getBatteryInfo()
        elseif self.mode == MODE.percentage then
            info = self:getProgressPercentage()
        elseif self.mode == MODE.book_time_to_read then
            info = self:getBookTimeToRead()
        elseif self.mode == MODE.chapter_time_to_read then
            info = self:getChapterTimeToRead()
        else
            info = ""
        end
        self.progress_text:setText(info)
    end
    self.text_width = self.progress_text:getSize().w + self.text_left_margin
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
function ReaderFooter:onUpdatePos()
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
    if mode ~= nil then self.mode = mode end
    self.view.footer_visible = (self.mode ~= MODE.off)
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
        if self.settings.all_at_once then
            if self.mode >= 1 then
                self.mode = MODE.off
            else
                self.mode = MODE.page_progress
            end
        else
            self.mode = (self.mode + 1) % 8
            for i, m in ipairs(MODE_INDEX) do
                if self.mode == MODE.off then break end
                if self.mode == i then
                    if self.settings[m] then
                        break
                    else
                        self.mode = (self.mode + 1) % 8
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
    self.view.footer_visible = (status_line == 1)
    self.ui.document:setStatusLineProp(status_line)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

return ReaderFooter
