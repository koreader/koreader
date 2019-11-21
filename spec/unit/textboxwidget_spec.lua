describe("TextBoxWidget module", function()
    local TextBoxWidget, Font
    setup(function()
        require("commonrequire")
        Font = require("ui/font")
        TextBoxWidget = require("ui/widget/textboxwidget")
    end)

    it("should select the correct word on HoldWord event", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0},
            face = Font:getFace("cfont", 25),
            text = 'YOOOOOOOOOOOOOOOO\nFoo.\nBar.\nFoo welcomes Bar into the fun.',
        }

        local pos={x=110,y=4}
        tw:onHoldStartText(nil, {pos=pos})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'YOOOOOOOOOOOOOOOO')
        end, {pos=pos})

        pos={x=0,y=50}
        tw:onHoldStartText(nil, {pos=pos})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'Foo')
        end, {pos=pos})

        pos={x=20,y=80}
        tw:onHoldStartText(nil, {pos=pos})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'Bar')
        end, {pos=pos})

        tw:onHoldStartText(nil, {pos={x=50, y=100}})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'welcomes Bar into')
        end, {pos={x=240, y=100}})

        tw:onHoldStartText(nil, {pos={x=20, y=80}})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'Bar.\nFoo welcomes Bar into')
        end, {pos={x=240, y=100}})

        --[[
        -- No more used, not implemented when use_xtext=true
        tw:onHoldWord(function(w)
            assert.is.same(w, 'YOOOOOOOOOOOOOOOO')
        end, {pos={x=110,y=4}})
        tw:onHoldWord(function(w)
            assert.is.same(w, 'Foo')
        end, {pos={x=0,y=50}})
        tw:onHoldWord(function(w)
            assert.is.same(w, 'Bar')
        end, {pos={x=20,y=80}})
        ]]--
    end)
end)
