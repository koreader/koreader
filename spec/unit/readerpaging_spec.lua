describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local sample_djvu = "spec/front/unit/data/djvu3spec.djvu"
    local UIManager, Event, DocumentRegistry, ReaderUI, Screen

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        stub(UIManager, "getNthTopWidget")
        UIManager.getNthTopWidget.returns({})
        Event = require("ui/event")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen

        local purgeDir = require("ffi/util").purgeDir
        local DocSettings = require("docsettings")
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
    end)

    describe("Page mode on a PDF", function()
        before_each(function()
            local readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }

            UIManager:show(readerui)
        end)
        after_each(function()
            local readerui = ReaderUI.instance

            if readerui then
                readerui:closeDocument()
                readerui:onClose()
            end
        end)

        it("should emit EndOfBook event at the end", function()
            local readerui = ReaderUI.instance
            local paging = readerui.paging

            local s = spy.on(readerui.status, "onEndOfBook")

            UIManager:nextTick(function()
                UIManager:quit()
            end)
            UIManager:run()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui.zooming:setZoomMode("pageheight")
            paging:onGotoPage(readerui.document:getPageCount())
            paging:onGotoViewRel(1)
            assert.spy(s).was_called()
        end)
    end)

    describe("Scroll mode on a PDF", function()
        setup(function()
            local purgeDir = require("ffi/util").purgeDir
            local DocSettings = require("docsettings")
            purgeDir(DocSettings:getSidecarDir(sample_pdf))
            os.remove(DocSettings:getHistoryPath(sample_pdf))
        end)
        before_each(function()
            local readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }

            UIManager:show(readerui)
        end)
        after_each(function()
            local readerui = ReaderUI.instance

            if readerui then
                readerui:closeDocument()
                readerui:onClose()
            end
        end)

        it("should emit EndOfBook event at the end", function()
            local readerui = ReaderUI.instance
            local paging = readerui.paging

            local s = spy.on(readerui.status, "onEndOfBook")

            UIManager:nextTick(function()
                UIManager:quit()
            end)
            UIManager:run()
            paging.page_positions = {}
            readerui:handleEvent(Event:new("SetScrollMode", true))
            paging:onGotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            paging:onGotoViewRel(1)
            paging:onGotoViewRel(1)
            assert.spy(s).was_called()
        end)
    end)

    describe("Scroll mode on a DjVu", function()
        setup(function()
            local purgeDir = require("ffi/util").purgeDir
            local DocSettings = require("docsettings")
            purgeDir(DocSettings:getSidecarDir(sample_djvu))
            os.remove(DocSettings:getHistoryPath(sample_djvu))
        end)
        before_each(function()
            local readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_djvu),
            }

            UIManager:show(readerui)
        end)
        after_each(function()
            local readerui = ReaderUI.instance

            if readerui then
                readerui:closeDocument()
                readerui:onClose()
            end
        end)

        it("should scroll backward on the first page without crash", function()
            local readerui = ReaderUI.instance
            local paging = readerui.paging

            paging:onScrollPanRel(-100)
        end)

        it("should scroll forward on the last page without crash", function()
            local readerui = ReaderUI.instance
            local paging = readerui.paging

            paging:onGotoPage(readerui.document:getPageCount())
            paging:onScrollPanRel(120)
            paging:onScrollPanRel(-1)
            paging:onScrollPanRel(120)
        end)
    end)
end)
