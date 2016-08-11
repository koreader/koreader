describe("random package tests", function()
    local random

    local function is_magic_char(c)
        return c == "8" or c == "9" or c == "A" or c == "B"
    end

    setup(function()
        random = require("frontend/random")
    end)

    it("should generate uuid without dash", function()
        for i = 1, 10000 do
            local uuid = random.uuid()
            assert.Equals(uuid:len(), 32)
            assert.Equals(uuid:sub(13, 13), "4")
            assert.is_true(is_magic_char(uuid:sub(17, 17)))
        end
    end)

    it("should generate uuid with dash", function()
        for i = 1, 10000 do
            local uuid = random.uuid(true)
            assert.Equals(uuid:len(), 36)
            assert.Equals(uuid:sub(9, 9), "-")
            assert.Equals(uuid:sub(14, 14), "-")
            assert.Equals(uuid:sub(19, 19), "-")
            assert.Equals(uuid:sub(24, 24), "-")
            assert.Equals(uuid:sub(15, 15), "4")
            assert.is_true(is_magic_char(uuid:sub(20, 20)))
        end
    end)
end)
