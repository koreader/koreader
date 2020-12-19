describe("ImageWidget module", function()
    local ImageWidget
    setup(function()
        require("commonrequire")
        ImageWidget = require("ui/widget/imagewidget")
    end)

    it("should render without error", function()
        local imgw = ImageWidget:new{
            file = "resources/koreader.png"
        }
        imgw:_render()
        assert(imgw._bb)
    end)
    it("should error out on none exist image", function()
        local imgw = ImageWidget:new{
            file = "wtf.png"
        }
        assert.has_error(function()
            imgw:_render()
        end)
    end)
end)
