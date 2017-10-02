describe("ProgressWidget widget", function()
    local ProgressWidget, Screen
    setup(function()
        require("commonrequire")
        ProgressWidget = require("ui/widget/progresswidget")
        Screen = require("device").screen
    end)

    it("should not crash with nil self.last", function()
        local progress = ProgressWidget:new{
            width = Screen:scaleBySize(100),
            height = Screen:scaleBySize(50),
            percentage = 5/100,
            ticks = {1},
        }
        progress:paintTo(Screen.bb, 0, 0)
    end)
end)
