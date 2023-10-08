describe("Readertoc module", function()
    local DocumentRegistry, ReaderUI, Screen, DEBUG
    local readerui, toc, toc_max_depth, title

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        DEBUG = require("dbg")

        local sample_epub = "spec/front/unit/data/juliet.epub"
        -- Clear settings from previous tests
        local DocSettings = require("docsettings")
        local doc_settings = DocSettings:open(sample_epub)
        doc_settings:close()
        doc_settings:purge()

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        -- reset book to first page
        readerui.rolling:onGotoPage(0)
        toc = readerui.toc
    end)

    it("should get max toc depth", function()
        toc_max_depth = toc:getMaxDepth()
        assert.are.same(2, toc_max_depth)
    end)
    it("should get toc title from page", function()
        title = toc:getTocTitleByPage(60)
        DEBUG("toc", toc.toc)
        assert.is.equal("SCENE V. A hall in Capulet's house.", title)
        title = toc:getTocTitleByPage(187)
        assert.is.equal("SCENE I. Friar Laurence's cell.", title)
    end)
    describe("getTocTicks API", function()
        local ticks_level_1 = nil
        it("should get ticks of level 1", function()
            ticks_level_1 = toc:getTocTicks(1)
            assert.are.same(7, #ticks_level_1)
        end)
        local ticks_level_2 = nil
        it("should get ticks of level 2", function()
            ticks_level_2 = toc:getTocTicks(2)
            assert.are.same(26, #ticks_level_2)
        end)
        local ticks_level_m1 = nil
        it("should get ticks of level -1", function()
            ticks_level_m1 = toc:getTocTicks(-1)
            assert.are.same(26, #ticks_level_m1)
        end)
        it("should get the same ticks of level -1 and level 2", function()
            if toc_max_depth == 2 then
                assert.are.same(ticks_level_2, ticks_level_m1)
            end
        end)
        local ticks_level_flat = nil
        it("should get all ticks (flattened)", function()
            ticks_level_flat = toc:getTocTicksFlattened()
            assert.are.same(28, #ticks_level_flat)
        end)
    end)
    it("should get page of next chapter", function()
        assert.truthy(toc:getNextChapter(10) > 10)
        assert.truthy(toc:getNextChapter(100) > 100)
        assert.are.same(nil, toc:getNextChapter(290))
    end)
    it("should get page of previous chapter", function()
        assert.truthy(toc:getPreviousChapter(10) < 10)
        assert.truthy(toc:getPreviousChapter(100) < 100)
        assert.truthy(toc:getPreviousChapter(200) < 200)
    end)
    it("should get page left of chapter", function()
        assert.truthy(toc:getChapterPagesLeft(10) > 10)
        assert.truthy(toc:getChapterPagesLeft(95) > 10)
        -- assert.are.same(nil, toc:getChapterPagesLeft(290))
        -- Previous line somehow fails, but not if written this way:
        local pagesleft = toc:getChapterPagesLeft(290)
        assert.are.same(nil, pagesleft)
    end)
    it("should get page done of chapter", function()
        assert.truthy(toc:getChapterPagesDone(11) < 5)
        assert.truthy(toc:getChapterPagesDone(88) < 5)
        assert.truthy(toc:getChapterPagesDone(290) > 10)
    end)
    describe("collasible TOC", function()
        it("should collapse the secondary toc nodes by default", function()
            toc:onShowToc()
            assert.are.same(7, #toc.collapsed_toc)
        end)
        it("should not expand toc nodes that have no child nodes", function()
            toc:expandToc(2)
            assert.are.same(7, #toc.collapsed_toc)
        end)
        it("should expand toc nodes that have child nodes", function()
            toc:expandToc(3)
            assert.are.same(13, #toc.collapsed_toc)
            toc:expandToc(18)
            assert.are.same(18, #toc.collapsed_toc)
        end)
        it("should collapse toc nodes that have been expanded", function()
            toc:collapseToc(3)
            assert.are.same(12, #toc.collapsed_toc)
            toc:collapseToc(18)
            assert.are.same(7, #toc.collapsed_toc)

            --- @note: Delay the teardown 'til the last test, because of course the tests rely on incremental state changes across tests...
            readerui:closeDocument()
            readerui:onClose()
        end)
    end)
end)
