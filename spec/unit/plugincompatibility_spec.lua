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
            plugin_load_overrides = {},
            plugin_compatibility_prompts_shown = {},
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
            local should_load, reason, message, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should not load incompatible plugin on first encounter and prompt user", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }
            local should_load, reason, message, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_false(should_load)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
            assert.is_true(should_prompt)
        end)

        it("should not prompt again after user has been prompted once", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }
            -- First time - should prompt
            local _, _, _, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_true(should_prompt)
            -- Mark as prompted
            compatibility.settings:markAsPrompted("testplugin", "1.0")
            -- Second time - should not prompt
            local should_load
            should_load, _, _, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_false(should_load)
            assert.is_false(should_prompt)
        end)

        it("should load incompatible plugin when override is 'always'", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }
            compatibility.settings:setLoadOverride("testplugin", "1.0", "always")
            local should_load, reason, message, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should not load plugin when override is 'never'", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }
            compatibility.settings:setLoadOverride("testplugin", "1.0", "never")
            local should_load, reason, message, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_false(should_load)
            assert.equals("above_maximum", reason)
            assert.is_not_nil(message)
            assert.is_false(should_prompt)
        end)

        it("should load plugin once with 'load-once' override and then clear it", function()
            local plugin_meta = {
                name = "testplugin",
                version = "1.0",
                compatibility = {
                    max_version = "2000.01-1",
                },
            }
            compatibility.settings:setLoadOverride("testplugin", "1.0", "load-once")
            local should_load, reason, message, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
            assert.is_true(should_load)
            assert.is_nil(reason)
            assert.is_nil(message)
            assert.is_false(should_prompt)
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
                    max_version = "2000.01-1",
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
                    max_version = "2000.01-1",
                },
            }
            local should_load, reason, message, should_prompt = compatibility:shouldLoadPlugin(plugin_meta)
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
