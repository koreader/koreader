describe("Dispatcher runtime actions", function()
    local Dispatcher, util
    local settingsList

    setup(function()
        require("commonrequire")
        Dispatcher = require("frontend/dispatcher")
        util = require("util")
        -- grab private settingsList from upvalue of registerAction
        local i = 1
        while true do
            local name, val = debug.getupvalue(Dispatcher.registerAction, i)
            if not name then break end
            if name == "settingsList" then
                settingsList = val
                break
            end
            i = i + 1
        end
        assert.is_truthy(settingsList)
    end)

    it("should add and remove a custom action", function()
        assert.is_nil(settingsList.custom_test)
        Dispatcher:registerAction("custom_test", {category="none", event="TestEvent"})
        assert.equals("TestEvent", settingsList.custom_test.event)
        -- registering again should not duplicate
        Dispatcher:registerAction("custom_test", {category="none", event="TestEvent"})
        -- remove it
        Dispatcher:removeAction("custom_test")
        assert.is_nil(settingsList.custom_test)
    end)

    it("removeAction on missing name does not error", function()
        assert.is_truthy(Dispatcher:removeAction("nopenopenope"))
    end)
end)
