describe("defaults module", function()
    local Defaults, DataStorage, lfs
    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        Defaults = require("luadefaults"):open()
        lfs = require("libs/libkoreader-lfs")
    end)

    it("should load all defaults from defaults.lua", function()
        assert.is_true(Defaults:has("DHINTCOUNT"))
    end)

    it("should save changes to defaults.custom.lua", function()
        local persistent_filename = DataStorage:getDataDir() .. "/defaults.custom.lua"
        os.remove(persistent_filename)

        -- This defaults to false
        Defaults:makeTrue("DSHOWOVERLAP")
        assert.is_true(Defaults:hasBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isTrue("DSHOWOVERLAP"))

        Defaults:close()
        assert.is_true(lfs.attributes(persistent_filename, "mode") == "file")

        Defaults = nil
        Defaults = require("luadefaults"):open()
        assert.is_true(Defaults:hasBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isTrue("DSHOWOVERLAP"))

        os.remove(persistent_filename)
    end)

    it("should delete entry from defaults.custom.lua if value is reverted back to default", function()
        -- This defaults to false
        Defaults:makeTrue("DSHOWOVERLAP")
        assert.is_true(Defaults:hasBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isTrue("DSHOWOVERLAP"))
        Defaults:makeFalse("DSHOWOVERLAP")
        assert.is_true(Defaults:hasNotBeenCustomized("DSHOWOVERLAP"))
        assert.is_true(Defaults:isFalse("DSHOWOVERLAP"))
    end)
end)
