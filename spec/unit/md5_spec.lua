require("commonrequire")

local md5 = require("MD5")

describe("MD5 module", function()
    it("should calculate correct MD5 hashes", function()
        assert.is_equal(md5:sum(""), "d41d8cd98f00b204e9800998ecf8427e")
        assert.is_equal(md5:sum("\0"), "93b885adfe0da089cdf634904fd59f71")
        assert.is_equal(md5:sum("0123456789abcdefX"), "1b05aba914a8b12315c7ee52b42f3d35")
    end)
    it("should calculate MD5 sum by updating", function()
        md5:new()
        md5:update("0123456789")
        md5:update("abcdefghij")
        local md5sum = md5:sum()
        assert.is_equal(md5sum, md5:sum("0123456789abcdefghij"))
    end)
end)

