describe("BackgroundRunner widget tests", function()
    local Device, PluginShare, MockTime, UIManager

    setup(function()
        require("commonrequire")
        package.unloadAll()
        -- Device needs to be loaded before UIManager.
        Device = require("device")
        Device.input.waitEvent = function() end
        PluginShare = require("pluginshare")
        MockTime = require("mock_time")
        MockTime:install()
        UIManager = require("ui/uimanager")
        UIManager._run_forever = true
        requireBackgroundRunner()
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
        stopBackgroundRunner()
    end)

    it("should start job", function()
        local executed = false
        table.insert(PluginShare.backgroundJobs, {
            when = 10,
            repeated = false,
            executable = function()
                executed = true
            end,
        })
        MockTime:increase(2)
        UIManager:handleInput()
        MockTime:increase(9)
        UIManager:handleInput()
        assert.is_false(executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.is_true(executed)
    end)
end)
