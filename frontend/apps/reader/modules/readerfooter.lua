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
    progress_percentage = 0.0,
    progress_text = "WW:WW | 0000 / 0000 Next: 000",
--    show_time = true,
    text_font_face = "ffont",
    text_font_size = 14,
    height = Screen:scaleByDPI(19),
    padding = Screen:scaleByDPI(10)
}

function ReaderFooter:init()
    self.progress_text = TextWidget:new{
        text = self.progress_text,
        face = Font:getFace(self.text_font_face, self.text_font_size),
    }
    local text_width = self.progress_text:getSize().w
    self.progress_bar = ProgressWidget:new{
        width = math.floor(Screen:getWidth() - text_width - self.padding),
        height = Screen:scaleByDPI(7),
        percentage = self.progress_percentage,
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
    table.insert(horizontal_group, bar_container)
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
    self.pageno = self.view.state.page
    self.pages = self.view.document.info.number_of_pages
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


function ReaderFooter:fillToc()
    self.toc = self.ui.document:getToc()
end

function ReaderFooter:updateFooterPage()
    if type(self.pageno) ~= "number" then return end
    self.progress_bar.percentage = self.pageno / self.pages

--    if self.show_time then
       self.progress_text.text = os.date("%H:%M") .. " | " .. string.format("%d / %d", self.pageno, self.pages) .. " Next: " .. self.ui.toc:_getChapterPagesLeft(self.pageno,self.pages)
--    else
--        self.progress_text.text = string.format("%d / %d", self.pageno, self.pages)
--    end
end

function ReaderFooter:updateFooterPos()
    if type(self.position) ~= "number" then return end
    self.progress_bar.percentage = self.position / self.doc_height

--    if self.show_time then
        self.progress_text.text = os.date("%H:%M")
--    else
--        self.progress_text.text = string.format("%1.f", self.progress_bar.percentage*100).."%"
--    end
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

function ReaderFooter:applyFooterMode(mode)
    -- three modes switcher for reader footer
    -- 0 for footer off
    -- 1 for footer page info
    -- 2 for footer time info (WS64: unused!)
    if mode ~= nil then self.mode = mode end
    if self.mode == 0 then
        self.view.footer_visible = false
    else
        self.view.footer_visible = true
    end
--    if self.mode == 1 then
--        self.show_time = false
--    elseif self.mode == 2 then
--        self.show_time = true
--    end
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
        self.mode = 1 - self.mode
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
