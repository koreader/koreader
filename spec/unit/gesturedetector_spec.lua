describe("gesturedetector module", function()
    local GestureDetector, util
    setup(function()
        require("commonrequire")
        GestureDetector = require("device/gesturedetector")
        util = require("util")
    end)

    it("should translate on rotation", function()
        local ges = {
            ges = "swipe",
            direction = "north",
        }
        GestureDetector.screen = {}
        GestureDetector.screen.cur_rotation_mode = 1
        assert.is_true(util.tableEquals({
            ges = "swipe",
            direction = "east",
        }, GestureDetector:adjustGesCoordinate(ges)))
    end)

end)
