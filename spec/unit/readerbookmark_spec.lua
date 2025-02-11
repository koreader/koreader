describe("ReaderBookmark module", function()
    local DataStorage, DocumentRegistry, ReaderUI, UIManager, Screen, Geom, DocSettings, Util
    local sample_epub, sample_pdf

    setup(function()
        require("commonrequire")
        disable_plugins()
        DataStorage = require("datastorage")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Geom = require("ui/geometry")
        Util = require("ffi/util")

        sample_epub = "spec/front/unit/data/juliet.epub"
        sample_pdf = DataStorage:getDataDir() .. "/readerbookmark.pdf"

        Util.copyFile("spec/front/unit/data/sample.pdf", sample_pdf)
    end)

    local function highlight_text(readerui, pos0, pos1)
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldPan(nil, { pos = pos1 })
        readerui.highlight:onHoldRelease()
        assert.truthy(readerui.highlight.highlight_dialog)
        readerui.highlight:saveHighlight()
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
            readerui:onClose()
        end)
        before_each(function()
            UIManager:show(readerui)
        end)
        after_each(function()
            UIManager:quit()
        end)
        it("should show dogear after toggling non-bookmarked page", function()
            readerui.rolling:onGotoPage(10)
            assert.falsy(readerui.view.dogear_visible)
            readerui.bookmark:onToggleBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_dogear_epub.png")
            assert.truthy(readerui.view.dogear_visible)
        end)
        it("should not show dogear after toggling bookmarked page", function()
            readerui.rolling:onGotoPage(10)
            assert.truthy(readerui.view.dogear_visible)
            readerui.bookmark:onToggleBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_nodogear_epub.png")
            assert.falsy(readerui.view.dogear_visible)
        end)
        it("should sort bookmarks with ascending page numbers", function()
            local pages = {1, 20, 5, 30, 10, 40, 15, 25, 35, 45}
            for _, page in ipairs(pages) do
                readerui.rolling:onGotoPage(page)
                readerui.bookmark:onToggleBookmark()
            end
            readerui.bookmark:onShowBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_10marks_epub.png")
            assert.are.same(10, #readerui.annotation.annotations)
            assert.are.same(15, readerui.document:getPageFromXPointer(readerui.annotation.annotations[4].page))
        end)
        it("should keep descending page numbers after removing bookmarks", function()
            local pages = {1, 30, 10, 40, 20}
            for _, page in ipairs(pages) do
                readerui.rolling:onGotoPage(page)
                readerui.bookmark:onToggleBookmark()
            end
            readerui.bookmark:onShowBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_5marks_epub.png")
            assert.are.same(5, #readerui.annotation.annotations)
        end)
        it("should add bookmark by highlighting", function()
            readerui.rolling:onGotoPage(10)
            highlight_text(readerui,
                           Geom:new{ x = 260, y = 60 },
                           Geom:new{ x = 260, y = 90 })
            readerui.bookmark:onShowBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_6marks_epub.png")
            assert.are.same(6, #readerui.annotation.annotations)
        end)
        it("should get previous bookmark for certain page", function()
            local xpointer = readerui.document:getXPointer()
            local bm_xpointer = readerui.bookmark:getPreviousBookmarkedPage(xpointer)
            assert.are.same(6, #readerui.annotation.annotations)
            assert.are.same(5, readerui.document:getPageFromXPointer(bm_xpointer))
        end)
        it("should get next bookmark for certain page", function()
            local xpointer = readerui.document:getXPointer()
            local bm_xpointer = readerui.bookmark:getNextBookmarkedPage(xpointer)
            assert.are.same(15, readerui.document:getPageFromXPointer(bm_xpointer))
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
            UIManager:show(readerui)
        end)
        teardown(function()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:show(readerui)
        end)
        after_each(function()
            UIManager:quit()
        end)
        it("should show dogear after toggling non-bookmarked page", function()
            readerui.paging:onGotoPage(10)
            readerui.bookmark:onToggleBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_dogear_pdf.png")
            assert.truthy(readerui.view.dogear_visible)
        end)
        it("should not show dogear after toggling bookmarked page", function()
            readerui.paging:onGotoPage(10)
            readerui.bookmark:onToggleBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_nodogear_pdf.png")
            assert.truthy(not readerui.view.dogear_visible)
        end)
        it("should sort bookmarks with ascending page numbers", function()
            local pages = {20, 9, 30, 10, 15}
            for _, page in ipairs(pages) do
                readerui.paging:onGotoPage(page)
                readerui.bookmark:onToggleBookmark()
            end
            readerui.bookmark:onShowBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_5marks_pdf.png")
            local annotated_pages = {}
            for i, a in ipairs(readerui.annotation.annotations) do
                table.insert(annotated_pages, a.page)
            end
            assert.are.same({9, 10, 15, 20, 30}, annotated_pages)
        end)
        it("should keep descending page numbers after removing bookmarks", function()
            local pages = {30, 10, 20}
            for _, page in ipairs(pages) do
                readerui.paging:onGotoPage(page)
                readerui.bookmark:onToggleBookmark()
            end
            readerui.bookmark:onShowBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_2marks_pdf.png")
            assert.are.same(2, #readerui.annotation.annotations)
        end)
        it("should add bookmark by highlighting", function()
            readerui.paging:onGotoPage(10)
            highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
            readerui.bookmark:onShowBookmark()
            fastforward_ui_events()
            screenshot(Screen, "reader_bookmark_3marks_pdf.png")
            assert.are.same(3, #readerui.annotation.annotations)
        end)
        it("should get previous bookmark for certain page", function()
            assert.are.same(9, readerui.bookmark:getPreviousBookmarkedPage(10))
        end)
        it("should get next bookmark for certain page", function()
            assert.are.same(15, readerui.bookmark:getNextBookmarkedPage(10))
        end)
    end)
end)
