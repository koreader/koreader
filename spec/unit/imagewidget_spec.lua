require("commonrequire")
local ImageWidget = require("ui/widget/imagewidget")

describe("ImageWidget module", function()
    it("should render without error", function()
        local imgw = ImageWidget:new{
            file = "resources/icons/appbar.chevron.up.png"
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
