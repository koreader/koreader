describe("ReaderLink module", function()
    local DocumentRegistry, ReaderUI, sample_epub, sample_pdf, Event, Screen

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        sample_epub = "spec/front/unit/data/leaves.epub"
        sample_pdf = "spec/front/unit/data/paper.pdf"
    end)

    local readerui

    after_each(function()
        readerui:closeDocument()
        readerui:onClose()
        readerui = nil
    end)

    describe("with epub", function()

        before_each(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
        end)

        it("should jump to links", function()
            readerui.rolling:onGotoPage(5)
            readerui.link:onTap(nil, {pos = {x = 320, y = 190}})
            assert.is.same(37, readerui.rolling.current_page)
        end)

        it("keeps footnote popup open and returns to source", function()
            local UIManager = require("ui/uimanager")
            local previous_follow_setting = G_reader_settings:readSetting("footnote_popup_follow_links")
            local original_document = readerui.link.document
            local original_on_goto_link = readerui.link.onGotoLink
            local original_show = UIManager.show
            local original_close = UIManager.close
            local original_set_dirty = UIManager.setDirty
            local popup_widget
            local navigated_link
            local popup_close_count = 0

            local ok, err = xpcall(function()
                G_reader_settings:saveSetting("footnote_popup_follow_links", true)
                readerui.link.document = setmetatable({
                    configurable = original_document.configurable,
                    getHTMLFromXPointer = function()
                        return '<a href="#destination">Destination</a>'
                    end,
                    getPageMargins = function()
                        return original_document:getPageMargins()
                    end,
                    highlightXPointer = function() end,
                    isLinkToFootnote = function()
                        return true
                    end,
                }, { __index = original_document })
                UIManager.setDirty = function() end
                UIManager.show = function(_, widget)
                    popup_widget = widget
                end
                UIManager.close = function()
                    popup_close_count = popup_close_count + 1
                end
                readerui.link.onGotoLink = function(_, link)
                    navigated_link = link
                end

                assert.is_true(readerui.link:showAsFootnotePopup({
                    xpointer = "#footnote",
                    from_xpointer = "#source",
                }, false))
                assert.truthy(popup_widget.html:find('href="koreader://footnote-popup-source"', 1, true))

                popup_widget.html_link_tapped_callback({ uri = "#destination" })
                assert.same({ xpointer = "#destination" }, navigated_link)
                assert.equals(0, popup_close_count)

                popup_widget.html_link_tapped_callback({ uri = "koreader://footnote-popup-source" })
                assert.same({
                    xpointer = "#source",
                    marker_xpointer = "#source",
                }, navigated_link)
                assert.equals(0, popup_close_count)
            end, debug.traceback)

            readerui.link.document = original_document
            readerui.link.onGotoLink = original_on_goto_link
            UIManager.show = original_show
            UIManager.close = original_close
            UIManager.setDirty = original_set_dirty
            G_reader_settings:saveSetting("footnote_popup_follow_links", previous_follow_setting)
            if popup_widget then
                popup_widget.htmlwidget.htmlbox_widget:free()
            end
            if not ok then
                error(err)
            end
        end)

        it("should be able to go back after link jump", function()
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
                    saturation = 1,
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
                    saturation = 1,
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
