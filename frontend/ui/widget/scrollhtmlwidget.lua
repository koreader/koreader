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

local ScrollHtmlWidget = InputContainer:new{
    html_body = nil,
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

    self.htmlbox_widget:setContent(self.html_body, self.css, self.default_font_size)

    self.v_scroll_bar = VerticalScrollBar:new{
        enable = self.htmlbox_widget.page_count > 1,
        width = self.scroll_bar_width,
        height = self.height,
        scroll_callback = function(ratio)
            self:scrollToRatio(ratio)
        end
    }

    self.v_scroll_bar:set((self.htmlbox_widget.page_number-1) / self.htmlbox_widget.page_count, self.htmlbox_widget.page_number / self.htmlbox_widget.page_count)

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
            ScrollDown = {{Input.group.PgFwd}, doc = "scroll down"},
            ScrollUp = {{Input.group.PgBack}, doc = "scroll up"},
        }
    end
end

function ScrollHtmlWidget:getSinglePageHeight()
    return self.htmlbox_widget:getSinglePageHeight()
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
    self.v_scroll_bar:set((page_num-1) / self.htmlbox_widget.page_count, page_num / self.htmlbox_widget.page_count)
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()
    UIManager:setDirty(self.dialog, function()
        return "partial", self.dimen
    end)
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

    self.v_scroll_bar:set((self.htmlbox_widget.page_number-1) / self.htmlbox_widget.page_count, self.htmlbox_widget.page_number / self.htmlbox_widget.page_count)

    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()

    UIManager:setDirty(self.dialog, function()
        return "partial", self.dimen
    end)
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
        if self.htmlbox_widget.page_number > 1 then
            self:scrollText(-1)
            return true
        end
    else
        if self.htmlbox_widget.page_number < self.htmlbox_widget.page_count then
            self:scrollText(1)
            return true
        end
    end
    -- if we couldn't scroll (because we're already at top or bottom),
    -- let it propagate up (e.g. for quickdictlookup to go to next/prev result)
end

function ScrollHtmlWidget:onScrollDown()
    self:scrollText(1)
    return true
end

function ScrollHtmlWidget:onScrollUp()
    self:scrollText(-1)
    return true
end

return ScrollHtmlWidget
