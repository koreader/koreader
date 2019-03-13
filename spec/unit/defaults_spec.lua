describe("defaults module", function()
    local Defaults, DataStorage
    setup(function()
        require("commonrequire")
        Defaults = require("apps/filemanager/filemanagersetdefaults")
        DataStorage = require("datastorage")
    end)

    it("should load all defaults from defaults.lua", function()
        Defaults:init()
        assert.is_same(90, #Defaults.defaults_name)
        assert.is_same("DFULL_SCREEN", Defaults.defaults_name[28])
    end)

    it("should save changes to defaults.persistent.lua", function()
        local persistent_filename = DataStorage:getDataDir() .. "/defaults.persistent.lua"
        os.remove(persistent_filename)

        -- not in persistent but checked in defaults
        Defaults.changed[11] = true
        Defaults.changed[19] = true
        Defaults.changed[28] = true
        Defaults.changed[63] = true
        Defaults.changed[77] = true
        Defaults:saveSettings()
        assert.is_same(90, #Defaults.defaults_name)
        assert.is_same("DFULL_SCREEN", Defaults.defaults_name[28])
        assert.is_same("SEARCH_LIBRARY_PATH", Defaults.defaults_name[77])
        assert.is_same("DTAP_ZONE_BACKWARD", Defaults.defaults_name[63])
        assert.is_same("DCREREADER_CONFIG_WORD_GAP_LARGE", Defaults.defaults_name[19])
        assert.is_same("DCREREADER_CONFIG_MARGIN_SIZES_HUGE", Defaults.defaults_name[11])
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
DFULL_SCREEN = 1
DCREREADER_CONFIG_MARGIN_SIZES_HUGE = {
    [1] = 100,
    [2] = 100,
    [3] = 100,
    [4] = 100
}
]],
                       fd:read("*a"))
        fd:close()

        -- in persistent
        Defaults:init()
        Defaults.changed[28] = true
        Defaults.defaults_value[28] = 2
        Defaults.changed[63] = true
        Defaults.defaults_value[63] = {
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
DFULL_SCREEN = 2
DCREREADER_CONFIG_MARGIN_SIZES_HUGE = {
    [1] = 100,
    [2] = 100,
    [3] = 100,
    [4] = 100
}
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
DCREREADER_CONFIG_MARGIN_SIZES_LARGE = {
    [1] = 20,
    [2] = 20,
    [3] = 20,
    [4] = 20
}
DCREREADER_VIEW_MODE = "page"
DHINTCOUNT = 2
]])
        fd:close()

        -- in persistent
        Defaults:init()
        Defaults.changed[28] = true
        Defaults.defaults_value[28] = 1
        Defaults:saveSettings()
        fd = io.open(persistent_filename)
        assert.Equals(
[[-- For configuration changes that persists between updates
SEARCH_TITLE = true
DHINTCOUNT = 2
DCREREADER_CONFIG_MARGIN_SIZES_LARGE = {
    [1] = 20,
    [2] = 20,
    [3] = 20,
    [4] = 20
}
DFULL_SCREEN = 1
DCREREADER_VIEW_MODE = "page"
]],
                       fd:read("*a"))
        fd:close()
        os.remove(persistent_filename)
    end)
end)
