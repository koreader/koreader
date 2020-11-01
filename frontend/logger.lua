--[[--
Logger module.
See @{Logger.levels} for list of supported levels.

Example:

    local logger = require("logger")
    logger.info("Something happened.")
    logger.err("House is on fire!")
]]

local dump = require("dump")
local isSDL = require("ffi/util").isSDL()
local isAndroid, android = pcall(require, "android")

-- write to crash.log on SDL platform based on environment.
-- on other platforms crash.log is generated redirecting stdout in init shell scripts.
local logfile = isSDL and os.getenv("EMULATE_CRASH_LOG") and io.open("crash.log", "w+")

local DEFAULT_DUMP_LVL = 10

--- Supported logging levels
-- @table Logger.levels
-- @field dbg debug
-- @field info informational (default level)
-- @field warn warning
-- @field err error
local LOG_LVL = {
    dbg = 1,
    info = 2,
    warn = 3,
    err = 4,
}

local LOG_PREFIX = {
    dbg = 'DEBUG',
    info = 'INFO ',
    warn = 'WARN ',
    err = 'ERROR',
}

local noop = function() end

local Logger = {
    levels = LOG_LVL,
}

local function log(log_lvl, dump_lvl, ...)
    local line = ""
    for i,v in ipairs({...}) do
        if type(v) == "table" then
            line = line .. " " .. dump(v, dump_lvl)
        else
            line = line .. " " .. tostring(v)
        end
    end
    if isAndroid then
        if log_lvl == "dbg" then
            android.LOGV(line)
        elseif log_lvl == "info" then
            android.LOGI(line)
        elseif log_lvl == "warn" then
            android.LOGW(line)
        elseif log_lvl == "err" then
            android.LOGE(line)
        end
    else
        local msg = string.format("%s %s%s\n", os.date("%x-%X"), LOG_PREFIX[log_lvl], line)
        io.stdout:write(msg)
        io.stdout:flush()
        if logfile then
            logfile:write(msg)
            logfile:flush()
        end
    end
end

local LVL_FUNCTIONS = {
    dbg = function(...) log('dbg', DEFAULT_DUMP_LVL, ...) end,
    info = function(...) log('info', DEFAULT_DUMP_LVL, ...) end,
    warn = function(...) log('warn', DEFAULT_DUMP_LVL, ...) end,
    err = function(...) log('err', DEFAULT_DUMP_LVL, ...) end,
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

Logger:setLevel(LOG_LVL.info)

return Logger
