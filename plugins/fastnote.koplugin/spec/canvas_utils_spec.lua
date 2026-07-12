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

    describe("union_rect", function()

        it("returns the bounding rect of two non-overlapping rects", function()
            local a = { x = 10, y = 10, w = 20, h = 20 }
            local b = { x = 50, y = 50, w = 10, h = 10 }
            local u = utils.union_rect(a, b)
            assert.are.equal(10, u.x)
            assert.are.equal(10, u.y)
            assert.are.equal(50, u.w)  -- 10 to 60 = 50 wide
            assert.are.equal(50, u.h)
        end)

        it("returns the bounding rect of two overlapping rects", function()
            local a = { x = 0, y = 0, w = 30, h = 30 }
            local b = { x = 20, y = 20, w = 30, h = 30 }
            local u = utils.union_rect(a, b)
            assert.are.equal(0, u.x)
            assert.are.equal(0, u.y)
            assert.are.equal(50, u.w)
            assert.are.equal(50, u.h)
        end)

        it("returns the same rect when both args are identical", function()
            local a = { x = 5, y = 7, w = 100, h = 40 }
            local u = utils.union_rect(a, a)
            assert.are.equal(5,   u.x)
            assert.are.equal(7,   u.y)
            assert.are.equal(100, u.w)
            assert.are.equal(40,  u.h)
        end)

        it("returns the larger rect when one contains the other", function()
            local outer = { x = 0, y = 0, w = 100, h = 100 }
            local inner = { x = 10, y = 10, w = 20, h = 20 }
            local u = utils.union_rect(outer, inner)
            assert.are.equal(0,   u.x)
            assert.are.equal(0,   u.y)
            assert.are.equal(100, u.w)
            assert.are.equal(100, u.h)
        end)

    end)

    describe("live_ink_mode", function()
        -- Task C2 ("draw black, bloom color"): pure decision of whether a
        -- live-drawn segment should paint into _bb as solid ink or the
        -- stroke's true color. See
        -- .agents/plans/color-pipeline-diagnosis-and-fix.md.

        it("returns 'solid' for style=solid on color hw, light mode, no live_color_refresh", function()
            assert.are.equal("solid", utils.live_ink_mode("solid", false, true, false))
        end)

        it("returns 'true_color' for style=color on color hw, light mode", function()
            assert.are.equal("true_color", utils.live_ink_mode("color", false, true, false))
        end)

        it("returns 'true_color' in dark mode even when style=solid", function()
            -- Dark mode already forces white ink (existing _strokeColor
            -- behavior) -- it's already "solid", so no display divergence
            -- from StrokeBuffer's true color is needed.
            assert.are.equal("true_color", utils.live_ink_mode("solid", true, true, false))
        end)

        it("returns 'true_color' on mono hardware even when style=solid", function()
            assert.are.equal("true_color", utils.live_ink_mode("solid", false, false, false))
        end)

        it("returns 'true_color' when live_color_refresh is active, even when style=solid", function()
            -- live_color_refresh exists precisely to show true color live;
            -- solid black would defeat its purpose. Precedence:
            -- live_color_refresh > live_ink_style.
            assert.are.equal("true_color", utils.live_ink_mode("solid", false, true, true))
        end)

        it("returns 'true_color' for an unrecognized style value (fail safe to current behavior)", function()
            assert.are.equal("true_color", utils.live_ink_mode("bogus", false, true, false))
        end)

        it("returns 'true_color' when the tighten pass is disabled, even when style=solid", function()
            -- With tighten_enabled == false nothing ever repaints the true
            -- color back over the solid ink -- strokes would stay black
            -- until an unrelated full repaint. Solid only makes sense when
            -- the bloom is coming.
            assert.are.equal("true_color", utils.live_ink_mode("solid", false, true, false, false))
        end)

        it("returns 'solid' when tighten_enabled is explicitly true", function()
            assert.are.equal("solid", utils.live_ink_mode("solid", false, true, false, true))
        end)

    end)

    describe("selftest_layout", function()
        -- Task C1 fix: the color self-test bar block must sit at the TOP of
        -- the drawable area (below the chrome strip) so a centered
        -- InfoMessage shown afterward can never cover it -- see
        -- _runColorSelfTest in drawingcanvas.lua.

        it("centers the bar block horizontally at width_fraction of screen width", function()
            local r = utils.selftest_layout(1264, 1680, 75, 8, 40, 0.6, 8)
            local expected_w = math.floor(1264 * 0.6)
            assert.are.equal(expected_w, r.w)
            assert.are.equal(math.floor((1264 - expected_w) / 2), r.x)
        end)

        it("positions the block at the top of the drawable area (chrome_h + top_margin)", function()
            local r = utils.selftest_layout(1264, 1680, 75, 8, 40, 0.6, 8)
            assert.are.equal(75 + 8, r.y)
        end)

        it("sets height to bar_count * bar_height", function()
            local r = utils.selftest_layout(1264, 1680, 75, 8, 40, 0.6, 8)
            assert.are.equal(8 * 40, r.h)
        end)

        it("never lets the block's y sit above (overlap) the chrome strip, even with zero top_margin", function()
            local r = utils.selftest_layout(1264, 1680, 75, 8, 40, 0.6, 0)
            assert.is_true(r.y >= 75)
        end)

        it("keeps the block within screen width for a typical fraction", function()
            local r = utils.selftest_layout(1264, 1680, 75, 8, 40, 0.6, 8)
            assert.is_true(r.x >= 0)
            assert.is_true(r.x + r.w <= 1264)
        end)

        it("recomputes correctly for a different bar count and height", function()
            local r = utils.selftest_layout(600, 800, 50, 3, 20, 0.5, 10)
            assert.are.equal(math.floor(600 * 0.5), r.w)
            assert.are.equal(math.floor((600 - r.w) / 2), r.x)
            assert.are.equal(50 + 10, r.y)
            assert.are.equal(3 * 20, r.h)
        end)

    end)

end)

