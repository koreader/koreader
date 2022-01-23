describe("UIManager spec", function()
    local TimeVal, UIManager
    local now, wait_until
    local noop = function() end

    setup(function()
        require("commonrequire")
        TimeVal = require("ui/timeval")
        UIManager = require("ui/uimanager")
    end)

    it("should consume due tasks", function()
        now = TimeVal:now()
        local future = TimeVal:new{ sec = now.sec + 60000, usec = now.usec }
        local future2 = TimeVal:new{ sec = future.sec + 5, usec = future.usec}
        UIManager:quit()
        UIManager._task_queue = {
            { time = TimeVal:new{ sec = now.sec - 10, usec = now.usec }, action = noop, args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = noop, args = {}, argc = 0 },
            { time = now, action = noop, args = {}, argc = 0 },
            { time = future, action = noop, args = {}, argc = 0 },
            { time = future2, action = noop, args = {}, argc = 0 },
        }
        UIManager:_checkTasks()
        assert.are.same(2, #UIManager._task_queue, 2)
        assert.are.same(future, UIManager._task_queue[1].time)
        assert.are.same(future2, UIManager._task_queue[2].time)
    end)

    it("should calcualte wait_until properly in checkTasks routine", function()
        now = TimeVal:now()
        local future = TimeVal:new{ sec = now.sec + 60000, usec = now.usec }
        UIManager:quit()
        UIManager._task_queue = {
            { time = TimeVal:new{ sec = now.sec - 10, usec = now.usec }, action = noop, args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = noop, args = {}, argc = 0 },
            { time = now, action = noop, args = {}, argc = 0 },
            { time = future, action = noop, args = {}, argc = 0 },
            { time = TimeVal:new{ sec = future.sec + 5, usec = future.usec }, action = noop, args = {}, argc = 0 },
        }
        wait_until, now = UIManager:_checkTasks()
        assert.are.same(future, wait_until)
    end)

    it("should return nil wait_until properly in checkTasks routine", function()
        now = TimeVal:now()
        UIManager:quit()
        UIManager._task_queue = {
            { time = TimeVal:new{ sec = now.sec - 10, usec = now.usec }, action = noop, args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = noop, args = {}, argc = 0 },
            { time = now, action = noop, args = {}, argc = 0 },
        }
        wait_until, now = UIManager:_checkTasks()
        assert.are.same(nil, wait_until)
    end)

    it("should insert new task properly in empty task queue", function()
        now = TimeVal:now()
        UIManager:quit()
        UIManager._task_queue = {}
        assert.are.same(0, #UIManager._task_queue)
        UIManager:scheduleIn(50, 'foo')
        assert.are.same(1, #UIManager._task_queue)
        assert.are.same('foo', UIManager._task_queue[1].action)
    end)

    it("should insert new task properly in single task queue", function()
        now = TimeVal:now()
        local future = TimeVal:new{ sec = now.sec + 10000, usec = now.usec }
        UIManager:quit()
        UIManager._task_queue = {
            { time = future, action = '1', args = {}, argc = 0 },
        }
        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'quz')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same('quz', UIManager._task_queue[1].action)

        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '1', args = {}, argc = 0 },
        }
        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'foo')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same('foo', UIManager._task_queue[2].action)
        UIManager:scheduleIn(155, 'bar')
        assert.are.same(3, #UIManager._task_queue)
        assert.are.same('bar', UIManager._task_queue[3].action)
    end)

    it("should insert new task in ascendant order", function()
        now = TimeVal:now()
        UIManager:quit()
        UIManager._task_queue = {
            { time = TimeVal:new{ sec = now.sec - 10, usec = now.usec }, action = '1', args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = '2', args = {}, argc = 0 },
            { time = now, action = '3', args = {}, argc = 0 },
        }
        -- insert into the tail slot
        UIManager:scheduleIn(10, 'foo')
        assert.are.same('foo', UIManager._task_queue[4].action)
        -- insert into the second slot
        UIManager:schedule(TimeVal:new{ sec = now.sec - 5, usec = now.usec }, 'bar')
        assert.are.same('bar', UIManager._task_queue[2].action)
        -- insert into the head slot
        UIManager:schedule(TimeVal:new{ sec = now.sec - 15, usec = now.usec }, 'baz')
        assert.are.same('baz', UIManager._task_queue[1].action)
        -- insert into the last second slot
        UIManager:scheduleIn(5, 'qux')
        assert.are.same('qux', UIManager._task_queue[6].action)
        -- insert into the middle slot
        UIManager:schedule(TimeVal:new{ sec = now.sec, usec = now.usec - 1 }, 'quux')
        assert.are.same('quux', UIManager._task_queue[5].action)
    end)

    it("should unschedule all the tasks with the same action", function()
        now = TimeVal:now()
        UIManager:quit()
        UIManager._task_queue = {
            { time = TimeVal:new{ sec = now.sec - 15, usec = now.usec }, action = '3', args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec - 10, usec = now.usec }, action = '1', args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 6 }, action = '3', args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = '2', args = {}, argc = 0 },
            { time = now, action = '3', args = {}, argc = 0 },
        }
        -- insert into the tail slot
        UIManager:unschedule('3')
        assert.are.same({
            { time = TimeVal:new{ sec = now.sec - 10, usec = now.usec }, action = '1', args = {}, argc = 0 },
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = '2', args = {}, argc = 0 },
        }, UIManager._task_queue)
    end)

    it("should not have race between unschedule and _checkTasks", function()
        now = TimeVal:now()
        local run_count = 0
        local task_to_remove = function()
            run_count = run_count + 1
        end
        UIManager:quit()
        UIManager._task_queue = {
            { time = TimeVal:new{ sec = now.sec, usec = now.usec - 5 }, action = task_to_remove, args = {}, argc = 0 },
            {
                time = TimeVal:new{ sec = now.sec - 10, usec = now.usec },
                action = function()
                    run_count = run_count + 1
                    UIManager:unschedule(task_to_remove)
                end,
                args = {},
                argc = 0
            },
            { time = now, action = task_to_remove, args = {}, argc = 0 },
        }
        UIManager:_checkTasks()
        assert.are.same(2, run_count)
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

            assert.equals(2, UIManager._window_stack[1].widget.x_prefix_test_number)
            assert.equals(1, UIManager._window_stack[2].widget.x_prefix_test_number)
        end)
        it("should insert second modal widget on top of first modal widget", function()
            UIManager:show({
                x_prefix_test_number = 3,
                modal = true,
                handleEvent = function()
                    return true
                end
            })

            assert.equals(2, UIManager._window_stack[1].widget.x_prefix_test_number)
            assert.equals(1, UIManager._window_stack[2].widget.x_prefix_test_number)
            assert.equals(3, UIManager._window_stack[3].widget.x_prefix_test_number)
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
        assert.is.same(1, call_signals[1])
        assert.is.same(1, call_signals[2])
        assert.is.same(1, call_signals[3])
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

        -- Remember that the stack is processed top to bottom!
        -- Test making a hole in the middle of the stack.
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        assert.truthy(true)
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        assert.falsy(true)
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        assert.falsy(true)
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        table.remove(UIManager._window_stack, #UIManager._window_stack - 2)
                        table.remove(UIManager._window_stack, #UIManager._window_stack - 2)
                        table.remove(UIManager._window_stack, #UIManager._window_stack - 1)
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        assert.truthy(true)
                    end
                }
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(2, #UIManager._window_stack)

        -- Test inserting a new widget in the stack
        local new_widget = {
            widget = {
                handleEvent = function()
                    assert.truthy(true)
                end
            }
        }
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        table.insert(UIManager._window_stack, new_widget)
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        assert.truthy(true)
                    end
                }
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(3, #UIManager._window_stack)
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
