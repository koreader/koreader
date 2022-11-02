require("commonrequire")

local UIManager = require("ui/uimanager")

local time = require("ui/time")

local NB_TESTS = 40000
local noop = function() end

local function check()
    for i = 1, #UIManager._task_queue-1 do
        -- test for wrongly inserted time
        assert.is_true(UIManager._task_queue[i].time >= UIManager._task_queue[i+1].time,
            "time wrongly sorted")
        if UIManager._task_queue[i].time == UIManager._task_queue[i+1].time then
            -- for same time, test if later inserted action is after a former action
            assert.is_true(UIManager._task_queue[i].action >= UIManager._task_queue[i+1].action,
                "ragnarock")
        end
    end
end

describe("UIManager checkTasks benchmark", function()
    local now = time.now()
    local wait_until -- luacheck: no unused
    UIManager:quit()

    for i= NB_TESTS, 1, -1 do
        table.insert(
            UIManager._task_queue,
            { time = now + i, action = noop, args = {} }
        )
    end

    for i=1, NB_TESTS do
        wait_until, now = UIManager:_checkTasks() -- luacheck: no unused
    end
end)

describe("UIManager schedule simple benchmark", function()
    local now = time.now()
    UIManager:quit()

    for i=1, NB_TESTS/2 do
        UIManager:schedule(now + i, noop)
        UIManager:schedule(now + NB_TESTS - i, noop)
    end
end)

describe("UIManager more sophisticated schedule benchmark", function()
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

describe("UIManager schedule massive collision tests", function()
    print("Doing massive collision tests ......... this takes a lot of time")
    UIManager:quit()

    for i = 1, 6 do
        -- simple test (1000/10 collisions)
        UIManager._task_queue = {}
        for j = 1, 10 do
            UIManager:schedule(math.random(10), j)
            -- check() -- enabling this takes really long O(n^2)
        end
        check()

        -- armageddon test (10000 collisions)
        UIManager._task_queue = {}
        for j = 1, 1e5 do
            UIManager:schedule(math.random(100), j)
            -- check() -- enabling this takes really long O(n^2)
        end
        check()
    end
end)

describe("UIManager schedule massive ridiculous tests", function()
    print("Performing massive ridiculous collision tests ......... this really takes a lot of time")
    UIManager:quit()

    for i = 1, 6 do
        -- simple test (1000 collisions)
        UIManager._task_queue = {}
        local offs = 0
        for j = 1, 1e3 do
            UIManager:schedule(math.random(10), j + offs)
            offs = offs + 1
            -- check() -- enabling this takes really long O(n^2)
        end
        check()

        -- simple (unknown number of collisions and times)
        for j = 1, 1e4 do
            UIManager:schedule(math.random(), j + offs)
            offs = offs + 1
            -- check() -- enabling this takes really long O(n^2)
        end
        check()

        -- armageddon test (100 collisions)
        for j = 1, 1e5 do
            UIManager:schedule(math.random(math.random(100)), j + offs)
            offs = offs + 1
            -- check() -- enabling this takes really long O(n^2)
        end
        check()
    end
end)

describe("UIManager unschedule benchmark", function()
    local now = time.now()
    UIManager:quit()

    for i=NB_TESTS, 1, -1 do
        table.insert(
            UIManager._task_queue,
            { time = now + i, action = 'a', args={} }
        )
    end

    for i=1, NB_TESTS/2 do
        UIManager:schedule(now + i, noop)
        UIManager:unschedule(noop)
        UIManager:schedule(now + NB_TESTS - i, noop)
        UIManager:unschedule(noop)
    end
end)
