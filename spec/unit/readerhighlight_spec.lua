describe("Readerhighlight module", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen, Geom, Event
    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    local function highlight_single_word(pos0)
        local readerui = ReaderUI.instance
        local s = spy.on(readerui.languagesupport, "improveWordSelection")

        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldRelease()
        readerui.highlight:onHighlight()

        assert.spy(s).was_called()
        assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport),
                                      match.is_ref(readerui.highlight.selected_text))
        -- Reset in case we're called more than once.
        readerui.languagesupport.improveWordSelection:revert()

        UIManager:scheduleIn(1, function()
            UIManager:close(readerui.dictionary.dict_window)
            UIManager:close(readerui)
            UIManager:quit()
        end)
        UIManager:run()
    end
    local function highlight_text(pos0, pos1)
        local readerui = ReaderUI.instance
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldPan(nil, { pos = pos1 })
        local next_slot
        for i = #UIManager._window_stack, 0, -1 do
            local top_window = UIManager._window_stack[i]
            -- skip modal window
            if not top_window or not top_window.widget.modal then
                next_slot = i + 1
                break
            end
        end
        readerui.highlight:onHoldRelease()
        assert.truthy(readerui.highlight.highlight_dialog)
        assert.truthy(UIManager._window_stack[next_slot].widget
                      == readerui.highlight.highlight_dialog)
        readerui.highlight:onHighlight()
        UIManager:scheduleIn(1, function()
            UIManager:close(readerui.highlight.highlight_dialog)
            UIManager:close(readerui)
            UIManager:quit()
        end)
        UIManager:run()
    end
    local function tap_highlight_text(pos0, pos1, pos2)
        local readerui = ReaderUI.instance
        -- Check the actual call chain, instead of relying on the actual internal highlight_dialog object directly...
        -- Besides being less nutty, this will work for overlapping highlights...
        local s = spy.on(readerui.highlight, "showChooseHighlightDialog")

        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldPan(nil, { pos = pos1 })
        readerui.highlight:onHoldRelease()
        readerui.highlight:onHighlight()
        readerui.highlight:clear()
        UIManager:close(readerui.highlight.highlight_dialog)
        readerui.highlight:onTap(nil, { pos = pos2 })
        if not readerui.highlight.edit_highlight_dialog then
            -- Take an up-to-date screenshot if this step failed, it's probably because we found overlapping HLs
            UIManager:forceRePaint()
            Screen:shot("screenshots/tap_highlight_text_overlapping_highlights.png")
        end
        assert.spy(s).was_called()
        UIManager:nextTick(function()
            UIManager:close(readerui.highlight.edit_highlight_dialog)
            UIManager:close(readerui)
            UIManager:quit()
        end)
        UIManager:run()
    end

    describe("highlight for EPUB documents", function()
        local page = 10
        before_each(function()
            UIManager:quit()

            local sample_epub = "spec/front/unit/data/juliet.epub"
            local readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
            local selection_spy = spy.on(readerui.languagesupport, "improveWordSelection")

            UIManager:show(readerui)
            readerui.rolling:onGotoPage(page)
            selection_spy:clear()
            --- @fixme HACK: Mock UIManager:run x and y for readerui.dimen
            --- @todo Refactor readerview's dimen handling so we can get rid of
            -- this workaround
            readerui:paintTo(Screen.bb, 0, 0)
        end)
        after_each(function()
            local readerui = ReaderUI.instance

            if readerui then
                readerui.highlight:clear()
                readerui:closeDocument()
                readerui:onClose()
            end
        end)
        it("should highlight single word", function()
            local readerui = ReaderUI.instance
            local selection_spy = spy.on(readerui.languagesupport, "improveWordSelection")

            highlight_single_word(Geom:new{ x = 400, y = 70 })
            Screen:shot("screenshots/reader_highlight_single_word_epub.png")
            assert.spy(selection_spy).was_called()
            assert.truthy(readerui.view.highlight.saved[page])
        end)
        it("should highlight text", function()
            local readerui = ReaderUI.instance
            local selection_spy = spy.on(readerui.languagesupport, "improveWordSelection")

            highlight_text(Geom:new{ x = 400, y = 110 },
                           Geom:new{ x = 400, y = 170 })
            Screen:shot("screenshots/reader_highlight_text_epub.png")
            assert.spy(selection_spy).was_called()
            assert.truthy(readerui.view.highlight.saved[page])
        end)
        it("should response on tap gesture", function()
            local readerui = ReaderUI.instance
            local selection_spy = spy.on(readerui.languagesupport, "improveWordSelection")

            tap_highlight_text(Geom:new{ x = 130, y = 100 },
                               Geom:new{ x = 350, y = 395 },
                               Geom:new{ x = 80, y = 265 })
            Screen:shot("screenshots/reader_tap_highlight_text_epub.png")
            assert.spy(selection_spy).was_called()
        end)
    end)

    describe("highlight for PDF documents in page mode", function()
        local sample_pdf = "spec/front/unit/data/sample.pdf"
        describe("for scanned page with text layer", function()
            before_each(function()
                UIManager:quit()

                local readerui = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(sample_pdf),
                }
                readerui:handleEvent(Event:new("SetScrollMode", false))

                UIManager:show(readerui)
                readerui.paging:onGotoPage(10)
                -- We want up-to-date screenshots
                readerui:paintTo(Screen.bb, 0, 0)
            end)
            after_each(function()
                local readerui = ReaderUI.instance

                if readerui then
                    readerui.highlight:clear()
                    readerui:closeDocument()
                    readerui:onClose()
                end
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(Geom:new{ x = 260, y = 70 },
                                   Geom:new{ x = 260, y = 150 },
                                   Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf.png")
            end)
            it("should highlight single word", function()
                highlight_single_word(Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf.png")
            end)
            it("should highlight text", function()
                highlight_text(Geom:new{ x = 260, y = 170 }, Geom:new{ x = 260, y = 250 })
                Screen:shot("screenshots/reader_highlight_text_pdf.png")
            end)
        end)
        describe("for scanned page without text layer", function()
            before_each(function()
                UIManager:quit()

                local readerui = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(sample_pdf),
                }
                readerui:handleEvent(Event:new("SetScrollMode", false))

                UIManager:show(readerui)
                readerui.paging:onGotoPage(28)
                readerui:paintTo(Screen.bb, 0, 0)
            end)
            after_each(function()
                local readerui = ReaderUI.instance

                if readerui then
                    readerui.highlight:clear()
                    readerui:closeDocument()
                    readerui:onClose()
                end
            end)
            it("should respond to tap gesture", function()
                tap_highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 250, y = 75 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_scanned.png")
            end)
            it("should highlight single word", function()
                highlight_single_word(Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_scanned.png")
            end)
            it("should highlight text", function()
                highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_scanned.png")
            end)
        end)
        describe("for reflowed page", function()
            before_each(function()
                UIManager:quit()

                local readerui = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(sample_pdf),
                }
                readerui:handleEvent(Event:new("SetScrollMode", false))
                readerui.document.configurable.text_wrap = 1
                readerui:handleEvent(Event:new("ReflowUpdated"))

                UIManager:show(readerui)
                readerui.paging:onGotoPage(31)
                readerui:paintTo(Screen.bb, 0, 0)
            end)
            after_each(function()
                local readerui = ReaderUI.instance

                if readerui then
                    readerui.highlight:clear()
                    readerui.document.configurable.text_wrap = 0
                    readerui:handleEvent(Event:new("ReflowUpdated"))
                    readerui:closeDocument()
                    readerui:onClose()
                end
            end)
            it("should respond to tap gesture", function()
                tap_highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 250, y = 75 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_reflowed.png")
            end)
            it("should highlight single word", function()
                highlight_single_word(Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_reflowed.png")
            end)
            it("should highlight text", function()
                highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_reflowed.png")
            end)
        end)
    end)

    describe("highlight for PDF documents in scroll mode", function()
        local sample_pdf = "spec/front/unit/data/sample.pdf"
        describe("for scanned page with text layer", function()
            before_each(function()
                UIManager:quit()

                local readerui = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(sample_pdf),
                }
                readerui:handleEvent(Event:new("SetScrollMode", true))

                UIManager:show(readerui)
                readerui.paging:onGotoPage(10)
                readerui.zooming:setZoomMode("contentwidth")
                readerui:paintTo(Screen.bb, 0, 0)
            end)
            after_each(function()
                local readerui = ReaderUI.instance

                if readerui then
                    readerui.highlight:clear()
                    readerui:closeDocument()
                    readerui:onClose()
                end
            end)
            it("should highlight single word", function()
                highlight_single_word(Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_scroll.png")
            end)
            it("should highlight text", function()
                highlight_text(Geom:new{ x = 260, y = 170 }, Geom:new{ x = 260, y = 250 })
                Screen:shot("screenshots/reader_highlight_text_pdf_scroll.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(Geom:new{ x = 260, y = 70 },
                                   Geom:new{ x = 260, y = 150 },
                                   Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_scroll.png")
            end)
        end)
        describe("for scanned page without text layer", function()
            before_each(function()
                UIManager:quit()

                local readerui = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(sample_pdf),
                }
                readerui:handleEvent(Event:new("SetScrollMode", true))

                UIManager:show(readerui)
                readerui.paging:onGotoPage(28)
                readerui.zooming:setZoomMode("contentwidth")
                readerui:paintTo(Screen.bb, 0, 0)
            end)
            after_each(function()
                local readerui = ReaderUI.instance

                if readerui then
                    readerui.highlight:clear()
                    readerui:closeDocument()
                    readerui:onClose()
                end
            end)
            it("should highlight single word", function()
                highlight_single_word(Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_scanned_scroll.png")
            end)
            it("should highlight text", function()
                highlight_text(Geom:new{x = 192, y = 186}, Geom:new{x = 280, y = 186})
                Screen:shot("screenshots/reader_highlight_text_pdf_scanned_scroll.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 250, y = 75 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_scanned_scroll.png")
            end)
        end)
        describe("for reflowed page", function()
            before_each(function()
                UIManager:quit()

                local readerui = ReaderUI:new{
                    dimen = Screen:getSize(),
                    document = DocumentRegistry:openDocument(sample_pdf),
                }
                readerui:handleEvent(Event:new("SetScrollMode", true))
                readerui.document.configurable.text_wrap = 1
                readerui:handleEvent(Event:new("ReflowUpdated"))

                UIManager:show(readerui)
                readerui.paging:onGotoPage(31)
                readerui:paintTo(Screen.bb, 0, 0)
            end)
            after_each(function()
                local readerui = ReaderUI.instance

                if readerui then
                    readerui.highlight:clear()
                    readerui.document.configurable.text_wrap = 0
                    readerui:handleEvent(Event:new("ReflowUpdated"))
                    readerui:closeDocument()
                    readerui:onClose()
                end
            end)
            it("should highlight single word", function()
                highlight_single_word(Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_reflowed_scroll.png")
            end)
            it("should highlight text", function()
                highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_reflowed_scroll.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 250, y = 75 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_reflowed_scroll.png")
            end)
        end)
    end)

end)
