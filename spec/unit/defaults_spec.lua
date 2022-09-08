describe("defaults module", function()
    local Defaults, DataStorage
    setup(function()
        require("commonrequire")
        Defaults = require("apps/filemanager/filemanagersetdefaults")
        DataStorage = require("datastorage")
    end)

    it("should load all defaults from defaults.lua", function()
        Defaults:init()
        assert.is_same(99, #Defaults.defaults_name)
    end)

    it("should save changes to defaults.persistent.lua", function()
        local persistent_filename = DataStorage:getDataDir() .. "/defaults.persistent.lua"
        os.remove(persistent_filename)

        -- To see indices and help updating this when new settings are added:
        -- for i=1, 99 do print(i.." ".. Defaults.defaults_name[i]) end

        -- not in persistent but checked in defaults
        Defaults.changed[18] = true
        Defaults.changed[48] = true
        Defaults.changed[54] = true
        Defaults.changed[83] = true
        Defaults:saveSettings()
        assert.is_same(99, #Defaults.defaults_name)
        assert.is_same("DTAP_ZONE_BACKWARD", Defaults.defaults_name[84])
        assert.is_same("DCREREADER_CONFIG_WORD_SPACING_LARGE", Defaults.defaults_name[48])
        assert.is_same("DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE", Defaults.defaults_name[18])
        dofile(persistent_filename)
        assert.is_same(DCREREADER_CONFIG_WORD_SPACING_LARGE, { [1] = 100, [2] = 90 })
        assert.is_same(DTAP_ZONE_BACKWARD, { ["y"] = 0, ["x"] = 0, ["h"] = 1, ["w"] = 0.25 })
        assert.is_same(DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE, { [1] = 50, [2] = 50 })
        assert.is_same(DDOUBLE_TAP_ZONE_PREV_CHAPTER, { ["y"] = 0, ["x"] = 0, ["h"] = 1, ["w"] = 0.25 })

        -- in persistent
        Defaults:init()
        Defaults.changed[54] = true
        Defaults.defaults_value[54] = {
            y = 0,
            x = 0,
            h = 0.25,
            w = 0.75
        }
        Defaults.changed[84] = true
        Defaults.defaults_value[84] = {
            y = 10,
            x = 10.125,
            h = 20.25,
            w = 20.75
        }
        Defaults:saveSettings()
        dofile(persistent_filename)
        assert.is_same(DCREREADER_CONFIG_WORD_SPACING_LARGE, { [2] = 90, [1] = 100 })
        assert.is_same(DDOUBLE_TAP_ZONE_PREV_CHAPTER, {
            ["y"] = 0,
            ["x"] = 0,
            ["h"] = 0.25,
            ["w"] = 0.75
        })
        assert.is_same(DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE, { [2] = 50, [1] = 50 })
        assert.is_same(DTAP_ZONE_BACKWARD, {
            ["y"] = 10,
            ["x"] = 10.125,
            ["h"] = 20.25,
            ["w"] = 20.75
        })
        os.remove(persistent_filename)
    end)

    it("should delete entry from defaults.persistent.lua if value is reverted back to default", function()
        local persistent_filename = DataStorage:getDataDir() .. "/defaults.persistent.lua"
        local fd = io.open(persistent_filename, "w")
        fd:write(
[[-- For configuration changes that persists between updates
DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE = {
    [1] = 15,
    [2] = 15
}
DCREREADER_VIEW_MODE = "page"
DHINTCOUNT = 2
]])
        fd:close()

        -- in persistent
        Defaults:init()
        Defaults.changed[56] = true
        Defaults.defaults_value[56] = 1
        Defaults:saveSettings()
        dofile(persistent_filename)
        assert.Equals(DCREREADER_VIEW_MODE, "page")
        assert.is_same(DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE, {
            [2] = 15,
            [1] = 15
        })
        assert.Equals(DGLOBAL_CACHE_FREE_PROPORTION, 1)
        assert.Equals(DHINTCOUNT, 2)
        os.remove(persistent_filename)
    end)
end)
