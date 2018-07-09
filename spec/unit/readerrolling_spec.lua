describe("Readerrolling module", function()
    local DocumentRegistry, ReaderUI, Event
    local readerui, rolling

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Event = require("ui/event")

        local sample_epub = "spec/front/unit/data/juliet.epub"
        readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        rolling = readerui.rolling
    end)

    describe("test in portrait screen mode", function()
        it("should goto portrait screen mode", function()
            readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
        end)

        it("should goto certain page", function()
            for i = 1, 10, 5 do
                rolling:onGotoPage(i)
                assert.are.same(i, rolling.current_page)
            end
        end)

        it("should goto relative page", function()
            for i = 20, 40, 5 do
                rolling:onGotoPage(i)
                rolling:onGotoViewRel(1)
                assert.are.same(i + 1, rolling.current_page)
                rolling:onGotoViewRel(-1)
                assert.are.same(i, rolling.current_page)
            end
        end)

        it("should goto next chapter", function()
            local toc = readerui.toc
            for i = 30, 50, 5 do
                rolling:onGotoPage(i)
                rolling:onDoubleTapForward()
                assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
            end
        end)

        it("should goto previous chapter", function()
            local toc = readerui.toc
            for i = 60, 80, 5 do
                rolling:onGotoPage(i)
                rolling:onDoubleTapBackward()
                assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
            end
        end)

        it("should emit EndOfBook event at the end of sample epub", function()
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            -- check beginning of the book
            rolling:onGotoPage(1)
            assert.is.falsy(called)
            rolling:onGotoViewRel(-1)
            rolling:onGotoViewRel(-1)
            assert.is.falsy(called)
            -- check end of the book
            rolling:onGotoPage(readerui.document:getPageCount())
            assert.is.falsy(called)
            rolling:onGotoViewRel(1)
            assert.is.truthy(called)
            rolling:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)

        it("should emit EndOfBook event at the end sample txt", function()
            local sample_txt = "spec/front/unit/data/sample.txt"
            local txt_readerui = ReaderUI:new{
                document = DocumentRegistry:openDocument(sample_txt),
            }
            local called = false
            txt_readerui.onEndOfBook = function()
                called = true
            end
            local txt_rolling = txt_readerui.rolling
            -- check beginning of the book
            txt_rolling:onGotoPage(1)
            assert.is.falsy(called)
            txt_rolling:onGotoViewRel(-1)
            txt_rolling:onGotoViewRel(-1)
            assert.is.falsy(called)
            -- not at the end of the book
            txt_rolling:onGotoPage(3)
            assert.is.falsy(called)
            txt_rolling:onGotoViewRel(1)
            assert.is.falsy(called)
            -- at the end of the book
            txt_rolling:onGotoPage(txt_readerui.document:getPageCount())
            assert.is.falsy(called)
            txt_rolling:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)
    end)

    describe("test in landscape screen mode", function()
        it("should go to landscape screen mode", function()
            readerui:handleEvent(Event:new("ChangeScreenMode", "landscape"))
        end)
        it("should goto certain page", function()
            for i = 1, 10, 5 do
                rolling:onGotoPage(i)
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("should goto relative page", function()
            for i = 20, 40, 5 do
                rolling:onGotoPage(i)
                rolling:onGotoViewRel(1)
                assert.are.same(i + 1, rolling.current_page)
                rolling:onGotoViewRel(-1)
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("should goto next chapter", function()
            local toc = readerui.toc
            for i = 30, 50, 5 do
                rolling:onGotoPage(i)
                rolling:onDoubleTapForward()
                assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
            end
        end)
        it("should goto previous chapter", function()
            local toc = readerui.toc
            for i = 60, 80, 5 do
                rolling:onGotoPage(i)
                rolling:onDoubleTapBackward()
                assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
            end
        end)
        it("should emit EndOfBook event at the end", function()
            rolling:onGotoPage(readerui.document:getPageCount())
            local called = false
            readerui.onEndOfBook = function()
                called = true
            end
            rolling:onGotoViewRel(1)
            rolling:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui.onEndOfBook = nil
        end)
    end)

    describe("switching screen mode should not change current page number", function()
        teardown(function()
            readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
        end)
        it("for portrait-landscape-portrait switching", function()
            for i = 80, 100, 10 do
                readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
                rolling:onGotoPage(i)
                assert.are.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("ChangeScreenMode", "landscape"))
                assert.are_not.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("for landscape-portrait-landscape switching", function()
            for i = 110, 130, 10 do
                readerui:handleEvent(Event:new("ChangeScreenMode", "landscape"))
                rolling:onGotoPage(i)
                assert.are.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
                assert.are_not.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("ChangeScreenMode", "landscape"))
                assert.are.same(i, rolling.current_page)
            end
        end)
    end)

    describe("test changing word gap - space condensing", function()
        it("should show pages for different word gap", function()
            readerui.document:setSpaceCondensing(100)
            readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
            assert.are.same(208, readerui.document:getPageCount())
            readerui.document:setSpaceCondensing(75)
            readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
            assert.are.same(205, readerui.document:getPageCount())
            readerui.document:setSpaceCondensing(50)
            readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
            assert.are.same(199, readerui.document:getPageCount())
        end)
    end)

    describe("test initialization", function()
        it("should emit PageUpdate event after book is rendered", function()
            local ReaderView = require("apps/reader/modules/readerview")
            local saved_handler = ReaderView.onPageUpdate
            ReaderView.onPageUpdate = function(_self)
                assert.are.same(6, _self.ui.document:getPageCount())
            end
            local test_book = "spec/front/unit/data/sample.txt"
            require("docsettings"):open(test_book):purge()
            ReaderUI:new{
                document = DocumentRegistry:openDocument(test_book),
            }
            ReaderView.onPageUpdate = saved_handler
        end)
    end)
end)
