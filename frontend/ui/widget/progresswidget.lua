--[[--
Widget for displaying progress bar.

Configurable attributes:

 * width
 * height
 * margin_v  -- vertical margin between border and fill bar
 * margin_h  -- horizontal margin between border and fill bar
 * radius
 * bordersize
 * bordercolor
 * bgcolor
 * fillcolor  -- color of the main fill bar
 * altcolor   -- color of the alt fill bar
 * ticks (list)  -- default to nil, use this if you want to insert markers
 * tick_width
 * last  -- maximum tick, used with ticks

Example:

    local foo_bar = ProgressWidget:new{
        width = Screen:scaleBySize(400),
        height = Screen:scaleBySize(10),
        percentage = 50/100,
    }
    UIManager:show(foo_bar)

]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local Math = require("optmath")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

-- Somewhat empirically chosen threshold to switch between the two designs ;o)
local INITIAL_MARKER_HEIGHT_THRESHOLD = Screen:scaleBySize(12)

local ProgressWidget = Widget:extend{
    width = nil,
    height = nil,
    margin_h = Screen:scaleBySize(3),
    margin_v = Screen:scaleBySize(1),
    radius = Screen:scaleBySize(2),
    bordersize = Screen:scaleBySize(1),
    bordercolor = Blitbuffer.COLOR_BLACK,
    bgcolor = Blitbuffer.COLOR_WHITE,
    fillcolor = Blitbuffer.COLOR_DARK_GRAY,
    altcolor = Blitbuffer.COLOR_LIGHT_GRAY,
    percentage = nil,
    ticks = nil,
    tick_width = Screen:scaleBySize(3),
    last = nil,
    fill_from_right = false,
    allow_mirroring = true,
    alt = nil, -- table with alternate pages to mark with different color (in the form {{ini1, len1}, {ini2, len2}, ...})
    _orig_margin_v = nil,
    _orig_bordersize = nil,
    initial_pos_marker = false, -- overlay a marker at the initial percentage position
    initial_percentage = nil,
}

function ProgressWidget:init()
    if self.initial_pos_marker then
        if not self.initial_percentage then
            self.initial_percentage = self.percentage
        end

        self:renderMarkerIcon()
    end
end

function ProgressWidget:renderMarkerIcon()
    if not self.initial_pos_marker then
        return
    end

    if self.initial_pos_icon then
        self.initial_pos_icon:free()
    end

    -- Can't do anything if we don't have a proper height yet...
    if not self.height then
        return
    end

    if self.height <= INITIAL_MARKER_HEIGHT_THRESHOLD then
        self.initial_pos_icon = IconWidget:new{
            icon = "position.marker.top",
            width = Math.round(self.height / 2),
            height = Math.round(self.height / 2),
            alpha = true,
        }
    else
        self.initial_pos_icon = IconWidget:new{
            icon = "position.marker",
            width = self.height,
            height = self.height,
            alpha = true,
        }
    end
end

function ProgressWidget:getSize()
    return { w = self.width, h = self.height }
end

