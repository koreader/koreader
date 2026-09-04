describe("Button widget", function()
    local Button

    setup(function()
        require("commonrequire")
        Button = require("ui/widget/button")
    end)

    it("should register a Shortcut key_event for a string key_bindings", function()
        local callback_called = false
        local btn = Button:new{
            text = "Test",
            key_bindings = "LPgFwd",
            callback = function() callback_called = true end,
        }
        assert.are.same({ { "LPgFwd" } }, btn.key_events.Shortcut)
        btn.onShortcut(btn)
        assert.is_true(callback_called)
    end)

    it("should accept a table key_bindings unchanged", function()
        local btn = Button:new{
            text = "Test",
            key_bindings = { "Alt", "K" },
        }
        assert.are.same({ { "Alt", "K" } }, btn.key_events.Shortcut)
    end)

    it("should not fire the callback when disabled", function()
        local callback_called = false
        local btn = Button:new{
            text = "Test",
            enabled = false,
            key_bindings = "LPgFwd",
            callback = function() callback_called = true end,
        }
        assert.is_false(btn.onShortcut(btn))
        assert.is_false(callback_called)
    end)

    it("should not register a Shortcut event when key_bindings is unset", function()
        local btn = Button:new{ text = "Test" }
        assert.is_nil(btn.key_events.Shortcut)
    end)

    it("should not build a Shortcut key_event for a malformed key_bindings", function()
        local btn = Button:new{ text = "Test", key_bindings = 7 }
        assert.is_nil(btn.key_events.Shortcut)
    end)

    it("should support key_bindings and hold_key_bindings independently", function()
        local btn = Button:new{ text = "Test", key_bindings = 7, hold_key_bindings = "LPgBack" }
        assert.is_nil(btn.key_events.Shortcut)
        assert.is_not_nil(btn.key_events.HoldShortcut)
    end)
end)
