--[[--
This module provides development-only asserts and other debug guards.

Instead of a regular Lua @{assert}(), use @{dbg.dassert}() which can be toggled at runtime.

    dbg.dassert(important_variable ~= nil)

For checking whether the input given to a function is sane, you can use @{dbg.guard}().

    dbg:guard(NickelConf.frontLightLevel, "set",
        function(new_intensity)
            assert(type(new_intensity) == "number",
                   "Wrong brightness value type (expected number)!")
            assert(new_intensity >= 0 and new_intensity <= 100,
                   "Wrong brightness value given!")
        end)

These functions don't do anything when debugging is turned off.
--]]--

local logger = require("logger")
local dump = require("dump")
local isAndroid, android = pcall(require, "android")

local Dbg = {
    -- set to nil so first debug:turnOff call won't be skipped
    is_on = nil,
    is_verbose = nil,
}

local Dbg_mt = {}

local function LvDEBUG(lv, ...)
    local line
    if isAndroid then
        line = {}
    else
        line = {
            os.date("%x-%X DEBUG"),
        }
    end
    for _, v in ipairs({...}) do
        if type(v) == "table" then
            table.insert(line, dump(v, lv))
        else
            table.insert(line, tostring(v))
        end
    end
    if isAndroid then
        return android.LOGV(table.concat(line, " "))
    else
        table.insert(line, "\n")
        return io.write(table.concat(line, " "))
    end
end

--- Turn on debug mode.
-- This should only be used in tests and at the user's request.
function Dbg:turnOn()
    if self.is_on == true then return end
    self.is_on = true
    logger:setLevel(logger.levels.dbg)

    Dbg_mt.__call = function(_, ...) return LvDEBUG(math.huge, ...) end
    --- Pass a guard function to detect bad input values. Unsafe if method can return nil.
    Dbg.guard = function(_, mod, method, pre_guard, post_guard)
        local old_method = mod[method]
        mod[method] = function(...)
            if pre_guard then
                pre_guard(...)
            end
            -- NOTE: This will break on the first nil being returned...
            local values = {old_method(...)}
            if post_guard then
                post_guard(...)
            end
            return unpack(values)
        end
    end
    --- Use this instead of a regular Lua @{assert}().
    Dbg.dassert = function(check, msg)
        assert(check, msg)
        return check
    end
end

--- Turn off debug mode.
-- This should only be used in tests and at the user's request.
function Dbg:turnOff()
    if self.is_on == false then return end
    self.is_on = false
    logger:setLevel(logger.levels.info)
    Dbg_mt.__call = function() end
    Dbg.guard = function() end
    Dbg.dassert = function(check)
        return check
    end
end

--- Turn on verbose mode.
-- This should only be used in tests and at the user's request.
function Dbg:setVerbose(verbose)
    self.is_verbose = verbose
end

--- Simple table dump.
function Dbg:v(...)
    if self.is_verbose then
        return LvDEBUG(math.huge, ...)
    end
end

--- Simple traceback.
function Dbg:traceback()
    return LvDEBUG(math.huge, debug.traceback())
end

setmetatable(Dbg, Dbg_mt)

Dbg:turnOff()
return Dbg
