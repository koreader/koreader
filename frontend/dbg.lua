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

local Dbg = {
    -- set to nil so first debug:turnOff call won't be skipped
    is_on = nil,
    is_verbose = nil,
}

local Dbg_mt = {}

local LvDEBUG = logger.LvDEBUG

--- Turn on debug mode.
-- This should only be used in tests and at the user's request.
function Dbg:turnOn()
    if self.is_on == true then return end
    self.is_on = true
    logger:setLevel(logger.levels.dbg)

    Dbg_mt.__call = function(_, ...) return LvDEBUG(...) end
    --- Pass a guard function to detect bad input values.
    Dbg.guard = function(_, mod, method, pre_guard, post_guard)
        local old_method = mod[method]
        mod[method] = function(...)
            if pre_guard then
                pre_guard(...)
            end
            local values = table.pack(old_method(...))
            if post_guard then
                post_guard(...)
            end
            return unpack(values, 1, values.n)
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
    -- NOTE: This doesn't actually disengage previously wrapped methods!
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
        return LvDEBUG(...)
    end
end

--- Conditional logging with a stable ref.
function Dbg.log(...)
    if Dbg.is_on then
        return LvDEBUG(...)
    end
end

--- Simple traceback.
function Dbg:traceback()
    return LvDEBUG(debug.traceback())
end

setmetatable(Dbg, Dbg_mt)

Dbg:turnOff()
return Dbg
