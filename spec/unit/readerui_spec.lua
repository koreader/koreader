require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DocSettings = require("docsettings")
local DEBUG = require("dbg")

describe("Readerui module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new{
        document = DocumentRegistry:openDocument(sample_epub),
    }
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
    it("should close document", function()
        readerui:closeDocument()
        assert(readerui.document == nil)
    end)
end)
