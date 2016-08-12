describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui, UIManager, Event
    local paging

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
    end)

    describe("Page mode", function()
        setup(function()
            readerui = require("apps/reader/readerui"):new{
                document = require("document/documentregistry"):openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)

        it("should emit EndOfBook event at the end", function()
            UIManager:quit()
            UIManager:show(readerui)
            UIManager:scheduleIn(1, function() UIManager:close(readerui) end)
            UIManager:run()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui.zooming:setZoomMode("pageheight")
            paging:onGotoPage(readerui.document:getPageCount())
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onPagingRel(1)
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

            readerui = require("apps/reader/readerui"):new{
                document = require("document/documentregistry"):openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)

        it("should emit EndOfBook event at the end", function()
            UIManager:quit()
            UIManager:show(readerui)
            UIManager:scheduleIn(1, function() UIManager:close(readerui) end)
            UIManager:run()
            paging.page_positions = {}
            readerui:handleEvent(Event:new("SetScrollMode", true))
            paging:onGotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onPagingRel(1)
            paging:onPagingRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
            UIManager:quit()
        end)
    end)
end)
