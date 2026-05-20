--[[--
lib/stroke.lua — a single pen stroke.

Pure Lua; no KOReader runtime dependencies for all methods except paintTo.
paintTo(bb) requires the KOReader BlitBuffer and is not busted-testable.

Storage format for points (compact flat array, 3 values per point):
  pts = {x1, y1, w1, x2, y2, w2, ...}
where w is the pre-computed line width at that sample (pressure-derived).

ASSUMES: coordinates are screen-space integers.
--]]--

local Stroke = {}
Stroke.__index = Stroke

--- Create a new empty stroke.
-- @string color  Hex color string, e.g. "#000000". Defaults to black.
function Stroke.new(color)
    return setmetatable({
        color = color or "#000000",
        pts   = {},  -- flat array: {x,y,w, x,y,w, ...}
    }, Stroke)
end

--- Append a sample point to this stroke.
-- @number x  screen x
-- @number y  screen y
-- @number w  line width at this sample (px)
function Stroke:addPoint(x, y, w)
    local n = #self.pts
    self.pts[n + 1] = x
    self.pts[n + 2] = y
    self.pts[n + 3] = w
end

--- True when the stroke has fewer than 2 sample points.
-- A single point cannot be painted as a line segment.
function Stroke:isEmpty()
    return #self.pts < 6  -- < 2 points (each point = 3 values)
end

--- Number of sample points.
function Stroke:pointCount()
    return #self.pts / 3
end

--- Bounding box of this stroke (padded by max line width).
-- @return x, y, w, h  All integers.
function Stroke:bbox()
    local pts = self.pts
    if #pts == 0 then return 0, 0, 0, 0 end

    local min_x = pts[1]
    local min_y = pts[2]
    local max_x = pts[1]
    local max_y = pts[2]
    local max_w = pts[3]

    for i = 4, #pts, 3 do
        local x, y, w = pts[i], pts[i+1], pts[i+2]
        if x < min_x then min_x = x end
        if y < min_y then min_y = y end
        if x > max_x then max_x = x end
        if y > max_y then max_y = y end
        if w > max_w then max_w = w end
    end

    local pad = max_w
    return min_x - pad, min_y - pad,
           (max_x - min_x) + pad * 2, (max_y - min_y) + pad * 2
end

--- True if any segment of this stroke passes within `radius` of (px, py).
-- Uses point-to-segment distance.
-- @number px  query x
-- @number py  query y
-- @number radius  hit radius in pixels
function Stroke:hitTest(px, py, radius)
    local pts = self.pts
    local r2  = radius * radius
    for i = 4, #pts, 3 do
        local ax, ay = pts[i-3], pts[i-2]
        local bx, by = pts[i],   pts[i+1]
        local dx, dy = bx - ax, by - ay
        local len2   = dx * dx + dy * dy
        local t
        if len2 < 1 then
            t = 0
        else
            t = ((px - ax) * dx + (py - ay) * dy) / len2
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        local cx   = ax + t * dx
        local cy   = ay + t * dy
        local dist2 = (px - cx) * (px - cx) + (py - cy) * (py - cy)
        if dist2 <= r2 then return true end
    end
    return false
end

--- Replay this stroke onto a BlitBuffer.
-- KOReader runtime required; not busted-testable.
-- @param bb              BlitBuffer  the destination buffer
-- @param color_override  optional BlitBuffer color; when set, overrides self.color.
--   Used by dark-mode rendering so the display transform is a pure rendering
--   concern and stroke data stays canonical (#000000 on disk always).
function Stroke:paintTo(bb, color_override)
    local Blitbuffer   = require("ffi/blitbuffer")
    local canvas_utils = require("lib/canvas_utils")
    local color
    if color_override then
        color = color_override
    else
        local c = self.color
        color = (c and (c == "#ffffff" or c == "#FFFFFF"))
                and Blitbuffer.COLOR_WHITE
                or  Blitbuffer.COLOR_BLACK
    end
    local pts = self.pts
    for i = 4, #pts, 3 do
        local x1, y1     = pts[i-3], pts[i-2]
        local x2, y2, w2 = pts[i],   pts[i+1], pts[i+2]
        canvas_utils.drawLine(bb, x1, y1, x2, y2, w2, color)
    end
end

--- Serialise to a plain Lua table for JSON encoding.
-- Points are stored as a flat array [x,y,w, x,y,w, ...] for compactness.
function Stroke:toTable()
    return {color = self.color, pts = self.pts}
end

--- Reconstruct a Stroke from a plain Lua table (from JSON decode).
-- @param t  table  {color, pts=[flat array]}
function Stroke.fromTable(t)
    local s = Stroke.new(t.color)
    s.pts   = t.pts or {}
    return s
end

return Stroke
