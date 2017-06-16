describe("AutoFrontlight widget tests", function()
    local Device, MockTime

    setup(function()
        require("commonrequire")
        package.unloadAll()

        Device = require("device/generic/device"):new()
        Device.brightness = 0
        Device.hasFrontlight = function() return true end
        Device.powerd = require("device/generic/powerd"):new{
            frontlight = 0,
        }
        Device.powerd.frontlightIntensityHW = function()
            return 2
        end
        Device.powerd.setIntensityHW = function(self, intensity)
            self.frontlight = intensity
        end
        Device.ambientBrightnessLevel = function(self)
            return self.brightness
        end

        MockTime = require("mock_time")
        MockTime:install()
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
    end)

    it("should automatically turn on or off frontlight", function()
        local UIManager = require("ui/uimanager")
        Device.brightness = 0
        MockTime:increase(2)
        assert.are.equal(Device:getPowerDevice().frontlight, 2)
        Device.brightness = 1
        MockTime:increase(2)
        assert.are.equal(Device:getPowerDevice().frontlight, 2)
        Device.brightness = 2
        MockTime:increase(2)
        assert.are.equal(Device:getPowerDevice().frontlight, 0)
        Device.brightness = 3
        MockTime:increase(2)
        assert.are.equal(Device:getPowerDevice().frontlight, 0)
    end)
end)
