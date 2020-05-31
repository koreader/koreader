local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local SkimToWidget = InputContainer:new{
    title_face = Font:getFace("x_smalltfont"),
    width = nil,
    height = nil,
}

function SkimToWidget:init()
    self.medium_font_face = Font:getFace("ffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.span = math.ceil(self.screen_height * 0.01)
    self.width = self.screen_width * 0.95
    self.button_bordersize = Size.border.button
    -- the buttons need some kind of separation but maybe I should just implement
    -- margin_left and margin_right…
    self.button_margin = self.button_bordersize
    self.button_width = self.screen_width * 0.16 - (2*self.button_margin)
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close skimto page" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapProgress = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    }
                },
            },
         }
    end
    local dialog_title = _("Skim")
    self.curr_page = self.ui:getCurrentPage()
    self.page_count = self.document:getPageCount()

    local curr_page_display = tostring(self.curr_page)
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        curr_page_display = self.ui.pagemap:getCurrentPageLabel(true)
    end

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
        self.ticks_candidates = ticks_candidates[1]
    end

    local skimto_title = FrameContainer:new{
        padding = Size.padding.default,
        margin = Size.margin.title,
        bordersize = 0,
        TextWidget:new{
            text = dialog_title,
            face = self.title_face,
            bold = true,
            max_width = self.screen_width * 0.95,
        },
    }

    self.progress_bar = ProgressWidget:new{
        width = self.screen_width * 0.9,
        height = Size.item.height_big,
        percentage = self.curr_page / self.page_count,
        ticks = self.ticks_candidates,
        tick_width = Size.line.medium,
        last = self.page_count,
    }
    self.skimto_progress = FrameContainer:new{
        padding = Size.padding.button,
        margin = Size.margin.small,
        bordersize = 0,
        self.progress_bar,
    }

    local skimto_line = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    local skimto_bar = OverlapGroup:new{
        dimen = {
            w = self.width,
            h = skimto_title:getSize().h
        },
        skimto_title,
        CloseButton:new{ window = self, padding_top = Size.margin.title, },
    }
    local button_minus = Button:new{
        text = "-1",
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:goToPage(self.curr_page - 1)
        end,
    }
    local button_minus_ten = Button:new{
        text = "-10",
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:goToPage(self.curr_page - 10)
        end,
    }
    local button_plus = Button:new{
        text = "+1",
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:goToPage(self.curr_page + 1)
        end,
    }
    local button_plus_ten = Button:new{
        text = "+10",
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:goToPage(self.curr_page + 10)
        end,
    }
    self.current_page_text = Button:new{
        text = curr_page_display,
        bordersize = 0,
        margin = self.button_margin,
        radius = 0,
        padding = 0,
        enabled = true,
        width = self.screen_width * 0.2 - (2*self.button_margin),
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
    }

    local chapter_next_text = "▷│"
    local chapter_prev_text = "│◁"
    local bookmark_next_text = "☆▷"
    local bookmark_prev_text = "◁☆"
    if BD.mirroredUILayout() then
        chapter_next_text, chapter_prev_text = chapter_prev_text, chapter_next_text
        bookmark_next_text, bookmark_prev_text = bookmark_prev_text, bookmark_next_text
    end
    local button_chapter_next = Button:new{
        text = chapter_next_text,
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            local page = self:getNextChapter(self.curr_page)
            if page and page >=1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(self.page_count)
        end,
    }

    local button_chapter_prev = Button:new{
        text = chapter_prev_text,
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            local page = self:getPrevChapter(self.curr_page)
            if page and page >=1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(1)
        end,
    }

    local button_bookmark_next = Button:new{
        text = bookmark_next_text,
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:goToByEvent("GotoNextBookmarkFromPage")
        end,
        hold_callback = function()
            local page = self.ui.bookmark:getLastBookmarkedPageFromPage(self.ui:getCurrentPage())
            self:goToBookmark(page)
        end,
    }

    local button_bookmark_prev = Button:new{
        text = bookmark_prev_text,
        bordersize = self.button_bordersize,
        margin = self.button_margin,
        radius = 0,
        enabled = true,
        width = self.button_width,
        show_parent = self,
        callback = function()
            self:goToByEvent("GotoPreviousBookmarkFromPage")
        end,
        hold_callback = function()
            local page = self.ui.bookmark:getFirstBookmarkedPageFromPage(self.ui:getCurrentPage())
            self:goToBookmark(page)
        end,
    }

    local horizontal_span_up = HorizontalSpan:new{ width = self.screen_width * 0.2 }
       local button_table_up = HorizontalGroup:new{
        align = "center",
        button_chapter_prev,
        button_bookmark_prev,
        horizontal_span_up,
        button_bookmark_next,
        button_chapter_next,
    }

    local vertical_group_up = VerticalGroup:new{ align = "center" }
    local padding_span_up = VerticalSpan:new{ width = math.ceil(self.screen_height * 0.015) }
    table.insert(vertical_group_up, padding_span_up)
    table.insert(vertical_group_up, button_table_up)
    table.insert(vertical_group_up, padding_span_up)

    local button_table_down = HorizontalGroup:new{
        align = "center",
        button_minus,
        button_minus_ten,
        self.current_page_text,
        button_plus_ten,
        button_plus,
    }
    local vertical_group_down = VerticalGroup:new{ align = "center" }
    local padding_span = VerticalSpan:new{ width = math.ceil(self.screen_height * 0.015) }
    table.insert(vertical_group_down, padding_span)
    table.insert(vertical_group_down, button_table_down)
    table.insert(vertical_group_down, padding_span)

    self.skimto_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            skimto_bar,
            skimto_line,
            vertical_group_up,
            CenterContainer:new{
                dimen = Geom:new{
                    w = skimto_line:getSize().w,
                    h = self.skimto_progress:getSize().h,
                },
                self.skimto_progress,
            },
            vertical_group_down,
        }
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen =Geom:new{
            x = 0, y = 0,
            w = self.screen_width,
            h = self.screen_height,
        },
        MovableContainer:new{
            -- alpha = 0.8,
            self.skimto_frame,
        }
    }
