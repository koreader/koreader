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
    --[[
    -- NOTE: There was never actually sane error handling in there,
    --       it would just crash later because of a lack of BB object.
    --       We now return a checkerboard pattern on image decoding failure,
    --       which also happens to make the caller's life easier.
    it("should error out on missing or invalid images", function()
        local imgw = ImageWidget:new{
            file = "wtf.png"
        }
        assert.has_error(function()
            imgw:_render()
        end)
    end)
    --]]
end)
