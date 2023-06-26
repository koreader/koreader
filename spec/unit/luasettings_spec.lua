describe("luasettings module", function()
    local Settings
    setup(function()
        require("commonrequire")
        Settings = require("frontend/luasettings"):open("this-is-not-a-valid-file")
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
end)
