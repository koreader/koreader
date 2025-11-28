describe("PluginCompatibilitySettings module", function()
    local PluginCompatibilitySettings, Version
    local settings

    setup(function()
        require("commonrequire")
        PluginCompatibilitySettings = require("plugincompatibilitysettings")
        Version = require("frontend/version")
    end)

    before_each(function()
        -- Create a fresh settings instance for each test
        settings = PluginCompatibilitySettings:open()
        -- Reset the settings data to ensure clean state
        settings:reset({
            plugin_load_overrides = {},
            plugin_compatibility_prompts_shown = {},
        })
    end)

    describe("open", function()
        it("should create a new settings instance", function()
            local new_settings = PluginCompatibilitySettings:open()
            assert.is_not_nil(new_settings)
            assert.is_not_nil(new_settings.data)
        end)

        it("should initialize data structures", function()
            local new_settings = PluginCompatibilitySettings:open()
            assert.is_table(new_settings.data.plugin_load_overrides)
            assert.is_table(new_settings.data.plugin_compatibility_prompts_shown)
        end)
    end)

    describe("getOverrideKey", function()
        it("should generate a unique key for plugin name and version", function()
            local key1 = settings:getOverrideKey("plugin1", "1.0")
            local key2 = settings:getOverrideKey("plugin1", "2.0")
            local key3 = settings:getOverrideKey("plugin2", "1.0")

            assert.is_not_equal(key1, key2)
            assert.is_not_equal(key1, key3)
            assert.is_not_equal(key2, key3)
        end)

        it("should include KOReader version in the key", function()
            local key = settings:getOverrideKey("plugin1", "1.0")
            local koreader_version = Version:getShortVersion()

            assert.truthy(key:find(koreader_version, 1, true))
        end)

        it("should return consistent keys for same input", function()
            local key1 = settings:getOverrideKey("testplugin", "1.0")
            local key2 = settings:getOverrideKey("testplugin", "1.0")

            assert.equals(key1, key2)
        end)
    end)

    describe("hasBeenPrompted and markAsPrompted", function()
        it("should return false for unprompted plugin", function()
            local has_been_prompted = settings:hasBeenPrompted("testplugin", "1.0")
            assert.is_false(has_been_prompted)
        end)

        it("should return true after marking as prompted", function()
            settings:markAsPrompted("testplugin", "1.0")

            local has_been_prompted = settings:hasBeenPrompted("testplugin", "1.0")
            assert.is_true(has_been_prompted)
        end)

        it("should differentiate between plugin versions", function()
            settings:markAsPrompted("testplugin", "1.0")

            assert.is_true(settings:hasBeenPrompted("testplugin", "1.0"))
            assert.is_false(settings:hasBeenPrompted("testplugin", "2.0"))
        end)

        it("should differentiate between different plugins", function()
            settings:markAsPrompted("plugin1", "1.0")

            assert.is_true(settings:hasBeenPrompted("plugin1", "1.0"))
            assert.is_false(settings:hasBeenPrompted("plugin2", "1.0"))
        end)
    end)

    describe("removePromptedMark", function()
        it("should remove the prompted mark", function()
            settings:markAsPrompted("testplugin", "1.0")
            assert.is_true(settings:hasBeenPrompted("testplugin", "1.0"))

            settings:removePromptedMark("testplugin", "1.0")
            assert.is_false(settings:hasBeenPrompted("testplugin", "1.0"))
        end)

        it("should handle removing non-existent mark gracefully", function()
            -- Should not error
            settings:removePromptedMark("nonexistent", "1.0")
            assert.is_false(settings:hasBeenPrompted("nonexistent", "1.0"))
        end)
    end)

    describe("getLoadOverride and setLoadOverride", function()
        it("should return nil when no override is set", function()
            local override = settings:getLoadOverride("testplugin", "1.0")
            assert.is_nil(override)
        end)

        it("should store and retrieve 'always' override", function()
            settings:setLoadOverride("testplugin", "1.0", "always")

            local override = settings:getLoadOverride("testplugin", "1.0")
            assert.equals("always", override)
        end)

        it("should store and retrieve 'never' override", function()
            settings:setLoadOverride("testplugin", "1.0", "never")

            local override = settings:getLoadOverride("testplugin", "1.0")
            assert.equals("never", override)
        end)

        it("should store and retrieve 'load-once' override", function()
            settings:setLoadOverride("testplugin", "1.0", "load-once")

            local override = settings:getLoadOverride("testplugin", "1.0")
            assert.equals("load-once", override)
        end)

        it("should remove override when action is nil", function()
            settings:setLoadOverride("testplugin", "1.0", "always")
            assert.equals("always", settings:getLoadOverride("testplugin", "1.0"))

            settings:setLoadOverride("testplugin", "1.0", nil)
            assert.is_nil(settings:getLoadOverride("testplugin", "1.0"))
        end)

        it("should remove override when action is 'ask'", function()
            settings:setLoadOverride("testplugin", "1.0", "always")
            assert.equals("always", settings:getLoadOverride("testplugin", "1.0"))

            settings:setLoadOverride("testplugin", "1.0", "ask")
            assert.is_nil(settings:getLoadOverride("testplugin", "1.0"))
        end)

        it("should return nil for overrides with different plugin versions", function()
            settings:setLoadOverride("testplugin", "1.0", "always")

            assert.equals("always", settings:getLoadOverride("testplugin", "1.0"))
            assert.is_nil(settings:getLoadOverride("testplugin", "2.0"))
        end)

        it("should store override with version information", function()
            settings:setLoadOverride("testplugin", "1.0", "always")

            local override_data = settings.data.plugin_load_overrides["testplugin"]
            assert.is_not_nil(override_data)
            assert.equals("always", override_data.action)
            assert.equals("1.0", override_data.version)
            assert.equals(Version:getShortVersion(), override_data.koreader_version)
        end)
    end)

    describe("clearLoadOnceOverride", function()
        it("should clear load-once override", function()
            settings:setLoadOverride("testplugin", "1.0", "load-once")
            assert.equals("load-once", settings:getLoadOverride("testplugin", "1.0"))

            settings:clearLoadOnceOverride("testplugin")
            assert.is_nil(settings:getLoadOverride("testplugin", "1.0"))
        end)

        it("should not clear 'always' override", function()
            settings:setLoadOverride("testplugin", "1.0", "always")
            settings:clearLoadOnceOverride("testplugin")

            assert.equals("always", settings:getLoadOverride("testplugin", "1.0"))
        end)

        it("should not clear 'never' override", function()
            settings:setLoadOverride("testplugin", "1.0", "never")
            settings:clearLoadOnceOverride("testplugin")

            assert.equals("never", settings:getLoadOverride("testplugin", "1.0"))
        end)

        it("should handle clearing non-existent override gracefully", function()
            -- Should not error
            settings:clearLoadOnceOverride("nonexistent")
        end)
    end)

    describe("reset", function()
        it("should clear all settings when reset with empty table", function()
            settings:markAsPrompted("testplugin", "1.0")
            settings:setLoadOverride("testplugin", "1.0", "always")

            settings:reset({
                plugin_load_overrides = {},
                plugin_compatibility_prompts_shown = {},
            })

            assert.is_false(settings:hasBeenPrompted("testplugin", "1.0"))
            assert.is_nil(settings:getLoadOverride("testplugin", "1.0"))
        end)
    end)
end)
