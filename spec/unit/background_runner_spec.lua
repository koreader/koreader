describe("BackgroundRunner widget tests", function()
    local Device, PluginShare, MockTime, UIManager

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        -- Device needs to be loaded before UIManager.
        Device = require("device")
        Device.input.waitEvent = function() end
        PluginShare = require("pluginshare")
        MockTime = require("mock_time")
        MockTime:install()
        UIManager = require("ui/uimanager")
        UIManager:setRunForeverMode()
        requireBackgroundRunner()
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        stopBackgroundRunner()
    end)

    before_each(function()
        require("util").clearTable(PluginShare.backgroundJobs)
    end)

    it("should start job", function()
        local executed = false
        table.insert(PluginShare.backgroundJobs, {
            when = 10,
            executable = function()
                executed = true
            end,
        })
        notifyBackgroundJobsUpdated()

        MockTime:increase(2)
        UIManager:handleInput()
        assert.is_false(executed)
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
        notifyBackgroundJobsUpdated()

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
        notifyBackgroundJobsUpdated()

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
        notifyBackgroundJobsUpdated()

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
        local executed = false
        local job = {
            when = 1,
            executable = "ls | grep this-should-not-be-a-file",
            callback = function()
                executed = true
            end,
        }
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        while job.end_time == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        -- grep should return 1 when there is no match.
        assert.are.equal(1, job.result)
        assert.is_false(job.timeout)
        assert.is_false(job.bad_command)
        assert.is_true(executed)
    end)

    it("should forward string environment to the executable", function()
        local job = {
            when = 1,
            repeated = false,
            executable = "echo $ENV1 | grep $ENV2",
            environment = {
                ENV1 = "yes",
                ENV2 = "yes",
            }
        }
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        while job.end_time == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        -- grep should return 0 when there is a match.
        assert.are.equal(0, job.result)
        assert.is_false(job.timeout)
        assert.is_false(job.bad_command)

        job.environment = {
            ENV1 = "yes",
            ENV2 = "no",
        }
        job.end_time = nil
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        while job.end_time == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        -- grep should return 1 when there is no match.
        assert.are.equal(1, job.result)
        assert.is_false(job.timeout)
        assert.is_false(job.bad_command)

        assert.are.not_equal(os.getenv("ENV1"), "yes")
        assert.are.not_equal(os.getenv("ENV2"), "yes")
        assert.are.not_equal(os.getenv("ENV2"), "no")
    end)

    it("should forward function environment to the executable", function()
        local env2 = "yes"
        local job = {
            when = 1,
            repeated = false,
            executable = "echo $ENV1 | grep $ENV2",
            environment = function()
                return {
                    ENV1 = "yes",
                    ENV2 = env2,
                }
            end,
        }
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        while job.end_time == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        -- grep should return 0 when there is a match.
        assert.are.equal(0, job.result)
        assert.is_false(job.timeout)
        assert.is_false(job.bad_command)

        job.end_time = nil
        env2 = "no"
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        while job.end_time == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        -- grep should return 1 when there is no match.
        assert.are.equal(1, job.result)
        assert.is_false(job.timeout)
        assert.is_false(job.bad_command)
    end)

    it("should block long binary job", function()
        local job = {
            when = 1,
            repeated = true,
            executable = "sleep 1h",
            environment = {
                TIMEOUT = 1
            }
        }
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        while job.end_time == nil do
            MockTime:increase(2)
            UIManager:handleInput()
        end

        assert.are.equal(255, job.result)
        assert.is_true(job.timeout)
        assert.is_true(job.blocked)
    end)

    it("should execute callback", function()
        local executed = 0
        table.insert(PluginShare.backgroundJobs, {
            when = 1,
            repeated = 10,
            executable = function() end,
            callback = function()
                executed = executed + 1
            end,
        })
        notifyBackgroundJobsUpdated()

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

    it("should not execute two jobs sequentially", function()
        local executed = 0
        table.insert(PluginShare.backgroundJobs, {
            when = 1,
            executable = function()
                executed = executed + 1
            end,
        })
        table.insert(PluginShare.backgroundJobs, {
            when = 1,
            executable = function()
                executed = executed + 1
            end,
        })
        notifyBackgroundJobsUpdated()

        MockTime:increase(2)
        UIManager:handleInput()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, executed)
    end)

    it("should stop executing when suspending", function()
        local executed = 0
        local job = {
            when = 1,
            repeated = true,
            executable = function()
                executed = executed + 1
            end,
        }
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        MockTime:increase(2)
        UIManager:handleInput()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, executed)
        -- Simulate a suspend event.
        requireBackgroundRunner():onSuspend()
        for i = 1, 10 do
            MockTime:increase(2)
            UIManager:handleInput()
            assert.are.equal(2, executed)
        end
        -- Simulate a resume event.
        requireBackgroundRunner():onResume()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(4, executed)
    end)

    it("should not start multiple times after multiple onResume", function()
        local executed = 0
        local job = {
            when = 1,
            repeated = true,
            executable = function()
                executed = executed + 1
            end,
        }
        table.insert(PluginShare.backgroundJobs, job)
        notifyBackgroundJobsUpdated()

        for i = 1, 10 do
            requireBackgroundRunner():onResume()
        end

        MockTime:increase(2)
        UIManager:handleInput()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, executed)
    end)
end)
