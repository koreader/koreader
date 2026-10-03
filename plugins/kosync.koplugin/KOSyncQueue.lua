local DataStorage = require("datastorage")
local Persist = require("persist")
local logger = require("logger")
local util = require("util")

local QUEUE_PATH = DataStorage:getSettingsDir() .. "/kosync_queue.lua"
local MAX_AGE = 28 * 24 * 3600 -- 4 weeks in seconds
local MAX_ENTRIES = 200 -- paranoia cap

local KOSyncQueue = {}

function KOSyncQueue:_storage()
    if not self._persist then
        self._persist = Persist:new{ path = QUEUE_PATH, codec = "dump" }
    end
    return self._persist
end

function KOSyncQueue:load()
    local storage = self:_storage()
    if not storage:exists() then return {} end
    local data, err = storage:load()
    if not data then
        logger.warn("KOSyncQueue: failed to load queue:", err)
        return {}
    end
    return data
end

function KOSyncQueue:save(queue)
    local ok, err = self:_storage():save(queue)
    if not ok then
        logger.warn("KOSyncQueue: failed to save queue:", err)
    end
end

--- Queue a failed progress update for later retry.
-- Keeps one entry per document per day (for statistics granularity).
-- Expires entries older than 4 weeks.
function KOSyncQueue:push(item)
    local queue = self:load()
    local now = os.time()
    item.queued_at = now

    local today = math.floor(now / 86400)

    -- Filter: expire old entries, deduplicate same document+same day
    local filtered = {}
    for _, entry in ipairs(queue) do
        local dominated = entry.document == item.document
            and math.floor((entry.queued_at or 0) / 86400) == today
        if (now - (entry.queued_at or 0)) < MAX_AGE and not dominated then
            table.insert(filtered, entry)
        end
    end

    table.insert(filtered, item)

    -- Paranoia cap: drop oldest
    while #filtered > MAX_ENTRIES do
        table.remove(filtered, 1)
    end

    self:save(filtered)
    logger.dbg("KOSyncQueue: queued progress for", item.document, "total:", #filtered)
end

--- Attempt to send all queued items in order, stopping on the first failure.
-- @param send_func function(item, callback): reports success through callback(bool)
-- @param done_func optional function(sent): called when the drain finishes
function KOSyncQueue:drain(send_func, done_func)
    -- Network events may arrive while an asynchronous request is still in flight.
    if self._draining then return end
    local queue = self:load()
    if #queue == 0 then
        if done_func then done_func(0) end
        return
    end
    self._draining = true

    logger.info("KOSyncQueue: draining", #queue, "queued items")
    local sent = 0

    local function finish()
        self._draining = nil
        logger.info("KOSyncQueue: sent", sent, ", remaining", self:count())
        if done_func then done_func(sent) end
    end

    local function findItem(current, item)
        for i, entry in ipairs(current) do
            -- Compare the contents too: a same-day replacement can have the same
            -- document and queued_at when it was queued within the same second.
            if util.tableEquals(entry, item) then return i end
        end
    end

    local function sendNext(i)
        local item = queue[i]
        if not item then
            finish()
            return
        end
        -- Do not send snapshot entries that have since been replaced or cleared.
        if not findItem(self:load(), item) then
            sendNext(i + 1)
            return
        end
        local completed = false
        local function callback(ok)
            if completed then return end
            completed = true
            if not ok then
                finish()
                return
            end
            -- Reload after the request: pushes may have changed the queue in flight.
            local current = self:load()
            local index = findItem(current, item)
            if index then
                table.remove(current, index)
                self:save(current)
            end
            sent = sent + 1
            sendNext(i + 1)
        end
        local ok, err = pcall(send_func, item, callback)
        if not ok then
            logger.warn("KOSyncQueue: failed to send queued progress:", err)
            callback(false)
        end
    end

    sendNext(1)
end

function KOSyncQueue:count()
    return #self:load()
end

function KOSyncQueue:clear()
    self:save({})
end

return KOSyncQueue
