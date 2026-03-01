describe("input module", function()
    local Input
    local ffi, C
    setup(function()
        require("commonrequire")
        ffi = require("ffi")
        C = ffi.C
        require("ffi/linux_input_h")
        Input = require("device").input
    end)

    describe("stylus callback", function()
        after_each(function()
            -- Clean up after each test
            Input:unregisterStylusCallback()
            Input.MTSlots = {}
        end)

        describe("registerStylusCallback", function()
            it("should register a callback function", function()
                local callback = function() end
                Input:registerStylusCallback(callback)
                assert.is_equal(callback, Input.stylus_callback)
            end)

            it("should replace existing callback when registering new one", function()
                local callback1 = function() return "first" end
                local callback2 = function() return "second" end
                Input:registerStylusCallback(callback1)
                Input:registerStylusCallback(callback2)
                assert.is_equal(callback2, Input.stylus_callback)
            end)
        end)

        describe("unregisterStylusCallback", function()
            it("should remove the registered callback", function()
                local callback = function() end
                Input:registerStylusCallback(callback)
                assert.is_not_nil(Input.stylus_callback)
                Input:unregisterStylusCallback()
                assert.is_nil(Input.stylus_callback)
            end)

            it("should handle unregister when no callback registered", function()
                Input.stylus_callback = nil
                -- Should not error
                Input:unregisterStylusCallback()
                assert.is_nil(Input.stylus_callback)
            end)
        end)

        describe("routeStylusEvents", function()
            it("should do nothing when no callback registered", function()
                Input.stylus_callback = nil
                Input.MTSlots = {
                    { slot = 0, id = 1, x = 100, y = 200, tool = Input.TOOL_TYPE_PEN },
                }
                Input:routeStylusEvents()
                -- Slots should be unchanged
                assert.is_equal(1, #Input.MTSlots)
            end)

            it("should do nothing when MTSlots is empty", function()
                local called = false
                Input:registerStylusCallback(function() called = true end)
                Input.MTSlots = {}
                Input:routeStylusEvents()
                assert.is_false(called)
            end)

            it("should call callback for pen tool type", function()
                local received_slot = nil
                Input:registerStylusCallback(function(input, slot)
                    received_slot = slot
                    return false
                end)
                Input.MTSlots = {
                    { slot = 0, id = 1, x = 100, y = 200, tool = Input.TOOL_TYPE_PEN },
                }
                Input:routeStylusEvents()
                assert.is_not_nil(received_slot)
                assert.is_equal(100, received_slot.x)
                assert.is_equal(200, received_slot.y)
                assert.is_equal(Input.TOOL_TYPE_PEN, received_slot.tool)
            end)

            it("should call callback for pen_slot match", function()
                local received_slot = nil
                Input.pen_slot = 1
                Input:registerStylusCallback(function(input, slot)
                    received_slot = slot
                    return false
                end)
                Input.MTSlots = {
                    { slot = 1, id = 1, x = 150, y = 250, tool = Input.TOOL_TYPE_FINGER },
                }
                Input:routeStylusEvents()
                assert.is_not_nil(received_slot)
                assert.is_equal(150, received_slot.x)
                assert.is_equal(1, received_slot.slot)
            end)

            it("should not call callback for finger events", function()
                local called = false
                Input.pen_slot = nil
                Input:registerStylusCallback(function()
                    called = true
                    return false
                end)
                Input.MTSlots = {
                    { slot = 0, id = 1, x = 100, y = 200, tool = Input.TOOL_TYPE_FINGER },
                }
                Input:routeStylusEvents()
                assert.is_false(called)
            end)

            it("should remove dominated slots from MTSlots", function()
                Input:registerStylusCallback(function()
                    return true  -- dominate
                end)
                Input.MTSlots = {
                    { slot = 0, id = 1, x = 100, y = 200, tool = Input.TOOL_TYPE_PEN },
                }
                assert.is_equal(1, #Input.MTSlots)
                Input:routeStylusEvents()
                assert.is_equal(0, #Input.MTSlots)
            end)

            it("should keep non-dominated slots in MTSlots", function()
                Input:registerStylusCallback(function()
                    return false  -- don't dominate
                end)
                Input.MTSlots = {
                    { slot = 0, id = 1, x = 100, y = 200, tool = Input.TOOL_TYPE_PEN },
                }
                Input:routeStylusEvents()
                assert.is_equal(1, #Input.MTSlots)
            end)

            it("should handle mixed stylus and finger events", function()
                local stylus_count = 0
                Input:registerStylusCallback(function()
                    stylus_count = stylus_count + 1
                    return true  -- dominate stylus events
                end)
                Input.MTSlots = {
                    { slot = 0, id = 1, x = 100, y = 200, tool = Input.TOOL_TYPE_FINGER },
                    { slot = 1, id = 2, x = 150, y = 250, tool = Input.TOOL_TYPE_PEN },
                    { slot = 2, id = 3, x = 200, y = 300, tool = Input.TOOL_TYPE_FINGER },
                }
                Input:routeStylusEvents()
                -- Only pen event should trigger callback
                assert.is_equal(1, stylus_count)
                -- Pen slot should be removed, finger slots remain
                assert.is_equal(2, #Input.MTSlots)
                assert.is_equal(Input.TOOL_TYPE_FINGER, Input.MTSlots[1].tool)
                assert.is_equal(Input.TOOL_TYPE_FINGER, Input.MTSlots[2].tool)
            end)
        end)

        describe("tool type constants", function()
            it("should export TOOL_TYPE_FINGER", function()
                assert.is_equal(0, Input.TOOL_TYPE_FINGER)
            end)

            it("should export TOOL_TYPE_PEN", function()
                assert.is_equal(1, Input.TOOL_TYPE_PEN)
            end)
        end)
    end)

    describe("handleTouchEvPhoenix", function()
--[[
-- a touch looks something like this (from H2Ov1)
Event: time 1510346968.993890, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346968.994362, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346968.994384, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346968.994399, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1012
Event: time 1510346968.994409, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 914
Event: time 1510346968.994420, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346968.994429, -------------- SYN_REPORT ------------
Event: time 1510346969.057898, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.058251, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346969.058417, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346969.058436, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1012
Event: time 1510346969.058446, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 915
Event: time 1510346969.058456, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.058464, -------------- SYN_REPORT ------------
Event: time 1510346969.066903, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.067102, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346969.067260, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346969.067415, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1010
Event: time 1510346969.067433, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 918
Event: time 1510346969.067443, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.067451, -------------- SYN_REPORT ------------
Event: time 1510346969.076230, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.076549, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 0
Event: time 1510346969.076714, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 0
Event: time 1510346969.076869, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1010
Event: time 1510346969.076887, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 918
Event: time 1510346969.076898, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.076908, -------------- SYN_REPORT ------------
]]
        it("should set cur_slot correctly", function()
            local ev
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TRACKING_ID,
                value = 1,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TOUCH_MAJOR,
                value = 1,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_WIDTH_MAJOR,
                value = 1,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_X,
                value = 1012,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_Y,
                value = 914,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)

            -- EV_SYN
            -- depends on gesture_detector
            --[[
            ev = {
                type = C.EV_SYN,
                code = C.SYN_REPORT,
                value = 0,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ]]

            -- this value=2 stuff doesn't happen IRL, just testing logic
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TRACKING_ID,
                value = 2,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TOUCH_MAJOR,
                value = 2,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_WIDTH_MAJOR,
                value = 2,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_X,
                value = 1012,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_Y,
                value = 914,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
        end)
    end)

end)
