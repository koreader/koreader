require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local Event = require("ui/event")
local DEBUG = require("dbg")

describe("Readerrolling module", function()
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local readerui = ReaderUI:new{
        document = DocumentRegistry:openDocument(sample_epub),
    }
    local rolling = readerui.rolling
    describe("test in portrait screen mode", function()
        it("should goto portrait screen mode", function()
            readerui:handleEvent(Event:new("ChangeScreenMode", "portrait"))
        end)
        it("should goto certain page", function()
            for i = 1, 10, 5 do
                rolling:gotoPage(i)
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("should goto relative page", function()
            for i = 20, 40, 5 do
                rolling:gotoPage(i)
                rolling:onGotoViewRel(1)
                assert.are.same(i + 1, rolling.current_page)
                rolling:onGotoViewRel(-1)
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("should goto next chapter", function()
            local toc = readerui.toc
            for i = 30, 50, 5 do
                rolling:gotoPage(i)
                rolling:onDoubleTapForward()
                assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
            end
        end)
        it("should goto previous chapter", function()
            local toc = readerui.toc
            for i = 60, 80, 5 do
                rolling:gotoPage(i)
                rolling:onDoubleTapBackward()
                assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
            end
        end)
    end)
    describe("test in landscape screen mode", function()
        it("should go to landscape screen mode", function()
            readerui:handleEvent(Event:new("ChangeScreenMode", "landscape"))
        end)
        it("should goto certain page", function()
            for i = 1, 10, 5 do
                rolling:gotoPage(i)
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("should goto relative page", function()
            for i = 20, 40, 5 do
                rolling:gotoPage(i)
                rolling:onGotoViewRel(1)
                assert.are.same(i + 1, rolling.current_page)
                rolling:onGotoViewRel(-1)
                assert.are.same(i, rolling.current_page)
            end
        end)
        it("should goto next chapter", function()
            local toc = readerui.toc
            for i = 30, 50, 5 do
                rolling:gotoPage(i)
                rolling:onDoubleTapForward()
                assert.are.same(toc:getNextChapter(i, 0), rolling.current_page)
            end
        end)
        it("should goto previous chapter", function()
            local toc = readerui.toc
            for i = 60, 80, 5 do
                rolling:gotoPage(i)
                rolling:onDoubleTapBackward()
                assert.are.same(toc:getPreviousChapter(i, 0), rolling.current_page)
            end
        end)
    end)
    describe("switching screen mode should not change current page number", function()
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
end)
