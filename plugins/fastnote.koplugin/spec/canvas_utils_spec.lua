--[[--
Unit tests for canvas_utils module.
Pure math functions — no KOReader dependency required.

Run with: busted spec/canvas_utils_spec.lua
--]]--

-- Add the plugin directory to the path so we can require plugin modules
-- without a KOReader installation
package.path = package.path .. ";fastnote.koplugin/?.lua"

local utils = require("lib/canvas_utils")

describe("canvas_utils", function()

    describe("compute_dirty_rect", function()

        it("returns a rect enclosing a horizontal segment", function()
            local r = utils.compute_dirty_rect(10, 20, 50, 20, 4)
            assert.are.equal(10 - 4, r.x)
            assert.are.equal(20 - 4, r.y)
            assert.are.equal((50 - 10) + 4 * 2, r.w)
            assert.are.equal(4 * 2, r.h)
        end)

        it("returns a rect enclosing a vertical segment", function()
            local r = utils.compute_dirty_rect(30, 10, 30, 80, 2)
            assert.are.equal(30 - 2, r.x)
            assert.are.equal(10 - 2, r.y)
            assert.are.equal(2 * 2, r.w)
            assert.are.equal((80 - 10) + 2 * 2, r.h)
        end)

        it("handles a diagonal segment", function()
            local r = utils.compute_dirty_rect(10, 10, 50, 40, 3)
            -- x range: 10..50, y range: 10..40
            assert.are.equal(10 - 3, r.x)
            assert.are.equal(10 - 3, r.y)
            assert.are.equal((50 - 10) + 3 * 2, r.w)
            assert.are.equal((40 - 10) + 3 * 2, r.h)
        end)

        it("handles reversed point order (p2 left of p1)", function()
            local r = utils.compute_dirty_rect(80, 20, 20, 20, 2)
            -- x range should still be 20..80
            assert.are.equal(20 - 2, r.x)
            assert.are.equal(20 - 2, r.y)
            assert.are.equal((80 - 20) + 2 * 2, r.w)
            assert.are.equal(2 * 2, r.h)
        end)

        it("clamps x below zero to zero", function()
            local r = utils.compute_dirty_rect(1, 5, 10, 5, 5)
            -- x = 1 - 5 = -4 → clamp to 0
            assert.are.equal(0, r.x)
        end)

        it("clamps y below zero to zero", function()
            local r = utils.compute_dirty_rect(5, 1, 5, 10, 5)
            assert.are.equal(0, r.y)
        end)

        it("returns non-negative width and height for a point stroke", function()
            local r = utils.compute_dirty_rect(50, 50, 50, 50, 3)
            assert.is_true(r.w >= 0)
            assert.is_true(r.h >= 0)
        end)

    end)

    describe("point_in_zone", function()

        it("returns true when point is inside the zone", function()
            assert.is_true(utils.point_in_zone(10, 10, 0, 0, 60, 60))
        end)

        it("returns true at zone origin", function()
            assert.is_true(utils.point_in_zone(0, 0, 0, 0, 60, 60))
        end)

        it("returns true at zone far corner (exclusive edge)", function()
            -- zone x=0,y=0,w=60,h=60 → valid range is 0..59
            assert.is_false(utils.point_in_zone(60, 60, 0, 0, 60, 60))
        end)

        it("returns false when point is outside to the right", function()
            assert.is_false(utils.point_in_zone(100, 10, 0, 0, 60, 60))
        end)

        it("returns false when point is outside below", function()
            assert.is_false(utils.point_in_zone(10, 100, 0, 0, 60, 60))
        end)

        it("returns false when point is outside to the left", function()
            assert.is_false(utils.point_in_zone(-1, 10, 0, 0, 60, 60))
        end)

        it("works with a non-origin zone", function()
            -- zone at (100,200), size 80x80
            assert.is_true(utils.point_in_zone(140, 240, 100, 200, 80, 80))
            assert.is_false(utils.point_in_zone(50, 50, 100, 200, 80, 80))
        end)

    end)

    describe("pressure_to_width", function()

        it("returns min_width at zero pressure", function()
            local w = utils.pressure_to_width(0, 1023, 1, 8)
            assert.are.equal(1, w)
        end)

        it("returns max_width at full pressure", function()
            local w = utils.pressure_to_width(1023, 1023, 1, 8)
            assert.are.equal(8, w)
        end)

        it("returns a value between min and max at half pressure", function()
            local w = utils.pressure_to_width(511, 1023, 1, 8)
            assert.is_true(w > 1)
            assert.is_true(w < 8)
        end)

        it("never returns below min_width", function()
            local w = utils.pressure_to_width(0, 1023, 2, 10)
            assert.is_true(w >= 2)
        end)

        it("never returns above max_width", function()
            local w = utils.pressure_to_width(2000, 1023, 2, 10)
            assert.is_true(w <= 10)
        end)

        it("returns an integer (no fractional widths)", function()
            local w = utils.pressure_to_width(700, 1023, 1, 8)
            assert.are.equal(math.floor(w), w)
        end)

    end)

end)
