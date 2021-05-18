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

    local function highlight_single_word(readerui, pos0)
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldRelease()
        readerui.highlight:onHighlight()
        UIManager:scheduleIn(1, function()
            UIManager:close(readerui.dictionary.dict_window)
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
            UIManager:quit()
        end)
        UIManager:run()
    end
    local function highlight_text(readerui, pos0, pos1)
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
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
            UIManager:quit()
        end)
        UIManager:run()
    end
    local function tap_highlight_text(readerui, pos0, pos1, pos2)
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldPan(nil, { pos = pos1 })
        readerui.highlight:onHoldRelease()
        readerui.highlight:onHighlight()
        readerui.highlight:clear()
        UIManager:close(readerui.highlight.highlight_dialog)
        readerui.highlight:onTap(nil, { pos = pos2 })
        assert.truthy(readerui.highlight.edit_highlight_dialog)
        UIManager:nextTick(function()
            UIManager:close(readerui.highlight.edit_highlight_dialog)
            UIManager:close(readerui)
            -- We haven't torn it down yet
            ReaderUI.instance = readerui
            UIManager:quit()
        end)
        UIManager:run()
    end

    describe("highlight for EPUB documents", function()
        local page = 10
        local readerui
        setup(function()
            local sample_epub = "spec/front/unit/data/juliet.epub"
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:quit()
            readerui.rolling:onGotoPage(page)
            UIManager:show(readerui)
            --- @fixme HACK: Mock UIManager:run x and y for readerui.dimen
            --- @todo Refactor readerview's dimen handling so we can get rid of
            -- this workaround
            readerui:paintTo(Screen.bb, 0, 0)
        end)
        after_each(function()
            readerui.highlight:clear()
        end)
        it("should highlight single word", function()
            highlight_single_word(readerui, Geom:new{ x = 400, y = 70 })
            Screen:shot("screenshots/reader_highlight_single_word_epub.png")
            assert.truthy(readerui.view.highlight.saved[page])
        end)
        it("should highlight text", function()
            highlight_text(readerui,
                           Geom:new{ x = 400, y = 110 },
                           Geom:new{ x = 400, y = 170 })
            Screen:shot("screenshots/reader_highlight_text_epub.png")
            assert.truthy(readerui.view.highlight.saved[page])
        end)
        it("should response on tap gesture", function()
            tap_highlight_text(readerui,
                               Geom:new{ x = 130, y = 100 },
                               Geom:new{ x = 350, y = 395 },
                               Geom:new{ x = 80, y = 265 })
            Screen:shot("screenshots/reader_tap_highlight_text_epub.png")
        end)
    end)

    describe("highlight for PDF documents in page mode", function()
        local readerui
        setup(function()
            local sample_pdf = "spec/front/unit/data/sample.pdf"
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            readerui:handleEvent(Event:new("SetScrollMode", false))
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)
        describe("for scanned page with text layer", function()
            before_each(function()
                UIManager:quit()
                UIManager:show(readerui)
                readerui.paging:onGotoPage(10)
            end)
            after_each(function()
                readerui.highlight:clear()
            end)
            it("should highlight single word", function()
                highlight_single_word(readerui, Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf.png")
            end)
            it("should highlight text", function()
                highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(readerui,
                                   Geom:new{ x = 260, y = 70 },
                                   Geom:new{ x = 260, y = 150 },
                                   Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf.png")
            end)
        end)
        describe("for scanned page without text layer", function()
            before_each(function()
                UIManager:quit()
                UIManager:show(readerui)
                readerui.paging:onGotoPage(28)
            end)
            after_each(function()
                readerui.highlight:clear()
            end)
            it("should highlight single word", function()
                highlight_single_word(readerui, Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_scanned.png")
            end)
            it("should highlight text", function()
                highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_scanned.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_scanned.png")
            end)
        end)
        describe("for reflowed page", function()
            before_each(function()
                UIManager:quit()
                readerui.document.configurable.text_wrap = 1
                UIManager:show(readerui)
                readerui.paging:onGotoPage(31)
            end)
            after_each(function()
                readerui.highlight:clear()
                readerui.document.configurable.text_wrap = 0
                UIManager:close(readerui)  -- close to flush settings
                -- We haven't torn it down yet
                ReaderUI.instance = readerui
            end)
            it("should highlight single word", function()
                highlight_single_word(readerui, Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_reflowed.png")
            end)
            it("should highlight text", function()
                highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_reflowed.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_reflowed.png")
            end)
        end)
    end)

    describe("highlight for PDF documents in scroll mode", function()
        local readerui
        setup(function()
            local sample_pdf = "spec/front/unit/data/sample.pdf"
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
            }
            readerui:handleEvent(Event:new("SetScrollMode", true))
        end)
        teardown(function()
            readerui:closeDocument()
            readerui:onClose()
        end)
        describe("for scanned page with text layer", function()
            before_each(function()
                UIManager:quit()
                UIManager:show(readerui)
                readerui.paging:onGotoPage(10)
                readerui.zooming:setZoomMode("contentwidth")
            end)
            after_each(function()
                readerui.highlight:clear()
            end)
            it("should highlight single word", function()
                highlight_single_word(readerui, Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_scroll.png")
            end)
            it("should highlight text", function()
                highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_scroll.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(readerui,
                                   Geom:new{ x = 260, y = 70 },
                                   Geom:new{ x = 260, y = 150 },
                                   Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_scroll.png")
            end)
        end)
        describe("for scanned page without text layer", function()
            before_each(function()
                UIManager:quit()
                UIManager:show(readerui)
                readerui.paging:onGotoPage(28)
                readerui.zooming:setZoomMode("contentwidth")
            end)
            after_each(function()
                readerui.highlight:clear()
            end)
            it("should highlight single word", function()
                highlight_single_word(readerui, Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_scanned_scroll.png")
            end)
            it("should highlight text", function()
                highlight_text(readerui, Geom:new{x = 192, y = 186}, Geom:new{x = 280, y = 186})
                Screen:shot("screenshots/reader_highlight_text_pdf_scanned_scroll.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_scanned_scroll.png")
            end)
        end)
        describe("for reflowed page", function()
            before_each(function()
                UIManager:quit()
                readerui.document.configurable.text_wrap = 1
                UIManager:show(readerui)
                readerui.paging:onGotoPage(31)
            end)
            after_each(function()
                readerui.highlight:clear()
                readerui.document.configurable.text_wrap = 0
                UIManager:close(readerui)  -- close to flush settings
                -- We haven't torn it down yet
                ReaderUI.instance = readerui
            end)
            it("should highlight single word", function()
                highlight_single_word(readerui, Geom:new{ x = 260, y = 70 })
                Screen:shot("screenshots/reader_highlight_single_word_pdf_reflowed_scroll.png")
            end)
            it("should highlight text", function()
                highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                Screen:shot("screenshots/reader_highlight_text_pdf_reflowed_scroll.png")
            end)
            it("should response on tap gesture", function()
                tap_highlight_text(readerui, Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 }, Geom:new{ x = 280, y = 110 })
                Screen:shot("screenshots/reader_tap_highlight_text_pdf_reflowed_scroll.png")
            end)
        end)
    end)

end)
