describe("ReaderBookmark module", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen, Geom, DocSettings
    local sample_epub, sample_pdf

    setup(function()
        require("commonrequire")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Geom = require("ui/geometry")

        sample_epub = "spec/front/unit/data/juliet.epub"
        sample_pdf = "spec/front/unit/data/sample.pdf"
    end)

    local function highlight_text(readerui, pos0, pos1)
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldPan(nil, { pos = pos1 })
        readerui.highlight:onHoldRelease()
        assert.truthy(readerui.highlight.highlight_dialog)
        readerui.highlight:onHighlight()
        UIManager:nextTick(function()
            UIManager:close(readerui.highlight.highlight_dialog)
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
        end)
        UIManager:run()
    end
    local function toggler_dogear(readerui)
        readerui.bookmark:onToggleBookmark()
        UIManager:nextTick(function()
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
        end)
        UIManager:run()
    end
    local function show_bookmark_menu(readerui)
        UIManager:nextTick(function()
            UIManager:close(readerui.bookmark.bookmark_menu)
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
        end)
        UIManager:run()
    end

    describe("EPUB document", function()
        local readerui
        setup(function()
            DocSettings:open(sample_epub):purge()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
            readerui.status.enabled = false
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:quit()
            UIManager:show(readerui)
            readerui.rolling:onGotoPage(10)
        end)
        it("should compare bookmarks properly", function()
            assert.truthy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', page = 1, pos0 = 0, pos1 = 2, },
                { notes = 'foo', page = 1, pos0 = 0, pos1 = 2, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', page = 1, pos0 = 0, pos1 = 2, },
                { notes = 'bar', page = 1, pos0 = 0, pos1 = 2, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo0', page = 1, pos0 = 0, pos1 = 0, },
                { notes = 'foo', page = 1, pos0 = 0, pos1 = 2, }))
        end)
        it("should show dogear after toggling non-bookmarked page", function()
            assert.falsy(readerui.view.dogear_visible)
            toggler_dogear(readerui)
            Screen:shot("screenshots/reader_bookmark_dogear_epub.png")
            assert.truthy(readerui.view.dogear_visible)
        end)
        it("should not show dogear after toggling bookmarked page", function()
            assert.truthy(readerui.view.dogear_visible)
            toggler_dogear(readerui)
            Screen:shot("screenshots/reader_bookmark_nodogear_epub.png")
            assert.falsy(readerui.view.dogear_visible)
        end)
        it("should sort bookmarks with descending page numbers", function()
            local pages = {1, 20, 5, 30, 10, 40, 15, 25, 35, 45}
            for _, page in ipairs(pages) do
                readerui.rolling:onGotoPage(page)
                toggler_dogear(readerui)
            end
            readerui.bookmark:onShowBookmark()
            show_bookmark_menu(readerui)
            Screen:shot("screenshots/reader_bookmark_10marks_epub.png")
            assert.are.same(10, #readerui.bookmark.bookmarks)
        end)
        it("should keep descending page numbers after removing bookmarks", function()
            local pages = {1, 30, 10, 40, 20}
            readerui.bookmark.bookmarks = {}
            for _, page in ipairs(pages) do
                readerui.rolling:onGotoPage(page)
                toggler_dogear(readerui)
            end
            readerui.bookmark:onShowBookmark()
            show_bookmark_menu(readerui)
            Screen:shot("screenshots/reader_bookmark_5marks_epub.png")
            assert.are.same(5, #readerui.bookmark.bookmarks)
        end)
        it("should add bookmark by highlighting", function()
            highlight_text(readerui,
                           Geom:new{ x = 260, y = 60 },
                           Geom:new{ x = 260, y = 90 })
            readerui.bookmark:onShowBookmark()
            show_bookmark_menu(readerui)
            Screen:shot("screenshots/reader_bookmark_6marks_epub.png")
            assert.are.same(6, #readerui.bookmark.bookmarks)
        end)
        it("should get previous bookmark for certain page", function()
            local xpointer = readerui.document:getXPointer()
            local bm_xpointer = readerui.bookmark:getPreviousBookmarkedPage(xpointer)
            assert.are.same(6, #readerui.bookmark.bookmarks)
            assert.are.same(1, readerui.document:getPageFromXPointer(bm_xpointer))
        end)
        it("should get next bookmark for certain page", function()
            local xpointer = readerui.document:getXPointer()
            local bm_xpointer = readerui.bookmark:getNextBookmarkedPage(xpointer)
            assert.are.same(20, readerui.document:getPageFromXPointer(bm_xpointer))
        end)
    end)

    describe("PDF document", function()
        local readerui
        setup(function()
            DocSettings:open(sample_pdf):purge()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            readerui.status.enabled = false
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:quit()
            UIManager:show(readerui)
            readerui.paging:onGotoPage(10)
        end)
        it("should does bookmark comparison properly", function()
            assert.truthy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', pos0 = { page = 1 , x = 2, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, },
                { notes = 'foo', pos0 = { page = 1 , x = 2, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', page = 1, pos0 = 0, pos1 = 2, },
                { notes = 'foo', page = 1, pos1 = 2, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', page = 1, pos0 = 0, pos1 = 2, },
                { notes = 'foo', page = 1, pos0 = 2, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', pos0 = { page = 1 , x = 2, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, },
                { notes = 'foo', pos0 = { page = 2 , x = 2, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', pos0 = { page = 1 , x = 1, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, },
                { notes = 'foo', pos0 = { page = 1 , x = 2, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, }))
            assert.falsy(readerui.bookmark:isBookmarkSame(
                { notes = 'foo', pos0 = { page = 1 , x = 1, y = 3},
                  pos1 = { page = 1, x = 20, y = 3 }, },
                { notes = 'foo', pos0 = { page = 1 , x = 1, y = 3},
                  pos1 = { page = 1, x = 20, y = 2 }, }))
        end)
        it("should show dogear after toggling non-bookmarked page", function()
            toggler_dogear(readerui)
            Screen:shot("screenshots/reader_bookmark_dogear_pdf.png")
            assert.truthy(readerui.view.dogear_visible)
        end)
        it("should not show dogear after toggling bookmarked page", function()
            toggler_dogear(readerui)
            Screen:shot("screenshots/reader_bookmark_nodogear_pdf.png")
            assert.truthy(not readerui.view.dogear_visible)
        end)
        it("should sort bookmarks with descending page numbers", function()
            local pages = {1, 20, 5, 30, 10, 40, 15, 25, 35, 45}
            for _, page in ipairs(pages) do
                readerui.paging:onGotoPage(page)
                toggler_dogear(readerui)
            end
            readerui.bookmark:onShowBookmark()
            show_bookmark_menu(readerui)
            Screen:shot("screenshots/reader_bookmark_10marks_pdf.png")
            assert.are.same(10, #readerui.bookmark.bookmarks)
        end)
        it("should keep descending page numbers after removing bookmarks", function()
            local pages = {1, 30, 10, 40, 20}
            for _, page in ipairs(pages) do
                readerui.paging:onGotoPage(page)
                toggler_dogear(readerui)
            end
            readerui.bookmark:onShowBookmark()
            show_bookmark_menu(readerui)
            Screen:shot("screenshots/reader_bookmark_5marks_pdf.png")
            assert.are.same(5, #readerui.bookmark.bookmarks)
        end)
        it("should add bookmark by highlighting", function()
            highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
            readerui.bookmark:onShowBookmark()
            show_bookmark_menu(readerui)
            Screen:shot("screenshots/reader_bookmark_6marks_pdf.png")
            assert.are.same(6, #readerui.bookmark.bookmarks)
        end)
        it("should get previous bookmark for certain page", function()
            assert.are.same(5, readerui.bookmark:getPreviousBookmarkedPage(10))
        end)
        it("should get next bookmark for certain page", function()
            assert.are.same(15, readerui.bookmark:getNextBookmarkedPage(10))
        end)
        it("should search/add bookmarks properly", function()
            -- clear bookmarks created by previous tests
            readerui.bookmark.bookmarks = {}
            local p1 = { x = 0, y = 0, page = 100 }
            local bm1 = { notes = 'foo', page = 10,
                          pos0 = { x = 0, y = 0, page = 100 }, pos1 = p1, }
            assert.falsy(readerui.bookmark:isBookmarkAdded(bm1))
            readerui.bookmark:addBookmark(bm1)
            assert.are.same(readerui.bookmark.bookmarks, {bm1})

            local bm2 = { notes = 'foo', page = 1,
                          pos0 = { x = 0, y = 0, page = 1 }, pos1 = p1, }
            assert.falsy(readerui.bookmark:isBookmarkAdded(bm2))
            readerui.bookmark:addBookmark(bm2)
            assert.are.same({bm1, bm2}, readerui.bookmark.bookmarks)

            local bm3 = { notes = 'foo', page = 5,
                          pos0 = { x = 0, y = 0, page = 5 }, pos1 = p1, }
            assert.falsy(readerui.bookmark:isBookmarkAdded(bm3))
            readerui.bookmark:addBookmark(bm3)
            assert.are.same({bm1, bm3, bm2}, readerui.bookmark.bookmarks)

            assert.truthy(readerui.bookmark:isBookmarkAdded(bm1))
            assert.truthy(readerui.bookmark:isBookmarkAdded(bm2))
            assert.truthy(readerui.bookmark:isBookmarkAdded(bm3))
        end)
    end)
end)