function ProgressWidget:paintTo(bb, x, y)
    local my_size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new{
            x = x, y = y,
            w = my_size.w,
            h = my_size.h
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    if self.dimen.w == 0 or self.dimen.h == 0 then return end

    local _mirroredUI = BD.mirroredUILayout()
    -- We'll draw every bar element in order, bottom to top.
    local fill_width = my_size.w - 2*(self.margin_h + self.bordersize)
    local fill_y = y + self.margin_v + self.bordersize
    local fill_height = my_size.h - 2*(self.margin_v + self.bordersize)

    if self.radius == 0 then
        -- If we don't have rounded borders, we can start with a simple border colored rectangle.
        bb:paintRect(x, y, my_size.w, my_size.h, self.bordercolor)
        -- And a full background bar inside (i.e., on top) of that.
        bb:paintRect(x + self.margin_h + self.bordersize,
                     fill_y,
                     math.ceil(fill_width),
                     math.ceil(fill_height),
                     self.bgcolor)
    else
        -- Otherwise, we have to start with the background.
        bb:paintRoundedRect(x, y, my_size.w, my_size.h, self.bgcolor, self.radius)
        -- Then the border around that.
        bb:paintBorder(math.floor(x), math.floor(y),
                       my_size.w, my_size.h,
                       self.bordersize, self.bordercolor, self.radius)
    end

    -- Then we can just paint the fill rectangle(s) and tick(s) on top of that.
    -- First the fill bar(s)...
    -- Fill bar for alternate pages (e.g. non-linear flows).
    if self.alt and self.alt[1] ~= nil then
        for i=1, #self.alt do
            local tick_x = fill_width * ((self.alt[i][1] - 1) / self.last)
            local width = fill_width * (self.alt[i][2] / self.last)
            if _mirroredUI then
                tick_x = fill_width - tick_x - width
            end
            tick_x = math.floor(tick_x)
            width = math.ceil(width)

            bb:paintRect(x + self.margin_h + self.bordersize + tick_x,
                         fill_y,
                         width,
                         math.ceil(fill_height),
                         self.altcolor)
        end
    end

    -- Main fill bar for the specified percentage.
    if self.percentage >= 0 and self.percentage <= 1 then
        local fill_x = x + self.margin_h + self.bordersize
        if self.fill_from_right or (_mirroredUI and not self.fill_from_right) then
            fill_x = fill_x + (fill_width * (1 - self.percentage))
            fill_x = math.floor(fill_x)
        end

        bb:paintRect(fill_x,
                     fill_y,
                     math.ceil(fill_width * self.percentage),
                     math.ceil(fill_height),
                     self.fillcolor)

        -- Overlay the initial position marker on top of that
        if self.initial_pos_marker and self.initial_percentage >= 0 then
            if self.height <= INITIAL_MARKER_HEIGHT_THRESHOLD then
                self.initial_pos_icon:paintTo(bb, Math.round(fill_x + math.ceil(fill_width * self.initial_percentage) - self.height / 4), y - Math.round(self.height / 6))
            else
                self.initial_pos_icon:paintTo(bb, Math.round(fill_x + math.ceil(fill_width * self.initial_percentage) - self.height / 2), y)
            end
        end
    end

    -- ...then the tick(s).
    if self.ticks and self.last and self.last > 0 then
        for i, tick in ipairs(self.ticks) do
            local tick_x = fill_width * (tick / self.last)
            if _mirroredUI then
                tick_x = fill_width - tick_x
            end
            tick_x = math.floor(tick_x)

            bb:paintRect(x + self.margin_h + self.bordersize + tick_x,
                         fill_y,
                         self.tick_width,
                         math.ceil(fill_height),
                         self.bordercolor)
        end
    end
end

function ProgressWidget:setPercentage(percentage)
    self.percentage = percentage
    if self.initial_pos_marker then
        if not self.initial_percentage then
            self.initial_percentage = self.percentage
        end
    end
end

function ProgressWidget:getPercentageFromPosition(pos)
    if not pos or not pos.x then
        return nil
    end
    local width = self.dimen.w - 2*self.margin_h
    local x = pos.x - self.dimen.x - self.margin_h
    if x < 0 or x > width then
        return nil
    end
    if BD.mirroredUILayout() then
        x = width - x
    end
    return x / width
end

function ProgressWidget:setHeight(height)
    self.height = Screen:scaleBySize(height)
    -- Adjust vertical margin and border size to ensure there's
    -- at least 1 pixel left for the actual bar
    self._orig_margin_v = self._orig_margin_v or self.margin_v
    self._orig_bordersize = self._orig_bordersize or self.bordersize
    local margin_v_min = self._orig_margin_v > 0 and 1 or 0
    local bordersize_min = self._orig_bordersize > 0 and 1 or 0
    self.margin_v = math.min(self._orig_margin_v, math.floor((self.height - 2*self._orig_bordersize - 1) / 2))
    self.margin_v = math.max(self.margin_v, margin_v_min)
    self.bordersize = math.min(self._orig_bordersize, math.floor((self.height - 2*self.margin_v - 1) / 2))
    self.bordersize = math.max(self.bordersize, bordersize_min)

    -- Re-render marker, if any
    self:renderMarkerIcon()
end

function ProgressWidget:updateStyle(thick, height)
    if thick then
        self.margin_h = Screen:scaleBySize(3)
        self.margin_v = Screen:scaleBySize(1)
        self.bordersize = Screen:scaleBySize(1)
        self.radius = Screen:scaleBySize(2)
        self.bgcolor = Blitbuffer.COLOR_WHITE
        self.fillcolor = Blitbuffer.COLOR_DARK_GRAY
        self._orig_margin_v = nil
        self._orig_bordersize = nil
        if height then
            self:setHeight(height)
        end
    else
        self.margin_h = 0
        self.margin_v = 0
        self.bordersize = 0
        self.radius = 0
        self.bgcolor = Blitbuffer.COLOR_GRAY
        self.fillcolor = Blitbuffer.COLOR_GRAY_5
        self.ticks = nil
        self._orig_margin_v = nil
        self._orig_bordersize = nil
        if height then
            self:setHeight(height)
        end
    end
end

function ProgressWidget:free()
    if self.initial_pos_icon then
        self.initial_pos_icon:free()
    end
end

return ProgressWidget
