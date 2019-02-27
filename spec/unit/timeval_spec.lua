describe("TimeVal module", function()
    local TimeVal, dbg, dbg_on
    setup(function()
        require("commonrequire")
        TimeVal = require("ui/timeval")
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

    it("should subtract", function()
        local timev1 = TimeVal:new{ sec = 5, usec = 5000}
        local timev2 = TimeVal:new{ sec = 10, usec = 6000}

        assert.is.same({sec = 5,usec = 1000}, timev2 - timev1)
        assert.is.same({sec = -5,usec = -1000}, timev1 - timev2)
    end)

    it("should guard against reverse subtraction logic", function()
        dbg:turnOn()
        TimeVal = package.reload("ui/timeval")
        local timev1 = TimeVal:new{ sec = 5, usec = 5000}
        local timev2 = TimeVal:new{ sec = 10, usec = 5000}

        assert.has.errors(function() return timev1 - timev2 end)
    end)
end)
