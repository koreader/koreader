describe("device module", function()
    -- luacheck: push ignore
    local mock_fb, mock_input
    local iopen = io.open
    local ipopen = io.popen
    local osgetenv = os.getenv
    local ffi, C

    setup(function()
        local fb = require("ffi/framebuffer")
        mock_fb = {
            new = function()
                return {
                    device = package.loaded.device,
                    bb = require("ffi/blitbuffer").new(600, 800, 1),
                    getRawSize = function() return {w = 600, h = 800} end,
                    getWidth = function() return 600 end,
                    getHeight = function() return 800 end,
                    getDPI = function() return 72 end,
                    setViewport = function() end,
                    getRotationMode = function() return 0 end,
                    getScreenMode = function() return "portrait" end,
                    setRotationMode = function() end,
                    scaleByDPI = fb.scaleByDPI,
                    scaleBySize = fb.scaleBySize,
                    setWindowTitle = function() end,
                    refreshFull = function() end,
                    getHWNightmode = function() return false end,
                    setupDithering = function() end,
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
        package.loaded["ffi/framebuffer_mxcfb"] = mock_fb
        mock_input = require("device/input")
        mock_input.input = {}
        mock_input.gameControllerRumble = function() return false end
        stub(mock_input, "open")
        stub(os, "getenv")
        stub(os, "execute")
    end)

    after_each(function()
        -- Don't let UIManager hang on to a stale Device reference, and vice-versa...
        package.unload("device")
        package.unload("device/generic/device")
        package.unload("device/generic/powerd")
        package.unload("ui/uimanager")
        package.unload("apps/reader/readerui")
        mock_input.open:revert()
        os.getenv:revert()
        os.execute:revert()

        os.getenv = osgetenv
        io.open = iopen
        io.popen = ipopen
    end)

    describe("kobo", function()
        local time
        local NickelConf
        setup(function()
            time = require("ui/time")
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

        it("should setup eventAdjustHooks properly for input on trilogy C", function()
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                elseif key == "MODEL_NUMBER" then
                    return "320"
                else
                    return osgetenv(key)
                end
            end)

            package.loaded["device/kobo/device"] = nil
            local kobo_dev = require("device/kobo/device")
            kobo_dev:init()
            local Screen = kobo_dev.screen

            assert.is.same("Kobo_trilogy_C", kobo_dev.model)
            local x, y = Screen:getWidth()-5, 10
            -- mirror x, then switch_xy
            local ev_x = {
                type = C.EV_ABS,
                code = C.ABS_X,
                value = y,
                time = time:realtime(),
            }
            local ev_y = {
                type = C.EV_ABS,
                code = C.ABS_Y,
                value = Screen:getWidth() - 1 - x,
                time = time:realtime(),
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
                elseif key == "MODEL_NUMBER" then
                    return "320"
                else
                    return osgetenv(key)
                end
            end)

            package.loaded["device/kobo/device"] = nil
            local kobo_dev = require("device/kobo/device")
            kobo_dev:init()
            local Screen = kobo_dev.screen

            assert.is.same("Kobo_trilogy_C", kobo_dev.model)
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
                value = Screen:getWidth() - 1 - x,
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
    end)

    describe("kindle", function()
        local function make_io_open_kindle_model_override(model_no)
            return function(filename, mode)
                if filename == "/proc/usid" then
                    return {
                        read = function() return model_no end,
                        close = function() end
                    }
                else
                    return iopen(filename, mode)
                end
            end
        end

        insulate("without framework", function()
            local mock_lipc = {
                init = function()
                    return {
                        set_int_property = mock(function() end),
                        get_int_property = function() return 0 end,
                        get_string_property = function() return "string prop" end,
                        set_string_property = function() end,
                        register_int_property = function() return {} end,
                        close = function () end,
                    }
                end
            }
            package.loaded["liblipclua"] = mock_lipc

            before_each(function()
                os.getenv.invokes(function(e)
                    if e == "STOP_FRAMEWORK" then
                        return "yes"
                    else
                        return osgetenv(e)
                    end
                end)
            end)

            it("sets framework_lipc_handle", function ()
                io.open = make_io_open_kindle_model_override("B013XX")

                local kindle_dev = require("device/kindle/device")
                assert.is.truthy(kindle_dev.framework_lipc_handle)
            end)

            it("reactivates voyage whispertouch keys", function ()
                io.open = make_io_open_kindle_model_override("B013XX")

                local kindle_dev = require("device/kindle/device")
                local fw_lipc_handle = kindle_dev.framework_lipc_handle

                kindle_dev:init()

                for _, fsr_prop in pairs{
                    "fsrkeypadEnable",
                    "fsrkeypadPrevEnable",
                    "fsrkeypadNextEnable"
                } do
                    assert.stub(fw_lipc_handle.set_int_property).was.called_with(
                        fw_lipc_handle, "com.lab126.deviced", fsr_prop, 1
                    )
                end
            end)
        end)

        insulate("with framework", function()
            it("does not set framework_lipc_handle", function ()
                io.open = make_io_open_kindle_model_override("B013XX")

                local kindle_dev = require("device/kindle/device")
                assert.is.falsy(kindle_dev.framework_lipc_handle)
            end)
        end)

        it("should initialize voyage without error", function()
            io.open = make_io_open_kindle_model_override("B013XX")

            local kindle_dev = require("device/kindle/device")
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
            package.unload("device/kindle/device")
            io.open = make_io_open_kindle_model_override("G0B0GCXXX")

            stub(mock_input.input, "waitForEvent")
            mock_input.input.waitForEvent.returns(true, {
                {
                    type = C.EV_ABS,
                    time = {
                        usec = 450565,
                        sec = 1471081881
                    },
                    code = 24, -- C.ABS_PRESSURE
                    value = 16
                }
            })

            local UIManager = require("ui/uimanager")
            stub(UIManager, "onRotation")

            local kindle_dev = require("device/kindle/device")
            assert.is.same("KindleOasis", kindle_dev.model)
            kindle_dev:init()
            kindle_dev:lockGSensor(true)

            kindle_dev.input:waitEvent()
            assert.stub(UIManager.onRotation).was_called()

            mock_input.input.waitForEvent:revert()
            UIManager.onRotation:revert()
        end)
    end)

    describe("Flush book Settings for", function()
        it("Kobo", function()
            os.getenv.invokes(function(key)
                if key == "PRODUCT" then
                    return "trilogy"
                elseif key == "MODEL_NUMBER" then
                    return "320"
                else
                    return osgetenv(key)
                end
            end)
            -- Bypass frontend/device probeDevice, while making sure that it points to the right implementation
            local Device = require("device/kobo/device")
            -- Apparently common isn't setup properly in the testsuite, so we can't have nice things
            stub(Device, "initNetworkManager")
            stub(Device, "suspend")
            Device:init()
            -- Don't poke the RTC
            Device.wakeup_mgr = require("device/wakeupmgr"):new{rtc = require("device/kindle/mockrtc")}
            -- Don't poke the fl
            Device.powerd.fl = nil
            package.loaded.device = Device

            local UIManager = require("ui/uimanager")
            -- Generic's onPowerEvent may request a repaint, but we can't do that
            stub(UIManager, "forceRePaint")
            UIManager:init()

            local sample_pdf = "spec/front/unit/data/tall.pdf"
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:doShowReader(sample_pdf)
            local readerui = ReaderUI.instance
            stub(readerui, "onFlushSettings")
            UIManager.event_handlers.PowerPress()
            UIManager.event_handlers.PowerRelease()
            assert.stub(readerui.onFlushSettings).was_called()

            UIManager.forceRePaint:revert()
            Device.initNetworkManager:revert()
            Device.suspend:revert()
            readerui.onFlushSettings:revert()
            Device.screen_saver_mode = false
            readerui:onClose()
        end)

        it("Cervantes", function()
            io.popen = function(filename, mode)
                if filename:find("/usr/bin/ntxinfo") then
                    return {
                        read = function()
                            return 68 -- Cervantes4
                        end,
                        close = function() end
                    }
                else
                    return ipopen(filename, mode)
                end
            end

            local Device = require("device/cervantes/device")
            stub(Device, "initNetworkManager")
            stub(Device, "suspend")
            Device:init()
            Device.powerd.fl = nil
            package.loaded.device = Device

            local UIManager = require("ui/uimanager")
            stub(UIManager, "forceRePaint")
            UIManager:init()

            local sample_pdf = "spec/front/unit/data/tall.pdf"
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:doShowReader(sample_pdf)
            local readerui = ReaderUI.instance
            stub(readerui, "onFlushSettings")
            UIManager.event_handlers.PowerPress()
            UIManager.event_handlers.PowerRelease()
            assert.stub(readerui.onFlushSettings).was_called()

            UIManager.forceRePaint:revert()
            Device.initNetworkManager:revert()
            Device.suspend:revert()
            readerui.onFlushSettings:revert()
            Device.screen_saver_mode = false
            readerui:onClose()
        end)

        it("Remarkable", function()
            io.open = function(filename, mode)
                if filename == "/usr/bin/xochitl" then
                    return {
                        read = function()
                            return true
                        end,
                        close = function() end
                    }
                elseif filename == "/sys/devices/soc0/machine" then
                    return {
                        read = function()
                            return "reMarkable", "generic"
                        end,
                        close = function() end
                    }
                else
                    return iopen(filename, mode)
                end
            end
            local Device = require("device/remarkable/device")
            stub(Device, "initNetworkManager")
            stub(Device, "suspend")
            Device:init()
            Device.powerd.fl = nil
            package.loaded.device = Device

            local UIManager = require("ui/uimanager")
            stub(UIManager, "forceRePaint")
            UIManager:init()

            local sample_pdf = "spec/front/unit/data/tall.pdf"
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:doShowReader(sample_pdf)
            local readerui = ReaderUI.instance
            stub(readerui, "onFlushSettings")
            UIManager.event_handlers.PowerPress()
            UIManager.event_handlers.PowerRelease()
            assert.stub(readerui.onFlushSettings).was_called()

            UIManager.forceRePaint:revert()
            Device.initNetworkManager:revert()
            Device.suspend:revert()
            readerui.onFlushSettings:revert()
            Device.screen_saver_mode = false
            readerui:onClose()
        end)

        it("SDL", function()
            local Device = require("device/sdl/device")
            stub(Device, "initNetworkManager")
            stub(Device, "suspend")
            Device:init()
            package.loaded.device = Device

            local UIManager = require("ui/uimanager")
            UIManager:init()

            local sample_pdf = "spec/front/unit/data/tall.pdf"
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:doShowReader(sample_pdf)
            local readerui = ReaderUI.instance
            stub(readerui, "onFlushSettings")
            -- UIManager.event_handlers.PowerPress() -- We only fake a Release event on the Emu
            UIManager.event_handlers.PowerRelease()
            assert.stub(readerui.onFlushSettings).was_called()

            Device.initNetworkManager:revert()
            Device.suspend:revert()
            readerui.onFlushSettings:revert()
            Device.screen_saver_mode = false
            readerui:onClose()
        end)
    end)
    -- luacheck: pop
end)
