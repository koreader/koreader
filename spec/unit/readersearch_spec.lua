describe("Readersearch module", function()
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local DocumentRegistry, ReaderUI, Screen, dbg

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        dbg = require("dbg")
    end)

    describe("search API for EPUB documents", function()
        local readerui, doc, search, rolling
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
            doc = readerui.document
            search = readerui.search
            rolling = readerui.rolling
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)
        it("should search backward", function()
            rolling:onGotoPage(10)
            assert.truthy(search:searchFromCurrent("Verona", 1))
            for i = 1, 100, 10 do
                rolling:onGotoPage(i)
                local words = search:searchFromCurrent("Verona", 1)
                if words then
                    for _, word in ipairs(words) do
                        local pageno = doc:getPageFromXPointer(word.start)
                        --dbg("found at pageno", pageno)
                        assert.truthy(pageno <= i)
                    end
                end
            end
        end)
        it("should search forward", function()
            rolling:onGotoPage(10)
            assert.truthy(search:searchFromCurrent("Verona", 0))
            for i = 1, 100, 10 do
                rolling:onGotoPage(i)
                local words = search:searchFromCurrent("Verona", 0)
                if words then
                    for _, word in ipairs(words) do
                        local pageno = doc:getPageFromXPointer(word.start)
                        --dbg("found at pageno", pageno)
                        assert.truthy(pageno >= i)
                    end
                end
            end
        end)
        it("should find the first occurrence", function()
            for i = 10, 100, 10 do
                rolling:onGotoPage(i)
                local words = search:searchFromStart("Verona")
                assert.truthy(words)
                local pageno = doc:getPageFromXPointer(words[1].start)
                assert.truthy(pageno < 10)
            end
            for i = 1, 5, 1 do
                rolling:onGotoPage(i)
                local words = search:searchFromStart("Verona")
                assert(words == nil)
            end
        end)
        it("should find the last occurrence", function()
            -- local logger = require("logger")
            -- logger.warn("nb of pages", doc:getPageCount())
            -- 20190202: currently 242 pages
            for i = 100, 180, 10 do
                rolling:onGotoPage(i)
                local words = search:searchFromEnd("Verona")
                assert.truthy(words)
                local pageno = doc:getPageFromXPointer(words[1].start)
                -- logger.info("last match on page", pageno)
                assert.truthy(pageno > 185)
            end
            for i = 290, 335, 1 do
                rolling:onGotoPage(i)
                local words = search:searchFromEnd("Verona")
                assert(words == nil)
            end
        end)
        it("should find all occurrences", function()
            local count = 0
            rolling:onGotoPage(1)
            local cur_page = doc:getCurrentPage()
            local words = search:searchFromCurrent("Verona", 0)
            while words do
                local new_page = nil
                for _, word in ipairs(words) do
                    --dbg("found word", word.start)
                    local word_page = doc:getPageFromXPointer(word.start)
                    if word_page ~= cur_page then -- ignore words on current page
                        if not new_page then -- first word on a new page
                            new_page = word_page
                            count = count + 1
                            doc:gotoXPointer(word.start) -- go to this new page
                        else -- new page seen
                            if word_page == new_page then -- only count words on this new page
                                count = count + 1
                            end
                        end
                    end
                end
                if not new_page then -- no word seen on any new page
                    break
                end
                cur_page = doc:getCurrentPage()
                words = search:searchNext("Verona", 0)
            end
            assert.are.equal(13, count)
        end)
    end)

    describe("search API for PDF documents", function()
        local readerui, doc, search, paging
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            doc = readerui.document
            search = readerui.search
            paging = readerui.paging
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
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
        it("should not match empty string", function()
            assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "", true, 1))
        end)
        it("should not match on page without text layer", function()
            assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "e", true, 1))
        end)
        it("should search backward", function()
            paging:onGotoPage(20)
            assert.truthy(search:searchFromCurrent("test", 1))
            for i = 1, 40, 10 do
                paging:onGotoPage(i)
                local words = search:searchFromCurrent("test", 1)
                if words then
                    dbg("search backward: found at page", words.page)
                    assert.truthy(words.page <= i)
                end
            end
        end)
        it("should search forward", function()
            paging:onGotoPage(20)
            assert.truthy(search:searchFromCurrent("test", 0))
            for i = 1, 40, 10 do
                paging:onGotoPage(i)
                local words = search:searchFromCurrent("test", 0)
                if words then
                    dbg("search forward: found at page", words.page)
                    assert.truthy(words.page >= i)
                end
            end
        end)
        it("should find the first occurrence", function()
            for i = 20, 40, 10 do
                paging:onGotoPage(i)
                local words = search:searchFromStart("test")
                assert.truthy(words)
                assert.are.equal(10, words.page)
            end
            for i = 1, 10, 2 do
                paging:onGotoPage(i)
                local words = search:searchFromStart("test")
                assert(words == nil)
            end
        end)
        it("should find the last occurrence", function()
            for i = 10, 30, 10 do
                paging:onGotoPage(i)
                local words = search:searchFromEnd("test")
                assert.truthy(words)
                assert.are.equal(32, words.page)
            end
            for i = 40, 50, 2 do
                paging:onGotoPage(i)
                local words = search:searchFromEnd("test")
                assert(words == nil)
            end
        end)
        it("should find all occurrences", function()
            local count = 0
            paging:onGotoPage(1)
            local words = search:searchFromCurrent("test", 0)
            while words do
                count = count + #words
                --dbg("found words", #words, words.page)
                paging:onGotoPage(words.page)
                words = search:searchNext("test", 0)
            end
            assert.are.equal(11, count)
        end)
    end)
end)
