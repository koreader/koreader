describe("ReadTimer plugin tests", function()
    local MockTime, ReadTimer, UIManager, time

    local function new_readtimer()
        return ReadTimer:new{
            ui = {
                bookinfo = {
                    expandString = function(_, text)
                        return text
                    end,
                },
                menu = {
                    registerToMainMenu = function() end,
                },
            },
        }
    end

    setup(function()
        require("commonrequire")
        disable_plugins()
        MockTime = require("mock_time")
        time = require("ui/time")
        UIManager = require("ui/uimanager")
        MockTime:install()
    end)

    teardown(function()
        MockTime:uninstall()
    end)

    before_each(function()
        UIManager:quit()
        G_reader_settings:delSetting("readtimer")
        ReadTimer = dofile("plugins/readtimer.koplugin/main.lua")
        MockTime.monotonic_time = 0
        MockTime.boottime_or_realtime_coarse_time = 0
    end)

    it("should track remaining interval time with elapsed real time", function()
        local widget = new_readtimer()
        widget:rescheduleIn(15 * 60)

        MockTime.boottime_or_realtime_coarse_time = MockTime.boottime_or_realtime_coarse_time + time.s(8 * 60)

        assert.are.equal(7 * 60, widget:remaining())
        widget:onCloseWidget()
    end)

    it("should expire when elapsed real time passes even if monotonic time does not", function()
        local widget = new_readtimer()
        widget.settings.show_on_expiry = "nothing"
        widget:rescheduleIn(15 * 60)

        MockTime.boottime_or_realtime_coarse_time = MockTime.boottime_or_realtime_coarse_time + time.s(15 * 60)

        assert.is_true(widget:expireIfDue())
        assert.is_false(widget:scheduled())
        widget:onCloseWidget()
    end)

    it("should keep an auto-rescheduled interval after resume expiry", function()
        local widget = new_readtimer()
        widget.settings.show_on_expiry = "nothing"
        widget.settings.auto_reschedule_interval = true
        widget.last_interval_time = 15 * 60
        widget:rescheduleIn(widget.last_interval_time)

        MockTime.boottime_or_realtime_coarse_time = MockTime.boottime_or_realtime_coarse_time + time.s(15 * 60)

        widget:onResume()

        assert.is_true(widget:scheduled())
        assert.are.equal(15 * 60, widget:remaining())
        widget:onCloseWidget()
    end)
end)
