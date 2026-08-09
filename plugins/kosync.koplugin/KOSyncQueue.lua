local DataStorage = require("datastorage")
local Persist = require("persist")
local logger = require("logger")

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

--- Attempt to send all queued items in order.
-- @param send_func function(item) -> bool: sends one item, returns true on success
-- @return number of successfully sent items
function KOSyncQueue:drain(send_func)
    local queue = self:load()
    if #queue == 0 then return 0 end

    logger.info("KOSyncQueue: draining", #queue, "queued items")
    local sent = 0

    for i, item in ipairs(queue) do
        if send_func(item) then
            sent = sent + 1
        else
            -- Server still unreachable, keep remaining items
            local remaining = {}
            for j = i, #queue do
                table.insert(remaining, queue[j])
            end
            self:save(remaining)
            logger.info("KOSyncQueue: sent", sent, ", remaining", #remaining)
            return sent
        end
    end

    -- All sent
    self:save({})
    logger.info("KOSyncQueue: sent all", sent, "items")
    return sent
end

function KOSyncQueue:count()
    return #self:load()
end

function KOSyncQueue:clear()
    self:save({})
end

return KOSyncQueue
