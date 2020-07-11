describe("InputContainer widget", function()
    local InputContainer, Screen
    setup(function()
        require("commonrequire")
        InputContainer = require("ui/widget/container/inputcontainer")
        Screen = require("device").screen
    end)

    it("should register touch zones", function()
        local ic = InputContainer:new{}
        assert.is.same(#ic._ordered_touch_zones, 0)

        ic:registerTouchZones({
            {
                id = "foo",
                ges = "swipe",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function() end,
            },
            {
                id = "bar",
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0.1, ratio_w = 0.5, ratio_h = 1,
                },
                handler = function() end,
            },
        })

        local screen_width, screen_height = Screen:getWidth(), Screen:getHeight()
        assert.is.same(#ic._ordered_touch_zones, 2)
        assert.is.same("foo", ic._ordered_touch_zones[1].def.id)
        assert.is.same(ic._ordered_touch_zones[1].def.handler, ic._ordered_touch_zones[1].handler)
        assert.is.same("bar", ic._ordered_touch_zones[2].def.id)
        assert.is.same("tap", ic._ordered_touch_zones[2].gs_range.ges)
        assert.is.same(0, ic._ordered_touch_zones[2].gs_range.range.x)
        assert.is.same(math.floor(screen_height * 0.1), ic._ordered_touch_zones[2].gs_range.range.y)
        assert.is.same(screen_width / 2, ic._ordered_touch_zones[2].gs_range.range.w)
        assert.is.same(screen_height, ic._ordered_touch_zones[2].gs_range.range.h)
    end)

    it("should support overrides for touch zones", function()
        local ic = InputContainer:new{}
        ic:registerTouchZones({
            {
                id = "foo",
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function() end,
            },
            {
                id = "bar",
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 0.5, ratio_h = 1,
                },
                handler = function() end,
            },
            {
                id = "baz",
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 0.5, ratio_h = 1,
                },
                overrides = { 'foo' },
                handler = function() end,
            },
        })
        assert.is.same(ic._ordered_touch_zones[1].def.id, 'baz')
        assert.is.same(ic._ordered_touch_zones[2].def.id, 'foo')
        assert.is.same(ic._ordered_touch_zones[3].def.id, 'bar')
    end)

    it("should support indirect overrides for touch zones", function()
        local ic = InputContainer:new{}
        local dummy_screen_size = {ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,}
        ic:registerTouchZones({
            {
                id = "readerfooter_tap",
                ges = "tap",
                screen_zone = dummy_screen_size,
                overrides = {
                    'tap_forward', 'tap_backward', 'readermenu_tap',
                },
                handler = function() end,
            },
            {
                id = "readerfooter_hold",
                ges = "hold",
                screen_zone = dummy_screen_size,
                overrides = {'readerhighlight_hold'},
                handler = function() end,
            },
            {
                id = "readerhighlight_tap",
                ges = "tap",
                screen_zone = dummy_screen_size,
                overrides = { 'tap_forward', 'tap_backward', },
                handler = function() end,
            },
            {
                id = "readerhighlight_hold",
                ges = "hold",
                screen_zone = dummy_screen_size,
                handler = function() end,
            },
            {
                id = "readerhighlight_hold_release",
                ges = "hold_release",
                screen_zone = dummy_screen_size,
                handler = function() end,
            },
            {
                id = "readerhighlight_hold_pan",
                ges = "hold_pan",
                rate = 2.0,
                screen_zone = dummy_screen_size,
                handler = function() end,
            },
            {
                id = "tap_forward",
                ges = "tap",
                screen_zone = dummy_screen_size,
                handler = function() end,
            },
            {
                id = "tap_backward",
                ges = "tap",
                screen_zone = dummy_screen_size,
                handler = function() end,
            },
            {
                id = "readermenu_tap",
                ges = "tap",
                overrides = { "tap_forward", "tap_backward", },
                screen_zone = dummy_screen_size,
                handler = function() end,
            },
        })

        assert.is.same('readerfooter_tap', ic._ordered_touch_zones[1].def.id)
        assert.is.same('readerhighlight_tap', ic._ordered_touch_zones[2].def.id)
        assert.is.same('readermenu_tap', ic._ordered_touch_zones[3].def.id)
        assert.is.same('tap_forward', ic._ordered_touch_zones[4].def.id)
        assert.is.same('tap_backward', ic._ordered_touch_zones[5].def.id)
        assert.is.same('readerfooter_hold', ic._ordered_touch_zones[6].def.id)
        assert.is.same('readerhighlight_hold', ic._ordered_touch_zones[7].def.id)
        assert.is.same('readerhighlight_hold_release', ic._ordered_touch_zones[8].def.id)
        assert.is.same('readerhighlight_hold_pan', ic._ordered_touch_zones[9].def.id)
    end)
end)
