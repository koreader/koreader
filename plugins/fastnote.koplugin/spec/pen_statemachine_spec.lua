--[[--
Unit tests for lib/pen_statemachine module.
Pure Lua state machine — no KOReader or FFI dependency required.

Converts raw linux input events (EV_KEY, EV_ABS, EV_SYN) into high-level
pen events: "down", "move", "hover", "up".

Run with: busted spec/pen_statemachine_spec.lua
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local SM = require("lib/pen_statemachine")

-- linux input.h constants (same values used in the implementation)
local BTN_TOOL_PEN    = 0x140
local BTN_TOOL_RUBBER = 0x141
local BTN_TOUCH       = 0x14a
local ABS_X           = 0
local ABS_Y           = 1
local ABS_PRESSURE    = 24

-- Helper: call fn(cb), collect all events emitted via cb
local function collect(fn)
    local evs = {}
    fn(function(e) evs[#evs + 1] = e end)
    return evs
end

describe("pen_statemachine", function()

    -- ── Initial state ────────────────────────────────────────────────────────

    describe("initial state", function()

        it("in_proximity defaults to false", function()
            local sm = SM:new()
            assert.is_false(sm.in_proximity)
        end)

        it("pen_down defaults to false", function()
            local sm = SM:new()
            assert.is_false(sm.pen_down)
        end)

        it("tool defaults to 'pen'", function()
            local sm = SM:new()
            assert.equals("pen", sm.tool)
        end)

        it("raw_x defaults to 0", function()
            local sm = SM:new()
            assert.equals(0, sm.raw_x)
        end)

        it("raw_y defaults to 0", function()
            local sm = SM:new()
            assert.equals(0, sm.raw_y)
        end)

        it("raw_p defaults to 0", function()
            local sm = SM:new()
            assert.equals(0, sm.raw_p)
        end)

    end)

    -- ── BTN_TOOL_PEN ─────────────────────────────────────────────────────────

    describe("BTN_TOOL_PEN", function()

        it("value=1 sets in_proximity=true and tool='pen'", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            assert.is_true(sm.in_proximity)
            assert.equals("pen", sm.tool)
        end)

        it("value=0 clears in_proximity", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOOL_PEN, 0)
            assert.is_false(sm.in_proximity)
        end)

        it("value=0 while pen_down emits 'up'", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()          -- consume the pending "down" event
            local evs = collect(function(cb)
                sm:feed_key(BTN_TOOL_PEN, 0, cb)
            end)
            assert.equals(1, #evs)
            assert.equals("up", evs[1].type)
        end)

        it("value=0 while pen_down also clears pen_down", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()
            sm:feed_key(BTN_TOOL_PEN, 0)
            assert.is_false(sm.pen_down)
        end)

        it("value=0 when NOT pen_down emits nothing", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            local evs = collect(function(cb)
                sm:feed_key(BTN_TOOL_PEN, 0, cb)
            end)
            assert.equals(0, #evs)
        end)

    end)

    -- ── BTN_TOOL_RUBBER ──────────────────────────────────────────────────────

    describe("BTN_TOOL_RUBBER", function()

        it("value=1 sets in_proximity=true and tool='eraser'", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_RUBBER, 1)
            assert.is_true(sm.in_proximity)
            assert.equals("eraser", sm.tool)
        end)

        it("value=0 clears in_proximity", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_RUBBER, 1)
            sm:feed_key(BTN_TOOL_RUBBER, 0)
            assert.is_false(sm.in_proximity)
        end)

        it("value=0 while pen_down emits 'up'", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_RUBBER, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()
            local evs = collect(function(cb)
                sm:feed_key(BTN_TOOL_RUBBER, 0, cb)
            end)
            assert.equals(1, #evs)
            assert.equals("up", evs[1].type)
        end)

    end)

    -- ── BTN_TOUCH ────────────────────────────────────────────────────────────

    describe("BTN_TOUCH", function()

        it("value=1 sets pen_down=true", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            assert.is_true(sm.pen_down)
        end)

        it("value=0 clears pen_down", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()
            sm:feed_key(BTN_TOUCH, 0)
            assert.is_false(sm.pen_down)
        end)

        it("value=0 emits 'up'", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()
            local evs = collect(function(cb)
                sm:feed_key(BTN_TOUCH, 0, cb)
            end)
            assert.equals(1, #evs)
            assert.equals("up", evs[1].type)
        end)

    end)

    -- ── ABS coord latching ───────────────────────────────────────────────────

    describe("feed_abs", function()

        it("ABS_X latches into raw_x", function()
            local sm = SM:new()
            sm:feed_abs(ABS_X, 1234)
            assert.equals(1234, sm.raw_x)
        end)

        it("ABS_Y latches into raw_y", function()
            local sm = SM:new()
            sm:feed_abs(ABS_Y, 567)
            assert.equals(567, sm.raw_y)
        end)

        it("ABS_PRESSURE latches into raw_p", function()
            local sm = SM:new()
            sm:feed_abs(ABS_PRESSURE, 999)
            assert.equals(999, sm.raw_p)
        end)

        it("unknown code is ignored (no state change)", function()
            local sm = SM:new()
            sm:feed_abs(99, 100)
            assert.equals(0, sm.raw_x)
            assert.equals(0, sm.raw_y)
            assert.equals(0, sm.raw_p)
        end)

    end)

    -- ── feed_syn ─────────────────────────────────────────────────────────────

    describe("feed_syn", function()

        it("emits 'down' on first syn after BTN_TOUCH 1", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_abs(ABS_X, 600)
            sm:feed_abs(ABS_Y, 800)
            sm:feed_abs(ABS_PRESSURE, 512)
            sm:feed_key(BTN_TOUCH, 1)
            local evs = collect(function(cb) sm:feed_syn(cb) end)
            assert.equals(1, #evs)
            assert.equals("down", evs[1].type)
            assert.equals(600,    evs[1].x)
            assert.equals(800,    evs[1].y)
            assert.equals(512,    evs[1].pressure)
            assert.equals("pen",  evs[1].tool)
        end)

        it("'down' event carries tool='eraser' when eraser is active", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_RUBBER, 1)
            sm:feed_key(BTN_TOUCH, 1)
            local evs = collect(function(cb) sm:feed_syn(cb) end)
            assert.equals("eraser", evs[1].tool)
        end)

        it("second syn after down emits 'move', not another 'down'", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()    -- consumes the pending "down"
            sm:feed_abs(ABS_X, 700)
            sm:feed_abs(ABS_Y, 900)
            sm:feed_abs(ABS_PRESSURE, 300)
            local evs = collect(function(cb) sm:feed_syn(cb) end)
            assert.equals(1, #evs)
            assert.equals("move", evs[1].type)
            assert.equals(700,    evs[1].x)
            assert.equals(900,    evs[1].y)
            assert.equals(300,    evs[1].pressure)
        end)

        it("emits 'hover' when in_proximity but not pen_down", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_abs(ABS_X, 400)
            sm:feed_abs(ABS_Y, 500)
            local evs = collect(function(cb) sm:feed_syn(cb) end)
            assert.equals(1, #evs)
            assert.equals("hover", evs[1].type)
            assert.equals(400,     evs[1].x)
            assert.equals(500,     evs[1].y)
        end)

        it("emits nothing when not in proximity and not pen_down", function()
            local sm = SM:new()
            local evs = collect(function(cb) sm:feed_syn(cb) end)
            assert.equals(0, #evs)
        end)

        it("nil cb does not crash", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            assert.has_no_error(function() sm:feed_syn(nil) end)
        end)

        it("nil cb on feed_key does not crash", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()
            assert.has_no_error(function()
                sm:feed_key(BTN_TOUCH, 0, nil)
            end)
        end)

    end)

    -- ── Full stroke sequences ────────────────────────────────────────────────

    describe("full stroke sequence", function()

        it("proximity → down × coords × syn × move × syn × up produces correct events", function()
            local sm = SM:new()
            local evs = {}
            local function cb(e) evs[#evs + 1] = e end

            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_abs(ABS_X, 100); sm:feed_abs(ABS_Y, 200); sm:feed_abs(ABS_PRESSURE, 400)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn(cb)                           -- → "down" (100,200,400,pen)

            sm:feed_abs(ABS_X, 150); sm:feed_abs(ABS_Y, 250); sm:feed_abs(ABS_PRESSURE, 500)
            sm:feed_syn(cb)                           -- → "move" (150,250,500)

            sm:feed_abs(ABS_X, 200); sm:feed_abs(ABS_Y, 300)
            sm:feed_syn(cb)                           -- → "move" (200,300,500)

            sm:feed_key(BTN_TOUCH, 0, cb)             -- → "up"
            sm:feed_syn(cb)                           -- → "hover" (pen still in proximity)

            assert.equals(5, #evs)
            assert.equals("down",  evs[1].type)
            assert.equals(100,     evs[1].x)
            assert.equals(200,     evs[1].y)
            assert.equals(400,     evs[1].pressure)
            assert.equals("pen",   evs[1].tool)
            assert.equals("move",  evs[2].type)
            assert.equals(150,     evs[2].x)
            assert.equals("move",  evs[3].type)
            assert.equals(200,     evs[3].x)
            assert.equals("up",    evs[4].type)
            assert.equals("hover", evs[5].type)
        end)

        it("second stroke after first produces correct events", function()
            local sm = SM:new()
            -- First stroke (discard events)
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()
            sm:feed_key(BTN_TOUCH, 0)

            -- Second stroke
            sm:feed_abs(ABS_X, 300); sm:feed_abs(ABS_Y, 400); sm:feed_abs(ABS_PRESSURE, 600)
            sm:feed_key(BTN_TOUCH, 1)
            local evs = collect(function(cb) sm:feed_syn(cb) end)
            assert.equals(1, #evs)
            assert.equals("down", evs[1].type)
            assert.equals(300, evs[1].x)
            assert.equals(400, evs[1].y)
            assert.equals(600, evs[1].pressure)
        end)

        it("proximity loss during stroke emits 'up' and clears state", function()
            local sm = SM:new()
            sm:feed_key(BTN_TOOL_PEN, 1)
            sm:feed_key(BTN_TOUCH, 1)
            sm:feed_syn()   -- "down" consumed

            local evs = collect(function(cb)
                sm:feed_key(BTN_TOOL_PEN, 0, cb)   -- pen removed from range while drawing
            end)
            assert.equals(1, #evs)
            assert.equals("up", evs[1].type)
            assert.is_false(sm.pen_down)
            assert.is_false(sm.in_proximity)
        end)

    end)

end)
