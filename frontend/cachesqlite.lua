--[[--
An SQLite-based cache implementation, with an interface similar to @{cache|Cache}.

Example:

    local CacheSQLite = require("cachesqlite")
    local cache = CacheSQLite:new{
        size = 1024 * 1024 * 10, -- 10 MB
        -- Set to :memory: for an in-memory database.
        -- In that case, set auto_close to false.
        db_path = "/path/to/cache.db",
    }
    cache:insert("key", {value = "data"})
    local data = cache:check("key")

@module cachesqlite
--]]

local Persist = require("persist")
local SQ3 = require("lua-ljsqlite3/init")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local CacheSQLite = {
    --- Max storage space, in bytes.
    size = nil,
    --- Database file path. Set to :memory: for an in-memory database.
    db_path = nil,
    --- Compression codec from Persist.
    codec = "zstd",
    --- Whether to automatically close the DB connection after each operation. Set to false for batch operations or when using :memory:.
    auto_close = true,
}

function CacheSQLite:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

local is_connected = false

function CacheSQLite:init()
    if self.db_path == ":memory:" and self.auto_close == true then
        logger.warn("CacheSQLite: using in-memory database, forcing auto_close = false")
        self.auto_close = false
    end
    self:openDB()

    -- Create cache table if it doesn't exist
    self.db:exec[[
        CREATE TABLE IF NOT EXISTS cache (
            key TEXT PRIMARY KEY,
            value BLOB,
            size INTEGER,
            last_access INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_last_access ON cache(last_access);
    ]]

    -- Initialize size tracking
    self.current_size = self.db:rowexec([[
        SELECT
            ROUND(page_count * page_size, 0) as db_size_bytes,
            ROUND((page_count - freelist_count) * page_size, 0) as data_size_bytes
        FROM pragma_page_count(),
            pragma_page_size(),
            pragma_freelist_count();
    ]]) or 0
    logger.dbg("CacheSQLite:", self.db_path, "current size:", self.current_size)
    self:closeDB()

    self._persist = Persist.getCodec(self.codec)
end

--- Opens the SQLite database.
--- This is normally done internally, but can be called manually if needed.
function CacheSQLite:openDB()
    if not is_connected then
        self.db = SQ3.open(self.db_path)
        is_connected = true
    end
end

--- Closes the SQLite database.
--- This is normally done internally, but can be called manually if needed.
--- @param[opt=false] explicit boolean When auto_close is false, this must be set to true to close the DB.
function CacheSQLite:closeDB(explicit)
    if is_connected and (self.auto_close or explicit) then
        self.db:close()
        is_connected = false
    end
end

--- Retrieves the connected state of the database.
--- This is normally done internally, but can be called manually if needed.
--- @return boolean
function CacheSQLite:isConnected()
    return is_connected
end

--- Inserts an object into the cache.
--- @param key string
--- @param object any
--- @return boolean success, number size
function CacheSQLite:insert(key, object)
    self:openDB()
    local codec = Persist.getCodec(self.codec)
    local size
    object, size = codec.serialize(object)
    if type(size) == "cdata" then
        size = tonumber(size)
    end
    if not size then
        size = #object
    end

    if not self:willAccept(size) then
        logger.warn("Too much memory would be claimed by caching", key)
        return false, 0
    end

    -- Ensure we have enough space by removing old entries
    while self.current_size + size > self.size do
        local oldest = self.db:rowexec([[
            SELECT key, size FROM cache
            ORDER BY last_access ASC LIMIT 1
        ]])
        if oldest then
            self:remove(oldest[1])
        else
            break
        end
    end

    local stmt = self.db:prepare([[
        INSERT OR REPLACE INTO cache (key, value, size, last_access)
        VALUES (?, ?, ?, ?);
    ]])
    local ok, err = pcall(function()
        stmt:reset():bind(key, object, size, UIManager:getTime()):step()
    end)
    if not ok and err then
        err = err:gsub("\n.*", "") -- remove stacktrace
        logger.err("CacheSQLite:insert() failed:", err)
    end

    self.current_size = self.current_size + size
    self:closeDB()
    return ok, size
end

--- Retrieves an object if it is in the cache and updates its access time.
--- @param key string
--- @return any
function CacheSQLite:check(key)
    self:openDB()
    -- Update access time and retrieve value
    local stmt = self.db:prepare([[
        UPDATE cache SET last_access = ? WHERE key = ?
        RETURNING value;
    ]])
    local row = stmt:reset():bind(UIManager:getTime(), key):step()
    self:closeDB()

    if row then
        return self._persist.deserialize(row[1])
    end
end

--- Retrieves an object if it is in the cache without updating its access time.
--- @param key string
--- @return any
function CacheSQLite:get(key)
    self:openDB()
    local stmt = self.db:prepare("SELECT value FROM cache WHERE key = ?")
    local row = stmt:reset():bind(key):step()
    self:closeDB()
    if row then
        return self._persist.deserialize(row[1])
    end
end

--- Removes an object from the cache.
function CacheSQLite:remove(key)
    self:openDB()
    local stmt = self.db:prepare("SELECT size FROM cache WHERE key = ?")
    local row = stmt:reset():bind(key):step()
    if row then
        self.current_size = self.current_size - row[1]
        local delete_stmt = self.db:prepare("DELETE FROM cache WHERE key = ?")
        delete_stmt:reset():bind(key):step()
    end
    self:closeDB()
end

--- Queries whether the cache will accept an object of a given size in bytes.
function CacheSQLite:willAccept(size)
    -- We only allow a single object to fill 50% of the cache
    return size*4 < self.size*2
end

--- Clears the entire cache.
function CacheSQLite:clear()
    self:openDB()
    self.db:exec("DELETE FROM cache")
    self.current_size = 0
    self:closeDB()
end

return CacheSQLite
