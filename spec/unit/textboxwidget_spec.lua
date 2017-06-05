describe("TextBoxWidget module", function()
    local TextBoxWidget, Font
    setup(function()
        require("commonrequire")
        Font = package.reload("ui/font")
        TextBoxWidget = package.reload("ui/widget/textboxwidget")
    end)

    it("should select the correct word on HoldWord event", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0},
            face = Font:getFace("cfont", 25),
            text = 'YOOOOOOOOOOOOOOOO\nFoo.\nBar.',
        }
        tw:onHoldWord(function(w)
            assert.is.same(w, 'YOOOOOOOOOOOOOOOO')
        end, {pos={x=110,y=4}})
        tw:onHoldWord(function(w)
            assert.is.same(w, 'Foo')
        end, {pos={x=0,y=50}})
        tw:onHoldWord(function(w)
            assert.is.same(w, 'Bar')
        end, {pos={x=20,y=80}})
    end)
end)
