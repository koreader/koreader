describe("Kazakh plugin stemmer", function()
    local Stemmer

    setup(function()
        require("commonrequire")
        package.path = "plugins/kazakh.koplugin/?.lua;" .. package.path
        Stemmer = require("stemmer")
    end)

    local function nchars(s)
        local n = 0
        for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
        return n
    end

    local function contains(list, want)
        for _, v in ipairs(list) do
            if v == want then return true end
        end
        return false
    end

    local function index_of(list, want)
        for i, v in ipairs(list) do
            if v == want then return i end
        end
        return nil
    end

    -- inflected surface form -> the lemma a dictionary is keyed on
    local LEMMAS = {
        { "мектептерімізде", "мектеп" },  -- plural + possessive + locative
        { "кітаптарында",    "кітап"  },
        { "балаларға",       "бала"   },
        { "достарымен",      "дос"    },
        { "жазбаймын",       "жаз"    },  -- negation + tense + person
        { "сөйледі",         "сөйле"  },
        { "жанышта",         "жаныш"  },
        { "маманда",         "маман"  },
    }

    describe("ladder()", function()
        it("should reach the lemma of an inflected word", function()
            for _, case in ipairs(LEMMAS) do
                local word, lemma = case[1], case[2]
                assert.is_true(contains(Stemmer.ladder(word), lemma),
                               word .. " should analyse down to " .. lemma)
            end
        end)

        it("should offer the word itself first", function()
            for _, case in ipairs(LEMMAS) do
                assert.is_equal(case[1], Stemmer.ladder(case[1])[1])
            end
        end)

        it("should order candidates longest first, in characters", function()
            -- Sorting on string length would compare BYTES, which reorders
            -- rungs as soon as a token mixes scripts.
            for _, case in ipairs(LEMMAS) do
                local rungs = Stemmer.ladder(case[1])
                for i = 2, #rungs do
                    assert.is_true(nchars(rungs[i - 1]) >= nchars(rungs[i]),
                                   case[1] .. ": " .. rungs[i - 1] ..
                                   " should not be shorter than " .. rungs[i])
                end
            end
        end)

        it("should rank a shallower analysis above an over-stripped one", function()
            -- маманда strips to маман, and one suffix further to мама. Both are
            -- morphologically legal and both are real words; the plugin relies
            -- on ladder order to offer the right one first.
            local rungs = Stemmer.ladder("маманда")
            assert.is_true(index_of(rungs, "маман") < index_of(rungs, "мама"))
        end)

        it("should undo final-consonant voicing", function()
            -- A stem-final б/ғ/г voiced by the suffix is restored: the lemma is
            -- кітап, but with a possessive it surfaces as кітабы.
            assert.is_true(contains(Stemmer.ladder("кітабы"), "кітап"))
            assert.is_true(contains(Stemmer.ladder("бағы"), "бақ"))
            assert.is_true(contains(Stemmer.ladder("жүрегінде"), "жүрек"))
        end)

        it("should restore an elided stem vowel", function()
            -- орын loses its ы before a possessive: орын -> орны -> орнында.
            assert.is_true(contains(Stemmer.ladder("орнында"), "орын"))
        end)

        it("should leave an uninflected lemma alone", function()
            for _, word in ipairs({ "мектеп", "бала", "күн", "кітап" }) do
                assert.are.same({ word }, Stemmer.ladder(word))
            end
        end)

        it("should be idempotent on every rung it produces", function()
            -- Re-analysing a candidate must not produce a longer one, or the
            -- plugin's candidate list would depend on how often it was applied.
            for _, case in ipairs(LEMMAS) do
                for _, rung in ipairs(Stemmer.ladder(case[1])) do
                    assert.is_equal(rung, Stemmer.ladder(rung)[1])
                end
            end
        end)

        it("should handle input that is not an inflected Kazakh word", function()
            assert.are.same({}, Stemmer.ladder(""))
            assert.are.same({}, Stemmer.ladder(nil))
            assert.are.same({}, Stemmer.ladder("а"))
            assert.are.same({ "hello" }, Stemmer.ladder("hello"))
        end)

        it("should not strip a suffix off a token that is not a word", function()
            -- аб'ба ends in -ба, a real derivational suffix, but the token is
            -- not a Kazakh word and аб' is not a form of anything.
            for _, token in ipairs({ "аб'ба", "мектеп-интернат", "мектеп2лер" }) do
                assert.are.same({ token }, Stemmer.ladder(token))
            end
        end)
    end)
end)
