describe("AutoFrontlight widget tests", function()
    local Device, PowerD, MockTime, class, AutoFrontlight, UIManager

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))

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
        require("document/canvascontext"):init(require("device"))
    end)

    before_each(function()
        Device = require("device")
        Device.isKindle = function() return true end
        Device.model = "KindleVoyage"
        Device.brightness = 0
        Device.hasFrontlight = function() return true end
        Device.hasLightSensor = function() return true end
        Device.powerd = PowerD:new{
            device = Device,
        }
        Device.ambientBrightnessLevel = function(self)
            return self.brightness
        end
        Device.input.waitEvent = function() end
        require("luasettings"):
            open(require("datastorage"):getSettingsDir() .. "/autofrontlight.lua"):
            saveSetting("enable", true):
            close()

        UIManager = require("ui/uimanager")
        UIManager:setRunForeverMode()

        requireBackgroundRunner()
        class = dofile("plugins/autofrontlight.koplugin/main.lua")
        notifyBackgroundJobsUpdated()

        -- Ensure the background runner has succeeded set the job.insert_sec.
        MockTime:increase(2)
        UIManager:handleInput()
    end)

    after_each(function()
        AutoFrontlight:deprecateLastTask()
        -- Ensure the scheduled task from this test case won't impact others.
        MockTime:increase(2)
        UIManager:handleInput()
        AutoFrontlight = nil
        stopBackgroundRunner()
    end)

    it("should automatically turn on or off frontlight", function()
        AutoFrontlight = class:new()
        Device.brightness = 3
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
        Device.brightness = 0
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
        Device.brightness = 1
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
        Device.brightness = 2
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
        Device.brightness = 3
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
        Device.brightness = 4
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
        Device.brightness = 3
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
        Device.brightness = 2
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
        Device.brightness = 1
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
        Device.brightness = 0
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
    end)

    it("should turn on frontlight at the beginning", function()
        Device:getPowerDevice():turnOffFrontlight()
        Device.brightness = 0
        AutoFrontlight = class:new()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
    end)

    it("should turn off frontlight at the beginning", function()
        Device:getPowerDevice():turnOnFrontlight()
        Device.brightness = 3
        AutoFrontlight = class:new()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
    end)

    it("should handle configuration update", function()
        Device:getPowerDevice():turnOffFrontlight()
        Device.brightness = 0
        AutoFrontlight = class:new()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
        AutoFrontlight:flipSetting()
        Device.brightness = 3
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
    end)
end)
