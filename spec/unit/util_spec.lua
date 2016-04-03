describe("util module", function()
    local util
    setup(function()
        require("commonrequire")
        util = require("util")
    end)

    it("should strip punctuations around word", function()
        assert.is_equal(util.stripePunctuations("\"hello world\""), "hello world")
        assert.is_equal(util.stripePunctuations("\"hello world?\""), "hello world")
        assert.is_equal(util.stripePunctuations("\"hello, world?\""), "hello, world")
        assert.is_equal(util.stripePunctuations("“你好“"), "你好")
        assert.is_equal(util.stripePunctuations("“你好?“"), "你好")
    end)

    it("should split string with patterns", function()
        local sentence = "Hello world, welcome to KoReader!"
        local words = {}
        for word in util.gsplit(sentence, "%s+", false) do
            table.insert(words, word)
        end
        assert.are_same(words, {"Hello", "world,", "welcome", "to", "KoReader!"})
    end)

    it("should split command line arguments with quotation", function()
        local command = "./sdcv -nj \"words\" \"a lot\" 'more or less' --data-dir=dict"
        local argv = {}
        for arg1 in util.gsplit(command, "[\"'].-[\"']", true) do
            for arg2 in util.gsplit(arg1, "^[^\"'].-%s+", true) do
                for arg3 in util.gsplit(arg2, "[\"']", false) do
                    local trimed = arg3:gsub("^%s*(.-)%s*$", "%1")
                    if trimed ~= "" then
                        table.insert(argv, trimed)
                    end
                end
            end
        end
        assert.are_same(argv, {"./sdcv", "-nj", "words", "a lot", "more or less", "--data-dir=dict"})
    end)
end)
