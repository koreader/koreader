--[[--
lib/svg.lua — SVG serialisation for fastnote pages.

Pure Lua; no KOReader or FFI dependencies — fully busted-testable.

Format:
  <svg width="W" height="H">
    <rect width="W" height="H" fill="white"/>
    <!-- one <polyline> per stroke — renders in any SVG viewer -->
    <polyline points="x,y ..." stroke="#000000" stroke-width="N" .../>
    <metadata>
      <fn:data xmlns:fn="urn:fastnote:1">
        {"version":1,"w":W,"h":H,"strokes":[...]}
      </fn:data>
    </metadata>
  </svg>

The <polyline> elements use the average line width per stroke. The
<metadata> JSON block contains the full per-point data (including width)
for lossless round-tripping.

svg.read() recovers via the JSON block when present; falls back to
parsing <polyline> elements for SVGs produced by other tools.
--]]--

local json = require("lib/json")

local svg = {}

-- ---------------------------------------------------------------------------
-- Write
-- ---------------------------------------------------------------------------

--- Serialise a StrokeBuffer to an SVG string.
-- @param  strokebuf  StrokeBuffer
-- @param  w          number  canvas width in pixels
-- @param  h          number  canvas height in pixels
-- @return string  SVG text
function svg.write(strokebuf, w, h)
    local lines = {}

    lines[#lines + 1] = string.format(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', w, h)
    lines[#lines + 1] = string.format(
        '<rect width="%d" height="%d" fill="white"/>', w, h)

    -- Visual polylines -------------------------------------------------------
    for _, stroke in ipairs(strokebuf.strokes) do
        local pts = stroke.pts
        if #pts >= 6 then  -- at least 2 points
            -- Build points string and compute average width
            local pts_parts = {}
            local total_w = 0
            local n_pts = #pts / 3
            for i = 1, #pts, 3 do
                pts_parts[#pts_parts + 1] = string.format("%d,%d", pts[i], pts[i+1])
                total_w = total_w + pts[i+2]
            end
            local avg_w = math.max(1, math.floor(total_w / n_pts + 0.5))
            lines[#lines + 1] = string.format(
                '<polyline points="%s" fill="none" stroke="%s" stroke-width="%d"'
                .. ' stroke-linecap="round" stroke-linejoin="round"/>',
                table.concat(pts_parts, " "),
                stroke.color or "#000000",
                avg_w)
        end
    end

    -- Metadata: full stroke data for lossless round-trip --------------------
    local data = strokebuf:toTable()
    data.version = 1
    data.w       = w
    data.h       = h

    lines[#lines + 1] = '<metadata>'
    lines[#lines + 1] = '<fn:data xmlns:fn="urn:fastnote:1">'
    lines[#lines + 1] = json.encode(data)
    lines[#lines + 1] = '</fn:data>'
    lines[#lines + 1] = '</metadata>'
    lines[#lines + 1] = '</svg>'

    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Read
-- ---------------------------------------------------------------------------

--- Recover a StrokeBuffer from an SVG string.
-- Attempts JSON metadata first; falls back to <polyline> parsing.
-- @param  text  string  SVG text
-- @return StrokeBuffer, w|nil, h|nil
function svg.read(text)
    local StrokeBuffer = require("lib/strokebuffer")

    -- Primary: JSON metadata block -------------------------------------------
    local json_str = text:match('<fn:data[^>]*>(.-)</fn:data>')
    if json_str then
        local ok, data = pcall(json.decode, json_str:match("^%s*(.-)%s*$"))
        if ok and type(data) == "table" and type(data.strokes) == "table" then
            return StrokeBuffer.fromTable(data), data.w, data.h
        end
    end

    -- Fallback: parse <polyline> elements ------------------------------------
    -- Points carry no per-sample width; use stroke-width as a constant.
    local Stroke = require("lib/stroke")
    local sb     = StrokeBuffer.new()

    for pts_str, color_str, width_str in text:gmatch(
            '<polyline%s+points="([^"]*)"[^>]*stroke="([^"]*)"[^>]*stroke%-width="([^"]*)"') do
        local w_val = tonumber(width_str) or 3
        local stroke = Stroke.new(color_str)
        for x_str, y_str in pts_str:gmatch("(%d+),(%d+)") do
            stroke:addPoint(tonumber(x_str), tonumber(y_str), w_val)
        end
        if not stroke:isEmpty() then
            sb.strokes[#sb.strokes + 1] = stroke
        end
    end

    return sb, nil, nil
end

return svg
