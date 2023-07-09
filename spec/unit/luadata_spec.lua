describe("luadata module", function()
    local Settings, lfs
    setup(function()
        require("commonrequire")
        lfs = require("libs/libkoreader-lfs")
        Settings = require("frontend/luadata"):open("this-is-not-a-valid-file")
    end)

    it("should handle undefined keys", function()
        Settings:delSetting("abc")

        assert.True(Settings:hasNot("abc"))
        assert.True(Settings:nilOrTrue("abc"))
        assert.False(Settings:isTrue("abc"))
        Settings:saveSetting("abc", true)
        assert.True(Settings:has("abc"))
        assert.True(Settings:nilOrTrue("abc"))
        assert.True(Settings:isTrue("abc"))
    end)

    it("should flip bool values", function()
        Settings:delSetting("abc")

        assert.True(Settings:hasNot("abc"))
        Settings:flipNilOrTrue("abc")
        assert.False(Settings:nilOrTrue("abc"))
        assert.True(Settings:has("abc"))
        assert.False(Settings:isTrue("abc"))
        Settings:flipNilOrTrue("abc")
        assert.True(Settings:nilOrTrue("abc"))
        assert.True(Settings:hasNot("abc"))
        assert.False(Settings:isTrue("abc"))

        Settings:flipTrue("abc")
        assert.True(Settings:has("abc"))
        assert.True(Settings:isTrue("abc"))
        assert.True(Settings:nilOrTrue("abc"))
        Settings:flipTrue("abc")
        assert.False(Settings:has("abc"))
        assert.False(Settings:isTrue("abc"))
        assert.True(Settings:nilOrTrue("abc"))
    end)

    it("should create child settings", function()
        Settings:delSetting("key")

        Settings:saveSetting("key", {
            a = "b",
            c = "True",
            d = false,
        })

        local child = Settings:child("key")

        assert.is_not_nil(child)
        assert.True(child:has("a"))
        assert.are.equal(child:readSetting("a"), "b")
        assert.True(child:has("c"))
        assert.False(child:isTrue("c")) -- It's a string, not a bool!
        assert.True(child:has("d"))
        assert.True(child:isFalse("d"))
        assert.False(child:isTrue("e"))
        child:flipTrue("e")
        child:close()

        child = Settings:child("key")
        assert.True(child:isTrue("e"))
    end)

    describe("table wrapper", function()

        setup(function()
            Settings:delSetting("key")
        end)

        it("should add item to table", function()
            Settings:addTableItem("key", 1)
            Settings:addTableItem("key", 2)
            Settings:addTableItem("key", 3)

            assert.are.equal(1, Settings:readSetting("key")[1])
            assert.are.equal(2, Settings:readSetting("key")[2])
            assert.are.equal(3, Settings:readSetting("key")[3])
        end)

        it("should remove item from table", function()
            Settings:removeTableItem("key", 1)

            assert.are.equal(2, Settings:readSetting("key")[1])
            assert.are.equal(3, Settings:readSetting("key")[2])
        end)
    end)

    describe("backup data file", function()
        local file, d
        setup(function()
            file = "dummy-test-file"
            d = Settings:open(file)
        end)
        it("should generate data file", function()
            d:saveSetting("a", "a")
            assert.Equals("file", lfs.attributes(d.file, "mode"))
        end)
        it("should generate backup data file on flush", function()
            d:flush()
            -- file and file.old.1 should be generated.
            assert.Equals("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.1", "mode"))
            d:close()
        end)
        it("should remove garbage data file", function()
            -- write some garbage to sidecar-file.
            local f_out = io.open(d.file, "w")
            f_out:write("bla bla bla")
            f_out:close()

            d = Settings:open(file)
            -- file should be removed.
            assert.are.not_equal("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.2", "mode"))
            assert.Equals("a", d:readSetting("a"))
            d:saveSetting("a", "b")
            d:close()
            -- backup should be generated.
            assert.Equals("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.1", "mode"))
            -- The contents in file and file.old.1 are different.
            -- a:b v.s. a:a
        end)
        it("should open backup data file after garbage removal", function()
            d = Settings:open(file)
            -- We should get the right result.
            assert.Equals("b", d:readSetting("a"))
            -- write some garbage to file.
            local f_out = io.open(d.file, "w")
            f_out:write("bla bla bla")
            f_out:close()

            -- do not flush the result, open docsettings again.
            d = Settings:open(file)
            -- data file should be removed.
            assert.are.not_equal("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.2", "mode"))
            -- The content should come from file.old.2.
            assert.Equals("a", d:readSetting("a"))
            d:close()
            -- data file should be generated and last good backup should not change name.
            assert.Equals("file", lfs.attributes(d.file, "mode"))
            assert.Equals("file", lfs.attributes(d.file .. ".old.2", "mode"))
        end)
    end)
end)
