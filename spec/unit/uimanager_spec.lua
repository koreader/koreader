describe("UIManager spec", function()
    local time, UIManager
    local now, wait_until
    local noop = function() end

    -- commonrequire is needed by setup and other describe blocks
    local commonrequire = require("commonrequire")
    time = require("ui/time") -- time is used by multiple describe blocks

    setup(function()
        -- Keep original UIManager for existing tests if they don't need mocks
        UIManager = require("ui/uimanager")
    end)

    it("should consume due tasks", function()
        now = time.now()
        local future = now + time.s(60000)
        local future2 = future + time.s(5)
        UIManager:quit()
        UIManager._task_queue = {
            { time = future2, action = noop, args = {} },
            { time = future, action = noop, args = {} },
            { time = now, action = noop, args = {} },
            { time = now - time.us(5), action = noop, args = {} },
            { time = now - time.s(10), action = noop, args = {} },
        }

        UIManager:_checkTasks()
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same(future, UIManager._task_queue[2].time)
        assert.are.same(future2, UIManager._task_queue[1].time)
    end)

    it("should calculate wait_until properly in checkTasks routine", function()
        now = time.now()
        local future_time = now + time.s(60000)
        UIManager:quit()
        UIManager._task_queue = {
            { time = future_time, action = noop, args = {} },
            { time = now, action = noop, args = {} },
            { time = now - time.us(5), action = noop, args = {} },
            { time = now - time.s(10), action = noop, args = {} },
        }

        wait_until, now = UIManager:_checkTasks()
        assert.are.same(future_time, wait_until)
    end)

    it("should return nil wait_until properly in checkTasks routine", function()
        now = time.now()
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = noop, args = {} },
            { time = now - time.us(5), action = noop, args = {} },
            { time = now - time.s(10), action = noop, args = {} },
        }

        wait_until, now = UIManager:_checkTasks()
        assert.are.same(nil, wait_until)
    end)

    it("should insert new task properly in empty task queue", function()
        now = time.now()
        UIManager:quit()
        assert.are.same(0, #UIManager._task_queue)
        UIManager:scheduleIn(50, 'foo')
        assert.are.same(1, #UIManager._task_queue)
        assert.are.same('foo', UIManager._task_queue[1].action)
    end)

    it("should insert new task properly in single task queue", function()
        now = time.now()
        local future_time = now + time.s(10000)
        UIManager:quit()
        UIManager._task_queue = {
            { time = future_time, action = '1', args = {} },
        }

        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'quz')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same('quz', UIManager._task_queue[2].action)

        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '1', args = {} },
        }

        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'foo')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same('foo', UIManager._task_queue[1].action)
        UIManager:scheduleIn(155, 'bar')
        assert.are.same(3, #UIManager._task_queue)
        assert.are.same('bar', UIManager._task_queue[1].action)
    end)

    it("should insert new task in descendant order", function()
        now = time.now()
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '3', args = {} },
            { time = now - time.us(5), action = '2', args = {} },
            { time = now - time.s(10), action = '1', args = {} },
        }

        -- insert into the tail slot
        UIManager:scheduleIn(10, 'foo')
        assert.are.same('foo', UIManager._task_queue[1].action)
        -- insert into the second slot
        UIManager:schedule(now - time.s(5), 'bar')
        assert.are.same('bar', UIManager._task_queue[4].action)
        -- insert into the head slot
        UIManager:schedule(now - time.s(15), 'baz')
        assert.are.same('baz', UIManager._task_queue[6].action)
        -- insert into the last second slot
        UIManager:scheduleIn(5, 'qux')
        assert.are.same('qux', UIManager._task_queue[2].action)
        -- insert into the middle slot
        UIManager:schedule(now - time.us(1), 'quux')
        assert.are.same('quux', UIManager._task_queue[4].action)
    end)

    it("should insert new tasks with same times before existing tasks", function()
        local ffiutil = require("ffi/util")

        now = time.now()
        UIManager:quit()

        -- insert task "5s" between "now" and "10s"
        UIManager:schedule(now, "now");
        assert.are.same("now", UIManager._task_queue[1].action)
        UIManager:schedule(now + time.s(10), "10s");
        assert.are.same("10s", UIManager._task_queue[1].action)
        UIManager:schedule(now + time.s(5), "5s");
        assert.are.same("5s", UIManager._task_queue[2].action)

        -- insert task in place of "10s", as it'll expire shortly after "10s"
        -- NOTE: Can't use this here right now, as time.now, which is used internally,
        -- may or may not have moved, depending on host's performance and clock granularity
        -- (especially if host is fast and/or COARSE is available).
        -- But a short wait fixes this here.
        ffiutil.usleep(1000)
        UIManager:scheduleIn(10, 'foo') -- is a bit later than "10s", as time.now() is used internally
        assert.are.same('foo', UIManager._task_queue[1].action)

        -- insert task in place of "10s", which was just shifted by foo
        UIManager:schedule(now + time.s(10), 'bar')
        assert.are.same('bar', UIManager._task_queue[2].action)

        -- insert task in place of "bar"
        UIManager:schedule(now + time.s(10), 'baz')
        assert.are.same('baz', UIManager._task_queue[2].action)

        -- insert task in place of "5s"
        UIManager:schedule(now + time.s(5), 'nix')
        assert.are.same('nix', UIManager._task_queue[5].action)
        -- "barba" replaces "nix"
        UIManager:scheduleIn(5, 'barba') -- is a bit later than "5s", as time.now() is used internally
        assert.are.same('barba', UIManager._task_queue[5].action)

        -- "mama is scheduled now and as such inserted in "now"'s place
        UIManager:schedule(now, 'mama')
        assert.are.same('mama', UIManager._task_queue[8].action)

        -- "papa" is shortly after "now", so inserted in its place
        -- NOTE: For the same reason as above, test this last, as time.now may not have moved...
        UIManager:nextTick('papa') -- is a bit later than "now"
        assert.are.same('papa', UIManager._task_queue[8].action)

        -- "letta" is shortly after "papa", so inserted in its place
        UIManager:tickAfterNext('letta')
        assert.are.same("function", type(UIManager._task_queue[8].action))
    end)

    it("should unschedule all the tasks with the same action", function()
        now = time.now()
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '3', args = {} },
            { time = now - time.us(5), action = '2', args = {} },
            { time = now - time.us(6), action = '3', args = {} },
            { time = now - time.s(10), action = '1', args = {} },
            { time = now - time.s(15), action = '3', args = {} },
        }

        -- insert into the tail slot
        UIManager:unschedule('3')
        assert.are.same({
            { time = now - time.us(5), action = '2', args = {} },
            { time = now - time.s(10), action = '1', args = {} },
        }, UIManager._task_queue)
    end)

    it("should not have race between unschedule and _checkTasks", function()
        now = time.now()
        local run_count = 0
        local task_to_remove = function()
            run_count = run_count + 1
        end
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = task_to_remove, args = {} }, -- this will be removed
            { time = now - time.us(5), action = task_to_remove, args = {} }, -- this will be removed
            {
                time = now - time.s(10),
                action = function() -- this will be called, too
                    run_count = run_count + 1
                    UIManager:unschedule(task_to_remove)
                end,
                args = {},
            },
            { time = now - time.s(15), action = task_to_remove, args = {} }, -- this will be called
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
        -- scenario 1: 2nd widget removes the 3rd widget in the stack
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

        -- scenario 2: top widget removes itself
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

