--[[--
Logger module.
See @{Logger.levels} for list of supported levels.

Example:

    local logger = require("logger")
    logger.info("Something happened.")
    logger.err("House is on fire!")
]]

local serpent = require("ffi/serpent")
local isAndroid, android = pcall(require, "android")

local DEFAULT_DUMP_LVL = 10

--- Supported logging levels
-- @table Logger.levels
-- @field dbg debug
-- @field info informational (default level)
-- @field warn warning
-- @field err error
local LOG_LVL = {
    dbg  = 1,
    info = 2,
    warn = 3,
    err  = 4,
}

local LOG_PREFIX = {
    dbg  = "DEBUG",
    info = "INFO ",
    warn = "WARN ",
    err  = "ERROR",
}

local noop = function() end

local serpent_opts = {
    maxlevel = DEFAULT_DUMP_LVL,
    indent = "  ",
    nocode = true,
}

local Logger = {
    levels = LOG_LVL,
}

local log
if isAndroid then
    local ANDROID_LOG_FNS = {
        dbg  = android.LOGV,
        info = android.LOGI,
        warn = android.LOGW,
        err  = android.LOGE,
    }

    log = function(log_lvl, ...)
        local line = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "table" then
                table.insert(line, serpent.block(v, serpent_opts))
            else
                table.insert(line, tostring(v))
            end
        end
        return ANDROID_LOG_FNS[log_lvl](table.concat(line, " "))
    end
else
    log = function(log_lvl, ...)
        local line = {
            os.date("%x-%X"),
            LOG_PREFIX[log_lvl],
        }
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "table" then
                table.insert(line, serpent.block(v, serpent_opts))
            else
                table.insert(line, tostring(v))
            end
        end

        -- NOTE: Either we add the LF to the table and we get an extra space before it because of table.concat,
        --       or we pass it to write after a comma, and it generates an extra write syscall...
        --       That, or just rewrite every logger call to handle spacing themselves ;).
        table.insert(line, "\n")
        return io.write(table.concat(line, " "))
    end
end

local LVL_FUNCTIONS = {
    dbg  = function(...) return log("dbg", ...) end,
    info = function(...) return log("info", ...) end,
    warn = function(...) return log("warn", ...) end,
    err  = function(...) return log("err", ...) end,
}

--[[--
Set logging level. By default, level is set to info.

@int new_lvl new logging level, must be one of the levels from @{Logger.levels}

@usage
Logger:setLevel(Logger.levels.warn)
]]
function Logger:setLevel(new_lvl)
    for lvl_name, lvl_value in pairs(LOG_LVL) do
        if new_lvl <= lvl_value then
            self[lvl_name] = LVL_FUNCTIONS[lvl_name]
        else
            self[lvl_name] = noop
        end
    end
end

-- For dbg's sake
function Logger.LvDEBUG(...)
    return log("dbg", ...)
end

Logger:setLevel(LOG_LVL.info)

return Logger
