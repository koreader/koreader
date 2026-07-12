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

--- Decide whether a live-drawn segment should paint into the display buffer
-- as solid ink or as the stroke's true color (Task C2, "draw black, bloom
-- color" -- see .agents/plans/color-pipeline-diagnosis-and-fix.md).
--
-- A2 (the live-drawing waveform on color hardware) is 1-bit: a colored
-- stroke thresholds to a faint, sparse dither pattern instead of a solid
-- line. "solid" style paints the live segment in solid black instead, while
-- the stroke's true color still goes into StrokeBuffer unchanged (ADR-002)
-- and is revealed by the deferred tighten pass.
--
-- Precedence, checked in order:
--   1. Dark mode already forces solid white ink (existing behavior) --
--      always "true_color" here, since there is nothing to diverge from.
--   2. Mono hardware never has this problem (no A2 dither thresholding of
--      color) -- always "true_color".
--   3. The live_color_refresh experiment exists specifically to show true
--      color live; solid black would defeat its purpose -- always
--      "true_color" when it's active.
--   4. The tighten pass is what repaints the true color back over solid
--      ink -- with it disabled (tighten_enabled == false), solid ink would
--      stay black until an unrelated full repaint, so "true_color" wins.
--   5. Otherwise: "solid" style on color hardware -> "solid". Any other
--      style value (including "color", and unrecognized values as a
--      fail-safe) -> "true_color".
--
-- @param style                     string   "solid" | "color" (live_ink_style config)
-- @param dark_mode                 boolean
-- @param has_color_hw              boolean
-- @param live_color_refresh_active boolean  result of _useLiveColorRefresh()
-- @param tighten_enabled           boolean  only an explicit false disables
--                                  solid ink (nil is treated as enabled)
-- @return string  "solid" | "true_color"
function canvas_utils.live_ink_mode(style, dark_mode, has_color_hw, live_color_refresh_active, tighten_enabled)
    if dark_mode then return "true_color" end
    if not has_color_hw then return "true_color" end
    if live_color_refresh_active then return "true_color" end
    if tighten_enabled == false then return "true_color" end
    if style == "solid" then return "solid" end
    return "true_color"
end

--- Compute the layout rect for the color self-test bar block (Task C1 fix).
-- Horizontally centered at width_fraction of screen width; positioned at
-- the TOP of the drawable area (chrome_h + top_margin), not centered
-- vertically -- a bar block centered in the drawable area sits directly
-- under the centered InfoMessage the self-test shows next to it, which
-- covers the bars completely. Placing the block at the top instead keeps
-- it clear of that InfoMessage. See _runColorSelfTest in drawingcanvas.lua.
--
-- @param screen_w      number  screen width in pixels
-- @param screen_h      number  screen height in pixels (kept for a stable,
--                              self-describing signature; the top-anchored
--                              block doesn't need it for this calculation)
-- @param chrome_h      number  chrome strip height in pixels
-- @param bar_count     number  number of bars stacked in the block
-- @param bar_height    number  height of each bar in pixels
-- @param width_fraction number fraction of screen_w the block should span (0..1)
-- @param top_margin    number  gap between the chrome strip and the first bar
-- @return table {x, y, w, h}
function canvas_utils.selftest_layout(screen_w, screen_h, chrome_h, bar_count,
                                       bar_height, width_fraction, top_margin)
    local w = math.floor(screen_w * width_fraction)
    local h = bar_count * bar_height
    local x = math.floor((screen_w - w) / 2)
    local y = chrome_h + top_margin
    return { x = x, y = y, w = w, h = h }
end

return canvas_utils
