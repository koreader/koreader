describe("ReaderLink module", function()
    local DocumentRegistry, ReaderUI, UIManager, sample_epub, sample_pdf

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        sample_epub = "spec/front/unit/data/leaves.epub"
        sample_pdf = "spec/front/unit/data/Adaptively.Scaling.The.Metropolis.Algorithm.Using.Expected.Squared.Jumped.Distance.pdf"
    end)

    it("should jump to links in epub", function()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.rolling:onGotoPage(4)
        readerui.link:onTap(nil, {pos = {x = 336, y = 668}})
        assert.is.same(36, readerui.rolling.current_page)
    end)

    it("should jump to links in pdf", function()
        UIManager:quit()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui.paging:onGotoPage(1)
        readerui.link:onTap(nil, {pos = {x = 363, y = 585}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
    end)

    it("should be able to go back after link jump in epub", function()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.rolling:onGotoPage(4)
        readerui.link:onTap(nil, {pos = {x = 336, y = 668}})
        assert.is.same(36, readerui.rolling.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(4, readerui.rolling.current_page)
    end)

    it("should be able to go back after link jump in pdf", function()
        UIManager:quit()
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui.paging:onGotoPage(1)
        readerui.link:onTap(nil, {pos = {x = 363, y = 585}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(1, readerui.paging.current_page)
    end)

    it("should be able to go back after link jump in pdf in scroll mode", function()
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
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui.view:onSetScrollMode(true)
        assert.is.same(true, readerui.view.page_scroll)
        readerui.paging:onTapForward()
        readerui.paging:onTapForward()
        readerui.paging:onTapForward()
        assert.is.same(4, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)
        readerui.link:onTap(nil, {pos = {x = 181, y = 366}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(4, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)
    end)
end)
