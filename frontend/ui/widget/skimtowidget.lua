local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local SkimToWidget = FocusManager:new{}

function SkimToWidget:init()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    if Device:hasKeys() then
        self.key_events.Close = { { "Back" }, doc = "close skimto page" }
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            TapProgress = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = screen_width,
                        h = screen_height,
                    }
                },
            },
         }
    end

    self.buttons_layout = {}
    self.selected = { x = 1, y = 2 }

    local frame_width = math.floor(screen_width * 0.95)
    local frame_border_size = Size.border.window
    local frame_padding = Size.padding.fullscreen -- large padding for airy feeling
    local inner_width = frame_width - 2 * (frame_border_size + frame_padding)

    -- In this inner width, we'll be showing 5 buttons, with the middle one
    -- separated a bit more from the others
    local button_span_unit_width = Size.span.horizontal_small
    local larger_span_units = 3 -- 3 x small span width
    local nb_span_units = 2 + 2*larger_span_units
    local button_width = math.floor( (inner_width - nb_span_units * button_span_unit_width) / 5)
    local button_inner_width = button_width - 2 * (Size.border.button + Size.padding.button)
    -- Update inner_width (possibly smaller because of math.floor())
    inner_width = button_width * 5 + nb_span_units * button_span_unit_width

    self.curr_page = self.ui:getCurrentPage()
    self.page_count = self.document:getPageCount()
    self.ticks_flattened = self.ui.toc:getTocTicksFlattened()

    self.progress_bar = ProgressWidget:new{
        width = inner_width,
        height = Size.item.height_big,
        percentage = self.curr_page / self.page_count,
        ticks = self.ticks_flattened,
        tick_width = Size.line.medium,
        last = self.page_count,
        alt = self.ui.document.flows,
    }

    -- Bottom row buttons
    local button_minus = Button:new{
        text = "-1",
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 1)
        end,
    }
    local button_minus_ten = Button:new{
        text = "-10",
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 10)
        end,
    }
    local button_plus = Button:new{
        text = "+1",
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 1)
        end,
    }
    local button_plus_ten = Button:new{
        text = "+10",
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 10)
        end,
    }
    self.current_page_text = Button:new{
        text_func = function()
            local curr_page_display = tostring(self.curr_page)
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                curr_page_display = self.ui.pagemap:getCurrentPageLabel(true)
            end
            return curr_page_display
        end,
        radius = 0,
        padding = 0,
        bordersize = 0,
        enabled = true,
        width = button_width, -- no border/padding: use outer button width
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
    }

    -- Top row buttons
    local chapter_next_text = "▷▏"
    local chapter_prev_text = "▕◁"
    local bookmark_next_text = "☆▷"
    local bookmark_prev_text = "◁☆"
    local bookmark_enabled_text = "★"
    local bookmark_disabled_text = "☆"
    if BD.mirroredUILayout() then
        chapter_next_text, chapter_prev_text = chapter_prev_text, chapter_next_text
        bookmark_next_text, bookmark_prev_text = bookmark_prev_text, bookmark_next_text
    end
    local button_chapter_next = Button:new{
        text = chapter_next_text,
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getNextChapter(self.curr_page)
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
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getPreviousChapter(self.curr_page)
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
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
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
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToByEvent("GotoPreviousBookmarkFromPage")
        end,
        hold_callback = function()
            local page = self.ui.bookmark:getFirstBookmarkedPageFromPage(self.ui:getCurrentPage())
            self:goToBookmark(page)
        end,
    }
    self.button_bookmark_toggle = Button:new{
        text_func = function()
            return self.ui.view.dogear_visible and bookmark_enabled_text or bookmark_disabled_text
        end,
        radius = 0,
        enabled = true,
        width = button_inner_width,
        show_parent = self,
        callback = function()
            self.ui:handleEvent(Event:new("ToggleBookmark"))
            self:update()
        end,
        hold_callback = function()
            self.ui:handleEvent(Event:new("ShowBookmark"))
            UIManager:close(self)
        end,
    }

    local row_span = VerticalSpan:new{ width = Size.padding.fullscreen }
    local small_button_span = HorizontalSpan:new{ width = button_span_unit_width }
    local large_button_span = HorizontalSpan:new{ width = button_span_unit_width * larger_span_units }

    local top_buttons_row = HorizontalGroup:new{
        align = "center",
        button_chapter_prev,
        small_button_span,
        button_bookmark_prev,
        large_button_span,
        self.button_bookmark_toggle,
        large_button_span,
        button_bookmark_next,
        small_button_span,
        button_chapter_next,
    }
    local bottom_buttons_row = HorizontalGroup:new{
        align = "center",
        button_minus_ten,
        small_button_span,
        button_minus,
        large_button_span,
        self.current_page_text,
        large_button_span,
        button_plus,
        small_button_span,
        button_plus_ten,
    }

    self.skimto_frame = FrameContainer:new{
        margin = 0,
        bordersize = frame_border_size,
        padding = frame_padding,
        radius = Size.radius.window,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            top_buttons_row,
            row_span,
            self.progress_bar,
            row_span,
            bottom_buttons_row,
        }
    }
    self.movable = MovableContainer:new{
        self.skimto_frame,
    }
    self[1] = WidgetContainer:new{
        align = "center",
        dimen =Geom:new{
            x = 0, y = 0,
            w = screen_width,
            h = screen_height,
        },
        self.movable,
    }

    if Device:hasDPad() then
        self.buttons_layout = {
            { button_chapter_prev, button_bookmark_prev, self.button_bookmark_toggle, button_bookmark_next, button_chapter_next },
            { button_minus_ten, button_minus, self.current_page_text, button_plus, button_plus_ten },
        }
        self.layout = self.buttons_layout
        self.layout[2][1]:onFocus()
        self.key_events.SelectByKeyPress = { { "Press" }, doc = "select focused item" }
    end
    if Device:hasKeyboard() then
        self.key_events.QKey = { { "Q" }, event = "FirstRowKeyPress", args =    0 }
        self.key_events.WKey = { { "W" }, event = "FirstRowKeyPress", args = 0.11 }
        self.key_events.EKey = { { "E" }, event = "FirstRowKeyPress", args = 0.22 }
        self.key_events.RKey = { { "R" }, event = "FirstRowKeyPress", args = 0.33 }
        self.key_events.TKey = { { "T" }, event = "FirstRowKeyPress", args = 0.44 }
        self.key_events.YKey = { { "Y" }, event = "FirstRowKeyPress", args = 0.55 }
        self.key_events.UKey = { { "U" }, event = "FirstRowKeyPress", args = 0.66 }
        self.key_events.IKey = { { "I" }, event = "FirstRowKeyPress", args = 0.77 }
        self.key_events.OKey = { { "O" }, event = "FirstRowKeyPress", args = 0.88 }
        self.key_events.PKey = { { "P" }, event = "FirstRowKeyPress", args =    1 }
    end
