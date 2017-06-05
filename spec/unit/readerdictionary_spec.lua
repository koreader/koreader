describe("Readerdictionary module", function()
    local DocumentRegistry, ReaderUI, lfs, UIManager, Screen, Event, DEBUG

    setup(function()
        require("commonrequire")
        DEBUG = package.reload("dbg")
        DocumentRegistry = package.reload("document/documentregistry")
        Event = package.reload("ui/event")
        ReaderUI = package.reload("apps/reader/readerui")
        Screen = package.reload("device").screen
        UIManager = package.reload("ui/uimanager")
        lfs = require("libs/libkoreader-lfs")
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