describe("UIManager input blocking with BlockedPoints", function()
    local UIManager_BlockedPointsTest -- Renamed to avoid conflict with UIManager above
    local mock_BlockedPoints
    local send_event_spy
    local logger_dbg_spy
    local UIManagerInjector = commonrequire.preload("ui/uimanager")
    local Geom = require("ui/geometry")
    -- Event module is not strictly needed for creating event tables, but good for consistency
    -- local Event = require("ui/event")
    local Logger = require("logger") -- To spy on logger.dbg

    before_each(function()
        -- Mock BlockedPoints
        mock_BlockedPoints = {
            isBlocked = function(x, y) return false end -- Default: not blocked
        }

        -- Spy on logger.dbg
        -- Note: Busted's spy replaces the function on the table.
        -- We need to save and restore the original if other tests need it,
        -- or if Logger.dbg is a complex function.
        -- For simple cases, spy.restore() in after_each is often enough.
        if Logger.dbg_original == nil then -- Store original only once
            Logger.dbg_original = Logger.dbg
        end
        logger_dbg_spy = spy.new(function(...) end)
        Logger.dbg = logger_dbg_spy

        -- Inject mock BlockedPoints
        UIManager_BlockedPointsTest = UIManagerInjector({
            ["ui/blockedpoints"] = mock_BlockedPoints,
            ["logger"] = Logger, -- Ensure our spied logger is used by the module
        })

        -- Spy on the method that would be called if event is not blocked
        send_event_spy = spy.on(UIManager_BlockedPointsTest, "sendEvent")
        if not UIManager_BlockedPointsTest.event_handlers then UIManager_BlockedPointsTest.event_handlers = {} end
        UIManager_BlockedPointsTest.event_handlers.__default__ = send_event_spy -- capture default processing
    end)

    after_each(function()
        spy.restore() -- Restores all spies created by spy.on and spy.new
        if Logger.dbg_original then
            Logger.dbg = Logger.dbg_original -- Restore original logger.dbg
            -- Logger.dbg_original = nil -- Avoid restoring multiple times if before_each runs again in another context
        end
        -- Clean up G_reader_settings if UIManager init creates it (UIManager might depend on it)
        -- local ReaderSettings = package.loaded.luasettings -- path to ReaderSettings
        -- if ReaderSettings and ReaderSettings.G_reader_settings_backup then
        --     _G.G_reader_settings = ReaderSettings.G_reader_settings_backup
        --     ReaderSettings.G_reader_settings_backup = nil
        -- end
    end)

    it("should block input event if BlockedPoints:isBlocked returns true", function()
        mock_BlockedPoints.isBlocked = function(x, y)
            if x == 50 and y == 50 then return true end
            return false
        end

        local test_event = { name = "TestTapBlocked", ges = "tap", pos = Geom:new{ x = 50, y = 50, w = 0, h = 0 } }
        UIManager_BlockedPointsTest:handleInputEvent(test_event)

        assert.spy(logger_dbg_spy).was.called_with("UIManager: Blocked input event at", 50, 50)
        assert.spy(send_event_spy).was.not_called()
    end)

    it("should process input event if BlockedPoints:isBlocked returns false", function()
        mock_BlockedPoints.isBlocked = function(x, y)
            if x == 60 and y == 60 then return false end
            return true -- Block other coordinates to be sure
        end

        local test_event = { name = "TestTapAllowed", ges = "tap", pos = Geom:new{ x = 60, y = 60, w = 0, h = 0 } }
        UIManager_BlockedPointsTest:handleInputEvent(test_event)

        assert.spy(logger_dbg_spy).was.not_called_with("UIManager: Blocked input event at", 60, 60)
        -- Check if default handler was called (which is our send_event_spy)
        assert.spy(send_event_spy).was.called_with(UIManager_BlockedPointsTest, test_event)
    end)

    it("should process event normally if event has no 'pos' field", function()
        local test_event = { name = "TestKeyPress", ges = "key_press", code = 123 } -- No pos field
        local is_blocked_spy = spy.on(mock_BlockedPoints, "isBlocked")

        UIManager_BlockedPointsTest:handleInputEvent(test_event)

        assert.spy(is_blocked_spy).was.not_called()
        assert.spy(logger_dbg_spy).was.not_called_with("UIManager: Blocked input event at")
        assert.spy(send_event_spy).was.called_with(UIManager_BlockedPointsTest, test_event)
    end)

    it("should process event normally if event.pos is not a table with x,y numbers", function()
        local test_event_nil_xy = { name = "TestMalformedPosNil", ges = "tap", pos = Geom:new{} } -- x,y might be nil
        local test_event_string_xy = { name = "TestMalformedPosStr", ges = "tap", pos = Geom:new{x="foo", y="bar"} }
        local is_blocked_spy = spy.on(mock_BlockedPoints, "isBlocked")

        UIManager_BlockedPointsTest:handleInputEvent(test_event_nil_xy)
        assert.spy(is_blocked_spy).was.not_called() -- BlockedPoints:isBlocked should not be called
        assert.spy(send_event_spy).was.called_with(UIManager_BlockedPointsTest, test_event_nil_xy)
        send_event_spy:reset() -- Reset spy for next call

        UIManager_BlockedPointsTest:handleInputEvent(test_event_string_xy)
        assert.spy(is_blocked_spy).was.not_called() -- Type check for x,y as numbers fails
        assert.spy(send_event_spy).was.called_with(UIManager_BlockedPointsTest, test_event_string_xy)
    end)

    it("should handle event if input_event is not a table (e.g. string event name)", function()
        local test_event_string = "CustomPowerOffEvent"
        -- Mock this specific handler on the UIManager instance being tested
        UIManager_BlockedPointsTest.event_handlers[test_event_string] = spy.new(function() end)

        local is_blocked_spy = spy.on(mock_BlockedPoints, "isBlocked")

        UIManager_BlockedPointsTest:handleInputEvent(test_event_string)

        assert.spy(is_blocked_spy).was.not_called()
        assert.spy(UIManager_BlockedPointsTest.event_handlers[test_event_string]).was.called()
        -- Default handler (send_event_spy) should not be called if a specific handler exists
        assert.spy(send_event_spy).was.not_called()
    end)
end)
