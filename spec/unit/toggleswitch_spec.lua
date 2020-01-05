describe("ToggleSwitch module", function()
    local ToggleSwitch
    setup(function()
        require("commonrequire")
        ToggleSwitch = require("ui/widget/toggleswitch")
    end)

    it("should toggle without args", function()
        local config = {
            onConfigChoose = function() end,
        }

        local switch = ToggleSwitch:new{
            event = "ChangeSpec",
            default_value = 2,
            toggle = { "Finished", "Reading", "On hold" },
            values = { 1, 2, 3 },
            name = "spec_status",
            alternate = false,
            enabled = true,
            config = config,
        }
        switch:togglePosition(1, true)
        switch:onTapSelect(3)
    end)
end)
