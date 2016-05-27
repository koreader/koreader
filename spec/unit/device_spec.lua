describe("device module", function()
    local mock_fb, mock_input
    setup(function()
        mock_fb = {
            new = function()
                return {
                    getSize = function() return {w = 600, h = 800} end,
                    getWidth = function() return 600 end,
                    getDPI = function() return 72 end,
                    setViewport = function() end
                }
            end
        }
        require("commonrequire")
    end)

    describe("kobo", function()
        local TimeVal
        setup(function()
            TimeVal = require("ui/timeval")
            mock_fb = {
                new = function()
                    return {
                        getSize = function() return {w = 600, h = 800} end,
                        getWidth = function() return 600 end,
                        getDPI = function() return 72 end,
                        setViewport = function() end
                    }
                end
            }
        end)

        it("should initialize properly on Kobo dahlia", function()
            package.loaded['ffi/framebuffer_mxcfb'] = mock_fb
            stub(os, "getenv")
            os.getenv.returns("dahlia")
            local kobo_dev = require("device/kobo/device")

            mock_input = require('device/input')
            stub(mock_input, "open")
            kobo_dev:init()
            assert.is.same("Kobo_dahlia", kobo_dev.model)

            package.loaded['ffi/framebuffer_mxcfb'] = nil
            os.getenv:revert()
            mock_input.open:revert()
        end)

        it("should setup eventAdjustHooks properly for input in trilogy", function()
            local saved_getenv = os.getenv
            stub(os, "getenv")
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                else
                    return saved_getenv(key)
                end
            end)
            package.loaded['device/kobo/device'] = nil
            package.loaded['ffi/framebuffer_mxcfb'] = mock_fb
            mock_input = require('device/input')
            stub(mock_input, "open")

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

            package.loaded['ffi/framebuffer_mxcfb'] = nil
            os.getenv:revert()
            mock_input.open:revert()
            -- reset eventAdjustHook
            kobo_dev.input.eventAdjustHook = function() end
            kobo_dev.touch_probe_ev_epoch_time = true
        end)

        it("should setup eventAdjustHooks properly for trilogy with non-epoch ev time", function()
            local saved_getenv = os.getenv
            stub(os, "getenv")
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                else
                    return saved_getenv(key)
                end
            end)
            package.loaded['device/kobo/device'] = nil
            package.loaded['ffi/framebuffer_mxcfb'] = mock_fb
            mock_input = require('device/input')
            stub(mock_input, "open")

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

            package.loaded['ffi/framebuffer_mxcfb'] = nil
            os.getenv:revert()
            mock_input.open:revert()
            kobo_dev.input.eventAdjustHook = function() end
        end)

        it("should flush book settings before suspend", function()
            local sample_pdf = "spec/front/unit/data/tall.pdf"
            local ReaderUI = require("apps/reader/readerui")
            local Device = require("device")
            local NickelConf = require("device/kobo/nickel_conf")

            stub(NickelConf.frontLightLevel, "get")
            stub(NickelConf.frontLightState, "get")
            NickelConf.frontLightLevel.get.returns(1)
            NickelConf.frontLightState.get.returns(0)

            local UIManager = require("ui/uimanager")
            stub(Device, "suspend")
            stub(Device.powerd, "beforeSuspend")
            stub(Device, "isKobo")

            Device.isKobo.returns(true)
            local saved_noop = UIManager._resetAutoSuspendTimer
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
            NickelConf.frontLightLevel.get:revert()
            NickelConf.frontLightState.get:revert()
            UIManager._startAutoSuspend = nil
            UIManager._stopAutoSuspend = nil
            UIManager._resetAutoSuspendTimer = saved_noop
            readerui:onClose()
        end)
    end)

    describe("kindle", function()
        it("should initialize voyager without error", function()
            package.loaded['ffi/framebuffer_mxcfb'] = mock_fb
            stub(io, "open")
            io.open.returns({
                read = function()
                    return "XX13XX"
                end,
                close = function() end
            })
            mock_input = require('device/input')
            stub(mock_input, "open")

            local kindle_dev = require("device/kindle/device")
            assert.is.same(kindle_dev.model, "KindleVoyage")
            kindle_dev:init()
            assert.is.same(kindle_dev.input.event_map[104], "LPgBack")
            assert.is.same(kindle_dev.input.event_map[109], "LPgFwd")
            assert.is.same(kindle_dev.powerd.fl_min, 0)
            assert.is.same(kindle_dev.powerd.fl_max, 24)

            io.open:revert()
            package.loaded['ffi/framebuffer_mxcfb'] = nil
            mock_input.open:revert()
        end)

        it("should toggle frontlight", function()
            package.loaded['ffi/framebuffer_mxcfb'] = mock_fb
            stub(io, "open")
            io.open.returns({
                read = function()
                    return "12"
                end,
                close = function() end
            })
            mock_input = require('device/input')
            stub(mock_input, "open")
            stub(os, "execute")

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

            io.open:revert()
            package.loaded['ffi/framebuffer_mxcfb'] = nil
            mock_input.open:revert()
            os.execute:revert()
        end)
    end)
end)
