describe("InputContainer widget", function()
    local InputContainer, Screen
    setup(function()
        require("commonrequire")
        InputContainer = require("ui/widget/container/inputcontainer")
        Screen = require("device").screen
    end)

    it("should register touch zones", function()
        local ic = InputContainer:new{}
        assert.is.same(#ic._touch_zones, 0)

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
        assert.is.same(#ic._touch_zones, 2)
        assert.is.same("foo", ic._touch_zones[1].def.id)
        assert.is.same(ic._touch_zones[1].def.handler, ic._touch_zones[1].handler)
        assert.is.same("bar", ic._touch_zones[2].def.id)
        assert.is.same("tap", ic._touch_zones[2].gs_range.ges)
        assert.is.same(0, ic._touch_zones[2].gs_range.range.x)
        assert.is.same(screen_height * 0.1, ic._touch_zones[2].gs_range.range.y)
        assert.is.same(screen_width / 2, ic._touch_zones[2].gs_range.range.w)
        assert.is.same(screen_height, ic._touch_zones[2].gs_range.range.h)
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
        assert.is.same(ic._touch_zones[1].def.id, 'baz')
        assert.is.same(ic._touch_zones[2].def.id, 'foo')
        assert.is.same(ic._touch_zones[3].def.id, 'bar')
    end)
end)
