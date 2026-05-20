--[[--
spec/palmreject_spec.lua — unit tests for lib/palmreject.lua
Run: busted spec/palmreject_spec.lua   (from plugin root)
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local PalmReject = require("lib/palmreject")

-- Injectable clock: a table holding a mutable "now" value in ms.
-- Pass clock.fn to PalmReject.new(); advance with clock.advance(delta_ms).
local function make_clock(start_ms)
    local t = {now = start_ms or 0}
    t.fn = function() return t.now end
    t.advance = function(delta) t.now = t.now + delta end
    return t
end

-- Helper: touch-down event
local function touch_down(slot, id, x, y, major)
    return {type="down", slot=slot, id=id, x=x, y=y, touch_major=major or 20}
end
local function touch_move(slot, id, x, y)
    return {type="move", slot=slot, id=id, x=x, y=y}
end
local function touch_up(slot, id)
    return {type="up", slot=slot, id=id}
end

describe("PalmReject", function()

    -- ── Initial state ────────────────────────────────────────────────────────

    describe("initial state", function()
        it("pen is not proximate on creation", function()
            local pr = PalmReject.new()
            assert.is_false(pr:isPenProximate())
        end)

        it("touch events pass through when pen is not proximate", function()
            local pr = PalmReject.new()
            local ev = touch_down(0, 1, 100, 200)
            assert.is_not_nil(pr:onTouchEvent(ev))
        end)
    end)

    -- ── Pen proximity gate ───────────────────────────────────────────────────

    describe("pen proximity gate", function()
        it("pen 'down' makes pen proximate", function()
            local pr = PalmReject.new()
            pr:onPenEvent({type="down", x=0, y=0, pressure=100, tool="pen"})
            assert.is_true(pr:isPenProximate())
        end)

        it("pen 'hover' makes pen proximate", function()
            local pr = PalmReject.new()
            pr:onPenEvent({type="hover", x=0, y=0})
            assert.is_true(pr:isPenProximate())
        end)

        it("touch is rejected while pen is down", function()
            local pr = PalmReject.new()
            pr:onPenEvent({type="down", x=0, y=0, pressure=100, tool="pen"})
            local result = pr:onTouchEvent(touch_down(0, 1, 50, 50))
            assert.is_nil(result)
        end)

        it("rejected slot's move events are also rejected", function()
            local pr = PalmReject.new()
            pr:onPenEvent({type="down", x=0, y=0, pressure=100, tool="pen"})
            pr:onTouchEvent(touch_down(0, 1, 50, 50))  -- rejected
            local result = pr:onTouchEvent(touch_move(0, 1, 55, 55))
            assert.is_nil(result)
        end)

        it("rejected slot's up event is also rejected", function()
            local pr = PalmReject.new()
            pr:onPenEvent({type="down", x=0, y=0, pressure=100, tool="pen"})
            pr:onTouchEvent(touch_down(0, 1, 50, 50))
            local result = pr:onTouchEvent(touch_up(0, 1))
            assert.is_nil(result)
        end)

        it("touch passes after pen up + blackout elapsed", function()
            local clock = make_clock(0)
            local pr    = PalmReject.new({blackout_ms = 200}, clock.fn)

            pr:onPenEvent({type="down"})
            pr:onPenEvent({type="up"})
            clock.advance(250)  -- past the 200 ms blackout

            local result = pr:onTouchEvent(touch_down(0, 1, 50, 50))
            assert.is_not_nil(result)
        end)

        it("touch is rejected during blackout window", function()
            local clock = make_clock(0)
            local pr    = PalmReject.new({blackout_ms = 200}, clock.fn)

            pr:onPenEvent({type="down"})
            pr:onPenEvent({type="up"})
            clock.advance(100)  -- still within 200 ms blackout

            local result = pr:onTouchEvent(touch_down(0, 1, 50, 50))
            assert.is_nil(result)
        end)

        it("pen is not proximate exactly at blackout boundary", function()
            local clock = make_clock(0)
            local pr    = PalmReject.new({blackout_ms = 200}, clock.fn)

            pr:onPenEvent({type="down"})
            pr:onPenEvent({type="up"})
            clock.advance(200)  -- exactly at boundary — not proximate
            assert.is_false(pr:isPenProximate())
        end)

        it("new pen down resets the blackout timer", function()
            local clock = make_clock(0)
            local pr    = PalmReject.new({blackout_ms = 200}, clock.fn)

            pr:onPenEvent({type="down"})
            pr:onPenEvent({type="up"})
            clock.advance(100)
            -- Pen comes back down before blackout clears
            pr:onPenEvent({type="down"})
            assert.is_true(pr:isPenProximate())
            -- _pen_up_at should be nil now (not in blackout, actively down)
            assert.is_nil(pr._pen_up_at)
        end)
    end)

    -- ── Area threshold gate ──────────────────────────────────────────────────

    describe("area gate", function()
        it("large contact is rejected when area_threshold is set", function()
            local pr = PalmReject.new({area_threshold = 100})
            local ev = touch_down(0, 1, 50, 50, 150)  -- touch_major=150 > 100
            assert.is_nil(pr:onTouchEvent(ev))
        end)

        it("small contact passes when area_threshold is set", function()
            local pr = PalmReject.new({area_threshold = 100})
            local ev = touch_down(0, 1, 50, 50, 30)   -- touch_major=30 < 100
            assert.is_not_nil(pr:onTouchEvent(ev))
        end)

        it("area gate is disabled when area_threshold is 0", function()
            local pr = PalmReject.new({area_threshold = 0})
            local ev = touch_down(0, 1, 50, 50, 9999)
            assert.is_not_nil(pr:onTouchEvent(ev))
        end)

        it("area gate rejects even when pen is not proximate", function()
            local pr = PalmReject.new({area_threshold = 50})
            -- No pen events at all
            local ev = touch_down(0, 1, 50, 50, 200)
            assert.is_nil(pr:onTouchEvent(ev))
        end)
    end)

    -- ── Multi-slot isolation ─────────────────────────────────────────────────

    describe("multi-slot", function()
        it("each slot is tracked independently", function()
            local pr = PalmReject.new()
            pr:onPenEvent({type="down"})  -- pen proximate

            -- Slot 0 arrives while pen proximate → rejected
            pr:onTouchEvent(touch_down(0, 10, 50, 50))

            pr:onPenEvent({type="up"})
            -- Use a zero-ms blackout for simplicity
            local clock = make_clock(1000)
            pr = PalmReject.new({blackout_ms = 0}, clock.fn)

            -- Slot 1 arrives when pen is not proximate → passes
            local result = pr:onTouchEvent(touch_down(1, 20, 100, 100))
            assert.is_not_nil(result)
        end)

        it("slot state is cleared on up event", function()
            local clock = make_clock(0)
            local pr    = PalmReject.new({blackout_ms = 0}, clock.fn)

            -- slot 0 passes
            pr:onTouchEvent(touch_down(0, 1, 50, 50))
            pr:onTouchEvent(touch_up(0, 1))

            -- slot 0 is gone — re-use same slot number, passes again
            local result = pr:onTouchEvent(touch_down(0, 2, 60, 60))
            assert.is_not_nil(result)
        end)
    end)

    -- ── Pass-through when not rejected ──────────────────────────────────────

    describe("pass-through", function()
        it("returns the event unchanged when passing", function()
            local pr = PalmReject.new()
            local ev = touch_down(0, 1, 42, 84, 10)
            local result = pr:onTouchEvent(ev)
            assert.equals(ev, result)  -- same table reference
        end)

        it("move event passes when slot was not rejected", function()
            local pr = PalmReject.new()
            pr:onTouchEvent(touch_down(0, 1, 50, 50))
            local result = pr:onTouchEvent(touch_move(0, 1, 55, 55))
            assert.is_not_nil(result)
        end)

        it("up event passes when slot was not rejected", function()
            local pr = PalmReject.new()
            pr:onTouchEvent(touch_down(0, 1, 50, 50))
            local result = pr:onTouchEvent(touch_up(0, 1))
            assert.is_not_nil(result)
        end)
    end)

end)
