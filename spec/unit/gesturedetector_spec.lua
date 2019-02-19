describe("gesturedetector module", function()
    local GestureDetector
    setup(function()
        require("commonrequire")
        GestureDetector = require("device/gesturedetector")
    end)

    describe("adjustGesCoordinate", function()
        it("should not translate rotation 0", function()
            local ges = {
                ges = "swipe",
                direction = "north",
            }
            GestureDetector.screen = {}
            GestureDetector.screen.cur_rotation_mode = 0
            assert.is_equal("north", GestureDetector:adjustGesCoordinate(ges).direction)

            ges.ges = ""
        end)
        it("should translate rotation 90", function()
            local ges = {
                ges = "swipe",
                direction = "north",
            }
            GestureDetector.screen = {}
            GestureDetector.screen.cur_rotation_mode = 3
            assert.is_equal("west", GestureDetector:adjustGesCoordinate(ges).direction)
        end)
        it("should translate rotation 180", function()
            local ges = {
                ges = "swipe",
                direction = "north",
            }
            GestureDetector.screen = {}
            GestureDetector.screen.cur_rotation_mode = 2
            assert.is_equal("south", GestureDetector:adjustGesCoordinate(ges).direction)
        end)
        it("should translate rotation 270", function()
            local ges = {
                ges = "swipe",
                direction = "north",
            }
            GestureDetector.screen = {}
            GestureDetector.screen.cur_rotation_mode = 1
            assert.is_equal("east", GestureDetector:adjustGesCoordinate(ges).direction)
        end)
    end)
end)
