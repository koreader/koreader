require("commonrequire")

local UIManager = require("ui/uimanager")

local time = require("ui/time")

local NB_TESTS = 40000
local noop = function() end

describe("UIManager simple checkTasks and scheduling benchmark", function()
    local now = time.now()
    local wait_until -- luacheck: no unused
    UIManager:quit()
    UIManager._task_queue = {}

    -- use schedule here, to be agnostic of the _task_queue order (ascending, descending).
    for i=1, NB_TESTS/2 do
        UIManager:schedule(now + i, noop)
        UIManager:schedule(now + NB_TESTS - i, noop)
    end

    for i=1, NB_TESTS do
        wait_until, now = UIManager:_checkTasks() -- luacheck: no unused
    end
end)

describe("UIManager more advanced checkTasks and scheduling benchmark", function()
    -- This BM is doing schedulings like the are done in real usage
    -- with autosuspend, autodim, autowarmth and friends.
    -- Additional _checkTask is called to better simulate bench this too.
    local wait_until -- luacheck: no unused

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

            for k = 1, 10 do
                UIManager:schedule(now + time.s(k), standby_dummy) -- standby
            end
            now = now + 10

            -- consume the last 10 standby_dummy, plus 10 checks.
            for k = 1, 20 do
                wait_until, now = UIManager:_checkTasks() -- luacheck: no unused
            end

            UIManager:schedule(now + time.s(15*60), autowarmth_dummy) -- autowarmth
            UIManager:schedule(now + time.s(180), dimmer_dummy) -- dimmer

            now = now + 30
            UIManager:unschedule(dimmer_dummy)
            UIManager:unschedule(autowarmth_dummy) -- remove autowarmth
        end
    end
end)
