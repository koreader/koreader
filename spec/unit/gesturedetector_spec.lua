describe("gesturedetector module", function()
    local GestureDetector, time
    setup(function()
        require("commonrequire")
        GestureDetector = require("device/gesturedetector")
        time = require("ui/time")
    end)

    local function feedConcurrentTaps(allow_concurrent_taps)
        local input = {
            main_finger_slot = 0,
            disable_double_tap = true,
            allow_concurrent_taps = allow_concurrent_taps,
            tap_interval_override = nil,
            setTimeout = function() end,
            clearTimeout = function() end,
        }
        local gesture_detector = GestureDetector:new{
            input = input,
            screen = {
                scaleByDPI = function(_, value) return value end,
            },
            active_contacts = {},
            contact_count = 0,
            previous_tap = {},
            clock_id = 0,
        }
        local slot0 = {
            slot = 0,
            id = 1,
            x = 10,
            y = 20,
            timev = time.s(1),
        }
        local slot1 = {
            slot = 1,
            id = 2,
            x = 80,
            y = 20,
            timev = time.s(1) + time.ms(10),
        }

        gesture_detector:feedEvent{slot0, slot1}
        slot0.id = -1
        slot0.timev = time.s(1) + time.ms(20)
        local first_lift_gestures = gesture_detector:feedEvent{slot0}

        slot1.id = -1
        slot1.timev = time.s(1) + time.ms(30)
        local second_lift_gestures = gesture_detector:feedEvent{slot1}

        return first_lift_gestures, second_lift_gestures
    end

    describe("concurrent taps", function()
        it("should combine concurrent contacts by default", function()
            local first_lift_gestures, second_lift_gestures = feedConcurrentTaps(false)

            assert.are.equal(1, #first_lift_gestures)
            assert.are.equal("two_finger_tap", first_lift_gestures[1].ges)
            assert.are.equal(0, #second_lift_gestures)
        end)

        it("should keep concurrent contacts independent when requested", function()
            local first_lift_gestures, second_lift_gestures = feedConcurrentTaps(true)

            assert.are.equal(1, #first_lift_gestures)
            assert.are.equal("tap", first_lift_gestures[1].ges)
            assert.are.equal(10, first_lift_gestures[1].pos.x)
            assert.are.equal(1, #second_lift_gestures)
            assert.are.equal("tap", second_lift_gestures[1].ges)
            assert.are.equal(80, second_lift_gestures[1].pos.x)
        end)
    end)

    describe("adjustGesCoordinate", function()
        local function adjustTest(ges_type, direction, rotation_mode)
            local ges = {
                ges = ges_type,
                direction = direction,
                multiswipe_directions = direction,
            }
            GestureDetector.screen = {
                                        DEVICE_ROTATED_UPRIGHT = 0,
                                        DEVICE_ROTATED_CLOCKWISE = 1,
                                        DEVICE_ROTATED_UPSIDE_DOWN = 2,
                                        DEVICE_ROTATED_COUNTER_CLOCKWISE = 3,
                                     }
            GestureDetector.screen.getTouchRotation = function() return rotation_mode end
            GestureDetector.screen.getHeight = function() return 800 end
            GestureDetector.screen.getWidth = function() return 600 end

            return GestureDetector:adjustGesCoordinate(ges).direction
        end

        it("should not translate rotation 0", function()
            assert.are.equal("north", adjustTest("swipe", "north", 0))
            assert.are.equal("north", adjustTest("multiswipe", "north", 0))
            assert.are.equal("north", adjustTest("pan", "north", 0))
            assert.are.equal("north", adjustTest("two_finger_swipe", "north", 0))
            assert.are.equal("north", adjustTest("two_finger_pan", "north", 0))
        end)
        it("should translate rotation 270", function()
            assert.are.equal("west", adjustTest("swipe", "north", 3))
            assert.are.equal("west", adjustTest("multiswipe", "north", 3))
            assert.are.equal("west", adjustTest("pan", "north", 3))
            assert.are.equal("west", adjustTest("two_finger_swipe", "north", 3))
            assert.are.equal("west", adjustTest("two_finger_pan", "north", 3))
        end)
        it("should translate rotation 180", function()
            assert.are.equal("south", adjustTest("swipe", "north", 2))
            assert.are.equal("south", adjustTest("multiswipe", "north", 2))
            assert.are.equal("south", adjustTest("pan", "north", 2))
            assert.are.equal("south", adjustTest("two_finger_swipe", "north", 2))
            assert.are.equal("south", adjustTest("two_finger_pan", "north", 2))
        end)
        it("should translate rotation 90", function()
            assert.are.equal("east", adjustTest("swipe", "north", 1))
            assert.are.equal("east", adjustTest("multiswipe", "north", 1))
            assert.are.equal("east", adjustTest("pan", "north", 1))
            assert.are.equal("east", adjustTest("two_finger_swipe", "north", 1))
            assert.are.equal("east", adjustTest("two_finger_pan", "north", 1))
        end)
    end)
end)
