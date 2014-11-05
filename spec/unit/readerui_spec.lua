require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")

describe("Readerui module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui
    setup(function()
        readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
    end)
    it("should save settings", function()
        -- remove history settings and sidecar settings
        DocSettings:open(sample_epub):clear()
        local doc_settings = DocSettings:open(sample_epub)
        assert.are.same(doc_settings.data, {})
        readerui:saveSettings()
        assert.are_not.same(readerui.doc_settings.data, {})
        doc_settings = DocSettings:open(sample_epub)
        assert.truthy(doc_settings.data.last_xpointer)
        assert.are.same(doc_settings.data.last_xpointer,
                readerui.doc_settings.data.last_xpointer)
    end)
    it("should show reader", function()
        UIManager:quit()
        UIManager:show(readerui)
        UIManager:scheduleIn(1, function() UIManager:close(readerui) end)
        UIManager:run()
    end)
    it("should close document", function()
        readerui:closeDocument()
        assert(readerui.document == nil)
    end)
end)
