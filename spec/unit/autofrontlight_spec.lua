describe("AutoFrontlight widget tests", function()
    local Device, PowerD, MockTime, AutoFrontlight

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
        require("luasettings"):
            open(require("datastorage"):getSettingsDir() .. "/autofrontlight.lua"):
            saveSetting("enable", "true"):
            close()
        require("ui/uimanager")._run_forever = true
    end)

    after_each(function()
        AutoFrontlight:deprecateLastTask()
        -- Ensure the scheduled task from this test case won't impact others.
        MockTime:increase(2)
        require("ui/uimanager"):handleInput()
        AutoFrontlight = nil
    end)

    it("should automatically turn on or off frontlight", function()
        local UIManager = require("ui/uimanager")
        local class = dofile("plugins/autofrontlight.koplugin/main.lua")
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

    it("should turn on frontlight at the begining", function()
        local UIManager = require("ui/uimanager")
        local class = dofile("plugins/autofrontlight.koplugin/main.lua")
        Device.brightness = 0
        AutoFrontlight = class:new()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, Device:getPowerDevice().frontlight)
    end)

    it("should turn off frontlight at the begining", function()
        local UIManager = require("ui/uimanager")
        local class = dofile("plugins/autofrontlight.koplugin/main.lua")
        Device.brightness = 3
        AutoFrontlight = class:new()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(0, Device:getPowerDevice().frontlight)
    end)

    it("should handle configuration update", function()
        local UIManager = require("ui/uimanager")
        local class = dofile("plugins/autofrontlight.koplugin/main.lua")
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
