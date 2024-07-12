--[[--
HTML widget with vertical scroll bar.
--]]

local BD = require("ui/bidi")
local Device = require("device")
local HtmlBoxWidget = require("ui/widget/htmlboxwidget")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local Input = Device.input
local Screen = Device.screen

local ScrollHtmlWidget = InputContainer:extend{
    html_body = nil,
    is_xhtml = false,
    css = nil,
    default_font_size = Screen:scaleBySize(24), -- same as infofont
    htmlbox_widget = nil,
    v_scroll_bar = nil,
    dialog = nil,
    html_link_tapped_callback = nil,
    dimen = nil,
    width = 0,
    height = 0,
    scroll_bar_width = Screen:scaleBySize(6),
    text_scroll_span = Screen:scaleBySize(12),
}

function ScrollHtmlWidget:init()
    self.htmlbox_widget = HtmlBoxWidget:new{
        dimen = Geom:new{
            w = self.width - self.scroll_bar_width - self.text_scroll_span,
            h = self.height,
        },
        html_link_tapped_callback = self.html_link_tapped_callback,
    }

    self.htmlbox_widget:setContent(self.html_body, self.css, self.default_font_size, self.is_xhtml)

    self.v_scroll_bar = VerticalScrollBar:new{
        enable = self.htmlbox_widget.page_count > 1,
        width = self.scroll_bar_width,
        height = self.height,
        scroll_callback = function(ratio)
            self:scrollToRatio(ratio)
        end
    }

    self:_updateScrollBar()

    local horizontal_group = HorizontalGroup:new{}
    table.insert(horizontal_group, self.htmlbox_widget)
    table.insert(horizontal_group, HorizontalSpan:new{width=self.text_scroll_span})
    table.insert(horizontal_group, self.v_scroll_bar)
    self[1] = horizontal_group

    self.dimen = Geom:new(self[1]:getSize())

    if Device:isTouchDevice() then
        self.ges_events = {
            ScrollText = {
                GestureRange:new{
                    ges = "swipe",
                    range = function() return self.dimen end,
                },
            },
            TapScrollText = { -- allow scrolling with tap
                GestureRange:new{
                    ges = "tap",
                    range = function() return self.dimen end,
                },
            },
        }
    end

    if Device:hasKeys() then
        self.key_events = {
            ScrollDown = { { Input.group.PgFwd } },
            ScrollUp = { { Input.group.PgBack } },
        }
    end
end

-- Not to be confused with ScrollTextWidget's updateScrollBar, which has user-visible effects.
-- This simply updates the scroll bar's internal state according to the current page & page count.
function ScrollHtmlWidget:_updateScrollBar()
    self.v_scroll_bar:set((self.htmlbox_widget.page_number-1) / self.htmlbox_widget.page_count, self.htmlbox_widget.page_number / self.htmlbox_widget.page_count)
end

function ScrollHtmlWidget:getSinglePageHeight()
    return self.htmlbox_widget:getSinglePageHeight()
end

-- Reset the scrolling *state* to the top of the document, but don't actually re-render/refresh anything.
-- (Useful when replacing a Scroll*Widget during an update call, c.f., DictQuickLookup).
function ScrollHtmlWidget:resetScroll()
    self.htmlbox_widget.page_number = 1
    self:_updateScrollBar()

    self.v_scroll_bar.enable = self.htmlbox_widget.page_count > 1
end

function ScrollHtmlWidget:scrollToRatio(ratio)
    ratio = math.max(0, math.min(1, ratio)) -- ensure ratio is between 0 and 1 (100%)
    local page_num = 1 + math.floor((self.htmlbox_widget.page_count) * ratio)
    if page_num > self.htmlbox_widget.page_count then
        page_num = self.htmlbox_widget.page_count
    end
    if page_num == self.htmlbox_widget.page_number then
        return
    end
    self.htmlbox_widget.page_number = page_num
    self:_updateScrollBar()

    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()

    -- If our dialog is currently wrapped in a MovableContainer and that container has been made translucent,
    -- reset the alpha and refresh the whole thing, because we assume that a scroll means the user actually wants to
    -- *read* the content, which is kinda hard on a nearly transparent widget ;).
    if self.dialog.movable and self.dialog.movable.alpha then
        self.dialog.movable.alpha = nil
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dialog.movable.dimen
        end)
    else
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dimen
        end)
    end
end

function ScrollHtmlWidget:scrollText(direction)
    if direction == 0 then
        return
    end

    if direction > 0 then
        if self.htmlbox_widget.page_number >= self.htmlbox_widget.page_count then
            return
        end

        self.htmlbox_widget.page_number = self.htmlbox_widget.page_number + 1
    elseif direction < 0 then
        if self.htmlbox_widget.page_number <= 1 then
            return
        end

        self.htmlbox_widget.page_number = self.htmlbox_widget.page_number - 1
    end
    self:_updateScrollBar()

    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()

    -- Handle the container's alpha as above...
    if self.dialog.movable and self.dialog.movable.alpha then
        self.dialog.movable.alpha = nil
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dialog.movable.dimen
        end)
    else
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dimen
        end)
    end
end

function ScrollHtmlWidget:onScrollText(arg, ges)
    if ges.direction == "north" then
        self:scrollText(1)
        return true
    elseif ges.direction == "south" then
        self:scrollText(-1)
        return true
    end
    -- if swipe west/east, let it propagate up (e.g. for quickdictlookup to
    -- go to next/prev result)
end

function ScrollHtmlWidget:onTapScrollText(arg, ges)
    if BD.flipIfMirroredUILayout(ges.pos.x < Screen:getWidth()/2) then
        return self:onScrollUp()
    else
        return self:onScrollDown()
    end
end

function ScrollHtmlWidget:onScrollUp()
    if self.htmlbox_widget.page_number > 1 then
        self:scrollText(-1)
        return true
    end
    -- if we couldn't scroll (because we're already at top or bottom),
    -- let it propagate up (e.g. for quickdictlookup to go to next/prev result)
end

function ScrollHtmlWidget:onScrollDown()
    if self.htmlbox_widget.page_number < self.htmlbox_widget.page_count then
        self:scrollText(1)
        return true
    end
    -- if we couldn't scroll (because we're already at top or bottom),
    -- let it propagate up (e.g. for quickdictlookup to go to next/prev result)
end

return ScrollHtmlWidget
