describe("AutoWarmth plugin", function()
    local Device, original_has_natural_light, original_powerd
    local original_package_path, SunTime, UIManager

    setup(function()
        require("commonrequire")
        disable_plugins()
        original_package_path = package.path
        package.path = "plugins/autowarmth.koplugin/?.lua;" .. package.path
        Device = require("device")
        SunTime = require("suntime")
        UIManager = require("ui/uimanager")
        original_has_natural_light = Device.hasNaturalLight
        original_powerd = Device.powerd
    end)

    teardown(function()
        package.path = original_package_path
    end)

    before_each(function()
        Device.hasNaturalLight = function() return true end
        Device.powerd = {
            fl_warmth_max = 24,
            toNativeWarmth = function(_, warmth)
                return math.floor(warmth * 24 / 100 + 0.5)
            end,
        }
        stub(SunTime, "setPosition")
        stub(SunTime, "setAdvanced")
        stub(SunTime, "setDate")
        stub(SunTime, "calculateTimes")
        stub(SunTime, "getTimeInSec", function(_, hours)
            return hours and hours * 3600 or 0
        end)
        stub(UIManager, "unschedule")
        stub(UIManager, "scheduleIn")
    end)

    after_each(function()
        Device.hasNaturalLight = original_has_natural_light
        Device.powerd = original_powerd
        SunTime.setPosition:revert()
        SunTime.setAdvanced:revert()
        SunTime.setDate:revert()
        SunTime.calculateTimes:revert()
        SunTime.getTimeInSec:revert()
        UIManager.unschedule:revert()
        UIManager.scheduleIn:revert()
    end)

    it("schedules every distinct native warmth step", function()
        local AutoWarmth = dofile("plugins/autowarmth.koplugin/main.lua")
        local widget = setmetatable({
            activate = 2,
            easy_mode = false,
            location = "",
            latitude = 0,
            longitude = 0,
            timezone = 0,
            altitude = 0,
            scheduler_times = { 0, 1 },
            warmth = { 100, 0 },
            scheduleNextWarmthChange = function() end,
            scheduleToggleFrontlight = function() end,
            toggleFrontlight = function() end,
        }, { __index = AutoWarmth })

        widget:scheduleMidnightUpdate()

        assert.are.equal(25, #widget.sched_warmths)
        for i, warmth in ipairs(widget.sched_warmths) do
            assert.are.equal(25 - i, Device.powerd:toNativeWarmth(warmth))
        end
    end)
end)
