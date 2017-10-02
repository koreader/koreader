describe("UIManager spec", function()
    local UIManager, util
    local now, wait_until
    local noop = function() end

    setup(function()
        require("commonrequire")
        util = require("ffi/util")
        UIManager = require("ui/uimanager")
    end)

    it("should consume due tasks", function()
        now = { util.gettime() }
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
        now = { util.gettime() }
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
        now = { util.gettime() }
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
        now = { util.gettime() }
        UIManager:quit()
        UIManager._task_queue = {}
        assert.are.same(0, #UIManager._task_queue)
        UIManager:scheduleIn(50, 'foo')
        assert.are.same(1, #UIManager._task_queue)
        assert.are.same(UIManager._task_queue[1].action, 'foo')
    end)

    it("should insert new task properly in single task queue", function()
        now = { util.gettime() }
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
        now = { util.gettime() }
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

    it("should unschedule all the tasks with the same action", function()
        now = { util.gettime() }
        UIManager:quit()
        UIManager._task_queue = {
            { time = {now[1] - 15, now[2] }, action = '3' },
            { time = {now[1] - 10, now[2] }, action = '1' },
            { time = {now[1], now[2] - 6 }, action = '3' },
            { time = {now[1], now[2] - 5 }, action = '2' },
            { time = now, action = '3' },
        }
        -- insert into the tail slot
        UIManager:unschedule('3')
        assert.are.same({
            { time = {now[1] - 10, now[2] }, action = '1' },
            { time = {now[1], now[2] - 5 }, action = '2' },
        }, UIManager._task_queue)
    end)

    it("should not have race between unschedule and _checkTasks", function()
        now = { util.gettime() }
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

    it("should clear _task_queue_dirty bit before looping", function()
        UIManager:quit()
        assert.is.not_true(UIManager._task_queue_dirty)
        UIManager:nextTick(function() UIManager:nextTick(noop) end)
        UIManager:_checkTasks()
        assert.is_true(UIManager._task_queue_dirty)
    end)

    describe("modal widgets", function()
        it("should insert modal widget on top", function()
            -- first modal widget
            UIManager:show({
                x_prefix_test_number = 1,
                modal = true,
                handleEvent = function()
                    return true
                end
            })
            -- regular widget, should go under modal widget
            UIManager:show({
                x_prefix_test_number = 2,
                modal = nil,
                handleEvent = function()
                    return true
                end
            })

            assert.equals(UIManager._window_stack[1].widget.x_prefix_test_number, 2)
            assert.equals(UIManager._window_stack[2].widget.x_prefix_test_number, 1)
        end)
        it("should insert second modal widget on top of first modal widget", function()
            UIManager:show({
                x_prefix_test_number = 3,
                modal = true,
                handleEvent = function()
                    return true
                end
            })

            assert.equals(UIManager._window_stack[1].widget.x_prefix_test_number, 2)
            assert.equals(UIManager._window_stack[2].widget.x_prefix_test_number, 1)
            assert.equals(UIManager._window_stack[3].widget.x_prefix_test_number, 3)
        end)
    end)

    it("should check active widgets in order", function()
        local call_signals = {false, false, false}
        UIManager._window_stack = {
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[1] = true
                        return true
                    end
                }
            },
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[2] = true
                        return true
                    end
                }
            },
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[3] = true
                        return true
                    end
                }
            },
            {widget = {handleEvent = function()end}},
        }

        UIManager:sendEvent("foo")
        assert.falsy(call_signals[1])
        assert.falsy(call_signals[2])
        assert.truthy(call_signals[3])
    end)

    it("should handle stack change when checking for active widgets", function()
        -- senario 1: 2nd widget removes the 3rd widget in the stack
        local call_signals = {0, 0, 0}
        UIManager._window_stack = {
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[1] = call_signals[1] + 1
                    end
                }
            },
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[2] = call_signals[2] + 1
                    end
                }
            },
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[3] = call_signals[3] + 1
                        table.remove(UIManager._window_stack, 2)
                    end
                }
            },
            {widget = {handleEvent = function()end}},
        }

        UIManager:sendEvent("foo")
        assert.is.same(call_signals[1], 1)
        assert.is.same(call_signals[2], 0)
        assert.is.same(call_signals[3], 1)

        -- senario 2: top widget removes itself
        call_signals = {0, 0, 0}
        UIManager._window_stack = {
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[1] = call_signals[1] + 1
                    end
                }
            },
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[2] = call_signals[2] + 1
                    end
                }
            },
            {
                widget = {
                    is_always_active = true,
                    handleEvent = function()
                        call_signals[3] = call_signals[3] + 1
                        table.remove(UIManager._window_stack, 3)
                    end
                }
            },
        }

        UIManager:sendEvent("foo")
        assert.is.same(call_signals[1], 1)
        assert.is.same(call_signals[2], 1)
        assert.is.same(call_signals[3], 1)
    end)

    it("should handle stack change when broadcasting events", function()
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        UIManager._window_stack[1] = nil
                    end
                }
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(#UIManager._window_stack, 0)

        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        UIManager._window_stack[1] = nil
                        UIManager._window_stack[2] = nil
                        UIManager._window_stack[3] = nil
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        assert.falsy(true);
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        assert.falsy(true);
                    end
                }
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(#UIManager._window_stack, 0)
    end)

    it("should handle stack change when closing widgets", function()
        local widget_1 = {handleEvent = function()end}
        local widget_2  = {
            handleEvent = function()
                UIManager:close(widget_1)
            end
        }
        local widget_3 = {handleEvent = function()end}
        UIManager._window_stack = {
            {widget = widget_1},
            {widget = widget_2},
            {widget = widget_3},
        }
        UIManager:close(widget_2)

        assert.is.same(1, #UIManager._window_stack)
        assert.is.same(widget_3, UIManager._window_stack[1].widget)
    end)
end)
