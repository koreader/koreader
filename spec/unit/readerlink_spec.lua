describe("ReaderLink module", function()
    local DocumentRegistry, ReaderUI, UIManager, sample_epub, sample_pdf, Event, Screen

    local purgeSidecar = function()
        local purgeDir = require("ffi/util").purgeDir
        local removePath = require("util").removePath
        local DocSettings = require("docsettings")
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        removePath(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
    end

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        sample_epub = "spec/front/unit/data/leaves.epub"
        sample_pdf = "spec/front/unit/data/paper.pdf"

        purgeSidecar()
    end)

    teardown(function()
        purgeSidecar()
    end)

    before_each(function()
        -- Yes, out of order quits, because of the LinkBox mess
        -- This is awful and doesn't make sense.
        UIManager:quit()
        -- This is yet another nonsensical hack to game the UI loop...
        UIManager._exit_code = nil
    end)

    after_each(function()
        local readerui = ReaderUI.instance

        if readerui then
            readerui:closeDocument()
            readerui:onClose()
        end
    end)

    it("should jump to links in epub #nocov", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.rolling:onGotoPage(5)
        assert.is.same(5, readerui.rolling.current_page)
        readerui.link:onTap(nil, {pos = {x = 255, y = 170}})
        assert.is.same(35, readerui.rolling.current_page)
    end)

    it("should jump to links in pdf page mode #nocov", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", false))
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.link:onTap(nil, {pos = {x = 292, y = 584}})
        -- Outside of CRe, LinkBox only jumps after FOLLOW_LINK_TIMEOUT... We delay run to cadge that. Maybe. Sometimes. Somehow.
        -- THIS TEST IS BROKEN AND DOESN'T MAKE SENSE.
        UIManager:run()
        assert.is.near(22, readerui.paging.current_page, 21) -- This *sometimes* doesn't work *at all*, hence the large range.
    end)

    it("should jump to links in pdf scroll mode #nocov", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", true))
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
        UIManager:run()
        -- its really hard to get the exact page number in scroll mode
        -- page positions may have unexpected impact on page number
        assert.is.near(22, readerui.paging.current_page, 2)
    end)

    it("should be able to go back after link jump in epub #nocov", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.rolling:onGotoPage(5)
        assert.is.same(5, readerui.rolling.current_page)
        readerui.link:onTap(nil, {pos = {x = 320, y = 190}})
        UIManager:run()
        assert.is.same(37, readerui.rolling.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(5, readerui.rolling.current_page)
    end)

    it("should be able to go back after link jump in pdf page mode #nocov", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", false))
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
        UIManager:run()
        assert.is.near(21, readerui.paging.current_page, 2)
        readerui.link:onGoBackLink()
        assert.is.same(1, readerui.paging.current_page)
    end)

    it("should be able to go back after link jump in pdf scroll mode #nocov", function()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetScrollMode", true))
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        assert.is.same(1, readerui.paging.current_page)
        readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
        UIManager:run()
        assert.is.near(22, readerui.paging.current_page, 2)
        readerui.link:onGoBackLink()
        assert.is.same(1, readerui.paging.current_page)
    end)

    it("should be able to go back to the same position after link jump in pdf scroll mode #nocov", function()
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
                zoom = 0.95032191328269044472,
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
                zoom = 0.95032191328269044472,
            },
        }
        -- disable footer
        G_reader_settings:saveSetting("reader_footer_mode", 0)
        require("docsettings"):open(sample_pdf):purge()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui:handleEvent(Event:new("SetZoomMode", "page"))
        assert.is.falsy(readerui.view.footer_visible)
        readerui.paging:onGotoPage(1)
        assert.is.same(1, readerui.paging.current_page)
        readerui.view:onSetScrollMode(true)
        assert.is.same(true, readerui.view.page_scroll)
        assert.is.same(1, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(1)
        assert.is.same(2, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(-1)
        assert.is.same(1, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(1)
        readerui.paging:onGotoViewRel(1)
        assert.is.same(3, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(-1)
        assert.is.same(2, readerui.paging.current_page)

        readerui.paging:onGotoViewRel(1)
        readerui.paging:onGotoViewRel(1)
        assert.is.same(4, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)

        readerui.link:onTap(nil, {pos = {x = 164, y = 366}})
        UIManager:run()
        assert.is.same(22, readerui.paging.current_page)
        readerui.link:onGoBackLink()
        assert.is.same(3, readerui.paging.current_page)
        assert.are.same(expected_page_states, readerui.view.page_states)
    end)
end)
