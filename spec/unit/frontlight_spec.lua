describe("Frontlight function in PowerD", function()
    local PowerD
    local param, test_when_on, test_when_off
    setup(function()
        require("commonrequire")

        PowerD = require("device/generic/powerd"):new{
            frontlight = 0,
        }

        param = {
            fl_min = 1,
            fl_max = 5,
            device = {
                hasFrontlight = function() return true end,
                -- TODO @Frenzie remove this once possibly turning on frontlight
                -- on init is Kobo-only; see device/generic/powerd 2017-10-08
                isAndroid = function() return false end,
            },
        }
    end)

    before_each(function()
        stub(PowerD, "init")
        stub(PowerD, "frontlightIntensityHW")
        stub(PowerD, "setIntensityHW")
        PowerD.setIntensityHW = function(self, intensity)
            self.frontlight = intensity
        end
        spy.on(PowerD, "setIntensityHW")
        spy.on(PowerD, "turnOnFrontlightHW")
        spy.on(PowerD, "turnOffFrontlightHW")
    end)

    it("should read frontlight intensity during initialization", function()
        PowerD.frontlightIntensityHW.returns(2)
        local p = PowerD:new(param)
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.init).is_called(1)
        assert.stub(p.frontlightIntensityHW).is_called(1)
    end)

    test_when_off = function(fl_min)
        param.fl_min = fl_min
        PowerD.frontlightIntensityHW.returns(fl_min)
        local p = PowerD:new(param)
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.init).is_called(1)
        assert.stub(p.setIntensityHW).is_called(1)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.stub(p.frontlightIntensityHW).is_called(1)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        -- The intensity is param.fl_min, turnOnFrontlight() should take no effect.
        assert.is.falsy(p:turnOnFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.setIntensityHW).is_called(1)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        -- Same as the above one, toggleFrontlight() should also take no effect.
        assert.is.falsy(p:toggleFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.setIntensityHW).is_called(1)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:setIntensity(2))
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(2)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.falsy(p:turnOnFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(2)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:turnOffFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.setIntensityHW).is_called(3)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(0)
        assert.spy(p.turnOffFrontlightHW).is_called(2)

        assert.is.truthy(p:turnOnFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(4)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(2)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.setIntensityHW).is_called(5)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(3)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(6)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(2)
        assert.spy(p.turnOffFrontlightHW).is_called(3)
    end

    test_when_on = function(fl_min)
        assert(fl_min < 2)
        param.fl_min = fl_min
        PowerD.frontlightIntensityHW.returns(2)
        local p = PowerD:new(param)
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.init).is_called(1)
        assert.stub(p.setIntensityHW).is_called(1)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.falsy(p:setIntensity(2))
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(1)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.falsy(p:turnOnFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(1)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(0)

        assert.is.truthy(p:turnOffFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.setIntensityHW).is_called(2)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(1)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(2, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOn())
        assert.stub(p.setIntensityHW).is_called(3)
        assert.are.equal(2, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(2)
        assert.spy(p.turnOffFrontlightHW).is_called(1)

        assert.is.truthy(p:toggleFrontlight())
        assert.are.equal(0, p:frontlightIntensity())
        assert.is.truthy(p:isFrontlightOff())
        assert.stub(p.setIntensityHW).is_called(4)
        assert.are.equal(param.fl_min, p.frontlight)
        assert.spy(p.turnOnFrontlightHW).is_called(2)
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
