describe("CacheSQLite module", function()
    local CacheSQLite
    local cache
    describe("CacheSQLite on disk", function()
        setup(function()
            require("commonrequire")
            CacheSQLite = require("cachesqlite")
            cache = CacheSQLite:new{
                db_path = "test.db",
                size = 1024 * 1024 * 1024,
            }
        end)
        after_each(function()
            cache:clear()
            cache.size = 1024 * 1024 * 1024
        end)

        it("should clear cache", function()
            cache:clear()
        end)

        it("should insert and get", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            local deserialized = cache:get("test")
            assert.are.same(object, deserialized)
        end)

        it("should remove object", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            cache:remove("test")
            local deserialized = cache:get("test")
            assert.is_nil(deserialized)
        end)

        it("should accept regular object", function()
            assert.is_true(cache:willAccept(100))
            cache.size = 1024
            assert.is_true(cache:insert("test", {a = 1, b = 2}))
        end)

        it("should reject giant object", function()
            assert.is_false(cache:willAccept(1024 * 1024 * 1024))
            cache.size = 10
            assert.is_false(cache:insert("test", {a = 1, b = 2}))
        end)
    end)

    describe("CacheSQLite in memory", function()
        setup(function()
            require("commonrequire")
            CacheSQLite = require("cachesqlite")
            cache = CacheSQLite:new{
                db_path = ":memory:",
                auto_close = false,
                size = 1024 * 1024 * 1024,
            }
        end)
        after_each(function()
            cache:clear()
            cache.size = 1024 * 1024 * 1024
        end)

        it("should clear cache", function()
            cache:clear()
        end)

        it("should insert and get", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            local deserialized = cache:get("test")
            assert.are.same(object, deserialized)
        end)

        it("should remove object", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            cache:remove("test")
            local deserialized = cache:get("test")
            assert.is_nil(deserialized)
        end)

        it("should accept regular object", function()
            assert.is_true(cache:willAccept(100))
            cache.size = 1024
            assert.is_true(cache:insert("test", {a = 1, b = 2}))
        end)

        it("should reject giant object", function()
            assert.is_false(cache:willAccept(1024 * 1024 * 1024))
            cache.size = 10
            assert.is_false(cache:insert("test", {a = 1, b = 2}))
        end)
    end)
end)
