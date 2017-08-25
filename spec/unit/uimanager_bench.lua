require("commonrequire")
local util = require("ffi/util")
local UIManager = require("ui/uimanager")

local noop = function() end

describe("UIManager checkTasks benchmark", function()
    local now = { util.gettime() }
    local wait_until -- luacheck: no unused
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1,1000000 do
        table.insert(
            UIManager._task_queue,
            { time = { now[1] + 10000+i, now[2] }, action = noop }
        )
    end

    -- for i=1,1000 do
        wait_until, now = UIManager:_checkTasks() -- luacheck: no unused
    -- end
end)

describe("UIManager schedule benchmark", function()
    local now = { util.gettime() }
    UIManager:quit()
    UIManager._task_queue = {}
    for i=1,100000 do
        UIManager:schedule({ now[1] + i, now[2] }, noop)
    end
end)

describe("UIManager unschedule benchmark", function()
    local now = { util.gettime() }
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1,1000 do
        table.insert(
            UIManager._task_queue,
            { time = { now[1] + 10000+i, now[2] }, action = 'a' }
        )
    end

    for i=1,1000 do
        UIManager:schedule(now, noop)
        UIManager:unschedule(noop)
    end
end)
