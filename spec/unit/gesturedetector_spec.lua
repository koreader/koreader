describe("gesturedetector module", function()
    local GestureDetector
    setup(function()
        require("commonrequire")
        GestureDetector = require("device/gesturedetector")
    end)

    describe("adjustGesCoordinate", function()
        local function adjustTest(ges_type, direction, rotation_mode)
            local ges = {
                ges = ges_type,
                direction = direction,
                multiswipe_directions = direction,
            }
            GestureDetector.screen = {
                                        ORIENTATION_PORTRAIT = 0,
                                        ORIENTATION_LANDSCAPE = 1,
                                        ORIENTATION_PORTRAIT_ROTATED = 2,
                                        ORIENTATION_LANDSCAPE_ROTATED = 3,
                                     }
            GestureDetector.screen.cur_rotation_mode = rotation_mode

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
