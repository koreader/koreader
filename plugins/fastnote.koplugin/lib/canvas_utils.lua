--[[--
Pure math utilities for the fastnote drawing canvas.
No KOReader dependencies — fully unit-testable with busted.

@module fastnote.lib.canvas_utils
--]]--

-- ASSUMES: all coordinates are integers in screen-space pixels
-- ASSUMES: line_width is the full diameter (not radius) of the brush tip

local canvas_utils = {}

--- Compute the bounding rect that must be marked dirty after drawing a line
-- segment from (x1,y1) to (x2,y2) with a brush of the given width.
-- The rect is padded by half the brush width on every side so the full
-- stroke circle at each endpoint is covered.
-- Returned x/y are clamped to >= 0 (screen edge).
--
-- @param x1 number  start x
-- @param y1 number  start y
-- @param x2 number  end x
-- @param y2 number  end y
-- @param line_width number  brush diameter in pixels
-- @return table {x, y, w, h}
function canvas_utils.compute_dirty_rect(x1, y1, x2, y2, line_width)
    local half = line_width  -- pad by full width on each side to be safe

    local min_x = math.min(x1, x2)
    local min_y = math.min(y1, y2)
    local max_x = math.max(x1, x2)
    local max_y = math.max(y1, y2)

    local rx = math.max(0, min_x - half)
    local ry = math.max(0, min_y - half)
    local rw = (max_x - min_x) + half * 2
    local rh = (max_y - min_y) + half * 2

    return { x = rx, y = ry, w = rw, h = rh }
end

--- Test whether a screen point falls within a rectangular zone.
-- Uses exclusive upper bound (x in [zx, zx+zw), y in [zy, zy+zh)).
--
-- @param px number  point x
-- @param py number  point y
-- @param zx number  zone origin x
-- @param zy number  zone origin y
-- @param zw number  zone width
-- @param zh number  zone height
-- @return boolean
function canvas_utils.point_in_zone(px, py, zx, zy, zw, zh)
    return px >= zx and px < (zx + zw)
       and py >= zy and py < (zy + zh)
end

--- Map a raw pen pressure value to a brush line width.
-- Scales linearly from min_width (pressure 0) to max_width (pressure == max_pressure).
-- Clamps the result to [min_width, max_width] and returns an integer.
--
-- @param pressure     number  raw pressure (0..max_pressure)
-- @param max_pressure number  maximum pressure value from EVIOCGABS
-- @param min_width    number  minimum line width in pixels
-- @param max_width    number  maximum line width in pixels
-- @return number  integer line width
function canvas_utils.pressure_to_width(pressure, max_pressure, min_width, max_width)
    local clamped = math.max(0, math.min(pressure, max_pressure))
    local pressure_ratio = clamped / max_pressure  -- 0.0 .. 1.0
    local width = min_width + pressure_ratio * (max_width - min_width)
    return math.floor(width + 0.5)  -- round to nearest integer
end

--- Return the smallest {x,y,w,h} rect that contains both input rects.
-- Used to accumulate dirty regions for the deferred colour develop refresh.
-- @param a  table {x, y, w, h}
-- @param b  table {x, y, w, h}
-- @return   table {x, y, w, h}
function canvas_utils.union_rect(a, b)
    local x1 = math.min(a.x, b.x)
    local y1 = math.min(a.y, b.y)
    local x2 = math.max(a.x + a.w, b.x + b.w)
    local y2 = math.max(a.y + a.h, b.y + b.h)
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

--- Draw a thick line from (x0,y0) to (x1,y1) using Bresenham + paintRect.
-- KOReader's BlitBuffer has no paintLine method; this is the replacement.
-- @param bb     BlitBuffer  destination buffer
-- @param x0     number  start x (integer)
-- @param y0     number  start y (integer)
-- @param x1     number  end x (integer)
-- @param y1     number  end y (integer)
-- @param w      number  brush diameter in pixels (>= 1)
-- @param color  BlitBuffer color value
function canvas_utils.drawLine(bb, x0, y0, x1, y1, w, color)
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0),
                     math.floor(x1), math.floor(y1)
    local r          = math.max(0, math.floor((w - 1) / 2))
    local brush_side = 2 * r + 1
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy
    while true do
        bb:paintRect(x0 - r, y0 - r, brush_side, brush_side, color)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x0 = x0 + sx end
        if e2 <  dx then err = err + dx; y0 = y0 + sy end
    end
end

return canvas_utils
