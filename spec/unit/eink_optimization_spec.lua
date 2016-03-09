require("commonrequire")

describe("eink optimization setting", function()
    it("should be correctly loaded", function()
        G_reader_settings:saveSetting("eink", true)
        assert.Equals(require("device").screen.eink, true)
    end)
end)
