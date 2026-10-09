describe("DictPrefetch module", function()
    local DictPrefetch
    local DataStorage
    local ffiutil
    local lfs
    local root

    local function mkfile(path, size)
        local f = io.open(path, "wb")
        f:write(string.rep("x", size))
        f:close()
    end

    local function names(files)
        local t = {}
        for _, f in ipairs(files) do
            table.insert(t, f.path:sub(#root + 2))
        end
        return t
    end

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        ffiutil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        DictPrefetch = require("dictprefetch")

        root = ffiutil.joinPath(DataStorage:getDataDir(), "dictprefetch_test")
        ffiutil.purgeDir(root)
        lfs.mkdir(root)
        for _, dir in ipairs({ "dict", "dict/a", "dict/b", "dict/.hidden", "dict_ext", "dict_ext/c" }) do
            lfs.mkdir(root .. "/" .. dir)
        end
        mkfile(root .. "/dict/a/a.ifo", 300)
        mkfile(root .. "/dict/a/a.idx", 20000)
        mkfile(root .. "/dict/a/a.idx.oft", 5000)
        mkfile(root .. "/dict/a/a.dict.dz", 90000)
        mkfile(root .. "/dict/a/a.css", 9000)
        mkfile(root .. "/dict/b/b.ifo", 200)
        mkfile(root .. "/dict/b/b.idx", 8000)
        mkfile(root .. "/dict/b/b.syn", 60000)
        mkfile(root .. "/dict/b/b.syn.oft", 6000)
        mkfile(root .. "/dict/b/b.dict", 50000)
        mkfile(root .. "/dict/.hidden/h.idx", 7000)
        mkfile(root .. "/dict_ext/c/c.ifo", 100)
        mkfile(root .. "/dict_ext/c/c.idx", 12000)
        mkfile(root .. "/dict_ext/c/c.dict.dz", 40000)
    end)

    teardown(function()
        ffiutil.purgeDir(root)
    end)

    local function dirs()
        return { root .. "/dict", root .. "/dict_ext" }
    end

    it("should read the tail of every dictionary file, smallest first", function()
        local tails = DictPrefetch.listFiles(dirs(), 1e9)
        assert.are.same({
            "dict/a/a.idx.oft", "dict/b/b.syn.oft", "dict/b/b.idx", "dict_ext/c/c.idx",
            "dict/a/a.idx", "dict_ext/c/c.dict.dz", "dict/b/b.dict", "dict/b/b.syn",
            "dict/a/a.dict.dz",
        }, names(tails))
    end)

    it("should read the small files in full, offset tables first", function()
        local _, full = DictPrefetch.listFiles(dirs(), 1e9)
        assert.are.same({
            "dict/b/b.syn.oft", "dict/a/a.idx.oft",
            "dict/a/a.ifo", "dict/b/b.ifo", "dict_ext/c/c.ifo",
            "dict/a/a.idx", "dict_ext/c/c.idx", "dict/b/b.idx",
            "dict/b/b.syn",
        }, names(full))
    end)

    it("should skip what does not fit the budget, not stop there", function()
        -- 11000 bytes of offset tables, then 600 of .ifo: the 20000 bytes .idx
        -- does not fit, the smaller ones behind it do.
        local _, full = DictPrefetch.listFiles(dirs(), 11600 + 8000)
        assert.are.same({
            "dict/b/b.syn.oft", "dict/a/a.idx.oft",
            "dict/a/a.ifo", "dict/b/b.ifo", "dict_ext/c/c.ifo",
            "dict/b/b.idx",
        }, names(full))
    end)

    it("should read 4 kB per tail and whole files", function()
        local tails, full = DictPrefetch.listFiles(dirs(), 11600)
        assert.are.same(#tails * 4096 + 11600, DictPrefetch.warm(tails, full))
    end)

    it("should not fail on missing directories", function()
        local tails, full = DictPrefetch.listFiles({ root .. "/nope" }, 1e9)
        assert.are.same({}, tails)
        assert.are.same({}, full)
    end)

    it("should run in a subprocess, once, and stop", function()
        DictPrefetch:start(dirs())
        local pid = DictPrefetch.pid
        assert.is_not_nil(pid)
        DictPrefetch:start(dirs())
        assert.are.same(pid, DictPrefetch.pid)
        DictPrefetch:stop()
        assert.is_nil(DictPrefetch.pid)
        assert.is_false(DictPrefetch:stop())
        -- It must get collected, not left as a zombie.
        local deadline = os.time() + 10
        while not ffiutil.isSubProcessDone(pid) and os.time() < deadline do
            ffiutil.usleep(10000)
        end
        assert.is_true(ffiutil.isSubProcessDone(pid))
    end)
end)
