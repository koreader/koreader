describe("defaults module", function()
    local Defaults, DataStorage
    setup(function()
        require("commonrequire")
        Defaults = require("apps/filemanager/filemanagersetdefaults")
        DataStorage = require("datastorage")
    end)

    it("should load all defaults from defaults.lua", function()
        Defaults:init()
        assert.is_same(108, #Defaults.defaults_name)
        assert.is_same("DFULL_SCREEN", Defaults.defaults_name[54])
    end)

    it("should save changes to defaults.persistent.lua", function()
        local persistent_filename = DataStorage:getDataDir() .. "/defaults.persistent.lua"
        os.remove(persistent_filename)

        -- not in persistent but checked in defaults
        Defaults.changed[20] = true
        Defaults.changed[47] = true
        Defaults.changed[54] = true
        Defaults.changed[87] = true
        Defaults.changed[103] = true
        Defaults:saveSettings()
        assert.is_same(108, #Defaults.defaults_name)
        assert.is_same("DFULL_SCREEN", Defaults.defaults_name[54])
        assert.is_same("SEARCH_LIBRARY_PATH", Defaults.defaults_name[103])
        assert.is_same("DTAP_ZONE_BACKWARD", Defaults.defaults_name[87])
        assert.is_same("DCREREADER_CONFIG_WORD_GAP_LARGE", Defaults.defaults_name[47])
        assert.is_same("DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE", Defaults.defaults_name[20])
        local fd = io.open(persistent_filename, "r")
        assert.Equals(
[[-- For configuration changes that persists between updates
SEARCH_LIBRARY_PATH = ""
DTAP_ZONE_BACKWARD = {
    ["y"] = 0,
    ["x"] = 0,
    ["h"] = 1,
    ["w"] = 0.25
}
DCREREADER_CONFIG_WORD_GAP_LARGE = 100
DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE = {
    [1] = 50,
    [2] = 50
}
DFULL_SCREEN = 1
]],
                       fd:read("*a"))
        fd:close()

        -- in persistent
        Defaults:init()
        Defaults.changed[54] = true
        Defaults.defaults_value[54] = 2
        Defaults.changed[87] = true
        Defaults.defaults_value[87] = {
            y = 10,
            x = 10.125,
            h = 20.25,
            w = 20.75
        }
        Defaults:saveSettings()
        fd = io.open(persistent_filename)
        assert.Equals(
[[-- For configuration changes that persists between updates
SEARCH_LIBRARY_PATH = ""
DTAP_ZONE_BACKWARD = {
    ["y"] = 10,
    ["x"] = 10.125,
    ["h"] = 20.25,
    ["w"] = 20.75
}
DCREREADER_CONFIG_WORD_GAP_LARGE = 100
DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE = {
    [2] = 50,
    [1] = 50
}
DFULL_SCREEN = 2
]],
                       fd:read("*a"))
        fd:close()
        os.remove(persistent_filename)
    end)

    it("should delete entry from defaults.persistent.lua if value is reverted back to default", function()
        local persistent_filename = DataStorage:getDataDir() .. "/defaults.persistent.lua"
        local fd = io.open(persistent_filename, "w")
        fd:write(
[[-- For configuration changes that persists between updates
SEARCH_TITLE = true
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
        Defaults.changed[54] = true
        Defaults.defaults_value[54] = 1
        Defaults:saveSettings()
        fd = io.open(persistent_filename)
        assert.Equals(
[[-- For configuration changes that persists between updates
SEARCH_TITLE = true
DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE = {
    [2] = 15,
    [1] = 15
}
DHINTCOUNT = 2
DFULL_SCREEN = 1
DCREREADER_VIEW_MODE = "page"
]],
                       fd:read("*a"))
        fd:close()
        os.remove(persistent_filename)
    end)
end)