end

function SkimToWidget:update()
    if self.curr_page <= 0 then
        self.curr_page = 1
    end
    if self.curr_page > self.page_count then
        self.curr_page = self.page_count
    end
    self.progress_bar.percentage = self.curr_page / self.page_count
    local curr_page_display = tostring(self.curr_page)
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        curr_page_display = self.ui.pagemap:getCurrentPageLabel(true)
    end
    self.current_page_text:setText(curr_page_display, self.current_page_text.width)
end

function SkimToWidget:addOriginToLocationStack(add_current)
    -- Only add the page from which we launched the SkimToWidget
    -- to the location stack, unless add_current = true
    if not self.orig_page_added_to_stack or add_current then
        self.ui.link:addCurrentLocationToStack()
        self.orig_page_added_to_stack = true
    end
end

function SkimToWidget:getNextChapter(cur_pageno)
    local next_chapter = nil
    for i = 1, #self.ticks_candidates do
        if self.ticks_candidates[i] > cur_pageno then
            next_chapter = self.ticks_candidates[i]
            break
        end
    end
    return next_chapter
end

function SkimToWidget:getPrevChapter(cur_pageno)
    local previous_chapter = nil
    for i = 1, #self.ticks_candidates do
        if self.ticks_candidates[i] >= cur_pageno then
            break
        end
        previous_chapter = self.ticks_candidates[i]
    end
    return previous_chapter
end

function SkimToWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.skimto_frame.dimen
    end)
    return true
end

function SkimToWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.skimto_frame.dimen
    end)
    return true
end

function SkimToWidget:goToPage(page)
    self.curr_page = page
    self:addOriginToLocationStack()
    self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
    self:update()
end

function SkimToWidget:goToBookmark(page)
    if page then
        self:addOriginToLocationStack()
        self.ui.bookmark:gotoBookmark(page)
        self.curr_page = self.ui:getCurrentPage()
        self:update()
    end
end

function SkimToWidget:goToByEvent(event_name)
    if event_name then
        self:addOriginToLocationStack()
        self.ui:handleEvent(Event:new(event_name))
        self.curr_page = self.ui:getCurrentPage()
        self:update()
    end
end

function SkimToWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function SkimToWidget:onTapProgress(arg, ges_ev)
    if ges_ev.pos:intersectWith(self.progress_bar.dimen) then
        local perc = self.progress_bar:getPercentageFromPosition(ges_ev.pos)
        if not perc then
            return true
        end
        local page = Math.round(perc * self.page_count)
        self:addOriginToLocationStack()
        self.ui:handleEvent(Event:new("GotoPage", page ))
        self.curr_page = page
        self:update()
    elseif not ges_ev.pos:intersectWith(self.skimto_frame.dimen) then
        -- close if tap outside
        self:onClose()
    end
    -- otherwise, do nothing (it's easy missing taping a button)
    return true
end

function SkimToWidget:onClose()
    UIManager:close(self)
    return true
end

return SkimToWidget
