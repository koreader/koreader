require("commonrequire")
local util = require("ffi/util")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
DEBUG:turnOn()

describe("UIManager spec", function()
    local noop = function() end

    it("should consume due tasks", function()
        local now = { util.gettime() }
        local future = { now[1] + 60000, now[2] }
        local future2 = {future[1] + 5, future[2]}
        UIManager:quit()
        UIManager._task_queue = {
            { time = {now[1] - 10, now[2] }, action = noop },
            { time = {now[1], now[2] - 5 }, action = noop },
            { time = now, action = noop },
            { time = future, action = noop },
            { time = future2, action = noop },
        }
        UIManager:_checkTasks()
        assert.are.same(#UIManager._task_queue, 2)
        assert.are.same(UIManager._task_queue[1].time, future)
        assert.are.same(UIManager._task_queue[2].time, future2)
    end)

    it("should calcualte wait_until properly in checkTasks routine", function()
        local now = { util.gettime() }
        local future = { now[1] + 60000, now[2] }
        UIManager:quit()
        UIManager._task_queue = {
            { time = {now[1] - 10, now[2] }, action = noop },
            { time = {now[1], now[2] - 5 }, action = noop },
            { time = now, action = noop },
            { time = future, action = noop },
            { time = {future[1] + 5, future[2]}, action = noop },
        }
        wait_until, now = UIManager:_checkTasks()
        assert.are.same(wait_until, future)
    end)

    it("should return nil wait_until properly in checkTasks routine", function()
        local now = { util.gettime() }
        UIManager:quit()
        UIManager._task_queue = {
            { time = {now[1] - 10, now[2] }, action = noop },
            { time = {now[1], now[2] - 5 }, action = noop },
            { time = now, action = noop },
        }
        wait_until, now = UIManager:_checkTasks()
        assert.are.same(wait_until, nil)
    end)

    it("should insert new task properly in empty task queue", function()
        local now = { util.gettime() }
        UIManager:quit()
        UIManager._task_queue = {}
        assert.are.same(0, #UIManager._task_queue)
        UIManager:scheduleIn(50, 'foo')
        assert.are.same(1, #UIManager._task_queue)
        assert.are.same(UIManager._task_queue[1].action, 'foo')
    end)

    it("should insert new task properly in single task queue", function()
        local now = { util.gettime() }
        local future = { now[1]+10000, now[2] }
        UIManager:quit()
        UIManager._task_queue = {
            { time = future, action = '1' },
        }
        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'quz')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same(UIManager._task_queue[1].action, 'quz')

        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '1' },
        }
        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'foo')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same(UIManager._task_queue[2].action, 'foo')
        UIManager:scheduleIn(155, 'bar')
        assert.are.same(3, #UIManager._task_queue)
        assert.are.same(UIManager._task_queue[3].action, 'bar')
    end)

    it("should insert new task in ascendant order", function()
        local now = { util.gettime() }
        local noop1 = function() end
        UIManager:quit()
        UIManager._task_queue = {
            { time = {now[1] - 10, now[2] }, action = '1' },
            { time = {now[1], now[2] - 5 }, action = '2' },
            { time = now, action = '3' },
        }
        -- insert into the tail slot
        UIManager:scheduleIn(10, 'foo')
        assert.are.same('foo', UIManager._task_queue[4].action)
        -- insert into the second slot
        UIManager:schedule({now[1]-5, now[2]}, 'bar')
        assert.are.same('bar', UIManager._task_queue[2].action)
        -- insert into the head slot
        UIManager:schedule({now[1]-15, now[2]}, 'baz')
        assert.are.same('baz', UIManager._task_queue[1].action)
        -- insert into the last second slot
        UIManager:scheduleIn(5, 'qux')
        assert.are.same('qux', UIManager._task_queue[6].action)
        -- insert into the middle slot
        UIManager:schedule({now[1], now[2]-1}, 'quux')
        assert.are.same('quux', UIManager._task_queue[5].action)
    end)

    it("should not have race between unschedule and _checkTasks", function()
        local now = { util.gettime() }
        local run_count = 0
        local task_to_remove = function()
            run_count = run_count + 1
        end
        UIManager:quit()
        UIManager._task_queue = {
            { time = { now[1], now[2]-5 }, action = task_to_remove },
            {
                time = { now[1]-10, now[2] },
                action = function()
                    run_count = run_count + 1
                    UIManager:unschedule(task_to_remove)
                end
            },
            { time = now, action = task_to_remove },
        }
        UIManager:_checkTasks()
        assert.are.same(run_count, 2)
    end)
end)
