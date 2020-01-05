describe("DepGraph module", function()
    local DepGraph
    setup(function()
        require("commonrequire")
        DepGraph = require("depgraph")
    end)

    it("should serialize simple graph", function()
        local dg = DepGraph:new{}
        dg:addNode('a1', {'a2', 'b1'})
        dg:addNode('b1', {'a2', 'c1'})
        dg:addNode('c1')
        assert.are.same({'a2', 'c1', 'b1', 'a1'}, dg:serialize())
    end)

    it("should serialize complex graph", function()
        local dg = DepGraph:new{}
        dg:addNode('readerfooter_tap')
        dg:addNode('readerfooter_hold', {})
        dg:addNode('readerhighlight_tap', {'tap_backward', 'tap_forward'})
        dg:addNode('tap_backward', {'readerfooter_tap', 'readermenu_tap'})
        dg:addNode('tap_forward', {'readerfooter_tap', 'readermenu_tap'})
        dg:addNode('readerhighlight_hold', {'readerfooter_hold'})
        dg:addNode('readerhighlight_hold_release', {})
        dg:addNode('readerhighlight_hold_pan', {})
        dg:addNode('readermenu_tap', {'readerfooter_tap'})
        dg:addNode('paging_swipe', {})
        dg:addNode('paging_pan', {})
        dg:addNode('paging_pan_release', {})
        assert.are.same({
            'readerfooter_tap',
            'readermenu_tap',
            'tap_backward',
            'readerhighlight_hold_pan',
            'paging_pan_release',
            'readerfooter_hold',
            'readerhighlight_hold',
            'paging_pan',
            'paging_swipe',
            'tap_forward',
            'readerhighlight_tap',
            'readerhighlight_hold_release',
        }, dg:serialize())
    end)

    it("should serialize complex graph2", function()
        local dg = DepGraph:new{}
        dg:addNode('readerfooter_tap')
        dg:addNode('readerfooter_hold', {})
        dg:addNode('readerhighlight_tap', {})
        dg:addNode('tap_backward', {'readerfooter_tap', 'readermenu_tap', 'readerhighlight_tap'})
        dg:addNode('tap_forward', {'readerfooter_tap', 'readermenu_tap', 'readerhighlight_tap'})
        dg:addNode('readerhighlight_hold', {'readerfooter_hold'})
        dg:addNode('readerhighlight_hold_release', {})
        dg:addNode('readerhighlight_hold_pan', {})
        dg:addNode('readermenu_tap', {'readerfooter_tap'})
        assert.are.same({
            'readerfooter_tap',
            'readermenu_tap',
            'readerhighlight_tap',
            'tap_backward',
            'readerhighlight_hold_pan',
            'readerfooter_hold',
            'readerhighlight_hold',
            'tap_forward',
            'readerhighlight_hold_release',
        }, dg:serialize())
    end)


    it("should serialize complex graph with duplicates", function()
        local dg = DepGraph:new{}
        dg:addNode('readerfooter_tap', {})
        dg:addNode('readerfooter_hold', {})
        dg:addNode('readerhighlight_tap',
                   {'tap_backward', 'tap_backward', 'tap_forward'})
        dg:addNode('tap_backward', {'readerfooter_tap', 'readermenu_tap'})
        dg:addNode('tap_forward', {'readerfooter_tap', 'readermenu_tap'})
        dg:addNode('readerhighlight_hold', {'readerfooter_hold'})
        dg:addNode('readerhighlight_hold_release', {})
        dg:addNode('readerhighlight_hold_pan', {})
        dg:addNode('readermenu_tap', {'readerfooter_tap'})
        dg:addNode('paging_swipe', {})
        dg:addNode('paging_pan', {})
        dg:addNode('paging_pan_release', {})
        assert.are.same({
            'readerfooter_tap',
            'readermenu_tap',
            'tap_backward',
            'readerhighlight_hold_pan',
            'paging_pan_release',
            'readerfooter_hold',
            'readerhighlight_hold',
            'paging_pan',
            'paging_swipe',
            'tap_forward',
            'readerhighlight_tap',
            'readerhighlight_hold_release',
        }, dg:serialize())
    end)
end)
