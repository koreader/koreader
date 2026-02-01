describe("PluginLoader module", function()
    local PluginLoader
    local lfs_mock
    local original_lfs

    setup(function()
        require("commonrequire")
        PluginLoader = require("pluginloader")
        original_lfs = package.loaded["libs/libkoreader-lfs"]
    end)

    teardown(function()
        -- Restore original lfs
        package.loaded["libs/libkoreader-lfs"] = original_lfs
    end)

    before_each(function()
        -- Reset G_reader_settings for clean state
        G_reader_settings:reset({})

        -- Create a mock for lfs
        lfs_mock = {
            dir_results = {},
            attributes_results = {},
        }

        function lfs_mock.dir(path)
            local entries = lfs_mock.dir_results[path] or {}
            local i = 0
            return function()
                i = i + 1
                return entries[i]
            end
        end

        function lfs_mock.attributes(path, attr)
            local result = lfs_mock.attributes_results[path]
            if not result then
                return nil
            end
            if attr then
                return result[attr]
            end
            return result
        end

        -- Replace lfs with mock
        package.loaded["libs/libkoreader-lfs"] = lfs_mock

        -- Force reload of PluginLoader to use mocked lfs
        package.loaded["pluginloader"] = nil
        PluginLoader = require("pluginloader")
    end)

    after_each(function()
        -- Restore original lfs
        package.loaded["libs/libkoreader-lfs"] = original_lfs
        -- Clear PluginLoader cache
        PluginLoader.enabled_plugins = nil
        PluginLoader.disabled_plugins = nil
        PluginLoader.all_plugins = nil
    end)

    describe("plugin discovery", function()
        it("should extract directory-based plugin names", function()
            -- Setup mock filesystem
            lfs_mock.dir_results["plugins"] = {
                ".", "..", "plugin1.koplugin", "plugin2.koplugin", "plugin3.koplugin"
            }
            lfs_mock.attributes_results["plugins/plugin1.koplugin"] = { mode = "directory" }
            lfs_mock.attributes_results["plugins/plugin2.koplugin"] = { mode = "directory" }
            lfs_mock.attributes_results["plugins/plugin3.koplugin"] = { mode = "directory" }

            local discovered = PluginLoader:_discover()

            -- Verify directory-based names are extracted correctly
            assert.is_not_nil(discovered)
            assert.is_true(#discovered >= 3)

            local found_plugin1 = false
            local found_plugin2 = false
            local found_plugin3 = false

            for _, plugin in ipairs(discovered) do
                if plugin.name == "plugin1" then
                    found_plugin1 = true
                    assert.equals("plugins/plugin1.koplugin", plugin.path)
                elseif plugin.name == "plugin2" then
                    found_plugin2 = true
                    assert.equals("plugins/plugin2.koplugin", plugin.path)
                elseif plugin.name == "plugin3" then
                    found_plugin3 = true
                    assert.equals("plugins/plugin3.koplugin", plugin.path)
                end
            end

            assert.is_true(found_plugin1, "plugin1 not found in discovered list")
            assert.is_true(found_plugin2, "plugin2 not found in discovered list")
            assert.is_true(found_plugin3, "plugin3 not found in discovered list")
        end)

        it("should check disabled status using directory-based names", function()
            -- Setup disabled plugins setting
            G_reader_settings:saveSetting("plugins_disabled", {
                ["plugin2"] = true,
                ["plugin3"] = true,
            })

            -- Setup mock filesystem
            lfs_mock.dir_results["plugins"] = {
                ".", "..", "plugin1.koplugin", "plugin2.koplugin", "plugin3.koplugin"
            }
            lfs_mock.attributes_results["plugins/plugin1.koplugin"] = { mode = "directory" }
            lfs_mock.attributes_results["plugins/plugin2.koplugin"] = { mode = "directory" }
            lfs_mock.attributes_results["plugins/plugin3.koplugin"] = { mode = "directory" }

            local discovered = PluginLoader:_discover()

            -- Verify disabled status is correctly detected
            for _, plugin in ipairs(discovered) do
                if plugin.name == "plugin1" then
                    assert.is_false(plugin.disabled, "plugin1 should not be disabled")
                elseif plugin.name == "plugin2" then
                    assert.is_true(plugin.disabled, "plugin2 should be disabled")
                elseif plugin.name == "plugin3" then
                    assert.is_true(plugin.disabled, "plugin3 should be disabled")
                end
            end
        end)
    end)
end)
