describe("Readerdictionary module", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
    end)

    local readerui, rolling, dictionary
    setup(function()
        local sample_epub = "spec/front/unit/data/leaves.epub"
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        rolling = readerui.rolling
        dictionary = readerui.dictionary
    end)
    teardown(function()
        readerui:closeDocument()
        readerui:onClose()
    end)
    it("should show quick lookup window", function()
        UIManager:quit()
        UIManager:show(readerui)
        rolling:onGotoPage(100)
        dictionary:onLookupWord("test")
        UIManager:scheduleIn(1, function()
            UIManager:close(dictionary.dict_window)
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
        end)
        UIManager:run()
        Screen:shot("screenshots/reader_dictionary.png")
    end)
    it("should attempt to deinflect (Japanese) word on lookup", function()
        UIManager:quit()
        UIManager:show(readerui)
        rolling:onGotoPage(100)

        local word = "喋っている"
        local s = spy.on(readerui.languagesupport, "extraDictionaryFormCandidates")

        -- We can't use onLookupWord because we need to check whether
        -- extraDictionaryFormCandidates was called synchronously.
        dictionary:stardictLookup(word)

        assert.spy(s).was_called()
        assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport), word)
        if readerui.languagesupport.plugins["japanese_support"] then
            --- @todo This should probably check against a set or sorted list
            --       of the candidates we'd expect.
            assert.spy(s).was_returned_with(match.is_not_nil())
        end
        readerui.languagesupport.extraDictionaryFormCandidates:revert()

        UIManager:scheduleIn(1, function()
            UIManager:close(dictionary.dict_window)
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
        end)
        UIManager:run()
        Screen:shot("screenshots/reader_dictionary_japanese.png")
    end)
end)
