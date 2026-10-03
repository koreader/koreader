describe("KOSyncQueue module", function()
    local KOSyncQueue
    local orig_time
    local client_stub
    local schedule_stub

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
        if client_stub then
            client_stub:revert()
            client_stub = nil
        end
        if schedule_stub then
            schedule_stub:revert()
            schedule_stub = nil
        end
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

        local sent
        KOSyncQueue:drain(function(_, callback) callback(true) end, function(count) sent = count end)
        assert.are.equal(2, sent)
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should stop draining on first failure and keep remaining", function()
        KOSyncQueue:push({ document = "a", progress = "1", percentage = 0.1, device = "D", device_id = "d1" })
        KOSyncQueue:push({ document = "b", progress = "2", percentage = 0.2, device = "D", device_id = "d1" })
        KOSyncQueue:push({ document = "c", progress = "3", percentage = 0.3, device = "D", device_id = "d1" })

        local call_count = 0
        local sent
        KOSyncQueue:drain(function(_, callback)
            call_count = call_count + 1
            callback(call_count <= 1) -- first succeeds, second fails
        end, function(count) sent = count end)
        assert.are.equal(1, sent)
        assert.are.equal(2, KOSyncQueue:count())
    end)

    it("should wait for callbacks and retain a failed item for retry", function()
        KOSyncQueue:push({ document = "a", progress = "1" })
        KOSyncQueue:push({ document = "b", progress = "2" })
        KOSyncQueue:push({ document = "c", progress = "3" })
        local pending, sent
        local documents = {}
        local function send(item, callback)
            table.insert(documents, item.document)
            pending = callback
        end
        KOSyncQueue:drain(send, function(count) sent = count end)
        assert.are.same({ "a" }, documents)
        assert.are.equal(3, KOSyncQueue:count())
        assert.is_nil(sent)

        pending(true)
        assert.are.same({ "a", "b" }, documents)
        assert.are.equal(2, KOSyncQueue:count())
        assert.is_nil(sent)
        pending(false)
        assert.are.equal(1, sent)
        assert.are.same({ "a", "b" }, documents)
        assert.are.equal("b", KOSyncQueue:load()[1].document)

        KOSyncQueue:drain(send, function(count) sent = count end)
        assert.are.same({ "a", "b", "b" }, documents)
        pending(true)
        assert.are.same({ "a", "b", "b", "c" }, documents)
        pending(true)
        assert.are.equal(2, sent)
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should keep additions made during a successful drain", function()
        KOSyncQueue:push({ document = "a", progress = "1" })
        local pending
        KOSyncQueue:drain(function(_, callback) pending = callback end)
        KOSyncQueue:push({ document = "b", progress = "2" })
        pending(true)
        assert.are.equal(1, KOSyncQueue:count())
        assert.are.equal("b", KOSyncQueue:load()[1].document)
    end)

    it("should keep additions made during a failed drain", function()
        KOSyncQueue:push({ document = "a", progress = "1" })
        local pending
        KOSyncQueue:drain(function(_, callback) pending = callback end)
        KOSyncQueue:push({ document = "b", progress = "2" })
        pending(false)
        assert.are.equal(2, KOSyncQueue:count())
    end)

    it("should keep same-second replacements of an in-flight item", function()
        local now = os.time()
        os.time = function() return now end -- luacheck: ignore
        KOSyncQueue:push({ document = "a", progress = "1", metadata = { title = "Old" } })
        local pending
        KOSyncQueue:drain(function(_, callback) pending = callback end)
        KOSyncQueue:push({ document = "a", progress = "1", metadata = { title = "New" } })
        pending(true)
        assert.are.equal(1, KOSyncQueue:count())
        assert.are.equal("New", KOSyncQueue:load()[1].metadata.title)
    end)

    it("should skip snapshot items replaced before their turn", function()
        KOSyncQueue:push({ document = "a", progress = "1" })
        KOSyncQueue:push({ document = "b", progress = "2" })
        local pending
        local documents = {}
        KOSyncQueue:drain(function(item, callback)
            table.insert(documents, item.document)
            pending = callback
        end)
        KOSyncQueue:push({ document = "b", progress = "3" })
        pending(true)
        assert.are.same({ "a" }, documents)
        assert.are.equal("3", KOSyncQueue:load()[1].progress)
    end)

    it("should ignore overlapping drains", function()
        KOSyncQueue:push({ document = "a", progress = "1" })
        local pending
        KOSyncQueue:drain(function(_, callback) pending = callback end)
        KOSyncQueue:drain(function() error("duplicate send") end)
        assert.are.equal(1, KOSyncQueue:count())
        pending(true)
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should retain items when sending throws and allow another drain", function()
        KOSyncQueue:push({ document = "a", progress = "1" })
        local sent
        KOSyncQueue:drain(function() error("request setup failed") end, function(count) sent = count end)
        assert.are.equal(0, sent)
        assert.are.equal(1, KOSyncQueue:count())
        KOSyncQueue:drain(function(_, callback) callback(true) end)
        assert.are.equal(0, KOSyncQueue:count())
    end)

    it("should complete an empty drain without sending", function()
        local sent
        KOSyncQueue:drain(function() error("empty queue") end, function(count) sent = count end)
        assert.are.equal(0, sent)
    end)

    it("should retain an upload failure reported by KOSyncClient", function()
        local KOSync = dofile("plugins/kosync.koplugin/main.lua")
        local KOSyncClient = require("KOSyncClient")
        local client = KOSyncClient:new{
            init = function() end,
            client = {
                reset_middlewares = function() end,
                enable = function() end,
                update_progress = function() error("503 not expected") end,
            },
        }
        client_stub = stub(KOSyncClient, "new", function() return client end)
        local sync = setmetatable({ settings = {}, path = "plugins/kosync.koplugin" }, { __index = KOSync })
        KOSyncQueue:push({ document = "a", progress = "1" })
        sync:drainQueue()
        assert.are.equal(1, KOSyncQueue:count())
        assert.are.equal("a", KOSyncQueue:load()[1].document)
    end)

    it("should pull progress only after queued uploads complete", function()
        local KOSync = dofile("plugins/kosync.koplugin/main.lua")
        local KOSyncClient = require("KOSyncClient")
        local UIManager = require("ui/uimanager")
        local scheduled, pending
        schedule_stub = stub(UIManager, "scheduleIn", function(_, _, callback) scheduled = callback end)
        client_stub = stub(KOSyncClient, "new", function()
            return {
                update_progress = function(_, username, userkey, document, metadata, progress, percentage, device, device_id, callback)
                    assert.are.equal("user", username)
                    assert.are.equal("key", userkey)
                    assert.are.equal("a", document)
                    pending = callback
                end,
            }
        end)
        local pulls = 0
        local sync = setmetatable({
            settings = { username = "user", userkey = "key" },
            path = "plugins/kosync.koplugin",
            getProgress = function() pulls = pulls + 1 end,
        }, { __index = KOSync })
        KOSyncQueue:push({ document = "a", progress = "1" })
        sync:_onNetworkConnected()
        scheduled()
        assert.are.equal(0, pulls)
        pending(true)
        assert.are.equal(1, pulls)
        assert.are.equal(0, KOSyncQueue:count())

        sync:_onNetworkConnected()
        scheduled()
        assert.are.equal(2, pulls)
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
