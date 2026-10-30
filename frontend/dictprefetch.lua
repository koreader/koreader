--[[--
Warms the dictionary files sdcv reads back into the page cache after a wake-up.

Suspend drops the page cache, so the first lookup after a wake-up has to get
everything sdcv touches back from storage. On a FAT-formatted user partition
(Kindle, Kobo, ...) most of that is not dictionary data but filesystem metadata:
to reach an offset in a file, the kernel walks the file's cluster chain from its
start, and on cold storage every step of that walk is its own small read. A word
near the end of a 500 MB `.dict.dz` costs around a thousand reads before sdcv gets
a single byte of the definition. The storage is also at its slowest right after a
wake-up, so this is where the multi-second first lookup comes from.

Nothing sdcv does can avoid that walk, and sdcv only runs once a word has been
tapped. So we do it ourselves, in the background, right after a wake-up:

1. read the last 4 kB of every dictionary file, which walks (and so caches) its
   whole cluster chain for very little I/O;
2. read the small, always-used files (`.oft`, `.ifo`, `.idx`, `.syn`) in full,
   within a byte budget.

All of it runs in a subprocess, as a single read can block for seconds on cold
storage. A lookup stops it (we never want to compete with the read the user is
waiting for) and it is restarted once the lookup is done: whatever it already
read is still cached, so the restart only costs what was left.

@module dictprefetch
]]

local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")

-- The files sdcv may read during a lookup.
local DICT_FILES = { "%.ifo$", "%.idx$", "%.idx%.gz$", "%.oft$", "%.syn$", "%.dict$", "%.dict%.dz$" }
-- The ones worth reading in full, most valuable first.
local FULL_READ = { "%.oft$", "%.ifo$", "%.idx$", "%.syn$" }

local TAIL_BYTES = 4096
local CHUNK_BYTES = 128 * 1024
local MAX_DIR_ENTRIES = 4000

local DictPrefetch = {
    -- Budget for the full reads; the tail reads are always done.
    max_full_read_bytes = 24 * 1024 * 1024,
    -- How often we check whether the subprocess is done.
    poll_interval_s = 1,
    pid = nil,
    dirs = nil,
}

local function matchesAny(name, patterns)
    for i, pattern in ipairs(patterns) do
        if name:match(pattern) then return i end
    end
end

local function collect(dir, files, budget)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for name in iter, dir_obj do
        budget.entries = budget.entries - 1
        if budget.entries <= 0 then return end
        -- Like sdcv, ignore hidden entries.
        if name:sub(1, 1) ~= "." then
            local path = dir .. "/" .. name
            local attr = lfs.attributes(path)
            if attr and attr.mode == "directory" then
                collect(path, files, budget)
            elseif attr and attr.mode == "file" and matchesAny(name:lower(), DICT_FILES) then
                table.insert(files, { path = path, name = name:lower(), size = attr.size })
            end
        end
    end
end

--[[--
Lists what to read in the dictionary directories.

@tparam table dirs dictionary directories
@int max_full_read_bytes budget for the full reads
@treturn table files whose last 4 kB to read, smallest first
@treturn table files to read in full, most valuable first
]]
function DictPrefetch.listFiles(dirs, max_full_read_bytes)
    local files, budget = {}, { entries = MAX_DIR_ENTRIES }
    for _, dir in ipairs(dirs) do
        collect(dir, files, budget)
    end

    local tails = {}
    for _, f in ipairs(files) do
        if f.size > TAIL_BYTES then
            table.insert(tails, f)
        end
    end
    -- The walk costs more the bigger the file: do the cheap ones first, so that
    -- a lookup interrupting us finds as many dictionaries ready as possible.
    table.sort(tails, function(a, b) return a.size < b.size end)

    local candidates = {}
    for _, f in ipairs(files) do
        f.rank = matchesAny(f.name, FULL_READ)
        if f.rank then
            table.insert(candidates, f)
        end
    end
    table.sort(candidates, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.size > b.size
    end)
    -- Skip what does not fit rather than stopping, so that a single huge .syn
    -- does not crowd out the small files behind it.
    local full, total = {}, 0
    for _, f in ipairs(candidates) do
        if total + f.size <= max_full_read_bytes then
            total = total + f.size
            table.insert(full, f)
        end
    end
    return tails, full
end

--[[--
Reads the files, throwing the data away: what we are after is the page cache.

@treturn int bytes read
]]
function DictPrefetch.warm(tails, full)
    local read_bytes = 0
    for _, f in ipairs(tails) do
        local fd = io.open(f.path, "rb")
        if fd then
            if fd:seek("set", f.size - TAIL_BYTES) then
                local data = fd:read(TAIL_BYTES)
                read_bytes = read_bytes + (data and #data or 0)
            end
            fd:close()
        end
    end
    for _, f in ipairs(full) do
        local fd = io.open(f.path, "rb")
        if fd then
            while true do
                local data = fd:read(CHUNK_BYTES)
                if not data then break end
                read_bytes = read_bytes + #data
            end
            fd:close()
        end
    end
    return read_bytes
end

function DictPrefetch:_poll()
    if not self.pid then return end
    if ffiutil.isSubProcessDone(self.pid) then
        logger.dbg("DictPrefetch: subprocess", self.pid, "done")
        self.pid = nil
        return
    end
    UIManager:scheduleIn(self.poll_interval_s, self._poll_func)
end

--[[--
Starts warming the given dictionary directories in a subprocess, unless it is
already running.
]]
function DictPrefetch:start(dirs)
    if self.pid then return end
    self.dirs = dirs
    local max_full_read_bytes = self.max_full_read_bytes
    -- The directory walk is done in the subprocess too: on cold storage it is
    -- not free either.
    local pid = ffiutil.runInSubProcess(function()
        local start_time = time.now()
        local tails, full = DictPrefetch.listFiles(dirs, max_full_read_bytes)
        local read_bytes = DictPrefetch.warm(tails, full)
        logger.info(string.format("DictPrefetch: read %d tails and %d files (%.1f MB) in %.2f s",
            #tails, #full, read_bytes / 1e6, time.to_s(time.since(start_time))))
    end)
    if not pid then
        logger.warn("DictPrefetch: could not start subprocess")
        return
    end
    self.pid = pid
    self._poll_func = self._poll_func or function() self:_poll() end
    UIManager:scheduleIn(self.poll_interval_s, self._poll_func)
end

--[[--
Stops the subprocess if it is running.

@treturn bool whether it was running, i.e. whether its work is unfinished
]]
function DictPrefetch:stop()
    if not self.pid then return false end
    local done = ffiutil.isSubProcessDone(self.pid)
    if not done then
        ffiutil.terminateSubProcess(self.pid)
    end
    -- _poll keeps going until the subprocess has been collected; forget the pid
    -- here so that a new one can be started meanwhile.
    local pid = self.pid
    self.pid = nil
    if not done then
        local collect_killed
        collect_killed = function()
            if not ffiutil.isSubProcessDone(pid) then
                UIManager:scheduleIn(self.poll_interval_s, collect_killed)
            end
        end
        UIManager:scheduleIn(self.poll_interval_s, collect_killed)
    end
    UIManager:unschedule(self._poll_func)
    return not done
end

return DictPrefetch
