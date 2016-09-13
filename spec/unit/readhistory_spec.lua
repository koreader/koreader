describe("ReadHistory module", function()
    local DocSettings
    local DataStorage
    local mkdir
    local realpath
    local joinPath
    local usleep
    local history_file

    local function file(name)
        return joinPath(DataStorage:getDataDir(), name)
    end

    local function test_file(name)
        return joinPath(joinPath(DataStorage:getDataDir(), "testdata"), name)
    end

    local function legacy_history_file(name)
        return DocSettings:getHistoryPath(realpath(test_file(name)))
    end

    local function reload()
        package.loaded["readhistory"] = nil
        return require("readhistory")
    end

    local function rm(file)
        os.remove(file)
    end

    local function touch(file)
        local f = io.open(file, "w")
        f:close()
    end

    local function assert_item_is(h, i, name)
        assert.is.same(h.hist[i].text, name)
        assert.is.same(h.hist[i].index, i)
        assert.is.same(h.hist[i].file, realpath(test_file(name)))
    end

    setup(function()
        require("commonrequire")
        DocSettings = require("docsettings")
        DataStorage = require("datastorage")
        mkdir = require("libs/libkoreader-lfs").mkdir
        realpath = require("ffi/util").realpath
        joinPath = require("ffi/util").joinPath
        usleep = require("ffi/util").usleep

        mkdir(joinPath(DataStorage:getDataDir(), "testdata"))
    end)

    it("should read empty history.lua", function()
        rm(file("history.lua"))
        local h = reload()
        assert.is.same(#h.hist, 0)
        touch(file("history.lua"))
        h = reload()
        assert.is.same(#h.hist, 0)
    end)

    it("should read non-empty history.lua", function()
        rm(file("history.lua"))
        local h = reload()
        touch(test_file("a"))
        h:addItem(test_file("a"))
        h = reload()
        assert.is.same(#h.hist, 1)
        assert_item_is(h, 1, "a")
        rm(test_file("a"))
    end)

    it("should order legacy and history.lua", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        local h = reload()
        h:addItem(test_file("a"))
        usleep(1000000)
        touch(legacy_history_file("b"))
        h = reload()
        assert.is.same(#h.hist, 2)
        assert_item_is(h, 1, "b")
        assert_item_is(h, 2, "a")
        rm(legacy_history_file("b"))
        rm(test_file("a"))
        rm(test_file("b"))
    end)

    it("should read legacy history folder", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        touch(test_file("d"))
        touch(test_file("e"))
        touch(test_file("f"))
        local h = reload()
        h:addItem(test_file("f"))
        usleep(1000000)
        touch(legacy_history_file("c"))
        usleep(1000000)
        touch(legacy_history_file("b"))
        usleep(1000000)
        h:addItem(test_file("d"))
        usleep(1000000)
        touch(legacy_history_file("a"))
        usleep(1000000)
        h:addItem(test_file("e"))
        h = reload()
        assert.is.same(#h.hist, 6)
        assert_item_is(h, 1, "e")
        assert_item_is(h, 2, "a")
        assert_item_is(h, 3, "d")
        assert_item_is(h, 4, "b")
        assert_item_is(h, 5, "c")
        assert_item_is(h, 6, "f")

        rm(legacy_history_file("c"))
        rm(legacy_history_file("b"))
        rm(legacy_history_file("a"))
        rm(test_file("a"))
        rm(test_file("b"))
        rm(test_file("c"))
        rm(test_file("d"))
        rm(test_file("e"))
        rm(test_file("f"))
    end)

    it("should add item", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        local h = reload()
        h:addItem(test_file("a"))
        assert.is.same(#h.hist, 1)
        assert_item_is(h, 1, "a")
        rm(test_file("a"))
    end)

    it("should be able to remove the first item", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        local h = reload()
        h:addItem(test_file("a"))
        h:addItem(test_file("b"))
        h:addItem(test_file("c"))
        h:removeItem(h.hist[1])
        assert_item_is(h, 1, "b")
        assert_item_is(h, 2, "c")
        h:removeItem(h.hist[1])
        assert_item_is(h, 1, "c")
        rm(test_file("a"))
        rm(test_file("b"))
        rm(test_file("c"))
    end)

    it("should be able to remove an item in the middle", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        local h = reload()
        h:addItem(test_file("a"))
        h:addItem(test_file("b"))
        h:addItem(test_file("c"))
        h:removeItem(h.hist[2])
        assert_item_is(h, 1, "a")
        assert_item_is(h, 2, "c")
        rm(test_file("a"))
        rm(test_file("b"))
        rm(test_file("c"))
    end)

    it("should be able to remove the last item", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        local h = reload()
        h:addItem(test_file("a"))
        h:addItem(test_file("b"))
        h:addItem(test_file("c"))
        h:removeItem(h.hist[3])
        assert_item_is(h, 1, "a")
        assert_item_is(h, 2, "b")
        h:removeItem(h.hist[2])
        assert_item_is(h, 1, "a")
        rm(test_file("a"))
        rm(test_file("b"))
        rm(test_file("c"))
    end)

    it("should be able to remove two items", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        touch(test_file("d"))
        local h = reload()
        h:addItem(test_file("a"))
        h:addItem(test_file("b"))
        h:addItem(test_file("c"))
        h:addItem(test_file("d"))
        h:removeItem(h.hist[3])  -- remove c
        h:removeItem(h.hist[2])  -- remove b
        assert_item_is(h, 1, "a")
        assert_item_is(h, 2, "d")
        rm(test_file("a"))
        rm(test_file("b"))
        rm(test_file("c"))
        rm(test_file("d"))
    end)

    it("should be able to remove three items", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        touch(test_file("d"))
        touch(test_file("e"))
        local h = reload()
        h:addItem(test_file("a"))
        h:addItem(test_file("b"))
        h:addItem(test_file("c"))
        h:addItem(test_file("d"))
        h:addItem(test_file("e"))
        h:removeItem(h.hist[2])  -- remove b
        h:removeItem(h.hist[2])  -- remove c
        h:removeItem(h.hist[3])  -- remove e
        assert_item_is(h, 1, "a")
        assert_item_is(h, 2, "d")
        rm(test_file("a"))
        rm(test_file("b"))
        rm(test_file("c"))
        rm(test_file("d"))
        rm(test_file("e"))
    end)

    it("should remove duplicate entry", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        local h = reload()
        h:addItem(test_file("b"))
        h:addItem(test_file("b"))
        touch(legacy_history_file("a"))
        h:addItem(test_file("a"))  -- ensure a is before b
        h = reload()
        assert.is.same(#h.hist, 2)
        assert_item_is(h, 1, "a")
        assert_item_is(h, 2, "b")

        rm(legacy_history_file("a"))
        rm(test_file("a"))
        rm(test_file("b"))
    end)

    it("should reduce the total count", function()
        local function to_file(i)
            return test_file(string.format("%04d", i))
        end
        rm(file("history.lua"))
        local h = reload()
        for i = 1000, 1, -1 do
            touch(to_file(i))
            h:addItem(to_file(i))
        end

        for i = 1, 500 do  -- at most 500 items are stored
            assert_item_is(h, i, string.format("%04d", i))
        end
        
        for i = 1, 1000 do
            rm(to_file(i))
        end
    end)
end)
