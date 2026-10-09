describe("CreDocument:getVisibleWords wrapper", function()
    local CreDocument

    setup(function()
        require("commonrequire")
        CreDocument = require("document/credocument")
    end)

    it("forwards to the engine's getVisibleWords", function()
        local inst = setmetatable({
            _document = {
                getVisibleWords = function()
                    return "result"
                end,
            },
        }, { __index = CreDocument })

        assert.are_same("result", inst:getVisibleWords())
    end)

    it("returns per-word text and per-character rectangles", function()
        local sample = {
            {
                text = "was",
                chars = {
                    { char = "w", x0 = 1, y0 = 2, x1 = 9, y1 = 12 },
                },
            },
        }
        local inst = setmetatable({
            _document = {
                getVisibleWords = function()
                    return sample
                end,
            },
        }, { __index = CreDocument })

        local words = inst:getVisibleWords()
        assert.is_table(words)
        assert.are_same("was", words[1].text)
        assert.are_same("w", words[1].chars[1].char)
        assert.is_number(words[1].chars[1].x0)
        assert.is_number(words[1].chars[1].y1)
    end)
end)
