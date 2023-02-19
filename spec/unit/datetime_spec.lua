describe("datetime module", function()
    local datetime
    setup(function()
        require("commonrequire")
        datetime = require("datetime")
    end)

    describe("secondsToClock()", function()
        it("should convert seconds to 00:00 format", function()
            assert.is_equal("00:00",
                            datetime.secondsToClock(0, true))
            assert.is_equal("00:01",
                            datetime.secondsToClock(60, true))
        end)
        it("should round seconds to minutes in 00:00 format", function()
            assert.is_equal("00:01",
                            datetime.secondsToClock(89, true))
            assert.is_equal("00:02",
                            datetime.secondsToClock(90, true))
            assert.is_equal("00:02",
                            datetime.secondsToClock(110, true))
            assert.is_equal("00:02",
                            datetime.secondsToClock(120, true))
            assert.is_equal("01:00",
                            datetime.secondsToClock(3600, true))
            assert.is_equal("01:00",
                            datetime.secondsToClock(3599, true))
            assert.is_equal("01:00",
                            datetime.secondsToClock(3570, true))
            assert.is_equal("00:59",
                            datetime.secondsToClock(3569, true))
        end)
        it("should convert seconds to 00:00:00 format", function()
            assert.is_equal("00:00:00",
                            datetime.secondsToClock(0))
            assert.is_equal("00:01:00",
                            datetime.secondsToClock(60))
            assert.is_equal("00:01:29",
                            datetime.secondsToClock(89))
            assert.is_equal("00:01:30",
                            datetime.secondsToClock(90))
            assert.is_equal("00:01:50",
                            datetime.secondsToClock(110))
            assert.is_equal("00:02:00",
                            datetime.secondsToClock(120))
        end)
        it("should convert seconds to 0d00:00:00 format", function()
            assert.is_equal("00:00:00",
                            datetime.secondsToClock(0, false, true))
            assert.is_equal("00:02:00",
                            datetime.secondsToClock(120, false, true))
            assert.is_equal("5d00:02:00",
                            datetime.secondsToClock(432120, false, true))
        end)
        it("should convert seconds to 0d00:00 format", function()
            assert.is_equal("00:00",
                            datetime.secondsToClock(0, true, true))
            assert.is_equal("00:02",
                            datetime.secondsToClock(120, true, true))
            assert.is_equal("5d00:02",
                            datetime.secondsToClock(432110, true, true))
            assert.is_equal("5d00:02",
                            datetime.secondsToClock(432120, true, true))
        end)
    end)

    describe("secondsToHClock()", function()
        it("should convert seconds to 0' format", function()
            assert.is_equal("0'",
                            datetime.secondsToHClock(0, true))
            assert.is_equal("0'",
                            datetime.secondsToHClock(29, true))
            assert.is_equal("1'",
                            datetime.secondsToHClock(60, true))
        end)
        it("should round seconds to minutes in 0h00' format", function()
            assert.is_equal("1'",
                            datetime.secondsToHClock(89, true))
            assert.is_equal("2'",
                            datetime.secondsToHClock(90, true))
            assert.is_equal("2'",
                            datetime.secondsToHClock(110, true))
            assert.is_equal("2'",
                            datetime.secondsToHClock(120, true))
            assert.is_equal("1h00'",
                            datetime.secondsToHClock(3600, true))
            assert.is_equal("1h00'",
                            datetime.secondsToHClock(3599, true))
            assert.is_equal("1h00'",
                            datetime.secondsToHClock(3570, true))
            assert.is_equal("59'",
                            datetime.secondsToHClock(3569, true))
            assert.is_equal("10h01'",
                            datetime.secondsToHClock(36060, true))
        end)
        it("should round seconds to minutes in 0h 0m (thinspace) format", function()
            assert.is_equal("1m",
                datetime.secondsToHClock(89, true, true))
            assert.is_equal("2m",
                datetime.secondsToHClock(90, true, true))
            assert.is_equal("2m",
                datetime.secondsToHClock(110, true, true))
            assert.is_equal("1h\xE2\x80\x890m",
                datetime.secondsToHClock(3600, true, true))
            assert.is_equal("1h\xE2\x80\x890m",
                datetime.secondsToHClock(3599, true, true))
            assert.is_equal("59m",
                datetime.secondsToHClock(3569, true, true))
            assert.is_equal("10h\xE2\x80\x891m",
                datetime.secondsToHClock(36060, true, true))
        end)
        it("should round seconds to minutes in 0h 0m (hairspace) format", function()
            assert.is_equal("1m",
                datetime.secondsToHClock(89, true, true, false, true))
            assert.is_equal("2m",
                datetime.secondsToHClock(90, true, true, false, true))
            assert.is_equal("2m",
                datetime.secondsToHClock(110, true, true, false, true))
            assert.is_equal("1h\xE2\x80\x8A0m",
                datetime.secondsToHClock(3600, true, true, false, true))
            assert.is_equal("1h\xE2\x80\x8A0m",
                datetime.secondsToHClock(3599, true, true, false, true))
            assert.is_equal("59m",
                datetime.secondsToHClock(3569, true, true, false, true))
            assert.is_equal("10h\xE2\x80\x8A1m",
                datetime.secondsToHClock(36060, true, true, false, true))
        end)
        it("should convert seconds to 0h00'00'' format", function()
            assert.is_equal("0\"",
                            datetime.secondsToHClock(0))
            assert.is_equal("1'00\"",
                            datetime.secondsToHClock(60))
            assert.is_equal("1'29\"",
                            datetime.secondsToHClock(89))
            assert.is_equal("1'30\"",
                            datetime.secondsToHClock(90))
            assert.is_equal("1'50\"",
                            datetime.secondsToHClock(110))
            assert.is_equal("2'00\"",
                            datetime.secondsToHClock(120))
        end)
    end)

    describe("secondsToClockDuration()", function()
        it("should change type based on format", function()
            assert.is_equal("10h01'30\"",
                            datetime.secondsToClockDuration("modern", 36090, false))
            assert.is_equal("10h\xE2\x80\x891m\xE2\x80\x8930s",
                            datetime.secondsToClockDuration("letters", 36090, false))
            assert.is_equal("10:01:30",
                            datetime.secondsToClockDuration("classic", 36090, false))
            assert.is_equal("10:01:30",
                            datetime.secondsToClockDuration("unknown", 36090, false))
            assert.is_equal("10:01:30",
                            datetime.secondsToClockDuration(nil, 36090, false))
        end)
        it("should pass along withoutSeconds", function()
            assert.is_equal("10h01'30\"",
                            datetime.secondsToClockDuration("modern", 36090, false))
            assert.is_equal("10h02'",
                            datetime.secondsToClockDuration("modern", 36090, true))
            assert.is_equal("10h\xE2\x80\x891m\xE2\x80\x8930s",
                            datetime.secondsToClockDuration("letters", 36090, false))
            assert.is_equal("10h\xE2\x80\x892m",
                            datetime.secondsToClockDuration("letters", 36090, true))
            assert.is_equal("10:01:30",
                            datetime.secondsToClockDuration("classic", 36090, false))
            assert.is_equal("10:02",
                            datetime.secondsToClockDuration("classic", 36090, true))
        end)
        it("should pass along withDays", function()
            assert.is_equal("58h01'30\"",
                            datetime.secondsToClockDuration("modern", 208890, false, false))
            assert.is_equal("2d10h01'30\"",
                            datetime.secondsToClockDuration("modern", 208890, false, true))
            assert.is_equal("58h\xE2\x80\x891m\xE2\x80\x8930s",
                            datetime.secondsToClockDuration("letters", 208890, false, false))
            assert.is_equal("2d\xE2\x80\x8910h\xE2\x80\x891m\xE2\x80\x8930s",
                            datetime.secondsToClockDuration("letters", 208890, false, true))
            assert.is_equal("58:01:30",
                            datetime.secondsToClockDuration("classic", 208890, false, false))
            assert.is_equal("2d10:01:30",
                            datetime.secondsToClockDuration("classic", 208890, false, true))
        end)
    end)

    describe("secondsToDate()", function()
        it("should deliver a date string", function()
            local time = { year=2022, month=12, day=6, hour=13, min=30, sec=35 }
            local time_s = os.time(time)

            assert.is_equal("2022-12-06",
                            datetime.secondsToDate(time_s))
            assert.is_equal("2022-12-07",
                            datetime.secondsToDate(time_s + 86400)) -- one day later
            assert.is_equal("Tue Dec 06 2022",
                            datetime.secondsToDate(time_s, true))
            assert.is_equal("Wed Dec 07 2022",
                            datetime.secondsToDate(time_s + 86400, true))
        end)
    end)
    describe("secondsToDateTime()", function()
        it("should should deliver a date and time string", function()
            local time = { year=2022, month=11, day=20, hour=9, min=57, sec=39 }
            local time_s = os.time(time)

            assert.is_equal("2022-11-20  9:57",
                            datetime.secondsToDateTime(time_s))
            assert.is_equal("2022-11-21  9:57",
                            datetime.secondsToDateTime(time_s + 86400))

            assert.is_equal("2022-11-20  9:57 AM",
                            datetime.secondsToDateTime(time_s, true))
            assert.is_equal("2022-11-21  9:57 AM",
                            datetime.secondsToDateTime(time_s + 86400, true))

            assert.is_equal("Sun Nov 20 2022 9:57",
                            datetime.secondsToDateTime(time_s, false, true))
            assert.is_equal("Mon Nov 21 2022 9:57",
                            datetime.secondsToDateTime(time_s + 86400, false, true))

            assert.is_equal("Sun Nov 20 2022 9:57 AM",
                            datetime.secondsToDateTime(time_s, true, true))
            assert.is_equal("Mon Nov 21 2022 9:57 AM",
                            datetime.secondsToDateTime(time_s + 86400, true, true))
        end)
    end)
end)
