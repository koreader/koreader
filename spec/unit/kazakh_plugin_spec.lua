describe("Kazakh plugin", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    local readerui, kazakh

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("kazakh.koplugin")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/sample.txt"),
        }
        kazakh = readerui.languagesupport.plugins["kazakh"]
    end)

    teardown(function()
        ReaderUI.instance = readerui
        readerui:closeDocument()
        readerui:onClose()
        UIManager:quit()
        UIManager._exit_code = nil
    end)

    local function contains(list, want)
        for _, v in ipairs(list or {}) do
            if v == want then return true end
        end
        return false
    end

    -- The plugin reads the document language straight off doc_props, the same
    -- way language support picks which plugin to try first.
    local function lookup(language, word)
        readerui.doc_props.language = language
        return kazakh:onWordLookup{ text = word }
    end

    it("should register itself with language support", function()
        assert.is_not_nil(kazakh)
        assert.is_true(kazakh:supportsLanguage("kk"))
        assert.is_false(kazakh:supportsLanguage("ru"))
    end)

    describe("in a book marked as Kazakh", function()
        it("should analyse a word with no Kazakh-specific letter", function()
            -- достарымен is spelt entirely in letters Russian has too.
            assert.is_true(contains(lookup("kk", "достарымен"), "дос"))
        end)

        it("should analyse a word carrying a Kazakh-specific letter", function()
            assert.is_true(contains(lookup("kk", "балаларға"), "бала"))
        end)
    end)

    describe("in a book not marked as Kazakh", function()
        it("should still analyse a word carrying a Kazakh-specific letter", function()
            -- Reached through the language support fallback path.
            assert.is_true(contains(lookup("ru", "балаларға"), "бала"))
            assert.is_true(contains(lookup(nil, "балаларға"), "бала"))
        end)

        it("should decline a word spelt only in shared Cyrillic", function()
            assert.is_nil(lookup("ru", "достарымен"))
        end)

        it("should decline Russian text that happens to look inflected", function()
            -- домочадцы ends in -ы, which is a real Kazakh suffix; without the
            -- letter check this would be offered to the dictionary as домочадц.
            assert.is_nil(lookup("ru", "домочадцы"))
            assert.is_nil(lookup("ru", "дома"))
        end)
    end)

    it("should lowercase Cyrillic before analysing", function()
        -- string.lower only maps ASCII, so a capitalised word has to go through
        -- utf8proc or every rung keeps its capital and misses the headword.
        local candidates = lookup("kk", "Мектептерімізде")
        assert.is_true(contains(candidates, "мектеп"))
        assert.is_false(contains(candidates, "Мектеп"))
    end)

    describe("verb forms", function()
        -- Dictionaries commonly key a verb on its -у verbal noun, while the
        -- ladder only strips suffixes and bottoms out at the bare stem.
        it("should offer the -у form of an analysis", function()
            assert.is_true(contains(lookup("kk", "сөйледі"), "сөйлеу"))
            assert.is_true(contains(lookup("kk", "жазбаймын"), "жазу"))
        end)

        it("should offer the -у form of the tapped word itself", function()
            -- Tapping the bare stem must still reach the dictionary's headword.
            assert.is_true(contains(lookup("kk", "сөйле"), "сөйлеу"))
        end)

        it("should elide a stem-final ы/і before -у", function()
            -- оқы -> оқу, never оқыу.
            local c = lookup("kk", "оқыды")
            assert.is_true(contains(c, "оқу"))
            assert.is_false(contains(c, "оқыу"))
        end)

        it("should not add another -у to a form that already ends in one", function()
            for _, w in ipairs(lookup("kk", "оқу") or {}) do
                assert.is_not_equal("оқуу", w)
            end
        end)

        it("should rank the analyses above the verb forms", function()
            -- The dictionary sees candidates in order, so a real lemma should
            -- not sit behind a speculative verb form.
            local c = lookup("kk", "мектептерімізде")
            local lemma, verb
            for i, w in ipairs(c) do
                if w == "мектеп" then lemma = i end
                if w == "мектепу" then verb = i end
            end
            assert.is_not_nil(lemma)
            if verb then assert.is_true(lemma < verb) end
        end)
    end)

    it("should decline text that is not Cyrillic at all", function()
        assert.is_nil(lookup("kk", "hello"))
        assert.is_nil(lookup("kk", ""))
    end)
end)
