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
            document = DocumentRegistry:openDocument(sample_epub),
        }
        rolling = readerui.rolling
        dictionary = readerui.dictionary
    end)
    it("should show quick lookup window", function()
        local name = "screenshots/reader_dictionary.png"
        UIManager:quit()
        UIManager:show(readerui)
        rolling:onGotoPage(100)
        dictionary:onLookupWord("test")
        UIManager:scheduleIn(1, function()
            UIManager:close(dictionary.dict_window)
            UIManager:close(readerui)
        end)
        UIManager:run()
        Screen:shot(name)
    end)
end)
