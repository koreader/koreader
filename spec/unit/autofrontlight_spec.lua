describe("AutoFrontlight widget tests", function()
    local Device, PowerD, MockTime

    setup(function()
        require("commonrequire")
        package.unloadAll()

        MockTime = require("mock_time")
        MockTime:install()

        PowerD = require("device/generic/powerd"):new{
            frontlight = 0,
        }
        PowerD.frontlightIntensityHW = function()
            return 2
        end
        PowerD.setIntensityHW = function(self, intensity)
            self.frontlight = intensity
        end
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
    end)

    before_each(function()
        Device = require("device")
        Device.isKindle = function() return true end
        Device.model = "KindleVoyage"
        Device.brightness = 0
        Device.hasFrontlight = function() return true end
        Device.powerd = PowerD:new{
            device = Device,
        }
        Device.ambientBrightnessLevel = function(self)
            return self.brightness
        end
        Device.input.waitEvent = function() end
    end)

    it("should automatically turn on or off frontlight", function()
        local UIManager = require("ui/uimanager")
        UIManager._run_forever = true
        local class = dofile("plugins/autofrontlight.koplugin/main.lua")
        local AutoFrontlight = class:new()
        AutoFrontlight:init()
        Device.brightness = 3
        MockTime:increase(1)
        UIManager:handleInput()
        assert.are.equal(Device:getPowerDevice().frontlight, 0)
        Device.brightness = 0
        MockTime:increase(1)
        UIManager:handleInput()
        assert.are.equal(Device:getPowerDevice().frontlight, 2)
        Device.brightness = 1
        MockTime:increase(1)
        UIManager:handleInput()
        assert.are.equal(Device:getPowerDevice().frontlight, 2)
        Device.brightness = 2
        MockTime:increase(1)
        UIManager:handleInput()
        assert.are.equal(Device:getPowerDevice().frontlight, 0)
        Device.brightness = 3
        MockTime:increase(1)
        UIManager:handleInput()
        assert.are.equal(Device:getPowerDevice().frontlight, 0)
    end)
end)
