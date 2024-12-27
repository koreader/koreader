describe("Readerdictionary module", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("japanese.koplugin")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
    end)

    local readerui, dictionary
    setup(function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/sample.txt"),
        }
        dictionary = readerui.dictionary
    end)
    teardown(function()
        ReaderUI.instance = readerui
        readerui:closeDocument()
        readerui:onClose()
    end)
    before_each(function()
        ReaderUI.instance = readerui
        UIManager:show(readerui)
    end)
    after_each(function()
        UIManager:close(dictionary.dict_window)
        UIManager:close(readerui)
        UIManager:quit()
        UIManager._exit_code = nil
    end)
    it("should show quick lookup window", function()
        dictionary:onLookupWord("test")
        fastforward_ui_events()
        screenshot(Screen, "reader_dictionary.png")
    end)
    it("should attempt to deinflect (Japanese) word on lookup", function()

        local word = "喋っている"
        local s = spy.on(readerui.languagesupport, "extraDictionaryFormCandidates")

        -- We can't use onLookupWord because we need to check whether
        -- extraDictionaryFormCandidates was called synchronously.
        dictionary:stardictLookup(word)
        fastforward_ui_events()
        screenshot(Screen, "reader_dictionary_japanese.png")

        assert.spy(s).was_called()
        assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport), word)
        if readerui.languagesupport.plugins["japanese_support"] then
            --- @todo This should probably check against a set or sorted list
            --       of the candidates we'd expect.
            assert.spy(s).was_returned_with(match.is_not_nil())
        end
        readerui.languagesupport.extraDictionaryFormCandidates:revert()
    end)
end)
