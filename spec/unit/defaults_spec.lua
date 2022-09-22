describe("defaults module", function()
    local Defaults, DataStorage, lfs, persistent_filename
    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        persistent_filename = DataStorage:getDataDir() .. "/defaults.defaults_spec.lua"
        Defaults = require("luadefaults"):open(persistent_filename)
        lfs = require("libs/libkoreader-lfs")
    end)

    it("should load all defaults from defaults.lua", function()
        assert.is_true(Defaults:has("DHINTCOUNT"))
        Defaults:close()
    end)

    it("should save changes to defaults.custom.lua", function()
        os.remove(persistent_filename)
        os.remove(persistent_filename .. ".old")

        -- This defaults to false
        Defaults:makeTrue("DSHOWOVERLAP")
        assert.is_true(Defaults:hasBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isTrue("DSHOWOVERLAP"))

        Defaults:close()
        assert.is_true(lfs.attributes(persistent_filename, "mode") == "file")

        Defaults = nil
        Defaults = require("luadefaults"):open(persistent_filename)
        assert.is_true(Defaults:hasBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isTrue("DSHOWOVERLAP"))
        Defaults:makeFalse("DSHOWOVERLAP")
        Defaults:close()

        os.remove(persistent_filename)
        os.remove(persistent_filename .. ".old")
    end)

    it("should delete entry from defaults.custom.lua if value is reverted back to default", function()
        -- This defaults to false
        Defaults:makeTrue("DSHOWOVERLAP")
        assert.is_true(Defaults:hasBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isTrue("DSHOWOVERLAP"))
        Defaults:makeFalse("DSHOWOVERLAP")
        assert.is_true(Defaults:hasNotBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isFalse("DSHOWOVERLAP"))
        Defaults:close()
    end)
end)
