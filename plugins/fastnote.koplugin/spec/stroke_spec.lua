--[[--
spec/stroke_spec.lua — unit tests for lib/stroke.lua
Run: busted spec/stroke_spec.lua   (from plugin root)
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local Stroke = require("lib/stroke")

describe("Stroke", function()

    -- ── Construction ────────────────────────────────────────────────────────

    describe("new", function()
        it("defaults to black", function()
            local s = Stroke.new()
            assert.equals("#000000", s.color)
        end)

        it("accepts a custom color", function()
            local s = Stroke.new("#ff0000")
            assert.equals("#ff0000", s.color)
        end)

        it("starts with no points", function()
            local s = Stroke.new()
            assert.equals(0, #s.pts)
        end)
    end)

    -- ── addPoint / pointCount ────────────────────────────────────────────────

    describe("addPoint", function()
        it("appends a point (3 values per point)", function()
            local s = Stroke.new()
            s:addPoint(10, 20, 3)
            assert.equals(3, #s.pts)
            assert.equals(10, s.pts[1])
            assert.equals(20, s.pts[2])
            assert.equals(3,  s.pts[3])
        end)

        it("appending twice gives 6 values", function()
            local s = Stroke.new()
            s:addPoint(1, 2, 3)
            s:addPoint(4, 5, 6)
            assert.equals(6, #s.pts)
        end)

        it("pointCount reflects the number of samples", function()
            local s = Stroke.new()
            assert.equals(0, s:pointCount())
            s:addPoint(0, 0, 1)
            assert.equals(1, s:pointCount())
            s:addPoint(1, 1, 1)
            assert.equals(2, s:pointCount())
        end)
    end)

    -- ── isEmpty ─────────────────────────────────────────────────────────────

    describe("isEmpty", function()
        it("is true for zero points", function()
            assert.is_true(Stroke.new():isEmpty())
        end)

        it("is true for exactly one point", function()
            local s = Stroke.new()
            s:addPoint(5, 5, 2)
            assert.is_true(s:isEmpty())
        end)

        it("is false when two or more points exist", function()
            local s = Stroke.new()
            s:addPoint(0, 0, 1)
            s:addPoint(10, 10, 2)
            assert.is_false(s:isEmpty())
        end)
    end)

    -- ── bbox ────────────────────────────────────────────────────────────────

    describe("bbox", function()
        it("returns zeros for empty stroke", function()
            local x, y, w, h = Stroke.new():bbox()
            assert.equals(0, x)
            assert.equals(0, y)
            assert.equals(0, w)
            assert.equals(0, h)
        end)

        it("single-point bbox is padded by that point's width", function()
            local s = Stroke.new()
            s:addPoint(50, 100, 4)
            local x, y, w, h = s:bbox()
            assert.equals(50 - 4, x)
            assert.equals(100 - 4, y)
            assert.equals(4 * 2, w)
            assert.equals(4 * 2, h)
        end)

        it("two-point horizontal stroke", function()
            local s = Stroke.new()
            s:addPoint(10, 50, 2)
            s:addPoint(90, 50, 2)
            local x, y, w, h = s:bbox()
            assert.equals(10 - 2, x)
            assert.equals(50 - 2, y)
            assert.equals((90 - 10) + 4, w)
            assert.equals(4, h)
        end)

        it("uses the maximum width for padding", function()
            local s = Stroke.new()
            s:addPoint(0, 0, 1)
            s:addPoint(10, 0, 8)  -- max width = 8
            local x, y = s:bbox()
            assert.equals(0 - 8, x)
            assert.equals(0 - 8, y)
        end)
    end)

    -- ── hitTest ─────────────────────────────────────────────────────────────

    describe("hitTest", function()
        it("returns false for empty stroke", function()
            assert.is_false(Stroke.new():hitTest(5, 5, 10))
        end)

        it("returns false for single-point stroke", function()
            local s = Stroke.new()
            s:addPoint(5, 5, 2)
            assert.is_false(s:hitTest(5, 5, 10))
        end)

        it("returns true when point is on the segment", function()
            local s = Stroke.new()
            s:addPoint(0, 50, 2)
            s:addPoint(100, 50, 2)
            assert.is_true(s:hitTest(50, 50, 5))
        end)

        it("returns true when point is within radius of endpoint", function()
            local s = Stroke.new()
            s:addPoint(0, 0, 2)
            s:addPoint(100, 0, 2)
            assert.is_true(s:hitTest(3, 3, 5))  -- near start
        end)

        it("returns false when point is outside radius", function()
            local s = Stroke.new()
            s:addPoint(0, 0, 2)
            s:addPoint(100, 0, 2)
            assert.is_false(s:hitTest(50, 20, 5))  -- 20 px away, radius 5
        end)

        it("hit is detected on a diagonal segment", function()
            local s = Stroke.new()
            s:addPoint(0, 0, 2)
            s:addPoint(100, 100, 2)
            -- Midpoint is (50,50), query at (52,48) — ~2.8 px away
            assert.is_true(s:hitTest(52, 48, 5))
        end)
    end)

    -- ── toTable / fromTable round-trip ───────────────────────────────────────

    describe("toTable / fromTable", function()
        it("round-trips color", function()
            local s = Stroke.new("#aabbcc")
            local s2 = Stroke.fromTable(s:toTable())
            assert.equals("#aabbcc", s2.color)
        end)

        it("round-trips points exactly", function()
            local s = Stroke.new()
            s:addPoint(10, 20, 3)
            s:addPoint(30, 40, 5)
            local s2 = Stroke.fromTable(s:toTable())
            assert.same(s.pts, s2.pts)
        end)

        it("fromTable with missing pts produces empty pts", function()
            local s = Stroke.fromTable({color = "#000000"})
            assert.equals(0, #s.pts)
        end)
    end)

end)
