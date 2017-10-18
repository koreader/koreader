describe("util module", function()
    local DataStorage, util
    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        util = require("util")
    end)

    it("should strip punctuations around word", function()
        assert.is_equal("hello world", util.stripePunctuations("\"hello world\""))
        assert.is_equal("hello world", util.stripePunctuations("\"hello world?\""))
        assert.is_equal("hello, world", util.stripePunctuations("\"hello, world?\""))
        assert.is_equal("你好", util.stripePunctuations("“你好“"))
        assert.is_equal("你好", util.stripePunctuations("“你好?“"))
        assert.is_equal("", util.stripePunctuations(""))
        assert.is_nil(util.stripePunctuations(nil))
    end)

    describe("gsplit()", function()
        it("should split string with patterns", function()
            local sentence = "Hello world, welcome to KOReader!"
            local words = {}
            for word in util.gsplit(sentence, "%s+", false) do
                table.insert(words, word)
            end
            assert.are_same({"Hello", "world,", "welcome", "to", "KOReader!"}, words)
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
            assert.are_same({"./sdcv", "-nj", "words", "a lot", "more or less", "--data-dir=dict"}, argv)
        end)
        it("should split string with dashes", function()
            local words = {}
            for word in util.gsplit("a-b-c-d", "-", false) do
                table.insert(words, word)
            end
            assert.are_same({"a", "b", "c", "d"}, words)
        end)
        it("should split string with dashes with final dash", function()
            local words = {}
            for word in util.gsplit("a-b-c-d-", "-", false) do
                table.insert(words, word)
            end
            assert.are_same({"a", "b", "c", "d"}, words)
        end)
    end)

    describe("splitToWords()", function()
        it("should split line into words", function()
            local words = util.splitToWords("one two,three  four . five")
            assert.are_same({
                "one",
                " ",
                "two",
                ",",
                "three",
                "  ",
                "four",
                " . ",
                "five",
            }, words)
        end)
        it("should split ancient greek words", function()
            local words = util.splitToWords("Λαρισαῖος Λευκοθέα Λιγυαστάδης.")
            assert.are_same({
                "Λαρισαῖος",
                " ",
                "Λευκοθέα",
                " ",
                "Λιγυαστάδης",
                "."
            }, words)
        end)
        it("should split Chinese words", function()
            local words = util.splitToWords("彩虹是通过太阳光的折射引起的。")
            assert.are_same({
                "彩","虹","是","通","过","太","阳","光","的","折","射","引","起","的","。",
            }, words)
        end)
        it("should split words of multilingual text", function()
            local words = util.splitToWords("BBC纪录片")
            assert.are_same({"BBC", "纪", "录", "片"}, words)
        end)
    end)

    describe("splitToChars()", function()
        it("should split text to line - unicode", function()
            local text = "Pójdźże, chmurność glück schließen Štěstí neštěstí. Uñas gavilán"
            local word = ""
            local table_of_words = {}
            local c
            local table_chars = util.splitToChars(text)
            for i = 1, #table_chars  do
                c = table_chars[i]
                word = word .. c
                if util.isSplittable(c) then
                    table.insert(table_of_words, word)
                    word = ""
                end
                if i == #table_chars then table.insert(table_of_words, word) end
            end
            assert.are_same({
                "Pójdźże, ",
                "chmurność ",
                "glück ",
                "schließen ",
                "Štěstí ",
                "neštěstí. ",
                "Uñas ",
                "gavilán",
            }, table_of_words)
        end)
        it("should split text to line - CJK", function()
            local text = "彩虹是通过太阳光的折射引起的。"
            local word = ""
            local table_of_words = {}
            local c
            local table_chars = util.splitToChars(text)
            for i = 1, #table_chars  do
                c = table_chars[i]
                word = word .. c
                if util.isSplittable(c) then
                    table.insert(table_of_words, word)
                    word = ""
                end
                if i == #table_chars then table.insert(table_of_words, word) end
            end
            assert.are_same({
                "彩","虹","是","通","过","太","阳","光","的","折","射","引","起","的","。",
            }, table_of_words)
        end)
        it("should split text to line with next_c - unicode", function()
            local text = "Ce test : 1) est très simple ; 2 ) simple comme ( 2/2 ) > 50 % ? ok."
            local word = ""
            local table_of_words = {}
            local c, next_c
            local table_chars = util.splitToChars(text)
            for i = 1, #table_chars  do
                c = table_chars[i]
                next_c = i < #table_chars and table_chars[i+1] or nil
                word = word .. c
                if util.isSplittable(c, next_c) then
                    table.insert(table_of_words, word)
                    word = ""
                end
                if i == #table_chars then table.insert(table_of_words, word) end
            end
            assert.are_same({
                "Ce ",
                "test : ",
                "1) ",
                "est ",
                "très ",
                "simple ; ",
                "2 ) ",
                "simple ",
                "comme ",
                "( ",
                "2/2 ) > ",
                "50 % ? ",
                "ok."
            }, table_of_words)
        end)
        it("should split text to line with next_c and prev_c - unicode", function()
            local text = "Ce test : 1) est « très simple » ; 2 ) simple comme ( 2/2 ) > 50 % ? ok."
            local word = ""
            local table_of_words = {}
            local c, next_c, prev_c
            local table_chars = util.splitToChars(text)
            for i = 1, #table_chars  do
                c = table_chars[i]
                next_c = i < #table_chars and table_chars[i+1] or nil
                prev_c = i > 1 and table_chars[i-1] or nil
                word = word .. c
                if util.isSplittable(c, next_c, prev_c) then
                    table.insert(table_of_words, word)
                    word = ""
                end
                if i == #table_chars then table.insert(table_of_words, word) end
            end
            assert.are_same({
                "Ce ",
                "test : ",
                "1) ",
                "est ",
                "« très ",
                "simple » ; ",
                "2 ) ",
                "simple ",
                "comme ",
                "( 2/2 ) > 50 % ? ",
                "ok."
            }, table_of_words)
        end)
    end)

    it("should split file path and name", function()
        local test = function(full, path, name)
            local p, n = util.splitFilePathName(full)
            assert.are_same(p, path)
            assert.are_same(n, name)
        end
        test("/a/b/c.txt", "/a/b/", "c.txt")
        test("/a/b////c.txt", "/a/b////", "c.txt")
        test("/a/b/", "/a/b/", "")
        test("c.txt", "", "c.txt")
        test("", "", "")
        test(nil, "", "")
        test("a/b", "a/", "b")
        test("/b", "/", "b")
        assert.are_same("/a/b/", util.splitFilePathName("/a/b/c.txt"))
    end)

    it("should split file name and suffix", function()
        local test = function(full, name, suffix)
            local n, s = util.splitFileNameSuffix(full)
            assert.are_same(n, name)
            assert.are_same(s, suffix)
        end
        test("a.txt", "a", "txt")
        test("/a/b.txt", "/a/b", "txt")
        test("a", "a", "")
        test("/a/b", "/a/b", "")
        test("/a/", "/a/", "")
        test("/a/.txt", "/a/", "txt")
        test(nil, "", "")
        test("", "", "")
        assert.are_same("a", util.splitFileNameSuffix("a.txt"))
    end)

    describe("fixUtf8()", function()
        it("should replace invalid UTF-8 characters with an underscore", function()
            assert.is_equal("\127 _ _\127 ", util.fixUtf8("\127 \128 \194\127 ", "_"))
        end)

        it("should replace invalid UTF-8 characters with multiple characters", function()
            assert.is_equal("\127 __ __\127 ", util.fixUtf8("\127 \128 \194\127 ", "__"))
        end)

        it("should replace invalid UTF-8 characters with empty char", function()
            assert.is_equal("\127  \127 ", util.fixUtf8("\127 \128 \194\127 ", ""))
        end)

        it("should not replace valid UTF-8 � character", function()
            assert.is_equal("�valid � char �", util.fixUtf8("�valid � char �", "__"))
        end)

        it("should not replace valid UTF-8 characters", function()
            assert.is_equal("\99 \244\129\130\190", util.fixUtf8("\99 \244\129\130\190", "_"))
        end)

        it("should not replace valid UTF-8 characters Polish chars", function()
            assert.is_equal("Pójdźże źółć", util.fixUtf8("Pójdźże źółć", "_"))
        end)

        it("should not replace valid UTF-8 characters German chars", function()
            assert.is_equal("glück schließen", util.fixUtf8("glück schließen", "_"))
        end)
    end)

    describe("splitToArray()", function()
        it("should split input to array", function()
            assert.are_same({"100", "abc", "", "def", "ghi200"},
                            util.splitToArray("100\tabc\t\tdef\tghi200\t", "\t", true))
        end)

        it("should also split input to array", function()
            assert.are_same({"", "bc", "bc", "bc", "bc"},
                            util.splitToArray("abcabcabcabca", "a", true))
        end)

        it("should split input to array without empty entities", function()
            assert.are_same({"100", "abc", "def", "ghi200"},
                            util.splitToArray("100  abc   def ghi200  ", " ", false))
        end)
    end)

    describe("htmlToPlainTextIfHtml()", function()
        it("should guess it is not HTML and let is as is", function()
            local s = "if (i < 0 && j < 0) j = i&amp;"
            assert.is_equal(s, util.htmlToPlainTextIfHtml(s))
        end)
        it("should guess it is HTML and convert it to text", function()
            assert.is_equal("Making unit tests is fun & nécéssaire",
                            util.htmlToPlainTextIfHtml("<div> <br> Making <b>unit&nbsp;tests</b> is <i class='notreally'>fun &amp; n&#xE9;c&#233;ssaire</i><br/> </div>"))
        end)
        it("should guess it is double encoded HTML and convert it to text", function()
            assert.is_equal("Deux parties.\nPrologue.Désespérée, elle le tue...\nPremière partie. Sur la route & dans la nuit",
                            util.htmlToPlainTextIfHtml("Deux parties.&lt;br&gt;Prologue.Désespérée, elle le tue...&lt;br&gt;Première partie. Sur la route &amp;amp; dans la nuit"))
        end)
    end)

    describe("isEmptyDir()", function()
        it("should return true on empty dir", function()
            assert.is_true(util.isEmptyDir(DataStorage:getDataDir() .. "/data/dict")) -- should be empty during unit tests
        end)
        it("should return false on non-empty dir", function()
            assert.is_false(util.isEmptyDir(DataStorage:getDataDir())) -- should contain subdirectories
        end)
        it("should return nil on non-existent dir", function()
            assert.is_nil(util.isEmptyDir("/this/is/just/some/nonsense/really/this/should/not/exist"))
        end)
    end)

    describe("secondsToClock()", function()
        it("should convert seconds to 00:00 format", function()
            assert.is_equal("00:00",
                            util.secondsToClock(0, true))
            assert.is_equal("00:01",
                            util.secondsToClock(60, true))
        end)
        it("should round seconds to minutes in 00:00 format", function()
            assert.is_equal("00:01",
                            util.secondsToClock(89, true))
            assert.is_equal("00:02",
                            util.secondsToClock(90, true))
            assert.is_equal("00:02",
                            util.secondsToClock(110, true))
            assert.is_equal("00:02",
                            util.secondsToClock(120, true))
            assert.is_equal("01:00",
                            util.secondsToClock(3600, true))
            assert.is_equal("01:00",
                            util.secondsToClock(3599, true))
            assert.is_equal("01:00",
                            util.secondsToClock(3570, true))
            assert.is_equal("00:59",
                            util.secondsToClock(3569, true))
        end)
        it("should convert seconds to 00:00:00 format", function()
            assert.is_equal("00:00:00",
                            util.secondsToClock(0))
            assert.is_equal("00:01:00",
                            util.secondsToClock(60))
            assert.is_equal("00:01:29",
                            util.secondsToClock(89))
            assert.is_equal("00:01:30",
                            util.secondsToClock(90))
            assert.is_equal("00:01:50",
                            util.secondsToClock(110))
            assert.is_equal("00:02:00",
                            util.secondsToClock(120))
        end)
    end)
end)
