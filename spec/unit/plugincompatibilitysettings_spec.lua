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
            version_settings = {},
        })
    end)

    describe("open", function()
        it("should create a new settings instance", function()
            local new_settings = PluginCompatibilitySettings:open()
            assert.is_not_nil(new_settings)
            assert.is_not_nil(new_settings.data)
        end)

        it("should initialize version_settings structure", function()
            local new_settings = PluginCompatibilitySettings:open()
            -- version_settings should exist (may be empty or populated)
            assert.is_table(new_settings.data.version_settings)
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

        it("key format check", function()
            local key = settings:getOverrideKey("plugin1", "1.0")
            assert.equals("plugin1-1.0", key)
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

            local koreader_version = Version:getShortVersion()
            local version_settings = settings.data.version_settings[koreader_version]
            assert.is_not_nil(version_settings)

            local override_data = version_settings.plugin_load_overrides["testplugin"]
            assert.is_not_nil(override_data)
            assert.equals("always", override_data.action)
            assert.equals("1.0", override_data.version)
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
                version_settings = {},
            })

            assert.is_false(settings:hasBeenPrompted("testplugin", "1.0"))
            assert.is_nil(settings:getLoadOverride("testplugin", "1.0"))
        end)
    end)

    describe("version-indexed storage", function()
        it("should store settings under the current KOReader version", function()
            settings:markAsPrompted("testplugin", "1.0")
            settings:setLoadOverride("testplugin", "1.0", "always")

            local koreader_version = Version:getShortVersion()
            assert.is_not_nil(settings.data.version_settings[koreader_version])
        end)

        it("should isolate settings by KOReader version", function()
            -- Set up some settings under current version
            settings:setLoadOverride("testplugin", "1.0", "always")
            settings:markAsPrompted("testplugin", "1.0")

            local current_version = Version:getShortVersion()

            -- Manually create settings for a different version
            local other_version = "2099.12"
            settings.data.version_settings[other_version] = {
                plugin_load_overrides = {
                    testplugin = { action = "never", version = "1.0" },
                },
                plugin_compatibility_prompts_shown = {},
            }

            -- Current version should have "always"
            assert.equals("always", settings:getLoadOverride("testplugin", "1.0"))
            assert.equals("always", settings:getLoadOverride("testplugin", "1.0", current_version))

            -- Other version should have "never"
            assert.equals("never", settings:getLoadOverride("testplugin", "1.0", other_version))
        end)
    end)

    describe("getStoredVersions", function()
        it("should return empty table when no versions stored", function()
            settings:reset({ version_settings = {} })
            local versions = settings:getStoredVersions()
            assert.is_table(versions)
            assert.equals(0, #versions)
        end)

        it("should return all stored versions sorted newest first", function()
            -- Manually set up multiple versions
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.03"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.02"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local versions = settings:getStoredVersions()
            assert.equals(3, #versions)
            assert.equals("2025.03", versions[1])
            assert.equals("2025.02", versions[2])
            assert.equals("2025.01", versions[3])
        end)

        it("should handle versions with point releases", function()
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.01.1"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.01.2"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local versions = settings:getStoredVersions()
            assert.equals(3, #versions)
            -- Point releases should sort correctly
            assert.equals("2025.01.2", versions[1])
            assert.equals("2025.01.1", versions[2])
            assert.equals("2025.01", versions[3])
        end)
    end)

    describe("purgeOldVersionSettings", function()
        it("should return 0 when no versions stored", function()
            settings:reset({ version_settings = {} })
            local purged = settings:purgeOldVersionSettings(2)
            assert.equals(0, purged)
        end)

        it("should keep all versions when count is less than or equal to keep_versions", function()
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.02"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local purged = settings:purgeOldVersionSettings(3)
            assert.equals(0, purged)
            assert.is_not_nil(settings.data.version_settings["2025.01"])
            assert.is_not_nil(settings.data.version_settings["2025.02"])
        end)

        it("should purge older versions when count exceeds keep_versions", function()
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.02"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.03"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.04"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local purged = settings:purgeOldVersionSettings(2)
            assert.equals(2, purged)

            -- Newest 2 should remain
            assert.is_not_nil(settings.data.version_settings["2025.04"])
            assert.is_not_nil(settings.data.version_settings["2025.03"])

            -- Oldest 2 should be purged
            assert.is_nil(settings.data.version_settings["2025.02"])
            assert.is_nil(settings.data.version_settings["2025.01"])
        end)

        it("should keep only 1 version when keep_versions is 1", function()
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.02"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.03"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local purged = settings:purgeOldVersionSettings(1)
            assert.equals(2, purged)

            -- Only newest should remain
            assert.is_not_nil(settings.data.version_settings["2025.03"])
            assert.is_nil(settings.data.version_settings["2025.02"])
            assert.is_nil(settings.data.version_settings["2025.01"])
        end)

        it("should handle versions with point releases correctly", function()
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.01.1"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.02"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local purged = settings:purgeOldVersionSettings(2)
            assert.equals(1, purged)

            -- 2025.02 and 2025.01.1 should remain (newest 2)
            assert.is_not_nil(settings.data.version_settings["2025.02"])
            assert.is_not_nil(settings.data.version_settings["2025.01.1"])

            -- 2025.01 (oldest) should be purged
            assert.is_nil(settings.data.version_settings["2025.01"])
        end)

        it("should handle versions with revision numbers correctly", function()
            settings.data.version_settings = {
                ["2025.01"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.01-100"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
                ["2025.01-200"] = { plugin_load_overrides = {}, plugin_compatibility_prompts_shown = {} },
            }

            local purged = settings:purgeOldVersionSettings(2)
            assert.equals(1, purged)

            -- 2025.01-200 and 2025.01-100 should remain (newest 2)
            assert.is_not_nil(settings.data.version_settings["2025.01-200"])
            assert.is_not_nil(settings.data.version_settings["2025.01-100"])

            -- 2025.01 (oldest) should be purged
            assert.is_nil(settings.data.version_settings["2025.01"])
        end)

        it("should delete all old settings including prompts and overrides", function()
            settings.data.version_settings = {
                ["2025.01"] = {
                    plugin_load_overrides = {
                        plugin1 = { action = "always", version = "1.0" },
                    },
                    plugin_compatibility_prompts_shown = {
                        ["plugin1-1.0"] = true,
                    },
                },
                ["2025.02"] = {
                    plugin_load_overrides = {
                        plugin2 = { action = "never", version = "2.0" },
                    },
                    plugin_compatibility_prompts_shown = {
                        ["plugin2-2.0"] = true,
                    },
                },
            }

            local purged = settings:purgeOldVersionSettings(1)
            assert.equals(1, purged)

            -- 2025.01 and all its contents should be gone
            assert.is_nil(settings.data.version_settings["2025.01"])

            -- 2025.02 should still have its data
            assert.is_not_nil(settings.data.version_settings["2025.02"])
            assert.is_not_nil(settings.data.version_settings["2025.02"].plugin_load_overrides.plugin2)
        end)
    end)

    describe("_normalizeVersion", function()
        it("should normalize simple version strings", function()
            local normalized = settings:_normalizeVersion("2025.01")
            assert.is_not_nil(normalized)
            assert.is_number(normalized)
        end)

        it("should handle versions with point releases", function()
            local v1 = settings:_normalizeVersion("2025.01")
            local v2 = settings:_normalizeVersion("2025.01.1")

            assert.is_not_nil(v1)
            assert.is_not_nil(v2)
            assert.is_true(v2 > v1)
        end)

        it("should handle versions with revision numbers", function()
            local v1 = settings:_normalizeVersion("2025.01")
            local v2 = settings:_normalizeVersion("2025.01-100")

            assert.is_not_nil(v1)
            assert.is_not_nil(v2)
            assert.is_true(v2 > v1)
        end)

        it("should handle versions already prefixed with v", function()
            local v1 = settings:_normalizeVersion("2025.01")
            local v2 = settings:_normalizeVersion("v2025.01")

            assert.is_not_nil(v1)
            assert.is_not_nil(v2)
            assert.equals(v1, v2)
        end)

        it("should return nil for invalid versions", function()
            local normalized = settings:_normalizeVersion(nil)
            assert.is_nil(normalized)
        end)
    end)
end)
