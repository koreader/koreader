local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
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


local ReaderFooter = InputContainer:new{
    mode = 1,
    visible = true,
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
    padding = Screen:scaleBySize(10),
    settings = {},
}

function ReaderFooter:init()
    self.pageno = self.view.state.page
    self.pages = self.view.document:getPageCount()

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
    local text_default
    if self.settings.all_at_once then
        local info = {}
        if self.settings.battery then
            table.insert(info, "B:100%")
        end
        if self.settings.time then
            table.insert(info, "WW:WW")
        end
        if self.settings.page_progress then
            table.insert(info, "0000 / 0000")
        end
        if self.settings.pages_left then
            table.insert(info, "=> 000")
        end
        if self.settings.percentage then
            table.insert(info, "R:100%")
        end
        if self.settings.book_time_to_read then
            table.insert(info, "TB: 00:00")
        end
        if self.settings.chapter_time_to_read then
            table.insert(info, "TC: 00:00")
        end
        text_default = table.concat(info, " | ")
    else
        text_default = string.format(" %d / %d ", self.pages, self.pages)
    end

    self.progress_text = TextWidget:new{
        text = text_default,
        face = Font:getFace(self.text_font_face, self.text_font_size),
    }
    local text_width = self.progress_text:getSize().w
    local ticks_candidates = {}
    if self.ui.toc and self.settings.toc_markers then
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
    self.progress_bar = ProgressWidget:new{
        width = math.floor(Screen:getWidth() - text_width - self.padding),
        height = self.bar_height,
        percentage = self.progress_percentage,
        ticks = ticks_candidates[1] or {},
        tick_width = DMINIBAR_TOC_MARKER_WIDTH,
        last = self.pages,
    }
    local horizontal_group = HorizontalGroup:new{}
    local bar_container = RightContainer:new{
        dimen = Geom:new{ w = Screen:getWidth() - text_width, h = self.height },
        self.progress_bar,
    }
    local text_container = CenterContainer:new{
        dimen = Geom:new{ w = text_width, h = self.height },
        self.progress_text,
    }
    if self.settings.progress_bar then
        table.insert(horizontal_group, bar_container)
    end
    table.insert(horizontal_group, text_container)
    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        BottomContainer:new{
            dimen = Geom:new{w = Screen:getWidth(), h = self.height*2},
            FrameContainer:new{
                horizontal_group,
                background = Blitbuffer.COLOR_WHITE,
                bordersize = 0,
                padding = 0,
            }
        }
    }
    self.dimen = self[1]:getSize()
    self:updateFooterPage()
    local range = Geom:new{
        x = Screen:getWidth()*DTAP_ZONE_MINIBAR.x,
        y = Screen:getHeight()*DTAP_ZONE_MINIBAR.y,
        w = Screen:getWidth()*DTAP_ZONE_MINIBAR.w,
        h = Screen:getHeight()*DTAP_ZONE_MINIBAR.h
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
    self.mode = G_reader_settings:readSetting("reader_footer_mode") or self.mode
    self:applyFooterMode()
    if self.settings.auto_refresh_time then
        self.autoRefreshTime = function()
            self:updateFooterPage()
            UIManager:setDirty(self.view.dialog, "ui", self[1][1][1].dimen)
            UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
        end
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
        self.onCloseDocument = function()
            UIManager:unschedule(self.autoRefreshTime)
        end
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
                self:init()
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
    return string.format("%d / %d", self.pageno, self.pages)
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

function ReaderFooter:updateFooterPage()
    if type(self.pageno) ~= "number" then return end
    self.progress_bar.percentage = self.pageno / self.pages
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
        self.progress_text.text = table.concat(info, " | ")
    else
        local info = ""
        if self.mode == 1 then
            info = self:getProgressInfo()
        elseif self.mode == 2 then
            info = self:getTimeInfo()
        elseif self.mode == 3 then
            info = self:getNextChapterInfo()
        elseif self.mode == 4 then
            info = self:getBatteryInfo()
        elseif self.mode == 5 then
            info = self:getProgressPercentage()
        elseif self.mode == 6 then
            info = self:getBookTimeToRead()
        elseif self.mode == 7 then
            info = self:getChapterTimeToRead()
        end
        self.progress_text.text = info
    end
end

function ReaderFooter:updateFooterPos()
    if type(self.position) ~= "number" then return end
    self.progress_bar.percentage = self.position / self.doc_height

    if self.show_time then
        self.progress_text.text = self:getTimeInfo()
    else
        local percentage = self.progress_bar.percentage
        self.progress_text.text = string.format("%1.f", percentage*100) .. "%"
    end
end

function ReaderFooter:onPageUpdate(pageno)
    self.pageno = pageno
    self.pages = self.view.document.info.number_of_pages
    self:updateFooterPage()
end

function ReaderFooter:onPosUpdate(pos)
    self.position = pos
    self.doc_height = self.view.document.info.doc_height
    self:updateFooterPos()
end

-- recalculate footer sizes when document page count is updated
function ReaderFooter:onUpdatePos()
    UIManager:scheduleIn(0.1, function() self:init() end)
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
    if self.mode == 0 then
        self.view.footer_visible = false
    else
        self.view.footer_visible = true
    end
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(1)
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
        self.mode = (self.mode + 1) % 8
        if self.settings.all_at_once and (self.mode > 1) then
            self.mode = 0
        end
        if (self.mode == 1) and not self.settings.page_progress then
            self.mode = 2
        end
        if (self.mode == 2) and not self.settings.time then
            self.mode = 3
        end
        if (self.mode == 3) and not self.settings.pages_left then
            self.mode = 4
        end
        if (self.mode == 4) and not self.settings.battery then
            self.mode = 5
        end
        if (self.mode == 5) and not self.settings.percentage then
            self.mode = 6
        end
        if (self.mode == 6) and not self.settings.book_time_to_read then
            self.mode = 7
        end
        if (self.mode == 7) and not self.settings.chapter_time_to_read then
            self.mode = 0
        end
        self:applyFooterMode()
        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
    end
    if self.pageno then
        self:updateFooterPage()
    else
        self:updateFooterPos()
    end
    UIManager:setDirty(self.view.dialog, "ui", self[1][1][1].dimen)
    return true
end

function ReaderFooter:onHoldFooter(arg, ges)
    if self.mode == 0 then return end
    self.ui:handleEvent(Event:new("ShowGotoDialog"))
    return true
end

function ReaderFooter:onSetStatusLine(status_line)
    self.view.footer_visible = status_line == 1 and true or false
    self.ui.document:setStatusLineProp(status_line)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

return ReaderFooter
