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

end)
