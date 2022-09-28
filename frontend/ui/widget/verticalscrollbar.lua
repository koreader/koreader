local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local Screen = require("device").screen

local VerticalScrollBar = InputContainer:extend{
    enable = true,
    low = 0,
    high = 1,
    width = Size.padding.default,
    height = Size.item.height_large,
    bordersize = Size.border.thin,
    bordercolor = Blitbuffer.COLOR_BLACK,
    radius = 0,
    rectcolor = Blitbuffer.COLOR_BLACK,
    -- minimal height of the thumb/knob/grip (usually showing the current
    -- view size and position relative to the whole scrollable height):
    min_thumb_size = Size.line.thick,
    scroll_callback = nil,
    -- extra touchable width (for scrolling with pan) can be larger than
    -- the provided width (this is added on each side)
    extra_touch_on_side_width_ratio = 1, -- make it 3 x width
}

function VerticalScrollBar:init()
    self.extra_touch_on_side = math.ceil( self.extra_touch_on_side_width_ratio * self.width )
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

function VerticalScrollBar:onTapScroll(arg, ges)
    if self.scroll_callback then
        local ratio = (ges.pos.y - self.touch_dimen.y) / self.height
        self.scroll_callback(ratio)
        return true
    end
end
VerticalScrollBar.onHoldScroll = VerticalScrollBar.onTapScroll
VerticalScrollBar.onHoldPanScroll = VerticalScrollBar.onTapScroll
VerticalScrollBar.onHoldReleaseScroll = VerticalScrollBar.onTapScroll
VerticalScrollBar.onPanScroll = VerticalScrollBar.onTapScroll
VerticalScrollBar.onPanScrollRelease = VerticalScrollBar.onTapScroll

function VerticalScrollBar:getSize()
    return Geom:new{
        w = self.width,
        h = self.height
    }
end

function VerticalScrollBar:set(low, high)
    self.low = low > 0 and low or 0
    self.high = high < 1 and high or 1
end

function VerticalScrollBar:paintTo(bb, x, y)
    if not self.enable then return end
    self.touch_dimen = Geom:new{
        x = x - self.extra_touch_on_side,
        y = y,
        w = self.width + 2 * self.extra_touch_on_side,
        h = self.height,
    }
    bb:paintBorder(x, y, self.width, self.height,
                   self.bordersize, self.bordercolor, self.radius)
    bb:paintRect(x + self.bordersize, y + self.bordersize + self.low * self.height,
                 self.width - 2 * self.bordersize,
                 math.max((self.height - 2 * self.bordersize) * (self.high - self.low), self.min_thumb_size),
                 self.rectcolor)
end

return VerticalScrollBar
