describe("Key module", function()
    local Key

    setup(function()
        require("commonrequire")
        Key = require("device/key")
    end)

    it("returns the key sequence for string conversion", function()
        local key = Key:new("Highlighter", {
            Ctrl = false,
            Shift = true,
        })

        assert.are.same({ "Shift", "Highlighter" }, key:getSequence())
        assert.equals("Shift-Highlighter", tostring(key))
    end)
end)
