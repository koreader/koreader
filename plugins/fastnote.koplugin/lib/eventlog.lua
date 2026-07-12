--[[--
lib/eventlog.lua — line-buffered input event log for fastnote debug diagnostics.

Writes timestamped raw and decoded pen events to a plain-text file that can
be tailed over SSH:

    tail -F /mnt/onboard/.adds/koreader/fastnote/input.log

Pure Lua; no KOReader runtime dependencies — fully busted-testable.
Enable via the hamburger menu "Debug log" toggle; off by default.

Format (fixed columns, grep-friendly):
    <timestamp>  <level>  <ev_type>  <code_name>  <value>
    1748736123  RAW  EV_ABS  ABS_MT_TOOL_TYPE  2
    1748736123  RAW  EV_KEY  BTN_TOOL_RUBBER   1
    1748736123  DEC  down    tool=eraser       x=512 y=880 p=310

ASSUMES: standard Lua I/O (io.open, os.time, os.rename).
--]]--

local EventLog = {}
EventLog.__index = EventLog

-- Rotate the log file when it exceeds this size (bytes).
local MAX_SIZE = 2 * 1024 * 1024   -- 2 MB

--- Create (or re-open for append) an event log at the given path.
-- @string path  absolute path to the log file
-- @return EventLog instance, or nil + error string on failure
function EventLog.new(path)
    local file, err = io.open(path, "a")
    if not file then
        return nil, "eventlog: cannot open " .. path .. ": " .. (err or "unknown")
    end
    -- Line-buffered: each write flushes at the newline so tail -F shows events live.
    file:setvbuf("line")
    return setmetatable({ _path = path, _file = file }, EventLog)
end

--- Rotate: close current handle, rename to .1 (overwriting), reopen fresh.
-- Never throws: this runs from EventLog:write inside the ~120 Hz pen poll
-- loop, where an uncaught error would propagate into the KOReader UI event
-- loop (lua.instructions.md). If the reopen fails (disk full, path gone),
-- the log degrades to a closed no-op — write() already guards on _file.
function EventLog:_rotate()
    self._file:close()
    os.rename(self._path, self._path .. ".1")
    -- Open fresh (write mode, not append — we just rotated the old content away).
    local file = io.open(self._path, "w")
    if not file then
        self._file = nil
        return
    end
    file:setvbuf("line")
    self._file = file
end

--- Write one log line.
-- Checks file size before writing; rotates if >= MAX_SIZE.
-- @string level       "RAW" or "DEC"
-- @string ev_type_name  event type name ("EV_KEY", "EV_ABS", "EV_SYN", or decoded type)
-- @string code_name   code name or formatted field string
-- @string|number value  numeric value or formatted value string
function EventLog:write(level, ev_type_name, code_name, value)
    if not self._file then return end

    -- Size check: seek("end") returns current EOF offset (= file size) and moves
    -- the read cursor, but append mode always writes at EOF regardless — safe.
    local size = self._file:seek("end")
    if size and size >= MAX_SIZE then
        self:_rotate()
    end

    self._file:write(string.format("%d  %s  %s  %s  %s\n",
        os.time(),
        level,
        ev_type_name,
        tostring(code_name),
        tostring(value)))
end

--- Close the log file. Safe to call more than once.
function EventLog:close()
    if self._file then
        self._file:close()
        self._file = nil
    end
end

return EventLog
