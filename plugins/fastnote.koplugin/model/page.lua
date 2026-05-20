--[[--
model/page.lua — one page of a notebook.

Wraps a StrokeBuffer and the path to its SVG file.
Loading is lazy: the StrokeBuffer starts empty and is populated by load().
Pure Lua; no KOReader runtime dependencies except for repaintTo (BlitBuffer).
--]]--

local StrokeBuffer = require("lib/strokebuffer")

local Page = {}
Page.__index = Page

--- Create a Page object.
-- @string path  Absolute path to the SVG file (may not exist yet for new pages).
-- @param  sb    Optional pre-populated StrokeBuffer.
function Page.new(path, sb)
    return setmetatable({
        path       = path,
        stroke_buf = sb or StrokeBuffer.new(),
        _saved_n   = sb and #sb.strokes or 0,
    }, Page)
end

--- Load stroke data from the SVG file into a new Page object.
-- Returns a blank Page if the file does not exist (new page) or is unreadable.
-- @string path  Absolute path to the SVG file.
-- @return Page, w|nil, h|nil
function Page.load(path)
    local f = io.open(path, "r")
    if not f then
        return Page.new(path), nil, nil
    end
    local text = f:read("*a")
    f:close()

    local svg = require("lib/svg")
    local ok, sb, w, h = pcall(svg.read, text)
    if not ok or not sb then
        return Page.new(path), nil, nil
    end

    local p   = Page.new(path, sb)
    p._saved_n = #sb.strokes
    return p, w, h
end

--- Write current strokes to the SVG file.
-- @number w  Canvas width in pixels.
-- @number h  Canvas height in pixels.
-- @return boolean, string?
function Page:save(w, h)
    local svg = require("lib/svg")
    local f   = io.open(self.path, "w")
    if not f then
        return false, "cannot write " .. self.path
    end
    f:write(svg.write(self.stroke_buf, w, h))
    f:close()
    self._saved_n = #self.stroke_buf.strokes
    return true
end

--- True if strokes have been added or removed since the last save.
function Page:isDirty()
    return #self.stroke_buf.strokes ~= self._saved_n
end

return Page
