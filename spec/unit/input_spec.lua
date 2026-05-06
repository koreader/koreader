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

    describe("stylus callback routing", function()
        it("routes stylus slots before gesture detection and removes dominated slots", function()
            local old_callback = Input.stylus_callback
            local old_slots = Input.MTSlots

            local calls = {}
            Input.MTSlots = {
                { slot = Input.pen_slot, id = 7, x = 10, y = 20, tool = Input.TOOL_TYPE_PEN },
                { slot = Input.main_finger_slot, id = 8, x = 30, y = 40, tool = Input.TOOL_TYPE_FINGER },
            }

            Input:registerStylusCallback(function(_, slot)
                table.insert(calls, slot)
                return true
            end)

            Input:routeStylusEvents()

            assert.is_equal(1, #calls)
            assert.is_equal(Input.pen_slot, calls[1].slot)
            assert.is_equal(1, #Input.MTSlots)
            assert.is_equal(Input.main_finger_slot, Input.MTSlots[1].slot)

            Input.stylus_callback = old_callback
            Input.MTSlots = old_slots
        end)

        it("does not turn SDL pen side buttons into eraser tool selectors", function()
            local old_device = Input.device
            local old_event_map = Input.event_map
            local old_eraser_active = Input.stylus_eraser_active

            Input.device = { isSDL = function() return true end }
            Input.event_map = {}
            Input.stylus_eraser_active = nil

            Input:handleKeyBoardEv({
                type = C.EV_KEY,
                code = C.BTN_STYLUS,
                value = 1,
            })

            assert.is_nil(Input.stylus_eraser_active)

            Input.device = old_device
            Input.event_map = old_event_map
            Input.stylus_eraser_active = old_eraser_active
        end)
    end)

end)
