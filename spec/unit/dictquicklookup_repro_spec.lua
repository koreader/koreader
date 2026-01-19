describe("DictQuickLookup interaction", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen
    local readerui, dictionary

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("japanese.koplugin")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
    end)

    setup(function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/sample.txt"),
        }
    end)

    teardown(function()
        if readerui then readerui:onClose() end
        UIManager:quit()
    end)

    it("should use improveBufferSelection and expand selection when holding text", function()
        dictionary = readerui.dictionary
        dictionary:onLookupWord("test")
        fastforward_ui_events()

        local dict_window = dictionary.dict_window
        assert.is_not_nil(dict_window)

        local text_widget = dict_window.text_widget.text_widget
        local text = "これは辞書です"
        text_widget:setText(text)
        assert.is_not_nil(text_widget.charlist)

        local s_handleEvent = spy.on(readerui, "handleEvent")

        local japanese_plugin = nil
        for name, p in pairs(readerui.languagesupport.plugins) do
            if name == "japanese" then japanese_plugin = p break end
        end
        assert.is_not_nil(japanese_plugin)

        stub(japanese_plugin, "onWordSelection").returns({4, 5})

        local hold_release_handler = dict_window.ges_events.HoldReleaseText.args
        hold_release_handler("辞", 1.0, 4, 4)

        assert.spy(s_handleEvent).was_called()

        local found_lookup = false
        for i, call in ipairs(s_handleEvent.calls) do
            local event = call.vals[2]
            if event and event.handler == "onLookupWord" then
                found_lookup = true
                assert.equal("辞書", event.args[1])
            end
        end
        assert.is_true(found_lookup)

        japanese_plugin.onWordSelection:revert()
    end)
end)
