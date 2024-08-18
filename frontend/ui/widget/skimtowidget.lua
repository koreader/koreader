local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
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

local SkimToWidget = FocusManager:extend{}

function SkimToWidget:init()
    if self.ui.paging then -- "page" view
        self.ui.paging:enterSkimMode()
    end

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapProgress = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = screen_width,
                    h = screen_height,
                }
            },
        }
    end

    -- nil for default center full mode; "top" and "bottom" for compact mode
    local skim_dialog_position = G_reader_settings:readSetting("skim_dialog_position")
    local full_mode = not skim_dialog_position

    local frame_border_size = Size.border.window
    local button_span_unit_width = Size.span.horizontal_small
    local button_font_size, button_height, frame_padding, frame_width, inner_width, nb_buttons, larger_span_units, progress_bar_height
    if full_mode then
        button_font_size = nil -- use default
        button_height = nil
        frame_padding = Size.padding.fullscreen -- large padding for airy feeling
        frame_width = math.floor(math.min(screen_width, screen_height) * 0.95)
        inner_width = frame_width - 2 * (frame_border_size + frame_padding)
        nb_buttons = 5 -- with the middle one separated a bit more from the others
        larger_span_units = 3 -- 3 x small span width
        progress_bar_height = Size.item.height_big
    else
        button_font_size = 16
        button_height = Screen:scaleBySize(32)
        frame_padding = Size.padding.default
        frame_width = screen_width + 2 * frame_border_size -- hide side borders
        inner_width = frame_width - 2 * frame_padding
        nb_buttons = 11 -- in equal distances
        larger_span_units = 1
        progress_bar_height = Screen:scaleBySize(36)
    end
    local nb_span_units = (nb_buttons - 1) - 2 + 2 * larger_span_units
    local button_width = math.floor((inner_width - nb_span_units * button_span_unit_width) * (1 / nb_buttons))
    -- Update inner_width (possibly smaller because of math.floor())
    inner_width = nb_buttons * button_width + nb_span_units * button_span_unit_width

    self.curr_page = self.ui:getCurrentPage()
    self.page_count = self.ui.document:getPageCount()

    self.progress_bar = ProgressWidget:new{
        width = inner_width,
        height = progress_bar_height,
        percentage = self.curr_page / self.page_count,
        ticks = self.ui.toc:getTocTicksFlattened(),
        tick_width = Size.line.medium,
        last = self.page_count,
        alt = self.ui.document.flows,
        initial_pos_marker = true,
    }

    -- Bottom row buttons
    local button_minus = Button:new{
        text = "-1",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 1)
        end,
    }
    local button_minus_ten = Button:new{
        text = "-10",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 10)
        end,
    }
    local button_plus = Button:new{
        text = "+1",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 1)
        end,
    }
    local button_plus_ten = Button:new{
        text = "+10",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 10)
        end,
    }
    self.current_page_text = Button:new{
        text_func = function()
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                return self.ui.pagemap:getCurrentPageLabel(true)
            end
            return tostring(self.curr_page)
        end,
        text_font_size = button_font_size,
        radius = 0,
        padding = 0,
        bordersize = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
        hold_callback = function()
            self:goToOrigPage()
        end,
    }
    local button_orig_page = Button:new{
        text = "\u{21BA}", -- Anticlockwise Open Circle Arrow
        -- text = "\u{21A9}", -- Leftwards Arrow with Hook
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToOrigPage()
        end,
    }

    -- Top row buttons
    local chapter_next_text = "  ▷▏"
    local chapter_prev_text = "▕◁  "
    local bookmark_next_text = "\u{F097}\u{202F}▷"
    local bookmark_prev_text = "◁\u{202F}\u{F097}"
    local bookmark_enabled_text = "\u{F02E}"
    local bookmark_disabled_text = "\u{F097}"
    if BD.mirroredUILayout() then
        chapter_next_text, chapter_prev_text = chapter_prev_text, chapter_next_text
        bookmark_next_text, bookmark_prev_text = bookmark_prev_text, bookmark_next_text
    end
    local button_chapter_next = Button:new{
        text = chapter_next_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getNextChapter(self.curr_page)
            if page and page >= 1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(self.page_count)
        end,
    }
    local button_chapter_prev = Button:new{
        text = chapter_prev_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getPreviousChapter(self.curr_page)
            if page and page >= 1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(1)
        end,
    }
    local button_bookmark_next = Button:new{
        text = bookmark_next_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToByEvent("GotoNextBookmarkFromPage")
        end,
        hold_callback = function()
            self:goToByEvent("GotoLastBookmark")
        end,
    }
    local button_bookmark_prev = Button:new{
        text = bookmark_prev_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToByEvent("GotoPreviousBookmarkFromPage")
        end,
        hold_callback = function()
            self:goToByEvent("GotoFirstBookmark")
        end,
    }
    self.button_bookmark_toggle = Button:new{
        text_func = function()
            return self.ui.view.dogear_visible and bookmark_enabled_text or bookmark_disabled_text
        end,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
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

    local small_button_span = HorizontalSpan:new{ width = button_span_unit_width }
    local large_button_span = HorizontalSpan:new{ width = button_span_unit_width * larger_span_units }
    local top_row_span, bottom_row_span, top_buttons_row, bottom_buttons_row, radius
    if full_mode then
        top_row_span = VerticalSpan:new{ width = Size.padding.fullscreen }
        bottom_row_span = top_row_span
        top_buttons_row = HorizontalGroup:new{
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
        bottom_buttons_row = HorizontalGroup:new{
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
        radius = Size.radius.window
    else
        top_row_span = VerticalSpan:new{ width = Size.padding.default }
        top_buttons_row = HorizontalGroup:new{
            align = "center",
            button_chapter_prev,
            small_button_span,
            button_chapter_next,
            small_button_span,
            button_bookmark_prev,
            small_button_span,
            button_bookmark_next,
            small_button_span,
            self.button_bookmark_toggle,
            small_button_span,
            self.current_page_text,
            small_button_span,
            button_orig_page,
            small_button_span,
            button_minus_ten,
            small_button_span,
            button_plus_ten,
            small_button_span,
            button_minus,
            small_button_span,
            button_plus,
        }
        if skim_dialog_position == "top" then
            bottom_row_span, bottom_buttons_row = top_row_span, top_buttons_row
            top_buttons_row = VerticalSpan:new{ width = 0 }
            top_row_span = top_buttons_row
        end
    end

    self.skimto_frame = FrameContainer:new{
        margin = 0,
        bordersize = frame_border_size,
        padding = frame_padding,
        radius = radius,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            top_buttons_row,
            top_row_span,
            self.progress_bar,
            bottom_row_span,
            bottom_buttons_row,
        }
    }
    self.movable = MovableContainer:new{
        self.skimto_frame,
    }
    self[1] = WidgetContainer:new{
        align = skim_dialog_position or "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = screen_width,
            h = screen_height,
        },
        self.movable,
    }

    if Device:hasDPad() then
        if full_mode then
            self.layout = {
                { button_chapter_prev, button_bookmark_prev, self.button_bookmark_toggle, button_bookmark_next, button_chapter_next },
                { button_minus_ten, button_minus, self.current_page_text, button_plus, button_plus_ten },
            }
        else
            self.layout = {
                { button_chapter_prev, button_chapter_next, button_bookmark_prev, button_bookmark_next, self.button_bookmark_toggle,
                  self.current_page_text, button_orig_page, button_minus_ten, button_plus_ten, button_minus, button_plus },
            }
        end
        self:moveFocusTo(1, 1)
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
    self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK)
