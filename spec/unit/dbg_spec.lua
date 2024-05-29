describe("Dbg module", function()
    local dbg, dbg_on
    setup(function()
        package.path = "?.lua;common/?.lua;frontend/?.lua;" .. package.path
        dbg = require("dbg")
        dbg_on = dbg.is_on
    end)

    after_each(function()
        if dbg_on then
            dbg:turnOn()
        else
            dbg:turnOff()
        end
    end)

    it("setup mt.__call and guard after tunrnOn is called", function()
        dbg:turnOff()
        local old_call = getmetatable(dbg).__call
        local old_guard = dbg.guard
        dbg:turnOn()
        assert.is_not.same(old_call, getmetatable(dbg).__call)
        assert.is_not.same(old_guard, dbg.guard)
    end)

    it("should call pre_gard callback", function()
        local called = false
        local foo = {}
        function foo:bar() end
        assert.is.falsy(called)

        dbg:turnOff()
        assert.is.falsy(called)

        dbg:turnOn()
        dbg:guard(foo, 'bar', function() called = true end)
        foo:bar()
        assert.is.truthy(called)
    end)

    it("should call post_gard callback", function()
        local called = false
        local foo = {}
        function foo:bar() end
        assert.is.falsy(called)

        dbg:turnOff()
        assert.is.falsy(called)

        dbg:turnOn()
        dbg:guard(foo, 'bar', nil, function() called = true end)
        foo:bar()
        assert.is.truthy(called)
    end)

    it("should return all values returned by the guarded function", function()
        local called = false
        local re
        local foo = {}
        function foo:bar() return 1 end
        assert.is.falsy(called)

        dbg:turnOn()
        dbg:guard(foo, 'bar', function() called = true end)
        re = {foo:bar()}
        assert.is.truthy(called)
        assert.is.same(re, {1})

        called = false
        function foo:bar() return 1, 2, 3 end
        dbg:guard(foo, 'bar', function() called = true end)
        assert.is.falsy(called)
        re = {foo:bar()}
        assert.is.same(re, {1, 2, 3})
    end)

    it("should set verbose", function()
        assert.is_nil(dbg.is_verbose)
        dbg:setVerbose(true)
        assert.is_true(dbg.is_verbose)
        dbg:setVerbose(false)
        assert.is_false(dbg.is_verbose)
        dbg:setVerbose()
        assert.is_nil(dbg.is_verbose)
    end)
end)
