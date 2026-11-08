describe("Button widget", function()
    local Button
    local ButtonTable
    local Dbg
    local Size

    setup(function()
        require("commonrequire")
        Button = require("ui/widget/button")
        ButtonTable = require("ui/widget/buttontable")
        Dbg = require("dbg")
        Size = require("ui/size")
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

    it("should pass alpha to an icon label", function()
        local btn = Button:new{ icon = "check", alpha = true }
        assert.is_true(btn.label_widget.alpha)
    end)

    it("should pass alpha from a button table entry to an icon label", function()
        local button_table = ButtonTable:new{
            buttons = {
                {
                    { id = "check", icon = "check", alpha = true, callback = function() end },
                },
            },
        }
        assert.is_true(button_table.button_by_id.check.label_widget.alpha)
    end)

    it("should reject a malformed key_bindings", function()
        Dbg:turnOn()
        assert.has_error(function()
            Button:new{ text = "Test", key_bindings = 7 }
        end)
        Dbg:turnOff()
    end)

    -- #16149: a text button with an explicit radius must keep a *rounded*
    -- highlight. Take the rounded path (invert colours, keep the radius) rather
    -- than the invert flag, which paints a square highlight via invertRect.
    it("should highlight with rounded corners when the caller set a radius", function()
        for _, radius in ipairs({ 0, 8 }) do
            local btn = Button:new{ text = "Test", radius = radius }
            btn:_doFeedbackHighlight()
            assert.is_nil(btn[1].invert)
            assert.are.equal(Size.radius.button, btn[1].radius)
            btn:_undoFeedbackHighlight(false)
            -- the caller's radius must survive the round-trip
            assert.are.equal(radius, btn[1].radius)
        end
    end)

    -- #16267: Button:hide() clears the frame background, so a tap used to index
    -- a nil background. It must fall back to the invert flag instead of crashing.
    it("should not crash when highlighting a hidden icon button", function()
        local btn = Button:new{ icon = "check" }
        btn:hide()
        assert.is_nil(btn[1].background)
        assert.has_no.errors(function() btn:_doFeedbackHighlight() end)
        assert.has_no.errors(function() btn:_undoFeedbackHighlight(false) end)
        assert.is_true(btn[1].invert)
    end)
end)
