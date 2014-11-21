require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Event = require("ui/event")
local DEBUG = require("dbg")

describe("Readerdictionary module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui, rolling, dictionary
    setup(function()
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
        rolling:gotoPage(100)
        dictionary:onLookupWord("test")
        UIManager:scheduleIn(1, function()
            UIManager:close(dictionary.dict_window)
            UIManager:close(readerui)
        end)
        UIManager:run()
        Screen:shot(name)
    end)
end)
