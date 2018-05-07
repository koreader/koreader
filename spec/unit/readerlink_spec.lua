describe("ReaderLink module", function()
    local DocumentRegistry, ReaderUI, UIManager, sample_epub, sample_pdf, Event

    setup(function()
        require("commonrequire")
        package.unloadAll()
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        sample_epub = "spec/front/unit/data/leaves.epub"
        sample_pdf = "spec/front/unit/data/paper.pdf"
    end)

    it("should jump to links in epub #nocov", function()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.rolling:onGotoPage(4)
        readerui.link:onTap(nil, {pos = {x = 336, y = 668}})
        assert.is.same(36, readerui.rolling.current_page)
    end)

    it("should jump to links in pdf page mode", function()
        UIManager:quit()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", false))
        readerui.paging:onGotoPage(1)
        readerui.link:onTap(nil, {pos = {x = 363, y = 585}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
    end)

    it("should jump to links in pdf scroll mode", function()
        UIManager:quit()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", true))
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.link:onTap(nil, {pos = {x = 250, y = 534}})
        UIManager:run()
        -- its really hard to get the exact page number in scroll mode
        -- page positions may have unexpected impact on page number
        assert.truthy(readerui.paging.current_page == 21
            or readerui.paging.current_page == 20)
    end)

    it("should be able to go back after link jump in epub #nocov", function()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.rolling:onGotoPage(4)
        readerui.link:onTap(nil, {pos = {x = 336, y = 668}})
        assert.is.same(36, readerui.rolling.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(4, readerui.rolling.current_page)
    end)

    it("should be able to go back after link jump in pdf page mode", function()
        UIManager:quit()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", false))
        readerui.paging:onGotoPage(1)
        readerui.link:onTap(nil, {pos = {x = 363, y = 585}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(1, readerui.paging.current_page)
    end)

    it("should be able to go back after link jump in pdf scroll mode", function()
        UIManager:quit()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", true))
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.link:onTap(nil, {pos = {x = 250, y = 534}})
        UIManager:run()
        assert.truthy(readerui.paging.current_page == 21
            or readerui.paging.current_page == 20)
        readerui.link:onGoBackLink()
        assert.is.same(1, readerui.paging.current_page)
    end)

    it("should be able to go back to the same position after link jump in pdf scroll mode", function()
        UIManager:quit()
        local expected_page_states = {
            {
                gamma = 1,
                offset = {x = 17, y = 0},
                page = 3,
                page_area = {
                  x = 0, y = 0,
                  h = 800, w = 566,
                },
                rotation = 0,
                visible_area = {
                  x = 0, y = 694,
                  h = 106, w = 566,
                },
                zoom = 0.9501187648456056456,
           },
           {
                gamma = 1,
                offset = {x = 17, y = 0},
                page = 4,
                page_area = {
                  h = 800, w = 566,
                  x = 0, y = 0,
                },
                rotation = 0,
                visible_area = {
                  h = 686, w = 566,
                  x = 0, y = 0,
                },
                zoom = 0.9501187648456056456,
            },
        }
        -- disable footer
        G_reader_settings:saveSetting("reader_footer_mode", 0)
        require("docsettings"):open(sample_pdf):purge()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.falsy(readerui.view.footer_visible)
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.view:onSetScrollMode(true)
        assert.is.same(true, readerui.view.page_scroll)
        assert.is.same(1, readerui.paging.current_page)
        readerui.paging:onTapForward()
        assert.is.same(2, readerui.paging.current_page)
        readerui.paging:onTapForward()
        assert.is.same(3, readerui.paging.current_page)
        readerui.paging:onTapForward()
        assert.is.same(4, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)
        readerui.link:onTap(nil, {pos = {x = 181, y = 366}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(3, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)
    end)
end)
