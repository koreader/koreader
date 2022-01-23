describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui, UIManager, Event, DocumentRegistry, ReaderUI, Screen
    local paging

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
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
            UIManager:quit()
            UIManager:show(readerui)
            UIManager:nextTick(function()
                UIManager:close(readerui)
                -- We haven't torn it down yet
                ReaderUI.instance = readerui
            end)
            UIManager:run()
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
            UIManager:quit()
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
            UIManager:quit()
            UIManager:show(readerui)
            UIManager:nextTick(function()
                UIManager:close(readerui)
                -- We haven't torn it down yet
                ReaderUI.instance = readerui
            end)
            UIManager:run()
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
            UIManager:quit()
        end)

        it("should scroll backward on the first page without crash", function()
            local sample_djvu = "spec/front/unit/data/djvu3spec.djvu"
            -- Unsafe second // ReaderUI instance!
            local tmp_readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_djvu),
            }
            tmp_readerui.paging:onScrollPanRel(-100)
            tmp_readerui:closeDocument()
            tmp_readerui:onClose()
            -- Restore the ref to the original ReaderUI instance
            ReaderUI.instance = readerui
        end)

        it("should scroll forward on the last page without crash", function()
            local sample_djvu = "spec/front/unit/data/djvu3spec.djvu"
            -- Unsafe second // ReaderUI instance!
            local tmp_readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_djvu),
            }
            paging = tmp_readerui.paging
            paging:onGotoPage(tmp_readerui.document:getPageCount())
            paging:onScrollPanRel(120)
            paging:onScrollPanRel(-1)
            paging:onScrollPanRel(120)
            tmp_readerui:closeDocument()
            tmp_readerui:onClose()
            -- Restore the ref to the original ReaderUI instance
            ReaderUI.instance = readerui
        end)
    end)
end)
