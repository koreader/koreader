describe("BackgroundTaskPlugin", function()
    require("commonrequire")
    local BackgroundTaskPlugin = require("ui/plugin/background_task_plugin")
    local MockTime = require("mock_time")
    local UIManager = require("ui/uimanager")

    local BackgroundTaskPlugin_schedule_orig = BackgroundTaskPlugin._schedule
    setup(function()
        MockTime:install()
        local Device = require("device")
        Device.input.waitEvent = function() end
        UIManager:setRunForeverMode()
        requireBackgroundRunner()
        -- Monkey patch this method to notify BackgroundRunner
        -- as it is not accessible to UIManager in these tests
        BackgroundTaskPlugin._schedule = function(...)
            BackgroundTaskPlugin_schedule_orig(...)
            notifyBackgroundJobsUpdated()
        end
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        stopBackgroundRunner()
        BackgroundTaskPlugin._schedule = BackgroundTaskPlugin_schedule_orig
    end)

    local createTestPlugin = function(executable)
        return BackgroundTaskPlugin:new({
            name = "test_plugin",
            default_enable = true,
            when = 2,
            executable = executable,
        })
    end

    local TestPlugin2 = BackgroundTaskPlugin:extend()

    function TestPlugin2:new(o)
        o = o or {}
        o.name = "test_plugin2"
        o.default_enable = true
        o.when = 2
        o.executed = 0
        o.executable = function()
            o.executed = o.executed + 1
        end
        o = BackgroundTaskPlugin.new(self, o)
        return o
    end

    it("should be able to create a plugin", function()
        local executed = 0
        local test_plugin = createTestPlugin(function()
            executed = executed + 1
        end)
        MockTime:increase(2)
        UIManager:handleInput()

        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, executed)

        test_plugin:flipSetting()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, executed)  -- The last job is still pending.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, executed)

        test_plugin:flipSetting()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, executed)  -- The new job has just been inserted.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(4, executed)

        -- Fake a settings_id increment.
        test_plugin:_init()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(5, executed)  -- The job is from last settings_id.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(5, executed)  -- The new job has just been inserted.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(6, executed)  -- The job is from current settings_id.

        -- Ensure test_plugin is stopped.
        test_plugin:flipSetting()
        MockTime:increase(2)
        UIManager:handleInput()
    end)

    it("should be able to create a derived plugin", function()
        local test_plugin = TestPlugin2:new()
        MockTime:increase(2)
        UIManager:handleInput()

        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(1, test_plugin.executed)
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(2, test_plugin.executed)

        test_plugin:flipSetting()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, test_plugin.executed)  -- The last job is still pending.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, test_plugin.executed)

        test_plugin:flipSetting()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(3, test_plugin.executed)  -- The new job has just been inserted.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(4, test_plugin.executed)

        -- Fake a settings_id increment.
        test_plugin:_init()
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(5, test_plugin.executed)  -- The job is from last settings_id.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(5, test_plugin.executed)  -- The new job has just been inserted.
        MockTime:increase(2)
        UIManager:handleInput()
        assert.are.equal(6, test_plugin.executed)  -- The job is from current settings_id.

        -- Ensure test_plugin is stopped.
        test_plugin:flipSetting()
        MockTime:increase(2)
        UIManager:handleInput()
    end)
end)
