describe("Frontlight function in PowerD", function()
    local Device, PowerD
    local param, test_when_on, test_when_off
    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))

        PowerD = require("device/generic/powerd"):new{
            frontlight = 2,
        }

        param = {
            fl_min = 1,
            fl_max = 5,
            fl_intensity = 2,
            device = nil,
            is_fl_on = true,
        }

        PowerD.frontlightIntensityHW = function(self)
            return self.frontlight
        end
        PowerD.setIntensityHW = function(self, intensity)
            self.frontlight = intensity
            self:_decideFrontlightState()
        end
    end)

    teardown(function()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    before_each(function()
        Device = require("device")
        Device.isKobo = function() return true end
        Device.model = "Kobo_dahlia"
        Device.hasFrontlight = function() return true end
        param.device = Device
        Device.powerd = PowerD:new{
            param
        }


        stub(PowerD, "init")
        spy.on(PowerD, "frontlightIntensityHW")
        spy.on(PowerD, "setIntensityHW")
        spy.on(PowerD, "turnOnFrontlightHW")
        spy.on(PowerD, "turnOffFrontlightHW")
    end)

    it("should read frontlight intensity during initialization", function()
        local p = PowerD:new(param)
        assert.are.equal(2, p:frontlightIntensityHW())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.init).is_called(1)
        assert.spy(p.frontlightIntensityHW).is_called(2)
    end)

    test_when_off = function(fl_min)
        param.fl_min = fl_min
        param.fl_intensity = 0
        local p = PowerD:new(param)
        p:setIntensity(0)
        assert.are.equal(param.fl_min, p:frontlightIntensityHW())
        assert.are.equal(0, p:frontlightIntensity()) -- returns 0 when off
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.init).is_called(1)
        assert.spy(p.setIntensityHW).is_called(1)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.frontlightIntensityHW).is_called(2)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        -- The intensity is param.fl_min, turnOnFrontlight() should take no effect.
        assert.is.falsy(p:turnOnFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.spy(p.setIntensityHW).is_called(1)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        -- Same as the above one, toggleFrontlight() should also take no effect.
        assert.is.falsy(p:toggleFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.spy(p.setIntensityHW).is_called(1)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.truthy(p:setIntensity(2))
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.spy(p.setIntensityHW).is_called(2)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.falsy(p:turnOnFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.spy(p.setIntensityHW).is_called(2)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.truthy(p:turnOffFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.spy(p.setIntensityHW).is_called(3)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:turnOnFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.spy(p.setIntensityHW).is_called(4)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.spy(p.setIntensityHW).is_called(5)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(2)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.spy(p.setIntensityHW).is_called(6)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(2)
        assert.spy(p.turnOffFrontlightHW).is_called(2)
    end

    test_when_on = function(fl_min)
        assert(fl_min < 2)
        param.fl_min = fl_min
        param.fl_intensity = 2
        local p = PowerD:new(param)
        p:setIntensity(2)
        assert.are.equal(2, p:frontlightIntensityHW())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.init).is_called(1)
        --assert.spy(p.setIntensityHW).is_called(1)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.falsy(p:setIntensity(2))
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        --assert.spy(p.setIntensityHW).is_called(1)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.falsy(p:turnOnFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        --assert.spy(p.setIntensityHW).is_called(1)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.truthy(p:turnOffFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        --assert.spy(p.setIntensityHW).is_called(2)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        --assert.spy(p.setIntensityHW).is_called(3)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        --assert.spy(p.setIntensityHW).is_called(4)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(2)
    end

    it("should turn on and off frontlight when the frontlight was off", function()
        test_when_off(0)
    end)

    it("should turn on and off frontlight when the minimum level is 1 and frontlight was off",
       function() test_when_off(1) end)

    it("should turn on and off frontlight when the frontlight was on", function()
        test_when_on(0)
    end)

    it("should turn on and off frontlight when the minimum level is 1 and frontlight was on",
       function() test_when_on(1) end)
end)
