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
            'readerfooter_hold',
            'readermenu_tap',
            'tap_backward',
            'tap_forward',
            'readerhighlight_tap',
            'readerhighlight_hold',
            'readerhighlight_hold_release',
            'readerhighlight_hold_pan',
            'paging_swipe',
            'paging_pan',
            'paging_pan_release',
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
            'readerfooter_hold',
            'readerhighlight_tap',
            'readermenu_tap',
            'tap_backward',
            'tap_forward',
            'readerhighlight_hold',
            'readerhighlight_hold_release',
            'readerhighlight_hold_pan',
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
            'readerfooter_hold',
            'readermenu_tap',
            'tap_backward',
            'tap_forward',
            'readerhighlight_tap',
            'readerhighlight_hold',
            'readerhighlight_hold_release',
            'readerhighlight_hold_pan',
            'paging_swipe',
            'paging_pan',
            'paging_pan_release',
        }, dg:serialize())
    end)

    it("should serialize complex graph and keep dependencies after removing and re-adding", function()
        local dg = DepGraph:new{}
        dg:addNode("tap_backward")
        dg:addNode("tap_forward")
        -- The next 3 steps are what is done when registering:
        --    { id = "readermenu_tap", overrides = { "tap_forward", "tap_backward" } }
        dg:addNode("readermenu_tap")
        dg:addNodeDep("tap_backward", "readermenu_tap")
        dg:addNodeDep("tap_forward", "readermenu_tap")
        -- print(require("dump")(dg))
        --     ["nodes"] = {
        --         ["readermenu_tap"] = {},
        --         ["tap_backward"] = {
        --             ["deps"] = {
        --                 [1] = "readermenu_tap"
        --             }
        --         },
        --         ["tap_forward"] = {
        --             ["deps"] = {
        --                 [1] = "readermenu_tap"
        --             }
        --         }
        --     }
        dg:removeNode("tap_forward")
        dg:removeNode("tap_backward")
        dg:addNode("tap_forward")
        dg:addNode("tap_backward")
        -- print(require("dump")(dg))
        assert.are.same({
            "readermenu_tap",
            "tap_backward",
            "tap_forward",
        }, dg:serialize())
        local tapFwdNode = dg:getNode("tap_forward")
        assert.is_true(type(tapFwdNode.deps) == "table")
        assert.is_true(#tapFwdNode.deps > 0)
        local tapBwdNode = dg:getNode("tap_backward")
        assert.is_true(type(tapBwdNode.deps) == "table")
        assert.is_true(#tapBwdNode.deps > 0)
    end)

    it("should not serialize removed/disabled nodes", function()
        local dg = DepGraph:new{}
        dg:addNode('foo')
        dg:addNode('bar')
        dg:addNode('baz',
                   {'foo', 'bar', 'bam'})
        dg:addNode('feh')
        dg:removeNode('baz')
        dg:removeNode('bar')
        dg:addNode('blah', {'bla', 'h', 'bamf'})
        dg:removeNode('bamf')
        assert.are.same({
            'foo',
            'bam',
            'feh',
            'bla',
            'h',
            'blah',
        }, dg:serialize())

        -- Check that bamf was removed from blah's deps
        assert.are.same({
            'bla',
            'h',
        }, dg:getNode('blah').deps)

        -- Check that baz is re-enabled w/ its full deps (minus bar, that we removed earlier) if re-Added as a dep
        dg:addNode('whee', {'baz'})
        assert.are.same({
            'foo',
            'bam',
        }, dg:getNode('baz').deps)
        assert.are.same({
            'foo',
            'bam',
            'baz',
            'feh',
            'bla',
            'h',
            'blah',
            'whee',
        }, dg:serialize())

        -- Check that re-adding an existing node with new deps properly *appends* to its existing deps
        dg:addNode('baz', {'wham', 'bang'})
        assert.are.same({
            'foo',
            'bam',
            'wham',
            'bang',
        }, dg:getNode('baz').deps)

    end)
end)
