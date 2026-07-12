--[[--
spec/eventlog_spec.lua — unit tests for lib/eventlog.lua
Pure Lua — no KOReader runtime needed.

Run: busted spec/eventlog_spec.lua   (from plugin root)
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

describe("lib/eventlog", function()

    local EventLog

    before_each(function()
        package.loaded["lib/eventlog"] = nil
        EventLog = require("lib/eventlog")
    end)

    local function read_file(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return content
    end

    -- ── Construction ────────────────────────────────────────────────────────

    it("new() returns an EventLog object", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        assert.is_not_nil(log)
        log:close()
        os.remove(path)
    end)

    -- ── Write format ────────────────────────────────────────────────────────

    it("write() produces a line containing all four fields (RAW)", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("RAW", "EV_ABS", "ABS_MT_TOOL_TYPE", 2)
        log:close()

        local content = read_file(path)
        assert.is_not_nil(content)
        assert.is_truthy(content:find("RAW",               1, true))
        assert.is_truthy(content:find("EV_ABS",            1, true))
        assert.is_truthy(content:find("ABS_MT_TOOL_TYPE",  1, true))
        assert.is_truthy(content:find("2",                 1, true))
        os.remove(path)
    end)

    it("write() produces a line containing all fields (DEC)", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("DEC", "down", "tool=eraser", "x=512 y=880 p=310")
        log:close()

        local content = read_file(path)
        assert.is_truthy(content:find("DEC",        1, true))
        assert.is_truthy(content:find("down",        1, true))
        assert.is_truthy(content:find("tool=eraser", 1, true))
        assert.is_truthy(content:find("x=512",       1, true))
        os.remove(path)
    end)

    it("each line starts with a numeric timestamp", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("RAW", "EV_ABS", "ABS_MT_PRESSURE", 100)
        log:close()

        local content = read_file(path)
        -- First character of the line must be a digit
        assert.is_truthy(content:match("^%d"))
        os.remove(path)
    end)

    it("each line ends with a newline", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("RAW", "EV_KEY", "BTN_TOOL_PEN", 1)
        log:close()

        local content = read_file(path)
        assert.are.equal("\n", content:sub(-1))
        os.remove(path)
    end)

    -- ── Multiple writes ──────────────────────────────────────────────────────

    it("multiple writes produce one line each", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("RAW", "EV_KEY",  "BTN_TOOL_RUBBER", 1)
        log:write("RAW", "EV_SYN",  "SYN_REPORT",      0)
        log:write("DEC", "down",    "tool=eraser",     "x=10 y=20 p=300")
        log:close()

        local content = read_file(path)
        local lines = {}
        for line in content:gmatch("[^\n]+") do
            lines[#lines + 1] = line
        end
        assert.are.equal(3, #lines)
        os.remove(path)
    end)

    it("append mode: second EventLog on same path does not truncate", function()
        local path = os.tmpname()

        local log1 = EventLog.new(path)
        log1:write("RAW", "EV_ABS", "ABS_MT_TOOL_TYPE", 1)
        log1:close()

        local log2 = EventLog.new(path)
        log2:write("RAW", "EV_ABS", "ABS_MT_TOOL_TYPE", 2)
        log2:close()

        local content = read_file(path)
        local lines = {}
        for line in content:gmatch("[^\n]+") do
            lines[#lines + 1] = line
        end
        assert.are.equal(2, #lines)
        os.remove(path)
    end)

    -- ── Rotation ─────────────────────────────────────────────────────────────

    it("rotates when the file already exceeds MAX_SIZE before the write", function()
        local path = os.tmpname()

        -- Pre-fill: write just over 2 MB
        local large_chunk = string.rep("x", 2 * 1024 * 1024 + 1)
        local f = assert(io.open(path, "w"))
        f:write(large_chunk)
        f:close()

        local log = EventLog.new(path)
        log:write("RAW", "EV_ABS", "ABS_MT_TOOL_TYPE", 2)
        log:close()

        -- Main file should now be small (just the one event line)
        local new_content = read_file(path)
        assert.is_not_nil(new_content)
        assert.is_truthy(#new_content < 1024)   -- well under 1 KB

        -- Backup must exist and hold the original large data
        local backup = read_file(path .. ".1")
        assert.is_not_nil(backup)
        assert.is_truthy(#backup > 2 * 1024 * 1024)

        os.remove(path)
        os.remove(path .. ".1")
    end)

    it("degrades to a silent no-op when rotation cannot reopen the file", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("RAW", "EV_SYN", "SYN_REPORT", 0)

        -- Simulate reopen failure: point the log at a path inside a
        -- directory that doesn't exist, so both the rename and the reopen
        -- fail. _rotate must not throw -- it runs inside the 120 Hz pen
        -- poll loop, where an uncaught error would take down the KOReader
        -- UI event loop.
        log._path = "/nonexistent-eventlog-spec-dir/input.log"
        assert.has_no.errors(function() log:_rotate() end)

        -- After a failed rotation the log behaves as closed: writes are
        -- no-ops (write() already guards on _file) and close() stays safe.
        assert.has_no.errors(function()
            log:write("RAW", "EV_KEY", "BTN_STYLUS", 1)
        end)
        assert.has_no.errors(function() log:close() end)

        os.remove(path)
        os.remove(path .. ".1")
    end)

    -- ── close() ──────────────────────────────────────────────────────────────

    it("close() is idempotent (safe to call twice)", function()
        local path = os.tmpname()
        local log = EventLog.new(path)
        log:write("RAW", "EV_SYN", "SYN_REPORT", 0)
        log:close()
        assert.has_no.errors(function() log:close() end)
        os.remove(path)
    end)

end)
