local DocSettings = require("docsettings") -- for dump method
local isAndroid, android = pcall(require, "android")

local Dbg = {
    is_on = false,
    ev_log = nil,
}

local Dbg_mt = {}

local function LvDEBUG(lv, ...)
    local line = ""
    for i,v in ipairs({...}) do
        if type(v) == "table" then
            line = line .. " " .. DocSettings:dump(v, lv)
        else
            line = line .. " " .. tostring(v)
        end
    end
    if isAndroid then
        android.LOGI("#"..line)
    else
        print("#"..line)
    end
end

function Dbg_mt.__call(dbg, ...)
    if dbg.is_on then LvDEBUG(math.huge, ...) end
end

function Dbg:turnOn()
    self.is_on = true

    -- create or clear ev log file
    if not isAndroid then
        os.execute("echo > ev.log")
        self.ev_log = io.open("ev.log", "w")
    end
end

function Dbg:logEv(ev)
    local log = ev.type.."|"..ev.code.."|"
                ..ev.value.."|"..ev.time.sec.."|"..ev.time.usec.."\n"
    self.ev_log:write(log)
    self.ev_log:flush()
end

function Dbg:traceback()
    LvDEBUG(math.huge, debug.traceback())
end

setmetatable(Dbg, Dbg_mt)

return Dbg
