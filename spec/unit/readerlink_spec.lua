describe("ReaderLink module", function()
    local DocumentRegistry, ReaderUI, UIManager, sample_epub, sample_pdf, Event, Screen

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
    end)

    local readerui

    local function fastforward_ui_events()
        -- Fast forward all scheduled tasks.
        UIManager:shiftScheduledTasksBy(-1e9)
        UIManager:run()
    end

    after_each(function()
        readerui:closeDocument()
        readerui:onClose()
        readerui = nil
        UIManager:quit()
        UIManager._exit_code = nil
    end)

    describe("with epub", function()

        before_each(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
        end)

        it("should jump to links #nocov", function()
            readerui.rolling:onGotoPage(5)
            readerui.link:onTap(nil, {pos = {x = 320, y = 190}})
            assert.is.same(37, readerui.rolling.current_page)
        end)

        it("should be able to go back after link jump #nocov", function()
            readerui.rolling:onGotoPage(5)
            readerui.link:onTap(nil, {pos = {x = 320, y = 190}})
            assert.is.same(37, readerui.rolling.current_page)
            readerui.link:onGoBackLink()
            assert.is.same(5, readerui.rolling.current_page)
        end)

    end)

    describe("with pdf", function()

        before_each(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
        end)

        it("should jump to links in page mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            readerui.link:onTap(nil, {pos = {x = 363, y = 565}})
            fastforward_ui_events()
            assert.is.same(22, readerui.paging.current_page)
        end)

        it("should jump to links in scroll mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", true))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            assert.is.same(1, readerui.paging.current_page)
            readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
            fastforward_ui_events()
            -- its really hard to get the exact page number in scroll mode
            -- page positions may have unexpected impact on page number
            assert.truthy(readerui.paging.current_page == 21
                or readerui.paging.current_page == 20)
        end)

        it("should be able to go back after link jump in page mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", false))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            readerui.link:onTap(nil, {pos = {x = 363, y = 565}})
            fastforward_ui_events()
            assert.is.same(22, readerui.paging.current_page)
            readerui.link:onGoBackLink()
            assert.is.same(1, readerui.paging.current_page)
        end)

        it("should be able to go back after link jump in scroll mode", function()
            readerui:handleEvent(Event:new("SetScrollMode", true))
            readerui:handleEvent(Event:new("SetZoomMode", "page"))
            readerui.paging:onGotoPage(1)
            assert.is.same(1, readerui.paging.current_page)
            readerui.link:onTap(nil, {pos = {x = 228, y = 534}})
            fastforward_ui_events()
            assert.truthy(readerui.paging.current_page == 21
                or readerui.paging.current_page == 20)
            readerui.link:onGoBackLink()
            assert.is.same(1, readerui.paging.current_page)
        end)

    end)

    describe("with pdf", function()

        before_each()

        it("should be able to go back to the same position after link jump in scroll mode", function()
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
            readerui = ReaderUI:new{
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
            fastforward_ui_events()
            assert.is.same(22, readerui.paging.current_page)
            readerui.link:onGoBackLink()
            assert.is.same(3, readerui.paging.current_page)
            assert.are.same(expected_page_states, readerui.view.page_states)
        end)

    end)
end)
