describe("device module", function()
    -- luacheck: push ignore
    local mock_fb, mock_input
    local iopen = io.open
    local osgetenv = os.getenv

    setup(function()
        mock_fb = {
            new = function()
                return {
                    getSize = function() return {w = 600, h = 800} end,
                    getWidth = function() return 600 end,
                    getDPI = function() return 72 end,
                    setViewport = function() end,
                    getRotationMode = function() return 0 end,
                    getScreenMode = function() return "portrait" end,
                    setRotationMode = function() end,
                }
            end
        }
        require("commonrequire")
        package.unloadAll()
    end)

    before_each(function()
        package.loaded['ffi/framebuffer_mxcfb'] = mock_fb
        mock_input = require('device/input')
        stub(mock_input, "open")
        stub(os, "getenv")
        stub(os, "execute")
    end)

    after_each(function()
        mock_input.open:revert()
        os.getenv:revert()
        os.execute:revert()

        os.getenv = osgetenv
        io.open = iopen
    end)

    describe("kobo", function()
        local TimeVal
        local NickelConf
        setup(function()
            TimeVal = require("ui/timeval")
            NickelConf = require("device/kobo/nickel_conf")
        end)

        before_each(function()
            stub(NickelConf.frontLightLevel, "get")
            NickelConf.frontLightLevel.get.returns(0)
            stub(NickelConf.frontLightState, "get")
        end)

        after_each(function()
            NickelConf.frontLightLevel.get:revert()
            NickelConf.frontLightState.get:revert()
        end)

        it("should initialize properly on Kobo dahlia", function()
            os.getenv.returns("dahlia")
            local kobo_dev = require("device/kobo/device")

            kobo_dev:init()
            assert.is.same("Kobo_dahlia", kobo_dev.model)
        end)

        it("should setup eventAdjustHooks properly for input in trilogy", function()
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                else
                    return saved_getenv(key)
                end
            end)

            package.loaded['device/kobo/device'] = nil
            local kobo_dev = require("device/kobo/device")
            kobo_dev:init()
            local Screen = kobo_dev.screen

            kobo_dev.touch_probe_ev_epoch_time = false
            assert.is.same("Kobo_trilogy", kobo_dev.model)
            assert.truthy(kobo_dev:needsTouchScreenProbe())
            G_reader_settings:saveSetting("kobo_touch_switch_xy", true)
            kobo_dev:touchScreenProbe()
            local x, y = Screen:getWidth()-5, 10
            local EV_ABS = 3
            local ABS_X = 00
            local ABS_Y = 01
            -- mirror x, then switch_xy
            local ev_x = {
                type = EV_ABS,
                code = ABS_X,
                value = y,
            }
            local ev_y = {
                type = EV_ABS,
                code = ABS_Y,
                value = Screen:getWidth()-x,
            }

            kobo_dev.input:eventAdjustHook(ev_x)
            kobo_dev.input:eventAdjustHook(ev_y)
            assert.is.same(x, ev_y.value)
            assert.is.same(ABS_X, ev_y.code)
            assert.is.same(y, ev_x.value)
            assert.is.same(ABS_Y, ev_x.code)

            -- reset eventAdjustHook
            kobo_dev.input.eventAdjustHook = function() end
            kobo_dev.touch_probe_ev_epoch_time = true
        end)

        it("should setup eventAdjustHooks properly for trilogy with non-epoch ev time", function()
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                else
                    return saved_getenv(key)
                end
            end)
            local kobo_dev = require("device/kobo/device")
            kobo_dev:init()
            local Screen = kobo_dev.screen

            assert.is.same("Kobo_trilogy", kobo_dev.model)
            local x, y = Screen:getWidth()-5, 10
            local EV_ABS = 3
            local ABS_X = 00
            local ABS_Y = 01
            -- mirror x, then switch_xy
            local ev_x = {
                type = EV_ABS,
                code = ABS_X,
                value = x,
                time = {sec = 1000}
            }
            local ev_y = {
                type = EV_ABS,
                code = ABS_Y,
                value = y,
                time = {sec = 1000}
            }

            assert.truthy(kobo_dev.touch_probe_ev_epoch_time)
            G_reader_settings:saveSetting("kobo_touch_switch_xy", true)
            kobo_dev:touchScreenProbe()

            kobo_dev.input:eventAdjustHook(ev_x)
            kobo_dev.input:eventAdjustHook(ev_y)
            local cur_sec = TimeVal:now().sec
            assert.truthy(cur_sec - ev_x.time.sec < 10)
            assert.truthy(cur_sec - ev_y.time.sec < 10)

            kobo_dev.input.eventAdjustHook = function() end
        end)

        it("should flush book settings before suspend", function()
            local sample_pdf = "spec/front/unit/data/tall.pdf"
            local ReaderUI = require("apps/reader/readerui")
            local Device = require("device")

            NickelConf.frontLightLevel.get.returns(1)
            NickelConf.frontLightState.get.returns(0)

            local UIManager = require("ui/uimanager")
            stub(Device, "suspend")
            stub(Device.powerd, "beforeSuspend")
            stub(Device, "isKobo")

            Device.isKobo.returns(true)
            UIManager:init()

            ReaderUI:doShowReader(sample_pdf)
            local readerui = ReaderUI._getRunningInstance()
            stub(readerui, "onFlushSettings")
            UIManager.event_handlers["PowerPress"]()
            UIManager.event_handlers["PowerRelease"]()
            assert.stub(readerui.onFlushSettings).was_called()

            Device.suspend:revert()
            Device.powerd.beforeSuspend:revert()
            Device.isKobo:revert()
            readerui.onFlushSettings:revert()
            readerui:onClose()
        end)
    end)

    describe("kindle", function()
        it("should initialize voyage without error", function()
            io.open = function(filename, mode)
                if filename == "/proc/usid" then
                    return {
                        read = function() return "XX13XX" end,
                        close = function() end
                    }
                else
                    return iopen(filename, mode)
                end
            end

            local kindle_dev = require('device/kindle/device')
            assert.is.same(kindle_dev.model, "KindleVoyage")
            kindle_dev:init()
            assert.is.same(kindle_dev.input.event_map[104], "LPgBack")
            assert.is.same(kindle_dev.input.event_map[109], "LPgFwd")
            assert.is.same(kindle_dev.powerd.fl_min, 0)
            assert.is.same(kindle_dev.powerd.fl_max, 24)
        end)

        it("should toggle frontlight", function()
            io.open = function(filename, mode)
                if filename == "/proc/usid" then
                    return {
                        read = function() return "XX13XX" end,
                        close = function() end
                    }
                elseif filename == "/sys/class/backlight/max77696-bl/brightness" then
                    return {
                        read = function() return "12" end,
                        close = function() end
                    }
                else
                    return iopen(filename, mode)
                end
            end

            local kindle_dev = require("device/kindle/device")
            kindle_dev:init()

            assert.is.same(kindle_dev.powerd.fl_intensity, 12)
            kindle_dev.powerd:setIntensity(5)
            assert.stub(os.execute).was_called_with(
                "echo -n 5 > /sys/class/backlight/max77696-bl/brightness")
            assert.is.same(kindle_dev.powerd.fl_intensity, 5)

            kindle_dev.powerd:toggleFrontlight()
            assert.stub(os.execute).was_called_with(
                "echo -n 0 > /sys/class/backlight/max77696-bl/brightness")
            assert.is.same(kindle_dev.powerd.fl_intensity, 5)

            kindle_dev.powerd:toggleFrontlight()
            assert.stub(os.execute).was_called_with(
                "echo -n 5 > /sys/class/backlight/max77696-bl/brightness")
        end)

        it("oasis should interpret orientation event", function()
            package.unload('device/kindle/device')
            io.open = function(filename, mode)
                if filename == "/proc/usid" then
                    return {
                        read = function()
                            return "XXX0GCXXX"
                        end,
                        close = function() end
                    }
                else
                    return iopen(filename, mode)
                end
            end

            mock_ffi_input = require('ffi/input')
            stub(mock_ffi_input, "waitForEvent")
            mock_ffi_input.waitForEvent.returns({
                type = 3,
                time = {
                    usec = 450565,
                    sec = 1471081881
                },
                code = 24,
                value = 16
            })

            local UIManager = require("ui/uimanager")
            stub(UIManager, "onRotation")

            local kindle_dev = require('device/kindle/device')
            assert.is.same("KindleOasis", kindle_dev.model)
            kindle_dev:init()

            kindle_dev.input:waitEvent()
            assert.stub(UIManager.onRotation).was_called()

            mock_ffi_input.waitForEvent:revert()
            UIManager.onRotation:revert()
        end)
    end)
    -- luacheck: pop
end)