end

function SkimToWidget:addOriginToLocationStack()
    -- Only add the page from which we launched the SkimToWidget to the location stack
    if not self.orig_page_added_to_stack then
        self.ui.link:addCurrentLocationToStack()
        self.orig_page_added_to_stack = true
    end
end

function SkimToWidget:onCloseWidget()
    if self.ui.paging then
        self.ui.paging:exitSkimMode()
    end
    UIManager:setDirty(nil, function()
        return "ui", self.skimto_frame.dimen
    end)
    self:free()
end

function SkimToWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.skimto_frame.dimen
    end)
    return true
end

function SkimToWidget:goToOrigPage()
    if self.orig_page_added_to_stack then
        self.ui.link:onGoBackLink()
        self.curr_page = self.ui:getCurrentPage()
        self:update()
        self.orig_page_added_to_stack = nil
    end
end

function SkimToWidget:goToPage(page)
    self.curr_page = page
    self:addOriginToLocationStack()
    self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
    self:update()
end

function SkimToWidget:goToByEvent(event_name)
    self:addOriginToLocationStack()
    self.ui:handleEvent(Event:new(event_name, false))
        -- add_current_location_to_stack=false, as we handled it here
    self.curr_page = self.ui:getCurrentPage()
    self:update()
end

function SkimToWidget:onFirstRowKeyPress(percent)
    local page = Math.round(percent * self.page_count)
    self:goToPage(page)
end

function SkimToWidget:onTapProgress(arg, ges_ev)
    if ges_ev.pos:intersectWith(self.progress_bar.dimen) then
        local percent = self.progress_bar:getPercentageFromPosition(ges_ev.pos)
        if percent then
            local page = Math.round(percent * self.page_count)
            self:goToPage(page)
        end
    elseif not ges_ev.pos:intersectWith(self.skimto_frame.dimen) then
        -- close if tap outside
        self:onClose()
    end
    return true
end

function SkimToWidget:onClose()
    UIManager:close(self)
    return true
end

return SkimToWidget
