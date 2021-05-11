describe("device module", function()
    -- luacheck: push ignore
    local mock_fb, mock_input
    local iopen = io.open
    local osgetenv = os.getenv
    local ffi, C

    setup(function()
        mock_fb = {
            new = function()
                return {
                    getRawSize = function() return {w = 600, h = 800} end,
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
        ffi = require("ffi")
        C = ffi.C
        require("ffi/linux_input_h")
        require("document/canvascontext"):init(require("device"))
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
                    return osgetenv(key)
                end
            end)

            package.loaded['device/kobo/device'] = nil
            local kobo_dev = require("device/kobo/device")
            kobo_dev:init()
            local Screen = kobo_dev.screen

            assert.is.same("Kobo_trilogy", kobo_dev.model)
            assert.truthy(kobo_dev:needsTouchScreenProbe())
            G_reader_settings:saveSetting("kobo_touch_switch_xy", true)
            kobo_dev:touchScreenProbe()
            local x, y = Screen:getWidth()-5, 10
            -- mirror x, then switch_xy
            local ev_x = {
                type = C.EV_ABS,
                code = C.ABS_X,
                value = y,
                time = TimeVal:realtime(),
            }
            local ev_y = {
                type = C.EV_ABS,
                code = C.ABS_Y,
                value = Screen:getWidth()-x,
                time = TimeVal:realtime(),
            }

            kobo_dev.input:eventAdjustHook(ev_x)
            kobo_dev.input:eventAdjustHook(ev_y)
            assert.is.same(x, ev_y.value)
            assert.is.same(C.ABS_X, ev_y.code)
            assert.is.same(y, ev_x.value)
            assert.is.same(C.ABS_Y, ev_x.code)

            -- reset eventAdjustHook
            kobo_dev.input.eventAdjustHook = function() end
        end)

        it("should setup eventAdjustHooks properly for trilogy with non-epoch ev time", function()
            -- This has no more value since #6798 as ev time can now stay
            -- non-epoch. Adjustments are made on first event handled, and
            -- have only effects when handling long-press (so, the long-press
            -- for dict lookup tests with test this).
            -- We just check here it still works with non-epoch ev time, as previous test
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                else
                    return osgetenv(key)
                end
            end)

            package.loaded['device/kobo/device'] = nil
            local kobo_dev = require("device/kobo/device")
            kobo_dev:init()
            local Screen = kobo_dev.screen

            assert.is.same("Kobo_trilogy", kobo_dev.model)
            assert.truthy(kobo_dev:needsTouchScreenProbe())
            kobo_dev:touchScreenProbe()
            local x, y = Screen:getWidth()-5, 10
            local ev_x = {
                type = C.EV_ABS,
                code = C.ABS_X,
                value = y,
                time = {sec = 1000}
            }
            local ev_y = {
                type = C.EV_ABS,
                code = C.ABS_Y,
                value = Screen:getWidth()-x,
                time = {sec = 1000}
            }

            kobo_dev.input:eventAdjustHook(ev_x)
            kobo_dev.input:eventAdjustHook(ev_y)
            assert.is.same(x, ev_y.value)
            assert.is.same(C.ABS_X, ev_y.code)
            assert.is.same(y, ev_x.value)
            assert.is.same(C.ABS_Y, ev_x.code)

            -- reset eventAdjustHook
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
                        read = function() return "B013XX" end,
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
            -- NOTE: fl_max + 1 since #5989
            assert.is.same(kindle_dev.powerd.fl_max, 25)
        end)

        it("should toggle frontlight", function()
            io.open = function(filename, mode)
                if filename == "/proc/usid" then
                    return {
                        read = function() return "B013XX" end,
                        close = function() end
                    }
                elseif filename == "/sys/class/backlight/max77696-bl/brightness" then
                    return {
                        read = function() return 12 end,
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
            assert.is.same(kindle_dev.powerd.fl_intensity, 5)

            kindle_dev.powerd:toggleFrontlight()
            assert.stub(os.execute).was_called_with(
                "printf '%s' 0 > /sys/class/backlight/max77696-bl/brightness")
            -- Here be shenanigans: we don't override powerd's fl_intensity when we turn the light off,
            -- so that we can properly turn it back on at the previous intensity ;)
            assert.is.same(kindle_dev.powerd.fl_intensity, 5)
            -- But if we were to cat /sys/class/backlight/max77696-bl/brightness, it should now be 0.

            kindle_dev.powerd:toggleFrontlight()
            assert.is.same(kindle_dev.powerd.fl_intensity, 5)
            -- And /sys/class/backlight/max77696-bl/brightness is now !0
            -- (exact value is HW-dependent, each model has a different curve, we let lipc do the work for us).
        end)

        it("oasis should interpret orientation event", function()
            package.unload('device/kindle/device')
            io.open = function(filename, mode)
                if filename == "/proc/usid" then
                    return {
                        read = function()
                            return "G0B0GCXXX"
                        end,
                        close = function() end
                    }
                else
                    return iopen(filename, mode)
                end
            end

            mock_ffi_input = require('ffi/input')
            stub(mock_ffi_input, "waitForEvent")
            mock_ffi_input.waitForEvent.returns(true, {
                {
                    type = C.EV_ABS,
                    time = {
                        usec = 450565,
                        sec = 1471081881
                    },
                    code = 24, -- C.ABS_PRESSURE -> ABS_OASIS_ORIENTATION
                    value = 16
                }
            })

            local UIManager = require("ui/uimanager")
            stub(UIManager, "onRotation")

            local kindle_dev = require('device/kindle/device')
            assert.is.same("KindleOasis", kindle_dev.model)
            kindle_dev:init()
            kindle_dev:lockGSensor(true)

            kindle_dev.input:waitEvent()
            assert.stub(UIManager.onRotation).was_called()

            mock_ffi_input.waitForEvent:revert()
            UIManager.onRotation:revert()
        end)
    end)
    -- luacheck: pop
end)
