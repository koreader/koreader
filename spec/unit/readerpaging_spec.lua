describe("Readerpaging module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui
    local paging

    setup(function() require("commonrequire") end)

    describe("Page mode", function()
        setup(function()
            readerui = require("apps/reader/readerui"):new{
                document = require("document/documentregistry"):openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)

        it("should emit EndOfBook event at the end", function()
            readerui.zooming:setZoomMode("pageheight")
            paging:gotoPage(readerui.document:getPageCount())
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
            readerui = require("apps/reader/readerui"):new{
                document = require("document/documentregistry"):openDocument(sample_pdf),
            }
            paging = readerui.paging
        end)

        it("should emit EndOfBook event at the end", function()
            paging:gotoPage(readerui.document:getPageCount())
            readerui.zooming:setZoomMode("pageheight")
            readerui.view:onToggleScrollMode(true)
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
