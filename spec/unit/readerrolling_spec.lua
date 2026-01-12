describe("Readerrolling module", function()
    local DocumentRegistry, UIManager, ReaderUI, Event, Screen
    local readerui, rolling

    setup(function()
        require("commonrequire")
        disable_plugins()
        UIManager = require("ui/uimanager")
        stub(UIManager, "getNthTopWidget")
        UIManager.getNthTopWidget.returns({})
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Event = require("ui/event")
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

    describe("test in portrait screen mode", function()
        it("should goto portrait screen mode", function()
            readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
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
                rolling:onGotoNextChapter()
                assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
            end
        end)

        it("should goto previous chapter", function()
            local toc = readerui.toc
            for i = 60, 80, 5 do
                rolling:onGotoPage(i)
                rolling:onGotoPrevChapter()
                assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
            end
        end)

        it("should emit EndOfBook event at the end of sample epub", function()
            local called = false
            local saved_handler = readerui.onEndOfBook
            readerui.onEndOfBook = function()
                called = true
            end
            finally(function() readerui.onEndOfBook = saved_handler end)
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
        end)

        it("should emit EndOfBook event at the end sample txt", function()
            local sample_txt = "spec/front/unit/data/sample.txt"
            local old_instance = readerui
            finally(function()
                ReaderUI.instance = old_instance
                readerui = old_instance
                rolling = readerui.rolling
            end)
            ReaderUI.instance = nil
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_txt),
            }
            rolling = readerui.rolling
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
            -- not at the end of the book
            rolling:onGotoPage(3)
            assert.is.falsy(called)
            rolling:onGotoViewRel(1)
            assert.is.falsy(called)
            -- at the end of the book
            rolling:onGotoPage(readerui.document:getPageCount())
            assert.is.falsy(called)
            rolling:onGotoViewRel(1)
            assert.is.truthy(called)
            readerui:onClose()
        end)
    end)

    describe("test in landscape screen mode", function()
        it("should go to landscape screen mode", function()
            readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
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
                rolling:onGotoNextChapter()
                assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
            end
        end)
        it("should goto previous chapter", function()
            local toc = readerui.toc
            for i = 60, 80, 5 do
                rolling:onGotoPage(i)
                rolling:onGotoPrevChapter()
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
            readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
        end)
        it("for portrait-landscape-portrait switching", function()
            for i = 80, 10 do
                readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
                rolling:onGotoPage(i)
                assert.are.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
                assert.are_not.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("for landscape-portrait-landscape switching", function()
            for i = 110, 20 do
                readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
                rolling:onGotoPage(i)
                assert.are.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
                assert.are_not.same(i, rolling.current_page)
                readerui:handleEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
                assert.are.same(i, rolling.current_page)
            end
        end)
    end)

    describe("test changing word gap - space condensing", function()
        it("should show pages for different word gap", function()
            readerui:handleEvent(Event:new("SetWordSpacing", {100, 90}))
            assert.are.same(252, readerui.document:getPageCount())
            readerui:handleEvent(Event:new("SetWordSpacing", {95, 75}))
            assert.are.same(241, readerui.document:getPageCount())
            readerui:handleEvent(Event:new("SetWordSpacing", {75, 50}))
            assert.are.same(231, readerui.document:getPageCount())
        end)
    end)

    describe("test initialization", function()
        it("should emit PageUpdate event after book is rendered", function()
            local ReaderView = require("apps/reader/modules/readerview")
            local saved_handler = ReaderView.onPageUpdate
            ReaderView.onPageUpdate = function(this)
                assert.are.same(6, this.ui.document:getPageCount())
            end
            local test_book = "spec/front/unit/data/sample.txt"
            require("docsettings"):open(test_book):purge()
            readerui:onClose()
            readerui = ReaderUI:new{
                document = DocumentRegistry:openDocument(test_book),
            }
            ReaderView.onPageUpdate = saved_handler
        end)
    end)
end)
