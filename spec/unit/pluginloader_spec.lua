describe("PluginLoader module", function()
    local PluginLoader, UIManager
    local original_lfs

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        original_lfs = require("libs/libkoreader-lfs")
    end)

    before_each(function()
        local lfs_mock = {
            dir_results = {},
            attributes_results = {},
            mkdir = original_lfs.mkdir,
        }

        function lfs_mock.dir(path)
            local entries = lfs_mock.dir_results[path] or {}
            local index = 0
            return function()
                index = index + 1
                return entries[index]
            end
        end

        function lfs_mock.attributes(path, key)
            local attrs = lfs_mock.attributes_results[path]
            if not attrs then
                return nil
            end
            if key then
                return attrs[key]
            end
            return attrs
        end

        G_reader_settings:reset({})
        G_reader_settings:saveSetting("extra_plugin_paths", {})

        package.replace("libs/libkoreader-lfs", lfs_mock)
        PluginLoader = package.reload("pluginloader")
        PluginLoader.show_info = true
        PluginLoader.enabled_plugins = {}
        PluginLoader.disabled_plugins = {}
        PluginLoader.loaded_plugins = {}
        PluginLoader.all_plugins = nil
    end)

    after_each(function()
        package.replace("libs/libkoreader-lfs", original_lfs)
        package.unload("pluginloader")
    end)

    it("discovers plugins by directory id and matches disabled settings against that id", function()
        local lfs_mock = require("libs/libkoreader-lfs")
        lfs_mock.dir_results.plugins = {
            ".",
            "..",
            "pluginone.koplugin",
            "plugintwo.koplugin",
        }
        lfs_mock.attributes_results["plugins/pluginone.koplugin"] = { mode = "directory" }
        lfs_mock.attributes_results["plugins/plugintwo.koplugin"] = { mode = "directory" }

        G_reader_settings:saveSetting("plugins_disabled", {
            plugintwo = true,
        })

        local discovered = PluginLoader:_discover()

        assert.equals("pluginone", discovered[1].name)
        assert.is_false(discovered[1].disabled)
        assert.equals("plugintwo", discovered[2].name)
        assert.is_true(discovered[2].disabled)
    end)

    it("normalizes the internal id for enabled plugins", function()
        stub(_G, "dofile", function(path)
            if path == "plugins/test.koplugin/main.lua" then
                return {
                    name = "wrong_main_name",
                    description = "from main",
                }
            end
            if path == "plugins/test.koplugin/_meta.lua" then
                return {
                    name = "wrong_meta_name",
                    description = "from meta",
                }
            end
            error("unexpected path: " .. path)
        end)

        PluginLoader:_load({ {
            main = "plugins/test.koplugin/main.lua",
            meta = "plugins/test.koplugin/_meta.lua",
            path = "plugins/test.koplugin",
            disabled = false,
            name = "test",
        } })

        local plugin = PluginLoader.enabled_plugins[1]
        assert.equals("test", plugin.name)
        assert.equals("from meta", plugin.description)

        _G.dofile:revert()
    end)

    it("normalizes the internal id for disabled plugins", function()
        stub(_G, "dofile", function(path)
            if path == "plugins/test.koplugin/_meta.lua" then
                return {
                    name = "wrong_meta_name",
                    description = "from meta",
                }
            end
            error("unexpected path: " .. path)
        end)

        PluginLoader:_load({ {
            main = "plugins/test.koplugin/_meta.lua",
            meta = "plugins/test.koplugin/_meta.lua",
            path = "plugins/test.koplugin",
            disabled = true,
            name = "test",
        } })

        local plugin = PluginLoader.disabled_plugins[1]
        assert.equals("test", plugin.name)
        assert.equals("from meta", plugin.description)

        _G.dofile:revert()
    end)

    it("stores plugin manager toggles by internal plugin id", function()
        stub(PluginLoader, "loadPlugins", function()
            return {
                {
                    name = "test",
                    fullname = "Pretty Test",
                    description = "from meta",
                    path = "plugins/test.koplugin",
                },
            }, {}
        end)
        stub(PluginLoader, "getPluginInstance", function()
            return nil
        end)
        stub(UIManager, "askForRestart")

        local plugin_items = PluginLoader:genPluginManagerSubItem()
        plugin_items[2].sub_item_table[1].callback()

        local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
        assert.is_true(plugins_disabled.test)
        assert.is_nil(plugins_disabled["Pretty Test"])

        UIManager.askForRestart:revert()
        PluginLoader.getPluginInstance:revert()
        PluginLoader.loadPlugins:revert()
    end)

    it("calls deletePluginSettings on the loaded plugin instance by internal plugin id", function()
        local called_instance
        local instance = {
            deletePluginSettings = function(self)
                called_instance = self
            end,
        }

        stub(PluginLoader, "getPluginInstance", function()
            return instance
        end)

        local ok, err = PluginLoader:deletePluginSettingsByName("test")

        assert.is_true(ok)
        assert.is_nil(err)
        assert.are.equal(instance, called_instance)

        PluginLoader.getPluginInstance:revert()
    end)
end)
