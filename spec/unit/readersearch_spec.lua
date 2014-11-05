require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DEBUG = require("dbg")

local sample_epub = "spec/front/unit/data/juliet.epub"

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
                assert.are.equal(8, pageno)
            end
            for i = 1, 5, 1 do
                rolling:gotoPage(i)
                local words = search:searchFromStart("Verona")
                assert(words == nil)
            end
        end)
        it("should find the last occurrence", function()
            for i = 100, 200, 10 do
                rolling:gotoPage(i)
                local words = search:searchFromEnd("Verona")
                assert.truthy(words)
                local pageno = doc:getPageFromXPointer(words[1].start)
                assert.are.equal(208, pageno)
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
    end)
end)
