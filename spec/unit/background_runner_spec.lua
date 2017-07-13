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

    it("should repeat job", function()
        local executed = 0
        table.insert(PluginShare.backgroundJobs, {
            when = 1,
            repeated = function() return executed < 10 end,
            executable = function()
                executed = executed + 1
            end,
        })

        MockTime:increase(2)
        UIManager:handleInput()

        for i = 1, 10 do
            MockTime:increase(2)
            UIManager:handleInput()
            assert.are.equal(i, executed)
        end
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(10, executed)
    end)

    it("should repeat job for predefined times", function()
        local executed = 0
        table.insert(PluginShare.backgroundJobs, {
            when = 1,
            repeated = 10,
            executable = function()
                executed = executed + 1
            end,
        })

        MockTime:increase(2)
        UIManager:handleInput()

        for i = 1, 10 do
            MockTime:increase(2)
            UIManager:handleInput()
            assert.are.equal(i, executed)
        end
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(10, executed)
    end)

    it("should block long job", function()
        local executed = 0
        local job = {
            when = 1,
            repeated = true,
            executable = function()
                executed = executed + 1
                MockTime:increase(2)
            end,
        }
        table.insert(PluginShare.backgroundJobs, job)

        MockTime:increase(2)
        UIManager:handleInput()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, executed)
        assert.is_true(job.timeout)
        assert.is_true(job.blocked)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, executed)
    end)

    it("should execute binary", function()
        local job = {
            when = 1,
            executable = "ls | grep this-should-not-be-a-file",
        }
        table.insert(PluginShare.backgroundJobs, job)

        MockTime:increase(2)
        UIManager:handleInput()
        while job.end_sec == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        -- grep should return 1 when there is not matching.
        assert.are.equal(1, job.result)
        assert.is_false(job.timeout)
        assert.is_false(job.bad_command)
    end)
end)
