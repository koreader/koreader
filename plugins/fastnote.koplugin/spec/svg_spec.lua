--[[--
spec/svg_spec.lua — unit tests for lib/svg.lua
Run: busted spec/svg_spec.lua   (from plugin root)
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local svg          = require("lib/svg")
local StrokeBuffer = require("lib/strokebuffer")

-- Helper: build a StrokeBuffer with known strokes
local function make_sb()
    local sb = StrokeBuffer.new()
    -- Stroke 1: black, 4 points
    sb:penDown(10,  20, 3, "#000000")
    sb:penMove(30,  40, 4)
    sb:penMove(50,  60, 5)
    sb:penMove(70,  80, 3)
    sb:penUp()
    -- Stroke 2: colored, 2 points
    sb:penDown(100, 200, 2, "#ff0000")
    sb:penMove(300, 400, 2)
    sb:penUp()
    return sb
end

describe("svg.write", function()

    it("produces a string starting with <svg", function()
        local sb  = make_sb()
        local out = svg.write(sb, 1080, 1440)
        assert.is_string(out)
        assert.is_truthy(out:match("^<svg"))
    end)

    it("includes correct width and height attributes", function()
        local out = svg.write(make_sb(), 800, 600)
        assert.is_truthy(out:match('width="800"'))
        assert.is_truthy(out:match('height="600"'))
    end)

    it("includes a white background rect", function()
        local out = svg.write(make_sb(), 100, 100)
        assert.is_truthy(out:match('<rect'))
        assert.is_truthy(out:match('fill="white"'))
    end)

    it("produces a <polyline> for each non-empty stroke", function()
        local sb  = make_sb()
        local out = svg.write(sb, 1080, 1440)
        local count = 0
        for _ in out:gmatch('<polyline') do count = count + 1 end
        assert.equals(2, count)
    end)

    it("includes stroke color in polyline", function()
        local out = svg.write(make_sb(), 1080, 1440)
        assert.is_truthy(out:match('stroke="#ff0000"'))
    end)

    it("includes all sample points in the polyline", function()
        local sb = StrokeBuffer.new()
        sb:penDown(10, 20, 2); sb:penMove(30, 40, 2); sb:penMove(50, 60, 2); sb:penUp()
        local out = svg.write(sb, 500, 500)
        assert.is_truthy(out:match("10,20"))
        assert.is_truthy(out:match("30,40"))
        assert.is_truthy(out:match("50,60"))
    end)

    it("includes a <metadata> block", function()
        local out = svg.write(make_sb(), 1080, 1440)
        assert.is_truthy(out:match('<metadata>'))
        assert.is_truthy(out:match('<fn:data'))
    end)

    it("includes version, w, h in metadata JSON", function()
        local out = svg.write(make_sb(), 1080, 1440)
        local json_str = out:match('<fn:data[^>]*>(.-)</fn:data>')
        assert.is_truthy(json_str)
        assert.is_truthy(json_str:match('"version"'))
        assert.is_truthy(json_str:match('"w"'))
        assert.is_truthy(json_str:match('"h"'))
    end)

    it("skips strokes with fewer than 2 points", function()
        local sb = StrokeBuffer.new()
        sb:penDown(5, 5, 2)
        -- Don't call penMove — single-point stroke, but we bypass penUp
        -- by directly inserting a stub: use a real single-point stroke via penDown+penUp
        sb:penUp()  -- single-point, not committed
        local out = svg.write(sb, 100, 100)
        local count = 0
        for _ in out:gmatch('<polyline') do count = count + 1 end
        assert.equals(0, count)
    end)

end)

describe("svg.read", function()

    it("returns a StrokeBuffer", function()
        local sb_in  = make_sb()
        local text   = svg.write(sb_in, 1080, 1440)
        local sb_out = svg.read(text)
        assert.is_not_nil(sb_out)
    end)

    it("recovers w and h from metadata", function()
        local text         = svg.write(make_sb(), 1080, 1440)
        local _, w_out, h_out = svg.read(text)
        assert.equals(1080, w_out)
        assert.equals(1440, h_out)
    end)

    it("round-trips stroke count", function()
        local sb_in  = make_sb()
        local text   = svg.write(sb_in, 1080, 1440)
        local sb_out = svg.read(text)
        assert.equals(#sb_in.strokes, #sb_out.strokes)
    end)

    it("round-trips stroke colors", function()
        local sb_in  = make_sb()
        local text   = svg.write(sb_in, 1080, 1440)
        local sb_out = svg.read(text)
        assert.equals(sb_in.strokes[1].color, sb_out.strokes[1].color)
        assert.equals(sb_in.strokes[2].color, sb_out.strokes[2].color)
    end)

    it("round-trips point data losslessly", function()
        local sb_in  = make_sb()
        local text   = svg.write(sb_in, 1080, 1440)
        local sb_out = svg.read(text)
        assert.same(sb_in.strokes[1].pts, sb_out.strokes[1].pts)
        assert.same(sb_in.strokes[2].pts, sb_out.strokes[2].pts)
    end)

    it("handles an empty StrokeBuffer", function()
        local sb_in  = StrokeBuffer.new()
        local text   = svg.write(sb_in, 500, 400)
        local sb_out = svg.read(text)
        assert.is_true(sb_out:isEmpty())
    end)

    it("falls back to polyline parsing when metadata is absent", function()
        -- Craft an SVG without fn:data
        local plain_svg = [[
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
<polyline points="10,20 30,40 50,60" fill="none" stroke="#000000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>]]
        local sb = svg.read(plain_svg)
        assert.equals(1, #sb.strokes)
        assert.equals("#000000", sb.strokes[1].color)
        assert.equals(3, sb.strokes[1]:pointCount())
    end)

end)

describe("svg round-trip property", function()

    it("write then read is a no-op on point data for any stroke count", function()
        for n_strokes = 0, 5 do
            local sb = StrokeBuffer.new()
            for i = 1, n_strokes do
                sb:penDown(i * 10, 0, 2, "#000000")
                sb:penMove(i * 10 + 5, 5, 3)
                sb:penMove(i * 10 + 10, 10, 2)
                sb:penUp()
            end
            local text   = svg.write(sb, 200, 200)
            local sb2, _ = svg.read(text)
            assert.equals(#sb.strokes, #sb2.strokes,
                "stroke count mismatch for n=" .. n_strokes)
            for j = 1, #sb.strokes do
                assert.same(sb.strokes[j].pts, sb2.strokes[j].pts,
                    "pts mismatch for stroke " .. j .. " (n=" .. n_strokes .. ")")
            end
        end
    end)

end)
