describe("Readerui module", function()
    local DocumentRegistry, ReaderUI, DocSettings, UIManager, Screen
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui
    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        DocSettings = require("docsettings")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
    end)
    it("should save settings", function()
        -- remove history settings and sidecar settings
        DocSettings:open(sample_epub):purge()
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
        UIManager:scheduleIn(1, function()
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
        end)
        UIManager:run()
    end)
    it("should close document", function()
        readerui:closeDocument()
        assert(readerui.document == nil)
        readerui:onClose()
    end)
    it("should not reset ReaderUI.instance by mistake", function()
        ReaderUI:doShowReader(sample_epub) -- spins up a new, sane instance
        local new_readerui = ReaderUI:_getRunningInstance()
        assert.is.truthy(new_readerui.document)
        -- This *will* trip:
        -- * A pair of ReaderUI instance mimsatch warnings (on open/close) because it bypasses the safety of doShowReader!
        -- * A refcount warning from DocumentRegistry, because bypassinf the safeties means that two different instances opened the same Document.
        ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub)
        }:onClose()
        assert.is.truthy(new_readerui.document)
        new_readerui:closeDocument()
        new_readerui:onClose()
    end)
end)
