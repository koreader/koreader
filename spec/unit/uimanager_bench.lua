require("commonrequire")

local UIManager = require("ui/uimanager")

local fts = require("ui/fts")

local NB_TESTS = 40000
local noop = function() end

describe("UIManager checkTasks benchmark", function()
    local now_fts = fts.now()
    local wait_until_fts -- luacheck: no unused
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        table.insert(
            UIManager._task_queue,
            { time_fts = now_fts + i, action = noop, argc = 0, args = {} }
        )
    end

    for i=1, NB_TESTS do
        wait_until_fts, now_fts = UIManager:_checkTasks() -- luacheck: no unused
    end
end)

describe("UIManager schedule benchmark", function()
    local now_fts = fts.now()
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        UIManager:schedule( now_fts + i, noop )
    end
end)

describe("UIManager unschedule benchmark", function()
    local now_fts = fts.now()
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        table.insert(
            UIManager._task_queue,
            { time_fts = now_fts + i, action = 'a', argc=0, args={} }
        )
    end

    for i=1, NB_TESTS do
        UIManager:schedule( now_fts + i, noop)
        UIManager:unschedule(noop)
    end
end)
