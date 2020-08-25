local logger = require("logger")
local dump = require("dump")
local isAndroid, android = pcall(require, "android")

local Dbg = {
    -- set to nil so first debug:turnOff call won't be skipped
    is_on = nil,
    is_verbose = nil,
    ev_log = nil,
}

local Dbg_mt = {}

local function LvDEBUG(lv, ...)
    local line = ""
    for i,v in ipairs({...}) do
        if type(v) == "table" then
            line = line .. " " .. dump(v, lv)
        else
            line = line .. " " .. tostring(v)
        end
    end
    if isAndroid then
        android.LOGV(line)
    else
        io.stdout:write(string.format("# %s %s\n", os.date("%x-%X"), line))
        io.stdout:flush()
    end
end

function Dbg:turnOn()
    if self.is_on == true then return end
    self.is_on = true
    logger:setLevel(logger.levels.dbg)

    Dbg_mt.__call = function(dbg, ...) LvDEBUG(math.huge, ...) end
    Dbg.guard = function(_, mod, method, pre_guard, post_guard)
        local old_method = mod[method]
        mod[method] = function(...)
            if pre_guard then
                pre_guard(...)
            end
            local values = {old_method(...)}
            if post_guard then
                post_guard(...)
            end
            return unpack(values)
        end
    end
    Dbg.dassert = function(check, msg)
        assert(check, msg)
        return check
    end

    -- create or clear ev log file
    --- @note: On Linux, use CLOEXEC to avoid polluting the fd table of our child processes.
    ---        Otherwise, it can be problematic w/ wpa_supplicant & USBMS...
    ---        Note that this is entirely undocumented, but at least LuaJIT passes the mode as-is to fopen, so, we're good.
    if jit.os == "Linux" then
        self.ev_log = io.open("ev.log", "we")
    else
        self.ev_log = io.open("ev.log", "w")
    end
end

function Dbg:turnOff()
    if self.is_on == false then return end
    self.is_on = false
    logger:setLevel(logger.levels.info)
    function Dbg_mt.__call() end
    function Dbg.guard() end
    Dbg.dassert = function(check)
        return check
    end
    if self.ev_log then
        io.close(self.ev_log)
        self.ev_log = nil
    end
end

function Dbg:setVerbose(verbose)
    self.is_verbose = verbose
end

function Dbg:v(...)
    if self.is_verbose then
        LvDEBUG(math.huge, ...)
    end
end

function Dbg:logEv(ev)
    local ev_value = tostring(ev.value)
    local log = ev.type.."|"..ev.code.."|"
                ..ev_value.."|"..ev.time.sec.."|"..ev.time.usec.."\n"
    if self.ev_log then
        self.ev_log:write(log)
        self.ev_log:flush()
    end
end

function Dbg:traceback()
    LvDEBUG(math.huge, debug.traceback())
end

setmetatable(Dbg, Dbg_mt)

Dbg:turnOff()
return Dbg
