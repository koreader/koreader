describe("Time module", function()
    local time, dbg, dbg_on
    setup(function()
        require("commonrequire")
        time = require("ui/time")
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

    it("should set", function()
        local time1 = time.s(12)
        local time2 = time.ms(12)
        local time3 = time.us(12)

        assert.is.same(12000000, time1)
        assert.is.same(12000, time2)
        assert.is.same(12, time3)
    end)

    it("should convert", function()
        local time1 = 12000000
        local time2 = 12000
        local time3 = 12
        local time4 = time.s(12) + time.us(40)
        local time5 = time.s(12) + time.us(60)

        assert.is.same(12, time.to_s(time1))
        assert.is.same(12000, time.to_ms(time1))
        assert.is.same(12000000, time.to_us(time1))

        assert.is.same(0.012, time.to_s(time2))
        assert.is.same(12, time.to_ms(time2))
        assert.is.same(12000, time.to_us(time2))

        assert.is.same(0.000012, time.to_s(time3))
        assert.is.same(math.floor(0.012), time.to_ms(time3))
        assert.is.same(12, time.to_us(time3))

        assert.is.same(12.0000, time.to_number(time4))
        assert.is.same(12.0001, time.to_number(time5))
    end)


    it("should add", function()
        local time1 = time.s(5) + time.us(5000)
        local time2 = time.s(10) + time.us(6000)
        local time3 = time.s(10) + time.us(50000000)

        assert.is.same(time.s(15) + time.us(11000), time1 + time2)
        assert.is.same(time.s(65) + time.us(5000), time1 + time3)
    end)

    it("should subtract", function()
        local time1 = time.s(5.005)
        local time2 = time.s(10.006)

        assert.is.same(time.s(5.001), time2 - time1)
        local backwards_sub = time1 - time2
        assert.is.same(time.s(-5.001), backwards_sub)

        -- Check that to/from float conversions behave, even for negative values.
        assert.is.same(-5.001, time.to_number(backwards_sub))
        assert.is.same(time.s(-6) + time.us(999000), time.s(-5.001))

        local tv = time.s(-6) + time.us(1000)
        assert.is.is_true(math.abs(-5.999 - time.to_number(tv)) < 1e-9) -- we only have nano second precision
        assert.is.same(time.s(-6) + time.us(1000), time.s(-5.999))

        -- We lose precision because of rounding if we go higher resolution than a ms...
        tv = time.s(-6) + time.us(101)
        assert.is.is_true(math.abs(-5.9999 - time.to_number(tv)) < 1e-9) -- ns precision
        assert.is.same(time.s(-6) + time.us(100), time.s(-5.9999))
        --                                 ^ precision loss

        tv = time.s(-6) + time.us(11)
        assert.is.same(-6, time.to_number(tv))
        --              ^ precision loss
        assert.is.same(time.s(-6) + time.us(10), time.s(-5.99999))
        --                                ^ precision loss

        tv = time.s(-6) + time.us(1)
        assert.is.same(-6, time.to_number(tv))
        --              ^ precision loss
        assert.is.same(time.s(-6) + time.us(1), time.s(-5.999999))
    end)

    it("should derive sec and usec from more than 1 sec worth of usec", function()
        local time1 = time.s(5) + time.us(5000000)

        assert.is.same(time.s(10), time1)
    end)

    it("should compare", function()
        local time1 = time.s(5) + time.us(5000)
        local time2 = time.s(10) + time.us(6000)
        local time3 = time.s(5) + time.us(5000)
        local time4 = time.s(5) + time.us(6000)

        assert.is_true(time2 > time1)
        assert.is_false(time2 < time1)
        assert.is_true(time2 >= time1)

        assert.is_true(time4 > time1)
        assert.is_false(time4 < time1)
        assert.is_true(time4 >= time1)

        assert.is_true(time1 < time2)
        assert.is_false(time1 > time2)
        assert.is_true(time1 <= time2)

        assert.is_true(time1 == time3)
        assert.is_false(time1 == time2)
        assert.is_true(time1 >= time3)
        assert.is_true(time1 <= time3)
    end)

    it("should calculate durations", function()
        local time1 = time.s(5) + time.us(500000)
        local function now() return time.s(10) end
        local now_save = time.now
        time.now = now
        assert.is.equal(time.to_s(time.s(4) + time.us(500000)), time.to_s(time.since(time1)))
        assert.is.equal(time.to_ms(time.s(4) + time.us(500000)), time.to_ms(time.since(time1)))
        assert.is.equal(time.to_us(time.s(4) + time.us(500000)), time.to_us(time.since(time1)))
        time.now = now_save
    end)
end)
