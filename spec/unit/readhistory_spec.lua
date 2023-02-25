describe("ReadHistory module", function()
    local DocSettings
    local DataStorage
    local joinPath
    local mkdir
    local realpath
    local reload
    local lfs
    local now = 61

    local function file(name)
        return joinPath(DataStorage:getDataDir(), name)
    end

    local function test_data_dir()
        return joinPath(DataStorage:getDataDir(), "testdata")
    end

    local function test_file(name)
        return joinPath(test_data_dir(), name)
    end

    local function legacy_history_file(name)
        return DocSettings:getHistoryPath(realpath(test_file(name)))
    end

    local function rm(filename)
        os.remove(filename)
    end

    local function mv(source, target)
        os.rename(source, target)
    end

    local function touch(filename)
        -- Create file if need be
        local f = io.open(filename, "w")
        f:close()
        -- Increment by 61s every time we're called
        now = now + 61
        lfs.touch(filename, now, now)
    end

    local function assert_item_is(h, i, name, fileRemoved)
        assert.is.same(name, h.hist[i].text)
        assert.is.same(joinPath(realpath(test_data_dir()), name), h.hist[i].file)
        if fileRemoved then
            assert.is_nil(realpath(test_file(name)))
        else
            assert.is.same(realpath(test_file(name)), h.hist[i].file)
        end
    end

    setup(function()
        require("commonrequire")
        DocSettings = require("docsettings")
        DataStorage = require("datastorage")
        joinPath = require("ffi/util").joinPath
        mkdir = require("libs/libkoreader-lfs").mkdir
        realpath = require("ffi/util").realpath
        reload = function() return package.reload("readhistory") end
        lfs = require("libs/libkoreader-lfs")

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
        now = now + 61
        h:addItem(test_file("a"), now)
        h = reload()
        assert.is.same(1, #h.hist)
        assert_item_is(h, 1, "a")
        rm(test_file("a"))
    end)

    it("should order legacy and history.lua", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        local h = reload()
        now = now + 61
        h:addItem(test_file("a"), now)
        mkdir(DataStorage:getHistoryDir())
        touch(legacy_history_file("b"))
        h = reload()
        assert.is.same(2, #h.hist)
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
        now = now + 61
        h:addItem(test_file("f"), now)
        mkdir(DataStorage:getHistoryDir())
        touch(legacy_history_file("c"))
        touch(legacy_history_file("b"))
        now = now + 61
        h:addItem(test_file("d"), now)
        touch(legacy_history_file("a"))
        now = now + 61
        h:addItem(test_file("e"), now)
        h = reload()
        assert.is.same(6, #h.hist)
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
        now = now + 61
        h:addItem(test_file("a"), now)
        assert.is.same(1, #h.hist)
        assert_item_is(h, 1, "a")
        rm(test_file("a"))
    end)

    it("should be able to remove the first item", function()
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        touch(test_file("c"))
        local h = reload()
        -- NOTE: Identical timestamps to neuter sorting by mtime, instead alphabetical order kicks in (c.f., ReadHistory:_sort)
        --       This goes for basically the rest of the tests.
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)
        h:addItem(test_file("c"), now)
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
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)
        h:addItem(test_file("c"), now)
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
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)
        h:addItem(test_file("c"), now)
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
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)
        h:addItem(test_file("c"), now)
        h:addItem(test_file("d"), now)
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
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)
        h:addItem(test_file("c"), now)
        h:addItem(test_file("d"), now)
        h:addItem(test_file("e"), now)
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

    it("should reload the history file if it updated", function()
        -- Prepare a history.lua file with two items a and b.
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        local h = reload()
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)
        mv(file("history.lua"), file("history.backup"))

        h = reload()
        assert.is.same(0, #h.hist)
        mv(file("history.backup"), file("history.lua"))
        h:reload()

        assert.is.same(2, #h.hist)
        assert_item_is(h, 1, "a")
        assert_item_is(h, 2, "b")

        rm(test_file("a"))
        rm(test_file("b"))
    end)

    local function testAutoRemoveDeletedItems()
        -- Prepare a history.lua file with two items a and b.
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        local h = reload()
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)

        rm(test_file("a"))

        h:reload()
        assert.is.same(1, #h.hist)
        assert_item_is(h, 1, "b")

        rm(test_file("b"))
    end

    local function testDoNotAutoRemoveDeletedItems()
        -- Prepare a history.lua file with two items a and b.
        rm(file("history.lua"))
        touch(test_file("a"))
        touch(test_file("b"))
        local h = reload()
        now = now + 61
        h:addItem(test_file("a"), now)
        h:addItem(test_file("b"), now)

        rm(test_file("a"))

        h:reload()
        assert.is.same(2, #h.hist)
        assert_item_is(h, 1, "a", true)
        assert_item_is(h, 2, "b")

        rm(test_file("b"))
    end

    it("should automatically remove deleted items from history if setting has been set",
       function()
           G_reader_settings:saveSetting("autoremove_deleted_items_from_history", true)
           testAutoRemoveDeletedItems()
           G_reader_settings:delSetting("autoremove_deleted_items_from_history")
       end)

    it("should not automatically remove deleted items from history if setting has not been set",
       function()
           G_reader_settings:delSetting("autoremove_deleted_items_from_history")
           testDoNotAutoRemoveDeletedItems()
       end)

    it("should not automatically remove deleted items from history if setting has been set to false",
       function()
           G_reader_settings:saveSetting("autoremove_deleted_items_from_history", false)
           testDoNotAutoRemoveDeletedItems()
           G_reader_settings:delSetting("autoremove_deleted_items_from_history")
       end)
end)
