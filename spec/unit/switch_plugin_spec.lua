describe("SwitchPlugin", function()
    require("commonrequire")
    local SwitchPlugin = require("ui/plugin/switch_plugin")

    local createTestPlugin = function(default_enable, start, stop)
        return SwitchPlugin:new({
            name = "test_plugin",
            menu_item = "test_plugin_menu",
            menu_text = "This is a test plugin",
            confirm_message = "This is a test plugin, it's for test purpose only.",
            default_enable = default_enable,
            _start = function()
                start()
            end,
            _stop = function()
                stop()
            end,
        })
    end

    local TestPlugin2 = SwitchPlugin:extend()

    function TestPlugin2:new(o)
        o = o or {}
        o.name = "test_plugin2"
        o.menu_item = "test_plugin2_menu"
        o.menu_text = "This is a test plugin2"
        o.confirm_message = "This is a test plugin2, it's for test purpose only."
        o.start_called = 0
        o.stop_called = 0
        o = SwitchPlugin.new(self, o)
        return o
    end

    function TestPlugin2:_start()
        self.start_called = self.start_called + 1
    end

    function TestPlugin2:_stop()
        self.stop_called = self.stop_called + 1
    end

    it("should be able to create a enabled plugin", function()
        local start_called = 0
        local stop_called = 0
        local test_plugin = createTestPlugin(
            true,
            function()
                start_called = start_called + 1
            end,
            function()
                stop_called = stop_called + 1
            end)
        assert.are.equal(1, start_called)
        assert.are.equal(0, stop_called)
        test_plugin:flipSetting()
        assert.are.equal(1, start_called)
        assert.are.equal(1, stop_called)
        test_plugin:flipSetting()
        assert.are.equal(2, start_called)
        assert.are.equal(1, stop_called)

        local menu_items = {}
        test_plugin:addToMainMenu(menu_items)
        assert.are.equal("This is a test plugin", menu_items.test_plugin_menu.text)
    end)

    it("should be able to create a disabled plugin", function()
        local start_called = 0
        local stop_called = 0
        local test_plugin = createTestPlugin(
            false,
            function()
                start_called = start_called + 1
            end,
            function()
                stop_called = stop_called + 1
            end)
        assert.are.equal(0, start_called)
        assert.are.equal(1, stop_called)
        test_plugin:flipSetting()
        assert.are.equal(1, start_called)
        assert.are.equal(1, stop_called)
        test_plugin:flipSetting()
        assert.are.equal(1, start_called)
        assert.are.equal(2, stop_called)
    end)

    it("should be able to create a derived enabled plugin", function()
        local test_plugin = TestPlugin2:new({
            default_enable = true,
        })
        assert.are.equal(1, test_plugin.start_called)
        assert.are.equal(0, test_plugin.stop_called)
        test_plugin:flipSetting()
        assert.are.equal(1, test_plugin.start_called)
        assert.are.equal(1, test_plugin.stop_called)
        test_plugin:flipSetting()
        assert.are.equal(2, test_plugin.start_called)
        assert.are.equal(1, test_plugin.stop_called)

        local menu_items = {}
        test_plugin:addToMainMenu(menu_items)
        assert.are.equal("This is a test plugin2", menu_items.test_plugin2_menu.text)
    end)

    it("should be able to create a derived disabled plugin", function()
        local test_plugin = TestPlugin2:new()
        assert.are.equal(0, test_plugin.start_called)
        assert.are.equal(1, test_plugin.stop_called)
        test_plugin:flipSetting()
        assert.are.equal(1, test_plugin.start_called)
        assert.are.equal(1, test_plugin.stop_called)
        test_plugin:flipSetting()
        assert.are.equal(1, test_plugin.start_called)
        assert.are.equal(2, test_plugin.stop_called)
    end)

    it("should be able to create an invisible plugin", function()
        local test_plugin = SwitchPlugin:new({
            name = "test_plugin",
            ui = {
                menu = {
                    registerToMainMenu = function()
                         assert.is_true(false, "This should not reach.")
                    end,
                },
            },
        })
        test_plugin:init()
    end)

    it("should show a correct message box", function()
        local UIManager = require("ui/uimanager")

        local confirm_box
        UIManager.show = function(self, element)
            confirm_box = element
        end

        local test_plugin = TestPlugin2:new()
        -- The plugin is off by default, we expect an "enable" message.
        test_plugin:_showConfirmBox()
        assert.is_not_nil(confirm_box)
        assert.are.equal(
            "This is a test plugin2, it's for test purpose only.\nDo you want to enable it?",
            confirm_box.text)
        assert.are.equal("Enable", confirm_box.ok_text)
        confirm_box.ok_callback()
        confirm_box = nil

        -- The plugin is enabled by confirm_box.ok_callback(), we expect a "disable" message.
        test_plugin:_showConfirmBox()
        assert.is_not_nil(confirm_box)
        assert.are.equal(
            "This is a test plugin2, it's for test purpose only.\nDo you want to disable it?",
            confirm_box.text)
        assert.are.equal("Disable", confirm_box.ok_text)
        confirm_box.ok_callback()

        assert.is_false(test_plugin.enabled)

        package.unload("ui/uimanager")
    end)
end)