end

function SkimToWidget:update()
    if self.curr_page <= 0 then
        self.curr_page = 1
    end
    if self.curr_page > self.page_count then
        self.curr_page = self.page_count
    end
    self.progress_bar.percentage = self.curr_page / self.page_count
    self.current_page_text:setText(self.current_page_text:text_func(), self.current_page_text.width)
    self.button_bookmark_toggle:setText(self.button_bookmark_toggle:text_func(), self.button_bookmark_toggle.width)
end

function SkimToWidget:addOriginToLocationStack(add_current)
    -- Only add the page from which we launched the SkimToWidget
    -- to the location stack, unless add_current = true
    if not self.orig_page_added_to_stack or add_current then
        self.ui.link:addCurrentLocationToStack()
        self.orig_page_added_to_stack = true
    end
end

function SkimToWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.skimto_frame.dimen
    end)
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
        self.ui:handleEvent(Event:new(event_name, false))
            -- add_current_location_to_stack=false, as we handled it here
        self.curr_page = self.ui:getCurrentPage()
        self:update()
    end
end

function SkimToWidget:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function SkimToWidget:onSelectByKeyPress()
    local item = self:getFocusItem()
    item.callback()
end

function SkimToWidget:onFirstRowKeyPress(percent)
    local page = Math.round(percent * self.page_count)
    self:addOriginToLocationStack()
    self.ui:handleEvent(Event:new("GotoPage", page ))
    self.curr_page = page
    self:update()
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
