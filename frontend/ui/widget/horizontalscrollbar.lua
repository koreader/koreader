local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local Screen = require("device").screen

local HorizontalScrollBar = InputContainer:extend{
    enable = true,
    low = 0,
    high = 1,
    height = Size.padding.default,
    width = Size.item.height_large, -- as in VerticalScrollBar
    bordersize = Size.border.thin,
    bordercolor = Blitbuffer.COLOR_BLACK,
    radius = 0,
    rectcolor = Blitbuffer.COLOR_BLACK,
    -- minimal width of the thumb/knob/grip (usually showing the current
    -- view size and position relative to the whole scrollable width):
    min_thumb_size = Size.line.thick,
    scroll_callback = nil,
    -- extra touchable height (for scrolling with pan) can be larger than
    -- the provided height (this is added on each side)
    extra_touch_on_side_heightratio = 1, -- make it 3 x height
}

function HorizontalScrollBar:init()
    self.extra_touch_on_side = math.ceil( self.extra_touch_on_side_heightratio * self.height)
    if Device:isTouchDevice() then
        local pan_rate = Screen.low_pan_rate and 2.0 or 5.0
        self.ges_events = {
            TapScroll = {
                GestureRange:new{
                    ges = "tap",
                    range = function() return self.touch_dimen end,
                },
            },
            HoldScroll = {
                GestureRange:new{
                    ges = "hold",
                    range = function() return self.touch_dimen end,
                },
            },
            HoldPanScroll = {
                GestureRange:new{
                    ges = "hold_pan",
                    rate = pan_rate,
                    range = function() return self.touch_dimen end,
                },
            },
            HoldReleaseScroll = {
                GestureRange:new{
                    ges = "hold_release",
                    range = function() return self.touch_dimen end,
                },
            },
            PanScroll = {
                GestureRange:new{
                    ges = "pan",
                    rate = pan_rate,
                    range = function() return self.touch_dimen end,
                },
            },
            PanScrollRelease = {
                GestureRange:new{
                    ges = "pan_release",
                    range = function() return self.touch_dimen end,
                },
            }
        }
    end
end

function HorizontalScrollBar:onTapScroll(arg, ges)
    if self.scroll_callback then
        local ratio = (ges.pos.x - self.touch_dimen.x) / self.width
        if BD.mirroredUILayout() then
            ratio = 1 - ratio
        end
        self.scroll_callback(ratio)
        return true
    end
end
HorizontalScrollBar.onHoldScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onHoldPanScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onHoldReleaseScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onPanScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onPanScrollRelease = HorizontalScrollBar.onTapScroll

function HorizontalScrollBar:getSize()
    return Geom:new{
        w = self.width,
        h = self.height
    }
end

function HorizontalScrollBar:set(low, high)
    self.low = low > 0 and low or 0
    self.high = high < 1 and high or 1
end

function HorizontalScrollBar:paintTo(bb, x, y)
    if not self.enable then return end
    self.touch_dimen = Geom:new{
        x = x,
        y = y - self.extra_touch_on_side,
        w = self.width,
        h = self.height + 2 * self.extra_touch_on_side,
    }
    bb:paintBorder(x, y, self.width, self.height,
                   self.bordersize, self.bordercolor, self.radius)
    if BD.mirroredUILayout() then
        bb:paintRect(x + self.bordersize + (1-self.high) * self.width, y + self.bordersize,
                     math.max((self.width - 2 * self.bordersize) * (self.high - self.low), self.min_thumb_size),
                     self.height - 2 * self.bordersize,
                     self.rectcolor)
    else
        bb:paintRect(x + self.bordersize + self.low * self.width, y + self.bordersize,
                     math.max((self.width - 2 * self.bordersize) * (self.high - self.low), self.min_thumb_size),
                     self.height - 2 * self.bordersize,
                     self.rectcolor)
    end
end

return HorizontalScrollBar
