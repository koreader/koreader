describe("bookmarks_sync store", function()
    local SyncDB, DataStorage, util, lfs, purgeDir
    local root, device_id, sample_a, sample_b

    local function writeBytes(path, data)
        local dir = path:match("(.+)/[^/]+$")
        if dir then
            util.makePath(dir)
        end
        local f = assert(io.open(path, "wb"))
        f:write(data)
        f:close()
    end

    setup(function()
        require("commonrequire")
        package.path = "plugins/bookmarks_sync.koplugin/?.lua;" .. package.path
        SyncDB = require("sync_db")
        DataStorage = require("datastorage")
        util = require("util")
        lfs = require("libs/libkoreader-lfs")
        purgeDir = require("ffi/util").purgeDir
        device_id = "test-device"
    end)

    before_each(function()
        root = DataStorage:getDataDir() .. "/bookmarks_sync_test_root"
        purgeDir(root)
        util.makePath(root)
        G_reader_settings:delSetting("bookmarks_sync_pending")
        G_reader_settings:delSetting("bookmarks_sync_log_cursor")
        G_reader_settings:delSetting("bookmarks_sync_shared_path")

        sample_a = DataStorage:getDataDir() .. "/bookmarks_sync_sample_a.epub"
        sample_b = DataStorage:getDataDir() .. "/bookmarks_sync_sample_b.epub"
        writeBytes(sample_a, "book-bytes-version-one-" .. string.rep("A", 4096))
        writeBytes(sample_b, "book-bytes-version-two-" .. string.rep("B", 4096))
    end)

    after_each(function()
        purgeDir(root)
        os.remove(sample_a)
        os.remove(sample_b)
    end)

    it("normalizes book names", function()
        assert.are.equal("война и мир", SyncDB.normalizeName("Война и мир"))
        assert.are.equal("война и мир", SyncDB.normalizeName("Война  и   мир (1)"))
        assert.are.equal("елка", SyncDB.normalizeName("Ёлка"))
        assert.are.equal("book", SyncDB.getBaseName("/tmp/Book.EPUB"))
    end)

    it("sanitizes mark ids for filenames", function()
        assert.are.equal("2024-01-02_03-04-05", SyncDB.safeMarkId("2024-01-02 03:04:05"))
    end)

    it("merges loc slots without replacing existing ones", function()
        local dst = {
            fp1 = { format = "epub", pos0 = "a" },
        }
        local src = {
            fp1 = { format = "epub", pos0 = "other", page = 3 },
            fp2 = { format = "pdf", pos0 = "b" },
        }
        local merged = SyncDB.mergeLoc(dst, src)
        assert.are.equal("a", merged.fp1.pos0)
        assert.are.equal(3, merged.fp1.page)
        assert.are.equal("b", merged.fp2.pos0)
    end)

    it("detects content field conflicts", function()
        local a = { exact = "hello", notes = "n1", color = "red" }
        local b = { exact = "hello", notes = "n2", color = "red" }
        assert.is_true(SyncDB.fieldsDiffer(a, b, { "exact", "notes", "color" }))
        assert.is_false(SyncDB.fieldsDiffer(a, a, { "exact", "notes", "color" }))
    end)

    it("parses journal names and sync-conflict variants", function()
        local num, device = SyncDB.parseLogName("12")
        assert.are.equal(12, num)
        assert.is_nil(device)

        num, device = SyncDB.parseLogName("12-abc")
        assert.are.equal(12, num)
        assert.are.equal("abc", device)

        num = SyncDB.parseLogName("12.sync-conflict-20240101-120000-ABCDEF")
        assert.are.equal(12, num)
    end)

    it("resolves the same book_id for same bytes and same name", function()
        local id1, fp1 = SyncDB.resolveBook(sample_a, device_id, root)
        assert.is_truthy(id1)
        assert.is_truthy(fp1)

        local renamed = DataStorage:getDataDir() .. "/War and Peace.epub"
        writeBytes(renamed, "book-bytes-version-one-" .. string.rep("A", 4096))
        local id2, fp2 = SyncDB.resolveBook(renamed, device_id, root)
        assert.are.equal(id1, id2)
        assert.are.equal(fp1, fp2)
        os.remove(renamed)
    end)

    it("keeps one book_id for a new edition with the same name", function()
        local path1 = DataStorage:getDataDir() .. "/Same Title.epub"
        local path2 = DataStorage:getDataDir() .. "/Same Title.pdf"
        writeBytes(path1, "edition-one-" .. string.rep("1", 4096))
        writeBytes(path2, "edition-two-" .. string.rep("2", 4096))

        local id1, fp1 = SyncDB.resolveBook(path1, device_id, root)
        local id2, fp2, _, is_new_fp = SyncDB.resolveBook(path2, device_id, root)
        assert.are.equal(id1, id2)
        assert.are_not.equal(fp1, fp2)
        assert.is_true(is_new_fp)

        os.remove(path1)
        os.remove(path2)
    end)

    it("writes marks, gone and back using journal numbers", function()
        local book_id = SyncDB.resolveBook(sample_a, device_id, root)
        local mark_id = "2024-01-02 03:04:05"
        assert.is_true(SyncDB.upsertMarkFromAnnotation(root, book_id, {
            datetime = mark_id,
            exact = "quote",
            notes = "note",
            color = "yellow",
            loc = { fpA = { format = "epub", pos0 = "x" } },
        }, device_id))

        local mark = SyncDB.readMark(root, book_id, mark_id)
        assert.are.equal("quote", mark.exact)
        assert.are.equal("x", mark.loc.fpA.pos0)

        assert.is_false(SyncDB.isMarkGone(root, book_id, mark_id))
        local gone_num = SyncDB.markGone(root, book_id, mark_id, device_id)
        assert.is_true(gone_num > 0)
        assert.is_true(SyncDB.isMarkGone(root, book_id, mark_id))

        local back_num = SyncDB.markBack(root, book_id, mark_id, device_id)
        assert.is_true(back_num > gone_num)
        assert.is_false(SyncDB.isMarkGone(root, book_id, mark_id))
    end)

    it("treats equal gone and back numbers as ambiguous", function()
        local book_id = SyncDB.resolveBook(sample_a, device_id, root)
        local mark_id = "2024-05-06 07:08:09"
        SyncDB.upsertMarkFromAnnotation(root, book_id, {
            datetime = mark_id,
            exact = "ambiguous",
        }, device_id)

        -- Create gone/back files with the same explicit journal stamp.
        util.makePath(SyncDB.goneDir(root, book_id))
        util.makePath(SyncDB.backDir(root, book_id))
        local safe = SyncDB.safeMarkId(mark_id)
        SyncDB.touchLink(SyncDB.goneDir(root, book_id) .. "/" .. safe .. "--10")
        SyncDB.touchLink(SyncDB.backDir(root, book_id) .. "/" .. safe .. "--10")
        assert.is_nil(SyncDB.isMarkGone(root, book_id, mark_id))
    end)

    it("tracks seen and reanchor needs per fingerprint", function()
        local book_id, fp = SyncDB.resolveBook(sample_a, device_id, root)
        local mark_id = "2024-09-09 09:09:09"
        SyncDB.upsertMarkFromAnnotation(root, book_id, {
            datetime = mark_id,
            exact = "need-anchor",
        }, device_id)

        assert.is_true(SyncDB.needsReanchor(root, book_id, mark_id, device_id, fp))
        SyncDB.markSeen(root, book_id, mark_id, device_id, fp)
        assert.is_false(SyncDB.needsReanchor(root, book_id, mark_id, device_id, fp))

        SyncDB.markBack(root, book_id, mark_id, device_id)
        assert.is_true(SyncDB.needsReanchor(root, book_id, mark_id, device_id, fp))
    end)

    it("appends monotonic journal numbers", function()
        local n1 = SyncDB.appendJournal(root, "by-fp/abc/id1", device_id)
        local n2 = SyncDB.appendJournal(root, "by-name/book/id1", device_id)
        assert.are.equal(1, n1)
        assert.are.equal(2, n2)
        assert.are.equal(2, SyncDB.getMaxJournalNumber(root))
    end)

    it("finds syncthing conflict copies beside a mark file", function()
        local book_id = "book-1"
        local rel = "book/" .. book_id .. "/mark/2024-01-01_00-00-00.lua"
        local mark_path = root .. "/" .. rel
        util.makePath(mark_path:match("(.+)/[^/]+$"))
        SyncDB.writeLua(mark_path, { datetime = "2024-01-01 00:00:00", exact = "main" })
        local conflict = root .. "/book/" .. book_id .. "/mark/2024-01-01_00-00-00.sync-conflict-20240101-120000-ABCDEF.lua"
        SyncDB.writeLua(conflict, { datetime = "2024-01-01 00:00:00", exact = "other" })

        local copies = SyncDB.findConflictCopies(root, rel)
        assert.are.equal(1, #copies)
        assert.are.equal(conflict, copies[1])
    end)

    it("does not rewrite an unchanged mark into the journal", function()
        local book_id = SyncDB.resolveBook(sample_a, device_id, root)
        local before = SyncDB.getMaxJournalNumber(root)
        local mark = {
            datetime = "2024-11-11 11:11:11",
            exact = "stable",
            loc = { fp = { format = "epub", pos0 = "p" } },
        }
        SyncDB.upsertMarkFromAnnotation(root, book_id, mark, device_id)
        local after_first = SyncDB.getMaxJournalNumber(root)
        assert.is_true(after_first > before)
        SyncDB.upsertMarkFromAnnotation(root, book_id, mark, device_id)
        assert.are.equal(after_first, SyncDB.getMaxJournalNumber(root))
    end)
end)
