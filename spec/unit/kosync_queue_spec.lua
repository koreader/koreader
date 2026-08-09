describe("KOSyncQueue module", function()
    local KOSyncQueue
    local orig_time

    setup(function()
        require("commonrequire")
        package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
        KOSyncQueue = require("KOSyncQueue")
    end)

    before_each(function()
        KOSyncQueue:clear()
        orig_time = os.time -- luacheck: ignore
    end)

    after_each(function()
        KOSyncQueue:clear()
        os.time = orig_time -- luacheck: ignore
    end)

    it("should start with an empty queue", function()
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should push and persist an item", function()
        KOSyncQueue:push({
            document = "abc123",
            progress = "100",
            percentage = 0.5,
            device = "TestDevice",
            device_id = "dev-1",
        })
        assert.are.equal(1, KOSyncQueue:count())
    end)

    it("should deduplicate same document on same day", function()
        KOSyncQueue:push({
            document = "abc123",
            progress = "100",
            percentage = 0.5,
            device = "TestDevice",
            device_id = "dev-1",
        })
        KOSyncQueue:push({
            document = "abc123",
            progress = "200",
            percentage = 0.75,
            device = "TestDevice",
            device_id = "dev-1",
        })
        assert.are.equal(1, KOSyncQueue:count())
        local queue = KOSyncQueue:load()
        assert.are.equal("200", queue[1].progress)
    end)

    it("should keep entries from different days for same document", function()
        -- Push an entry "from yesterday"
        local yesterday = os.time() - 86400
        os.time = function() return yesterday end -- luacheck: ignore
        KOSyncQueue:push({
            document = "abc123",
            progress = "100",
            percentage = 0.5,
            device = "TestDevice",
            device_id = "dev-1",
        })
        -- Push an entry "today"
        os.time = orig_time -- luacheck: ignore
        KOSyncQueue:push({
            document = "abc123",
            progress = "200",
            percentage = 0.75,
            device = "TestDevice",
            device_id = "dev-1",
        })
        assert.are.equal(2, KOSyncQueue:count())
    end)

    it("should keep different documents on same day", function()
        KOSyncQueue:push({
            document = "book1",
            progress = "100",
            percentage = 0.5,
            device = "TestDevice",
            device_id = "dev-1",
        })
        KOSyncQueue:push({
            document = "book2",
            progress = "50",
            percentage = 0.25,
            device = "TestDevice",
            device_id = "dev-1",
        })
        assert.are.equal(2, KOSyncQueue:count())
    end)

    it("should expire entries older than 4 weeks", function()
        -- Push an entry "5 weeks ago"
        local old = os.time() - (35 * 86400)
        os.time = function() return old end -- luacheck: ignore
        KOSyncQueue:push({
            document = "old_book",
            progress = "100",
            percentage = 0.5,
            device = "TestDevice",
            device_id = "dev-1",
        })
        -- Push a new entry (triggers expiry filter)
        os.time = orig_time -- luacheck: ignore
        KOSyncQueue:push({
            document = "new_book",
            progress = "50",
            percentage = 0.25,
            device = "TestDevice",
            device_id = "dev-1",
        })
        assert.are.equal(1, KOSyncQueue:count())
        local queue = KOSyncQueue:load()
        assert.are.equal("new_book", queue[1].document)
    end)

    it("should drain successfully", function()
        KOSyncQueue:push({ document = "a", progress = "1", percentage = 0.1, device = "D", device_id = "d1" })
        KOSyncQueue:push({ document = "b", progress = "2", percentage = 0.2, device = "D", device_id = "d1" })

        local sent = KOSyncQueue:drain(function() return true end)
        assert.are.equal(2, sent)
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should stop draining on first failure and keep remaining", function()
        KOSyncQueue:push({ document = "a", progress = "1", percentage = 0.1, device = "D", device_id = "d1" })
        KOSyncQueue:push({ document = "b", progress = "2", percentage = 0.2, device = "D", device_id = "d1" })
        KOSyncQueue:push({ document = "c", progress = "3", percentage = 0.3, device = "D", device_id = "d1" })

        local call_count = 0
        local sent = KOSyncQueue:drain(function()
            call_count = call_count + 1
            return call_count <= 1 -- first succeeds, second fails
        end)
        assert.are.equal(1, sent)
        assert.are.equal(2, KOSyncQueue:count())
    end)

    it("should clear the queue", function()
        KOSyncQueue:push({ document = "a", progress = "1", percentage = 0.1, device = "D", device_id = "d1" })
        KOSyncQueue:clear()
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should respect the hard cap", function()
        for i = 1, 210 do
            -- Different documents to avoid dedup
            KOSyncQueue:push({
                document = "book_" .. i,
                progress = tostring(i),
                percentage = i / 210,
                device = "D",
                device_id = "d1",
            })
        end
        assert.is_true(KOSyncQueue:count() <= 200)
    end)
end)
