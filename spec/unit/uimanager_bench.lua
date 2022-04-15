require("commonrequire")

local UIManager = require("ui/uimanager")

local time = require("ui/time")

local NB_TESTS = 40000
local noop = function() end

describe("UIManager checkTasks benchmark", function()
    local now = time.now()
    local wait_until -- luacheck: no unused
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        table.insert(
            UIManager._task_queue,
            { time = now + i, action = noop, argc = 0, args = {} }
        )
    end

    for i=1, NB_TESTS do
        wait_until, now = UIManager:_checkTasks() -- luacheck: no unused
    end
end)

describe("UIManager schedule benchmark", function()
    local now = time.now()
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        UIManager:schedule(now + i, noop)
    end
end)

describe("UIManager unschedule benchmark", function()
    local now = time.now()
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        table.insert(
            UIManager._task_queue,
            { time = now + i, action = 'a', argc=0, args={} }
        )
    end

    for i=1, NB_TESTS do
        UIManager:schedule(now + i, noop)
        UIManager:unschedule(noop)
    end
end)
