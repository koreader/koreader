describe("touch probe module", function()
    local x, y
    setup(function()
        require("commonrequire")
    end)

    it("should probe properly for kobo touch", function()
        local Device = require("device")
        local TouchProbe = require("tools/kobo_touch_probe"):new{}
        local need_to_switch_xy
        TouchProbe.saveSwitchXYSetting = function(_, new_need_to_switch_xy)
            need_to_switch_xy = new_need_to_switch_xy
        end
        -- for kobo touch, we have mirror_x, then switch_xy
        -- tap lower right corner
        x, y = Device.screen:getWidth()-40, Device.screen:getHeight()-40
        need_to_switch_xy = nil
        TouchProbe:onTapProbe(nil, {
            pos = {
                x = y,
                y = Device.screen:getWidth()-x,
            }
        })
        assert.is.same(TouchProbe.curr_probe_step, 1)
        assert.truthy(need_to_switch_xy)

        -- now only test mirror_x
        -- tap lower right corner
        x, y = Device.screen:getWidth()-40, Device.screen:getHeight()-40
        need_to_switch_xy = nil
        TouchProbe:onTapProbe(nil, {
            pos = {
                x = Device.screen:getWidth()-x,
                y = y,
            }
        })
        assert.is.same(TouchProbe.curr_probe_step, 1)
        assert.falsy(need_to_switch_xy)

        -- now only test switch_xy
        -- tap lower right corner
        x, y = Device.screen:getWidth()-40, Device.screen:getHeight()-40
        need_to_switch_xy = nil
        TouchProbe:onTapProbe(nil, {
            pos = {
                x = y,
                y = x,
            }
        })
        assert.is.same(TouchProbe.curr_probe_step, 2)
        assert.falsy(need_to_switch_xy)
        -- tap upper right corner
        x, y = Device.screen:getWidth()-40, 40
        TouchProbe:onTapProbe(nil, {
            pos = {
                x = y,
                y = x,
            }
        })
        assert.is.same(TouchProbe.curr_probe_step, 2)
        assert.truthy(need_to_switch_xy)
    end)
end)
