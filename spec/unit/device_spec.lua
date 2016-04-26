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
