describe("PluginCompatibility module", function()
    local PluginCompatibility, Version
    local compatibility

    setup(function()
        require("commonrequire")
        PluginCompatibility = require("plugincompatibility")
        Version = require("frontend/version")
    end)

    before_each(function()
        -- Create a fresh instance for each test
        compatibility = PluginCompatibility:new()
        -- Reset the settings data to ensure clean state
        compatibility.settings:reset({
            version_settings = {},
        })
    end)

    describe("checkCompatibility", function()
        it("should return compatible for plugins without compatibility field", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_true(is_compatible)
            assert.is_nil(reason)
            assert.is_nil(message)
        end)

        it("should return compatible for plugins with empty compatibility field", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {},
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_true(is_compatible)
            assert.is_nil(reason)
            assert.is_nil(message)
        end)

        it("should return compatible when current version is within range", function()
            -- Get current version and create a range that includes it
            local current_version, _ = Version:getNormalizedCurrentVersion()
            if not current_version then
                pending("Cannot get current KOReader version")
                return
            end
            local year_now = math.floor(current_version / 100000000)
            local min_year = math.max(2000, year_now - 100)
            local max_year = year_now + 100
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    min_version = string.format("v%d.01-1", min_year),
                    max_version = string.format("v%d.12-999", max_year),
                },
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_true(is_compatible)
        end)
        it("should return incompatible when current version is below minimum", function()
            -- Get current version and create a future minimum
            local current_version, _ = Version:getNormalizedCurrentVersion()
            if not current_version then
                pending("Cannot get current KOReader version")
                return
            end
            -- Use a year 100 years in the future as minimum
            local year_now = math.floor(current_version / 100000000)
            local future_year = year_now + 100
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    min_version = string.format("v%d.01-1", future_year),
                },
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_false(is_compatible)
            assert.equals("below_minimum", reason)
            assert.is_not_nil(message)
            assert.truthy(message:find("Requires KOReader"))
        end)

        it("should return incompatible when current version is above maximum", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_false(is_compatible)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
            assert.truthy(message:find("Not compatible"))
        end)

        it("should handle only min_version specified", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    min_version = "v2000.01-1",
                },
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_true(is_compatible)
            assert.is_nil(reason)
            assert.is_nil(message)
        end)

        it("should handle only max_version specified", function()
            -- Get current version and use a future max_version
            local current_version, _ = Version:getNormalizedCurrentVersion()
            if not current_version then
                pending("Cannot get current KOReader version")
                return
            end
            local year_now = math.floor(current_version / 100000000)
            local future_year = year_now + 100
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = string.format("v%d.12-999", future_year),
                },
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_true(is_compatible)
            assert.is_nil(reason)
            assert.is_nil(message)
        end)
    end)

    describe("shouldLoadPlugin", function()
        it("should load compatible plugins without prompting", function()
            -- Get current version and create a range that includes it
            local current_version, _ = Version:getNormalizedCurrentVersion()
            if not current_version then
                pending("Cannot get current KOReader version")
                return
            end
            local year_now = math.floor(current_version / 100000000)
            local min_year = math.max(2000, year_now - 100)
            local max_year = year_now + 100
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    min_version = string.format("v%d.01-1", min_year),
                    max_version = string.format("v%d.12-999", max_year),
                },
            }
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_true(should_load)
            assert.is_nil(incompatible_plugin)
        end)

        it("should not load incompatible plugin on first encounter and prompt user", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_false(should_load)
            assert.is_not_nil(incompatible_plugin)
            assert.equals("above_maximum", incompatible_plugin.incompatibility_reason)
            assert.is_not_nil(incompatible_plugin.incompatibility_message)
            assert.is_true(incompatible_plugin.should_prompt_user)
        end)

        it("should not prompt again after user has been prompted once", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            -- First time - should prompt
            local _, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_true(incompatible_plugin.should_prompt_user)
            -- Mark as prompted
            compatibility.settings:markAsPrompted("testplugin", "1.0")
            -- Second time - should not prompt
            local should_load
            should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_false(should_load)
            assert.is_false(incompatible_plugin.should_prompt_user)
        end)

        it("should load incompatible plugin when override is 'always'", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            compatibility.settings:setLoadOverride("testplugin", "1.0", "always")
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_true(should_load)
            assert.is_nil(incompatible_plugin)
        end)

        it("should not load plugin when override is 'never'", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            compatibility.settings:setLoadOverride("testplugin", "1.0", "never")
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_false(should_load)
            assert.is_not_nil(incompatible_plugin)
            assert.equals("above_maximum", incompatible_plugin.incompatibility_reason)
            assert.is_not_nil(incompatible_plugin.incompatibility_message)
            assert.is_false(incompatible_plugin.should_prompt_user)
        end)

        it("should load plugin once with 'load-once' override and then clear it", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            compatibility.settings:setLoadOverride("testplugin", "1.0", "load-once")
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_true(should_load)
            assert.is_nil(incompatible_plugin)
            -- Verify the override was cleared
            local override = compatibility.settings:getLoadOverride("testplugin", "1.0")
            assert.is_nil(override)
        end)
    end)

    describe("getOverrideDescription", function()
        it("should return correct descriptions for each action", function()
            assert.truthy(PluginCompatibility.getOverrideDescription("always"):find("Always"))
            assert.truthy(PluginCompatibility.getOverrideDescription("never"):find("Never"))
            assert.truthy(PluginCompatibility.getOverrideDescription("load-once"):find("once"))
            assert.truthy(PluginCompatibility.getOverrideDescription(nil):find("Ask"))
        end)
    end)

    describe("COMPATIBILITY_CHECK_ENABLED flag", function()
        after_each(function()
            PluginCompatibility.isCompatibilityCheckEnabled = function()
                return true
            end
        end)

        it("should load incompatible plugins when flag is disabled", function()
            PluginCompatibility.isCompatibilityCheckEnabled = function()
                return false
            end
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            local is_compatible, reason, message = require("plugincompatibility").checkCompatibility(plugin_meta)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_true(is_compatible)
        end)

        it("shouldLoadPlugin should allow incompatible plugins when flag is disabled", function()
            PluginCompatibility.isCompatibilityCheckEnabled = function()
                return false
            end
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_true(should_load)
            assert.is_nil(incompatible_plugin)
        end)

        it("should respect compatibility checks when flag is re-enabled", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_false(is_compatible)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
        end)
    end)
    describe("showIncompatiblePluginsMenu and ButtonDialog callback behavior", function()
        local UIManager, original_show, original_close
        local shown_widgets

        setup(function()
            UIManager = require("ui/uimanager")
        end)

        before_each(function()
            shown_widgets = {}
            original_show = UIManager.show
            original_close = UIManager.close
            UIManager.show = function(_, widget)
                table.insert(shown_widgets, widget)
            end
            UIManager.close = function(_, widget)
                -- no-op for tests
            end
        end)

        after_each(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        --- Helper to find a widget by checking for a specific field or method
        local function findWidgetByField(widgets, field)
            for _, widget in ipairs(widgets) do
                if widget[field] then
                    return widget
                end
            end
            return nil
        end

        --- Helper to find a button in ButtonDialog by text
        local function findButtonByText(button_dialog, text_pattern)
            if not button_dialog or not button_dialog.buttons then
                return nil
            end
            for _, row in ipairs(button_dialog.buttons) do
                for _, button in ipairs(row) do
                    if button.text and button.text:find(text_pattern) then
                        return button
                    end
                end
            end
            return nil
        end

        --- Helper to find menu item by text
        local function findMenuItemByText(menu, text_pattern)
            if not menu or not menu.item_table then
                return nil
            end
            for _, item in ipairs(menu.item_table) do
                if item.text and item.text:find(text_pattern) then
                    return item
                end
            end
            return nil
        end

        it("should clear prompted marker when selecting 'Ask on incompatibility' after 'load-once'", function()
            local plugin = {
                name = "testplugin",
                fullname = "Test Plugin",
                version = "1.0",
                incompatibility_message = "Not compatible",
            }
            local incompatible_plugins = { plugin }
            -- Step 1: Show menu and select "load-once"
            compatibility:showIncompatiblePluginsMenu(incompatible_plugins, function() end)
            -- Find the Menu widget (has item_table)
            local menu = findWidgetByField(shown_widgets, "item_table")
            assert.is_not_nil(menu, "Menu widget should be shown")
            -- Find the plugin menu item and trigger its callback to show ButtonDialog
            local plugin_item = findMenuItemByText(menu, "Test Plugin")
            assert.is_not_nil(plugin_item, "Plugin menu item should exist")
            assert.is_not_nil(plugin_item.callback, "Plugin menu item should have callback")
            -- Clear shown_widgets to capture the ButtonDialog
            shown_widgets = {}
            plugin_item.callback()
            -- Find the ButtonDialog (has buttons field as array)
            local button_dialog = findWidgetByField(shown_widgets, "buttons")
            assert.is_not_nil(button_dialog, "ButtonDialog should be shown")
            -- Find and click "Load once" button
            local load_once_button = findButtonByText(button_dialog, "Load once")
            assert.is_not_nil(load_once_button, "Load once button should exist")
            load_once_button.callback()
            -- Verify load-once settings were applied
            local override = compatibility.settings:getLoadOverride("testplugin", "1.0")
            assert.equals("load-once", override)
            local has_been_prompted = compatibility.settings:hasBeenPrompted("testplugin", "1.0")
            assert.is_true(has_been_prompted, "Plugin should be marked as prompted after selecting load-once")
            -- Step 2: Now select "Ask on incompatibility" to reset
            shown_widgets = {}
            plugin_item.callback()
            button_dialog = findWidgetByField(shown_widgets, "buttons")
            assert.is_not_nil(button_dialog, "ButtonDialog should be shown again")
            -- Find and click "Ask on incompatibility" button
            local ask_button = findButtonByText(button_dialog, "Ask on incompatibility")
            assert.is_not_nil(ask_button, "Ask on incompatibility button should exist")
            ask_button.callback()
            -- Verify override is cleared
            override = compatibility.settings:getLoadOverride("testplugin", "1.0")
            assert.is_nil(override, "Override should be nil after selecting 'Ask on incompatibility'")
            has_been_prompted = compatibility.settings:hasBeenPrompted("testplugin", "1.0")
            assert.is_false(
                has_been_prompted,
                "Prompted marker should be removed when resetting to 'Ask on incompatibility'"
            )
            -- Verify that shouldLoadPlugin now prompts the user again
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "v2000.01-1",
                },
            }
            local should_load, incompatible_plugin = compatibility:shouldLoadPlugin(plugin_meta, "/fake/path")
            assert.is_false(should_load)
            assert.is_not_nil(incompatible_plugin)
            assert.is_not_nil(incompatible_plugin.incompatibility_message)
            assert.equals("above_maximum", incompatible_plugin.incompatibility_reason)
            assert.is_true(incompatible_plugin.should_prompt_user, "User should be prompted again after resetting to 'Ask on incompatibility'")
        end)

        it("should keep prompted marker when selecting non-nil action", function()
            local plugin = {
                name = "testplugin2",
                fullname = "Test Plugin 2",
                version = "2.0",
                incompatibility_message = "Not compatible",
            }
            local incompatible_plugins = { plugin }
            -- Show menu
            compatibility:showIncompatiblePluginsMenu(incompatible_plugins, function() end)
            local menu = findWidgetByField(shown_widgets, "item_table")
            local plugin_item = findMenuItemByText(menu, "Test Plugin 2")
            -- Select "Always load"
            shown_widgets = {}
            plugin_item.callback()
            local button_dialog = findWidgetByField(shown_widgets, "buttons")
            local always_button = findButtonByText(button_dialog, "Always load")
            assert.is_not_nil(always_button, "Always load button should exist")
            always_button.callback()
            -- Verify settings
            local override = compatibility.settings:getLoadOverride("testplugin2", "2.0")
            assert.equals("always", override)
            local has_been_prompted = compatibility.settings:hasBeenPrompted("testplugin2", "2.0")
            assert.is_true(has_been_prompted, "Plugin should be marked as prompted")
            -- Now switch to "Never load"
            shown_widgets = {}
            plugin_item.callback()
            button_dialog = findWidgetByField(shown_widgets, "buttons")
            local never_button = findButtonByText(button_dialog, "Never load")
            assert.is_not_nil(never_button, "Never load button should exist")
            never_button.callback()
            -- Verify override changed but prompted marker remains (correct behavior for non-nil actions)
            override = compatibility.settings:getLoadOverride("testplugin2", "2.0")
            assert.equals("never", override)
            has_been_prompted = compatibility.settings:hasBeenPrompted("testplugin2", "2.0")
            assert.is_true(has_been_prompted, "Prompted marker should remain for non-nil action")
        end)
    end)
end)
