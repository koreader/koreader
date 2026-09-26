describe("Dispatcher runtime actions", function()
    local Device
    local Dispatcher
    local settingsList
    local dispatcher_menu_order
    local isAvailable

    setup(function()
        require("commonrequire")
        Device = require("device")
        Dispatcher = require("frontend/dispatcher")
        -- grab private settingsList/dispatcher_menu_order from upvalues of registerAction
        local i = 1
        while true do
            local name, val = debug.getupvalue(Dispatcher.registerAction, i)
            if not name then break end
            if name == "settingsList" then
                settingsList = val
            elseif name == "dispatcher_menu_order" then
                dispatcher_menu_order = val
            end
            i = i + 1
        end
        assert.is_truthy(settingsList)
        assert.is_truthy(dispatcher_menu_order)

        i = 1
        while true do
            local name, val = debug.getupvalue(Dispatcher.getDisplayList, i)
            if not name then break end
            if name == "isAvailable" then
                isAvailable = val
                break
            end
            i = i + 1
        end
        assert.is_truthy(isAvailable)
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

    it("every settingsList action should have a matching dispatcher_menu_order entry", function()
        local order_set = {}
        for _, name in ipairs(dispatcher_menu_order) do
            if name ~= "----" then
                order_set[name] = true
            end
        end

        local missing_from_order = {}
        for name, _ in pairs(settingsList) do
            if not order_set[name] then
                table.insert(missing_from_order, name)
            end
        end
        assert.equals(0, #missing_from_order,
            "settingsList actions missing from dispatcher_menu_order: " .. table.concat(missing_from_order, ", "))

        local missing_from_settings = {}
        for name, _ in pairs(order_set) do
            if settingsList[name] == nil then
                table.insert(missing_from_settings, name)
            end
        end
        assert.equals(0, #missing_from_settings,
            "dispatcher_menu_order entries missing from settingsList: " .. table.concat(missing_from_settings, ", "))
    end)

    it("should evaluate condition_func live for text_selection", function()
        local orig = Device.hasKeyboard
        Device.hasKeyboard = function() return true end
        assert.is_true(isAvailable(settingsList.text_selection))

        Device.hasKeyboard = function() return false end
        assert.is_false(isAvailable(settingsList.text_selection))

        Device.hasKeyboard = orig
    end)

    it("should evaluate condition_func live for hasKeys-dependent actions", function()
        local orig_keys = Device.hasKeys
        local orig_repeat = Device.canKeyRepeat
        Device.hasKeys = function() return true end
        Device.canKeyRepeat = function() return true end
        assert.is_true(isAvailable(settingsList.swap_page_turn_buttons))
        assert.is_true(isAvailable(settingsList.set_page_turn_buttons))
        assert.is_true(isAvailable(settingsList.toggle_key_repeat))

        Device.hasKeys = function() return false end
        assert.is_false(isAvailable(settingsList.swap_page_turn_buttons))
        assert.is_false(isAvailable(settingsList.set_page_turn_buttons))
        assert.is_false(isAvailable(settingsList.toggle_key_repeat))

        Device.hasKeys = orig_keys
        Device.canKeyRepeat = orig_repeat
    end)

    it("should fall back to the static condition for actions without condition_func", function()
        assert.equals(settingsList.toc.condition ~= false, isAvailable(settingsList.toc))
    end)
end)
