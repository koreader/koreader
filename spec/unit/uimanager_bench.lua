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

describe("UIManager schedule simple benchmark", function()
    local now = time.now()
    UIManager:quit()
    UIManager._task_queue = {}

    for i=1, NB_TESTS do
        UIManager:schedule(now + i, noop)
    end
end)

describe("UIManager schedule more sophiticated benchmark", function()
    -- This BM is doing schedulings like the are done in real usage
    -- with autosuspend, autodim, autowarmth and friends.
    local now = time.now()
    UIManager:quit()

    local function standby_dummy() end
    local function autowarmth_dummy() end
    local function dimmer_dummy() end

    local function someTaps()
        for j = 1,10 do
            -- insert some random times for entering standby
            UIManager:schedule(now + time.s(j), standby_dummy) -- standby
            UIManager:unschedule(standby_dummy)
        end
    end

    for i=1, NB_TESTS do
        UIManager._task_queue = {}
        UIManager:schedule(now + time.s(24*60*60), noop) -- shutdown
        UIManager:schedule(now + time.s(15*60*60), noop) -- sleep
        UIManager:schedule(now + time.s(55), noop) -- footer refresh
        UIManager:schedule(now + time.s(130), noop) -- something
        UIManager:schedule(now + time.s(10), noop) -- something else

        for j = 1,5 do
            someTaps()
            UIManager:schedule(now + time.s(15*60), autowarmth_dummy) -- autowarmth
            UIManager:schedule(now + time.s(180), dimmer_dummy) -- dimmer

            now = now + 30
            UIManager:unschedule(dimmer_dummy)
            UIManager:unschedule(autowarmth_dummy) -- remove autowarmth
        end
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
