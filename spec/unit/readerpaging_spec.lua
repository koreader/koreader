describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui, Event, DocumentRegistry, ReaderUI, Screen
    local paging

    setup(function()
        require("commonrequire")
        disable_plugins()
        Event = require("ui/event")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
    end)

    describe("Page mode", function()
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)

        it("should emit EndOfBook event at the end", function()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui.zooming:setZoomMode("pageheight")
            paging:onGotoPage(readerui.document:getPageCount())
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)
    end)

    describe("Scroll mode", function()
        setup(function()
            local purgeDir = require("ffi/util").purgeDir
            local DocSettings = require("docsettings")
            purgeDir(DocSettings:getSidecarDir(sample_pdf))
            os.remove(DocSettings:getHistoryPath(sample_pdf))

            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)

        it("should emit EndOfBook event at the end", function()
            paging.page_positions = {}
            readerui:handleEvent(Event:new("SetScrollMode", true))
            paging:onGotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onGotoViewRel(1)
            paging:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)
    end)

    describe("Scroll mode", function()

        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument("spec/front/unit/data/djvu3spec.djvu"),
            }
            paging = readerui.paging
        end)

        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)

        it("should scroll backward on the first page without crash", function()
            paging:onScrollPanRel(-100)
        end)

        it("should scroll forward on the last page without crash", function()
            paging:onGotoPage(readerui.document:getPageCount())
            paging:onScrollPanRel(120)
            paging:onScrollPanRel(-1)
            paging:onScrollPanRel(120)
        end)
    end)
end)
