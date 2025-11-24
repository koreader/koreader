describe("PluginCompatibility module", function()
    local PluginCompatibility, Version

    setup(function()
        require("commonrequire")
        PluginCompatibility = require("plugincompatibility")
        Version = require("frontend/version")
    end)

    local function createMockSettings()
        -- Create a simple mock settings object that mimics LuaSettings API
        local mock = {
            data = {},
        }

        function mock:readSetting(key)
            return self.data[key]
        end

        function mock:saveSetting(key, value)
            self.data[key] = value
        end

        return mock
    end

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
                    max_version = "2000.01-1",
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
                    min_version = "2000.01-1",
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

    describe("getOverrideKey", function()
        it("should generate a unique key for plugin name and version", function()
            local key1 = PluginCompatibility.getOverrideKey("plugin1", "1.0")
            local key2 = PluginCompatibility.getOverrideKey("plugin1", "2.0")
            local key3 = PluginCompatibility.getOverrideKey("plugin2", "1.0")

            assert.is_not_equal(key1, key2)
            assert.is_not_equal(key1, key3)
            assert.is_not_equal(key2, key3)
        end)

        it("should include KOReader version in the key", function()
            local key = PluginCompatibility.getOverrideKey("plugin1", "1.0")
            local koreader_version = Version:getShortVersion()

            assert.truthy(key:find(koreader_version, 1, true))
        end)
    end)

    describe("hasBeenPrompted and markAsPrompted", function()
        it("should track if user has been prompted", function()
            local settings = createMockSettings()

            local has_been_prompted = PluginCompatibility.hasBeenPrompted(settings, "testplugin", "1.0")
            assert.is_false(has_been_prompted)

            PluginCompatibility.markAsPrompted(settings, "testplugin", "1.0")

            has_been_prompted = PluginCompatibility.hasBeenPrompted(settings, "testplugin", "1.0")
            assert.is_true(has_been_prompted)
        end)

        it("should differentiate between plugin versions", function()
            local settings = createMockSettings()

            PluginCompatibility.markAsPrompted(settings, "testplugin", "1.0")

            assert.is_true(PluginCompatibility.hasBeenPrompted(settings, "testplugin", "1.0"))
            assert.is_false(PluginCompatibility.hasBeenPrompted(settings, "testplugin", "2.0"))
        end)
    end)

    describe("getLoadOverride and setLoadOverride", function()
        it("should return nil when no override is set", function()
            local settings = createMockSettings()

            local override = PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0")
            assert.is_nil(override)
        end)

        it("should store and retrieve 'always' override", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "always")

            local override = PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0")
            assert.equals("always", override)
        end)

        it("should store and retrieve 'never' override", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "never")

            local override = PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0")
            assert.equals("never", override)
        end)

        it("should store and retrieve 'load-once' override", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "load-once")

            local override = PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0")
            assert.equals("load-once", override)
        end)

        it("should remove override when action is nil", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "always")
            assert.equals("always", PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", nil)
            assert.is_nil(PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))
        end)

        it("should return nil for overrides with different versions", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "always")

            assert.equals("always", PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))
            assert.is_nil(PluginCompatibility.getLoadOverride(settings, "testplugin", "2.0"))
        end)
    end)

    describe("clearLoadOnceOverride", function()
        it("should clear load-once override", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "load-once")
            assert.equals("load-once", PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))

            PluginCompatibility.clearLoadOnceOverride(settings, "testplugin")
            assert.is_nil(PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))
        end)

        it("should not clear 'always' override", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "always")
            PluginCompatibility.clearLoadOnceOverride(settings, "testplugin")

            assert.equals("always", PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))
        end)

        it("should not clear 'never' override", function()
            local settings = createMockSettings()

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "never")
            PluginCompatibility.clearLoadOnceOverride(settings, "testplugin")

            assert.equals("never", PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0"))
        end)
    end)

    describe("shouldLoadPlugin", function()
        it("should load compatible plugins without prompting", function()
            local settings = createMockSettings()

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

            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")

            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should not load incompatible plugin on first encounter and prompt user", function()
            local settings = createMockSettings()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")

            assert.is_false(should_load)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
            assert.is_true(should_prompt)
        end)

        it("should not prompt again after user has been prompted once", function()
            local settings = createMockSettings()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            -- First time - should prompt
            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")
            assert.is_true(should_prompt)

            -- Mark as prompted
            PluginCompatibility.markAsPrompted(settings, "testplugin", "1.0")

            -- Second time - should not prompt
            should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")
            assert.is_false(should_load)
            assert.is_false(should_prompt)
        end)

        it("should load incompatible plugin when override is 'always'", function()
            local settings = createMockSettings()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "always")

            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")

            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should not load plugin when override is 'never'", function()
            local settings = createMockSettings()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "never")

            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")

            assert.is_false(should_load)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should load plugin once with 'load-once' override and then clear it", function()
            local settings = createMockSettings()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            PluginCompatibility.setLoadOverride(settings, "testplugin", "1.0", "load-once")

            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")

            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)

            -- Verify the override was cleared
            local override = PluginCompatibility.getLoadOverride(settings, "testplugin", "1.0")
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
                    max_version = "2000.01-1",
                },
            }

            local is_compatible, reason, message = require("plugincompatibility").checkCompatibility(plugin_meta)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_true(is_compatible)
        end)

        it("shouldLoadPlugin should allow incompatible plugins when flag is disabled", function()
            local settings = createMockSettings()

            PluginCompatibility.isCompatibilityCheckEnabled = function()
                return false
            end

            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            local should_load, reason, message, should_prompt =
                PluginCompatibility.shouldLoadPlugin(settings, plugin_meta, "testplugin")

            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should respect compatibility checks when flag is re-enabled", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }

            local is_compatible, reason, message = PluginCompatibility.checkCompatibility(plugin_meta)
            assert.is_false(is_compatible)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
        end)
    end)
end)
