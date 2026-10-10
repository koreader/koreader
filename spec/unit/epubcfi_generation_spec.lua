describe("EPUB CFI generation", function()
    local DocumentRegistry, UIManager, ReaderUI, Screen
    local readerui, rolling

    setup(function()
        require("commonrequire")
        disable_plugins()
        UIManager = require("ui/uimanager")
        stub(UIManager, "getNthTopWidget")
        UIManager.getNthTopWidget.returns({})
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen

        local sample_epub = "spec/front/unit/data/juliet.epub"
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        rolling = readerui.rolling
    end)

    teardown(function()
        readerui:onClose()
    end)

    it("should return a CFI that changes as the position changes", function()
        local seen = {}
        for _, page in ipairs({1, 10, 20, 40}) do
            rolling:onGotoPage(page)
            local cfi = readerui.document:getEPubCFI()
            assert.is_string(cfi)
            assert.is_truthy(cfi:match("^epubcfi%(.+%)$"))
            assert.is_nil(seen[cfi], "CFI was stale (repeated) at page " .. page .. ": " .. cfi)
            seen[cfi] = page
        end
    end)

    it("should agree between getEPubCFI and getEPubCFIFromXPointer", function()
        for _, page in ipairs({1, 10, 20, 40}) do
            rolling:onGotoPage(page)
            local xp = readerui.document:getXPointer()
            assert.are.equal(readerui.document:getEPubCFI(),
                             readerui.document:getEPubCFIFromXPointer(xp))
        end
    end)

    it("should return nil for an xpointer absent from the document", function()
        assert.is_nil(readerui.document:getEPubCFIFromXPointer("/body[1]/DocFragment[999]/body[1]"))
    end)

    -- This must run last: onCloseDocument tears down scheduled tasks that
    -- earlier tests rely on.
    it("should save last_epubcfi consistent with xpointer on document close", function()
        rolling:onGotoPage(20)
        rolling:onCloseDocument()
        assert.are.equal(
            readerui.document:getEPubCFIFromXPointer(rolling.xpointer),
            readerui.doc_settings:readSetting("last_epubcfi"))
    end)
end)
