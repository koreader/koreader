require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DEBUG = require("dbg")

local sample_epub = "spec/front/unit/data/juliet.epub"
local sample_pdf = "spec/front/unit/data/sample.pdf"

describe("Readersearch module", function()
    describe("search API for EPUB documents", function()
        local doc, search, rolling
        setup(function()
            local readerui = ReaderUI:new{
                document = DocumentRegistry:openDocument(sample_epub),
            }
            doc = readerui.document
            search = readerui.search
            rolling = readerui.rolling
        end)
        it("should search backward", function()
            rolling:gotoPage(10)
            assert.truthy(search:searchFromCurrent("Verona", 1))
            for i = 1, 100, 10 do
                rolling:gotoPage(i)
                local words = search:searchFromCurrent("Verona", 1)
                if words then
                    for _, word in ipairs(words) do
                        local pageno = doc:getPageFromXPointer(word.start)
                        --DEBUG("found at pageno", pageno)
                        assert.truthy(pageno <= i)
                    end
                end
            end
        end)
        it("should search forward", function()
            rolling:gotoPage(10)
            assert.truthy(search:searchFromCurrent("Verona", 0))
            for i = 1, 100, 10 do
                rolling:gotoPage(i)
                local words = search:searchFromCurrent("Verona", 0)
                if words then
                    for _, word in ipairs(words) do
                        local pageno = doc:getPageFromXPointer(word.start)
                        --DEBUG("found at pageno", pageno)
                        assert.truthy(pageno >= i)
                    end
                end
            end
        end)
        it("should find the first occurrence", function()
            for i = 10, 100, 10 do
                rolling:gotoPage(i)
                local words = search:searchFromStart("Verona")
                assert.truthy(words)
                local pageno = doc:getPageFromXPointer(words[1].start)
                assert.are.equal(7, pageno)
            end
            for i = 1, 5, 1 do
                rolling:gotoPage(i)
                local words = search:searchFromStart("Verona")
                assert(words == nil)
            end
        end)
        it("should find the last occurrence", function()
            for i = 100, 180, 10 do
                rolling:gotoPage(i)
                local words = search:searchFromEnd("Verona")
                assert.truthy(words)
                local pageno = doc:getPageFromXPointer(words[1].start)
                assert.are.equal(198, pageno)
            end
            for i = 230, 235, 1 do
                rolling:gotoPage(i)
                local words = search:searchFromEnd("Verona")
                assert(words == nil)
            end
        end)
        it("should find all occurrences", function()
            local count = 0
            rolling:gotoPage(1)
            local words = search:searchFromCurrent("Verona", 0)
            while words do
                count = count + #words
                for _, word in ipairs(words) do
                    --DEBUG("found word", word.start)
                end
                doc:gotoXPointer(words[1].start)
                words = search:searchNext("Verona", 0)
            end
            assert.are.equal(13, count)
        end)
    end)
    describe("search API for PDF documents", function()
        local doc, search, paging
        setup(function()
            local readerui = ReaderUI:new{
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            doc = readerui.document
            search = readerui.search
            paging = readerui.paging
        end)
        it("should match single word with case insensitive option in one page", function()
            assert.are.equal(9, #doc.koptinterface:findAllMatches(doc, "what", true, 20))
            assert.are.equal(51, #doc.koptinterface:findAllMatches(doc, "the", true, 20))
            assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "xxxx", true, 20))
        end)
        it("should match single word with case sensitive option in one page", function()
            assert.are.equal(7, #doc.koptinterface:findAllMatches(doc, "what", false, 20))
            assert.are.equal(49, #doc.koptinterface:findAllMatches(doc, "the", false, 20))
            assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "xxxx", false, 20))
        end)
        it("should match phrase in one page", function()
            assert.are.equal(2*2, #doc.koptinterface:findAllMatches(doc, "mean that", true, 20))
        end)
        it("should match whole phrase in one page", function()
            assert.are.equal(1*3, #doc.koptinterface:findAllMatches(doc, "mean that the", true, 20))
        end)
        it("should match with lua pattern", function()
            assert.are.equal(7*1, #doc.koptinterface:findAllMatches(doc, "chapter", true, 30))
            assert.are.equal(3*2, #doc.koptinterface:findAllMatches(doc, "chapter %d", true, 30))
            assert.are.equal(2*2, #doc.koptinterface:findAllMatches(doc, "chapter %d%d", true, 30))
            assert.are.equal(0*2, #doc.koptinterface:findAllMatches(doc, "chapter %d%d%d", true, 30))
        end)
        it("should not match empty string", function()
            assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "", true, 1))
        end)
        it("should not match on page without text layer", function()
            assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "e", true, 1))
        end)
        it("should search backward", function()
            paging:gotoPage(20)
            assert.truthy(search:searchFromCurrent("test", 1))
            for i = 1, 40, 10 do
                paging:gotoPage(i)
                local words = search:searchFromCurrent("test", 1)
                if words then
                    DEBUG("search backward: found at page", words.page)
                    assert.truthy(words.page <= i)
                end
            end
        end)
        it("should search forward", function()
            paging:gotoPage(20)
            assert.truthy(search:searchFromCurrent("test", 0))
            for i = 1, 40, 10 do
                paging:gotoPage(i)
                local words = search:searchFromCurrent("test", 0)
                if words then
                    DEBUG("search forward: found at page", words.page)
                    assert.truthy(words.page >= i)
                end
            end
        end)
        it("should find the first occurrence", function()
            for i = 20, 40, 10 do
                paging:gotoPage(i)
                local words = search:searchFromStart("test")
                assert.truthy(words)
                assert.are.equal(10, words.page)
            end
            for i = 1, 10, 2 do
                paging:gotoPage(i)
                local words = search:searchFromStart("test")
                assert(words == nil)
            end
        end)
        it("should find the last occurrence", function()
            for i = 10, 30, 10 do
                paging:gotoPage(i)
                local words = search:searchFromEnd("test")
                assert.truthy(words)
                assert.are.equal(32, words.page)
            end
            for i = 40, 50, 2 do
                paging:gotoPage(i)
                local words = search:searchFromEnd("test")
                assert(words == nil)
            end
        end)
        it("should find all occurrences", function()
            local count = 0
            paging:gotoPage(1)
            local words = search:searchFromCurrent("test", 0)
            while words do
                count = count + #words
                --DEBUG("found words", #words, words.page)
                paging:gotoPage(words.page)
                words = search:searchNext("test", 0)
            end
            assert.are.equal(11, count)
        end)
    end)
end)
