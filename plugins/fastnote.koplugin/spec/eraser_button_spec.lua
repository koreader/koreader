-- spec/eraser_button_spec.lua
--
-- Unit tests for lib/eraser_button.lua.
-- Pure Lua -- no KOReader or FFI dependency required.
--
-- Run with: busted spec/eraser_button_spec.lua

package.path = package.path .. ";fastnote.koplugin/?.lua"

local eraser_button = require("lib/eraser_button")
local codes          = require("lib/input_codes")

local BTN_STYLUS  = codes.BTN_STYLUS
local BTN_STYLUS2 = codes.BTN_STYLUS2

describe("lib/eraser_button", function()

    -- ── configured = "stylus" (default): BTN_STYLUS is the eraser tip ───────

    describe("configured = 'stylus'", function()

        it("BTN_STYLUS press (value=1) -> 'rubber_on'", function()
            assert.equals("rubber_on", eraser_button.decode(BTN_STYLUS, 1, "stylus"))
        end)

        it("BTN_STYLUS release (value=0) -> 'pen_restore'", function()
            assert.equals("pen_restore", eraser_button.decode(BTN_STYLUS, 0, "stylus"))
        end)

        it("BTN_STYLUS2 press (value=1) -> 'side_button' (not the configured eraser)", function()
            assert.equals("side_button", eraser_button.decode(BTN_STYLUS2, 1, "stylus"))
        end)

        it("BTN_STYLUS2 release (value=0) -> 'side_button'", function()
            assert.equals("side_button", eraser_button.decode(BTN_STYLUS2, 0, "stylus"))
        end)

    end)

    -- ── configured = "stylus2": swapped unit, BTN_STYLUS2 is the eraser tip ─

    describe("configured = 'stylus2'", function()

        it("BTN_STYLUS2 press (value=1) -> 'rubber_on'", function()
            assert.equals("rubber_on", eraser_button.decode(BTN_STYLUS2, 1, "stylus2"))
        end)

        it("BTN_STYLUS2 release (value=0) -> 'pen_restore'", function()
            assert.equals("pen_restore", eraser_button.decode(BTN_STYLUS2, 0, "stylus2"))
        end)

        it("BTN_STYLUS press (value=1) -> 'side_button' (not the configured eraser)", function()
            assert.equals("side_button", eraser_button.decode(BTN_STYLUS, 1, "stylus2"))
        end)

        it("BTN_STYLUS release (value=0) -> 'side_button'", function()
            assert.equals("side_button", eraser_button.decode(BTN_STYLUS, 0, "stylus2"))
        end)

    end)

    -- ── Default configured_button (nil behaves like "stylus") ────────────────

    describe("configured_button = nil (default)", function()

        it("BTN_STYLUS press -> 'rubber_on' (defaults to 'stylus')", function()
            assert.equals("rubber_on", eraser_button.decode(BTN_STYLUS, 1, nil))
        end)

    end)

    -- ── Unknown code ──────────────────────────────────────────────────────────

    describe("unknown code", function()

        it("a code that is neither BTN_STYLUS nor BTN_STYLUS2 -> 'unknown'", function()
            assert.equals("unknown", eraser_button.decode(0x999, 1, "stylus"))
        end)

    end)

    -- ── update_held: order-independent eraser latch ─────────────────────────
    -- Pure state transition: given the current held-state and a decoded
    -- M.decode() action, returns the new held-state. This is the fix for the
    -- intra-frame ordering race described in
    -- .agents/plans/eraser-capture-runbook.md -- the latch only changes on
    -- the authoritative "rubber_on"/"pen_restore" actions, so it doesn't
    -- matter whether EV_KEY or EV_ABS arrives first within a frame.

    describe("update_held", function()

        it("'rubber_on' latches held to true, from false", function()
            assert.is_true(eraser_button.update_held(false, "rubber_on"))
        end)

        it("'rubber_on' leaves held true if already true", function()
            assert.is_true(eraser_button.update_held(true, "rubber_on"))
        end)

        it("'pen_restore' releases held to false, from true", function()
            assert.is_false(eraser_button.update_held(true, "pen_restore"))
        end)

        it("'pen_restore' leaves held false if already false", function()
            assert.is_false(eraser_button.update_held(false, "pen_restore"))
        end)

        it("'side_button' leaves held untouched (true stays true)", function()
            assert.is_true(eraser_button.update_held(true, "side_button"))
        end)

        it("'side_button' leaves held untouched (false stays false)", function()
            assert.is_false(eraser_button.update_held(false, "side_button"))
        end)

        it("'unknown' leaves held untouched (true stays true)", function()
            assert.is_true(eraser_button.update_held(true, "unknown"))
        end)

        it("'unknown' leaves held untouched (false stays false)", function()
            assert.is_false(eraser_button.update_held(false, "unknown"))
        end)

    end)

    -- ── mt_tool_for_pen_slot: latch overrides ABS_MT_TOOL_TYPE=pen reports ──
    -- Consulted by pendev.lua's ABS_MT_TOOL_TYPE == MT_TOOL_PEN branch so a
    -- sticky/re-emitted MT_TOOL_PEN report while the eraser is still held
    -- doesn't flip the tool back to pen.

    describe("mt_tool_for_pen_slot", function()

        local MT_TOOL_PEN    = codes.MT_TOOL_PEN
        local MT_TOOL_ERASER = codes.MT_TOOL_ERASER
        local BTN_TOOL_PEN    = codes.BTN_TOOL_PEN
        local BTN_TOOL_RUBBER = codes.BTN_TOOL_RUBBER

        it("MT_TOOL_PEN while held maps to BTN_TOOL_RUBBER", function()
            assert.equals(BTN_TOOL_RUBBER,
                eraser_button.mt_tool_for_pen_slot(true, MT_TOOL_PEN))
        end)

        it("MT_TOOL_PEN while not held maps to BTN_TOOL_PEN", function()
            assert.equals(BTN_TOOL_PEN,
                eraser_button.mt_tool_for_pen_slot(false, MT_TOOL_PEN))
        end)

        it("a non-MT_TOOL_PEN value returns nil (not this function's concern)", function()
            assert.is_nil(eraser_button.mt_tool_for_pen_slot(true, MT_TOOL_ERASER))
        end)

    end)

end)
