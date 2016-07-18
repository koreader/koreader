describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui
    local paging

    setup(function() require("commonrequire") end)

    describe("Page mode", function()
        local Event

        setup(function()
            Event = require("ui/event")
            readerui = require("apps/reader/readerui"):new{
                document = require("document/documentregistry"):openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)

        it("should emit EndOfBook event at the end in page mode", function()
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
        end)

        it("should emit EndOfBook event at the end in scroll mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", true))
            paging:onGotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onPagingRel(1)
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

            readerui = require("apps/reader/readerui"):new{
                document = require("document/documentregistry"):openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)

        it("should emit EndOfBook event at the end", function()
            paging:onGotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            readerui.view:onSetScrollMode(true)
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            paging:onPagingRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)
    end)
end)
