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
end)
