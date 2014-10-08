local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Font = require("ui/font")
local DEBUG = require("dbg")

local ReaderFooter = InputContainer:new{
    mode = 1,
    visible = true,
    pageno = nil,
    pages = nil,
    toc_level = 0,
    progress_percentage = 0.0,
    progress_text = nil,
    text_font_face = "ffont",
    text_font_size = DMINIBAR_FONT_SIZE,
    bar_height = Screen:scaleByDPI(DMINIBAR_HEIGHT),
    height = Screen:scaleByDPI(DMINIBAR_CONTAINER_HEIGHT),
    padding = Screen:scaleByDPI(10),
}

function ReaderFooter:init()
    if self.ui.document.info.has_pages then
        DMINIBAR_NEXT_CHAPTER = false
    end

    self.pageno = self.view.state.page
    self.pages = self.view.document:getPageCount()

    local text_default = ""
    if DMINIBAR_ALL_AT_ONCE then
        local info = {}
        if DMINIBAR_BATTERY then
            table.insert(info, "B:100%")
        end
        if DMINIBAR_TIME then
            table.insert(info, "WW:WW")
        end
        if DMINIBAR_PAGES then
            table.insert(info, "0000 / 0000")
        end
        if DMINIBAR_NEXT_CHAPTER then
            table.insert(info, "=> 000")
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
    local ticks = (self.ui.toc and DMINIBAR_PROGRESS_MARKER)
            and self.ui.toc:getTocTicks(self.toc_level) or {}
    self.progress_bar = ProgressWidget:new{
        width = math.floor(Screen:getWidth() - text_width - self.padding),
        height = self.bar_height,
        percentage = self.progress_percentage,
        ticks = ticks,
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
    if DMINIBAR_PROGRESSBAR then
        table.insert(horizontal_group, bar_container)
    end
    table.insert(horizontal_group, text_container)
    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        BottomContainer:new{
            dimen = Geom:new{w = Screen:getWidth(), h = self.height*2},
            FrameContainer:new{
                horizontal_group,
                background = 0,
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
end

function ReaderFooter:getBatteryInfo()
    local powerd = Device:getPowerDevice()
    --local state = powerd:isCharging() and -1 or powerd:getCapacity()
    return "B:" .. powerd:getCapacity() .. "%"
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

function ReaderFooter:updateFooterPage()
    if type(self.pageno) ~= "number" then return end
    self.progress_bar.percentage = self.pageno / self.pages
    if DMINIBAR_ALL_AT_ONCE then
        local info = {}
        if DMINIBAR_BATTERY then
            table.insert(info, self:getBatteryInfo())
        end
        if DMINIBAR_TIME then
            table.insert(info, self:getTimeInfo())
        end
        if DMINIBAR_PAGES then
            table.insert(info, self:getProgressInfo())
        end
        if DMINIBAR_NEXT_CHAPTER then
            table.insert(info, self:getNextChapterInfo())
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
        self.mode = (self.mode + 1) % 5
        if DMINIBAR_ALL_AT_ONCE and (self.mode > 1) then
            self.mode = 0
        end
        if (self.mode == 1) and not DMINIBAR_PAGES then
            self.mode = 2
        end
        if (self.mode == 2) and not DMINIBAR_TIME then
            self.mode = 3
        end
        if (self.mode == 3) and not DMINIBAR_NEXT_CHAPTER then
            self.mode = 4
        end
        if (self.mode == 4) and not DMINIBAR_BATTERY then
            self.mode = 0
        end
        self:applyFooterMode()
    end
    if self.pageno then
        self:updateFooterPage()
    else
        self:updateFooterPos()
    end
    UIManager:setDirty(self.view.dialog, "partial")
    G_reader_settings:saveSetting("reader_footer_mode", self.mode)
    return true
end

function ReaderFooter:onHoldFooter(arg, ges)
    self.ui:handleEvent(Event:new("ShowGotoDialog"))
    return true
end

function ReaderFooter:onSetStatusLine(status_line)
    self.view.footer_visible = status_line == 1 and true or false
    self.ui.document:setStatusLineProp(status_line)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

return ReaderFooter
