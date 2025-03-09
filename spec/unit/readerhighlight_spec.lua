describe("Readerhighlight module", function()
    local DataStorage, DocumentRegistry, ReaderUI, UIManager, Screen, Geom, Event
    local sample_pdf

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        DocumentRegistry = require("document/documentregistry")
        Event = require("ui/event")
        Geom = require("ui/geometry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        load_plugin('japanese.koplugin')
        sample_pdf = DataStorage:getDataDir() .. "/readerhighlight.pdf"
        require("ffi/util").copyFile("spec/front/unit/data/sample.pdf", sample_pdf)
    end)

    local readerui

    local function highlight_single_word(screenshot_filename, pos0)
        local s = spy.on(readerui.languagesupport, "improveWordSelection")
        -- Select a word.
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldRelease()
        readerui.highlight:saveHighlight()
        fastforward_ui_events()
        screenshot(Screen, screenshot_filename)
        assert.spy(s).was_called()
        assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport),
                                      match.is_ref(readerui.highlight.selected_text))
        -- Reset in case we're called more than once.
        readerui.languagesupport.improveWordSelection:revert()
    end
    local function highlight_text(screenshot_filename, pos0, pos1)
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
        fastforward_ui_events()
        screenshot(Screen, screenshot_filename)
        assert.truthy(readerui.highlight.highlight_dialog)
        assert.truthy(UIManager._window_stack[next_slot].widget
                      == readerui.highlight.highlight_dialog)
        readerui.highlight:saveHighlight()
    end
    local function tap_highlight_text(screenshot_filename, pos0, pos1, pos2)
        -- Highlight some text.
        readerui.highlight:onHold(nil, { pos = pos0 })
        readerui.highlight:onHoldPan(nil, { pos = pos1 })
        readerui.highlight:onHoldRelease()
        readerui.highlight:saveHighlight()
        readerui.highlight:clear()
        -- Close dialog.
        UIManager:close(readerui.highlight.highlight_dialog)
        fastforward_ui_events()
        -- Tap it.
        readerui.highlight:onTap(nil, { pos = pos2 })
        fastforward_ui_events()
        screenshot(Screen, screenshot_filename)
        assert.truthy(UIManager:getTopmostVisibleWidget().name == "edit_highlight_dialog")
    end

    describe("highlight for EPUB documents", function()
        local selection_spy
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument("spec/front/unit/data/juliet.epub"),
            }
            selection_spy = spy.on(readerui.languagesupport, "improveWordSelection")
        end)
        teardown(function()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:show(readerui)
            readerui.rolling:onGotoPage(10)
        end)
        after_each(function()
            selection_spy:clear()
            readerui.highlight:clear()
            readerui.annotation.annotations = {}
            UIManager:quit()
        end)
        it("should highlight word", function()
            highlight_single_word("readerhighlight_epub_word.png",
                                  Geom:new{ x = 400, y = 70 })
            assert.spy(selection_spy).was_called()
            assert.Equals(1, #readerui.annotation.annotations)
            assert.Equals('thy', readerui.annotation.annotations[1].text)
        end)
        it("should highlight text", function()
            highlight_text("readerhighlight_epub_text.png",
                           Geom:new{ x = 400, y = 110 },
                           Geom:new{ x = 400, y = 170 })
            assert.spy(selection_spy).was_called()
            assert.Equals(1, #readerui.annotation.annotations)
            assert.Equals('Montagues.\nSAMPSON', readerui.annotation.annotations[1].text)
        end)
        it("should response on tap gesture", function()
            tap_highlight_text("readerhighlight_epub_tap.png",
                               Geom:new{ x = 106, y = 271 },
                               Geom:new{ x = 370, y = 314 },
                               Geom:new{ x = 190, y = 305 })
            assert.spy(selection_spy).was_called()
            assert.Equals('GREGORY\nHow! turn thy back and run?', readerui.annotation.annotations[1].text)
        end)
    end)

    describe("highlight for PDF documents in page mode", function()
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
                _testsuite = true,
            }
            readerui.hinting.view.hinting = false
            readerui:handleEvent(Event:new("SetScrollMode", false))
        end)
        teardown(function()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:show(readerui)
        end)
        after_each(function()
            readerui.highlight:clear()
            readerui.annotation.annotations = {}
            UIManager:quit()
        end)
        describe("for scanned page with text layer", function()
            before_each(function()
                readerui.paging:onGotoPage(10)
            end)
            it("should highlight word", function()
                highlight_single_word("readerhighlight_pdf_layer_word.png",
                                      Geom:new{ x = 260, y = 70 })
                assert.Equals(1, #readerui.annotation.annotations)
                assert.Equals('Penn', readerui.annotation.annotations[1].text)
            end)
            it("should highlight text", function()
                highlight_text("readerhighlight_pdf_layer_text.png",
                               Geom:new{ x = 430, y = 210 },
                               Geom:new{ x = 60, y = 236 })
                assert.Equals(1, #readerui.annotation.annotations)
                assert.Equals('to take care of the London', readerui.annotation.annotations[1].text)
            end)
            it("should response on tap gesture", function()
                tap_highlight_text("readerhighlight_pdf_layer_tap.png",
                                   Geom:new{ x = 260, y = 70 },
                                   Geom:new{ x = 260, y = 150 },
                                   Geom:new{ x = 280, y = 110 })
            end)
        end)
        describe("for scanned page without text layer", function()
            before_each(function()
                readerui.paging:onGotoPage(28)
            end)
            it("should highlight word", function()
                highlight_single_word("readerhighlight_pdf_ocr_word.png",
                                      Geom:new{ x = 450, y = 60 })
                assert.Equals(1, #readerui.annotation.annotations)
                --- @fixme: OCR should automatically kicks in.
                -- assert.Equals('synthesis', readerui.annotation.annotations[1].text)
            end)
            it("should highlight text", function()
                highlight_text("readerhighlight_pdf_ocr_text.png",
                               Geom:new{ x = 150, y = 100 },
                               Geom:new{ x = 560, y = 80 })
                assert.Equals(1, #readerui.annotation.annotations)
                --- @fixme: OCR should automatically kicks in.
                -- assert.Equals('that completely changes', readerui.annotation.annotations[1].text)
            end)
            it("should respond to tap gesture", function()
                tap_highlight_text("readerhighlight_pdf_ocr_tap.png",
                                   Geom:new{ x = 500, y = 120 },
                                   Geom:new{ x = 100, y = 150 },
                                   Geom:new{ x = 530, y = 125 })
            end)
        end)
        describe("for reflowed page", function()
            before_each(function()
                readerui.document.configurable.text_wrap = 1
                readerui.paging:onGotoPage(31)
            end)
            after_each(function()
                readerui.document.configurable.text_wrap = 0
            end)
            it("should highlight word", function()
                highlight_single_word("readerhighlight_pdf_reflow_word.png",
                                      Geom:new{ x = 260, y = 70 })
                assert.Equals(1, #readerui.annotation.annotations)
            end)
            it("should highlight text", function()
                highlight_text("readerhighlight_pdf_reflow_text.png",
                               Geom:new{ x = 260, y = 70 },
                               Geom:new{ x = 260, y = 150 })
                assert.Equals(1, #readerui.annotation.annotations)
            end)
            it("should response on tap gesture", function()
                tap_highlight_text("readerhighlight_pdf_reflow_tap.png",
                                   Geom:new{ x = 260, y = 70 },
                                   Geom:new{ x = 360, y = 75 },
                                   Geom:new{ x = 310, y = 80 })
            end)
        end)
    end)

    describe("highlight for PDF documents in scroll mode", function()
        setup(function()
            readerui = ReaderUI:new{
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_pdf),
                _testsuite = true,
            }
            readerui.document.configurable.trim_page = 3
            readerui.hinting.view.hinting = false
            readerui:handleEvent(Event:new("SetScrollMode", true))
            readerui.zooming:setZoomMode("contentwidth")
        end)
        teardown(function()
            readerui:onClose()
        end)
        before_each(function()
            UIManager:show(readerui)
        end)
        after_each(function()
            readerui.highlight:clear()
            readerui.annotation.annotations = {}
            UIManager:quit()
        end)
        describe("for scanned page with text layer", function()
            before_each(function()
                readerui.paging:onGotoPage(10)
            end)
            it("should highlight word", function()
                highlight_single_word("readerhighlight_pdf_scroll_layer_word.png",
                                      Geom:new{ x = 318, y = 62 })
                assert.Equals(1, #readerui.annotation.annotations)
                assert.Equals("VOLTAIRE", readerui.annotation.annotations[1].text)
            end)
            it("should highlight text", function()
                highlight_text("readerhighlight_pdf_scroll_layer_text.png",
                               Geom:new{ x = 86, y = 158 },
                               Geom:new{ x = 402, y = 145 })
                assert.Equals(1, #readerui.annotation.annotations)
                assert.Equals("The patriarch, George Fox,", readerui.annotation.annotations[1].text)
            end)
            it("should response on tap gesture", function()
                tap_highlight_text("readerhighlight_pdf_scroll_layer_tap.png",
                                   Geom:new{ x = 544, y = 601 },
                                   Geom:new{ x = 344, y = 626 },
                                   Geom:new{ x = 130, y = 625 })
                assert.Equals(1, #readerui.annotation.annotations)
                assert.Equals("Will iam Penn returned soon to England", readerui.annotation.annotations[1].text)
            end)
        end)
        describe("for scanned page without text layer", function()
            before_each(function()
                readerui.paging:onGotoPage(28)
            end)
            it("should highlight word", function()
                highlight_single_word("readerhighlight_pdf_scroll_ocr_word.png",
                                      Geom:new{ x = 107, y = 59 })
                assert.Equals(1, #readerui.annotation.annotations)
                --- @fixme: OCR should automatically kicks in.
                -- assert.Equals("geometers", readerui.annotation.annotations[1].text)
            end)
            it("should highlight text", function()
                highlight_text("readerhighlight_pdf_scroll_ocr_text.png",
                               Geom:new{x = 192, y = 186}, Geom:new{x = 262, y = 189})
                assert.Equals(1, #readerui.annotation.annotations)
                --- @fixme: OCR should automatically kicks in.
                -- assert.Equals("concrete objects", readerui.annotation.annotations[1].text)
            end)
            it("should response on tap gesture", function()
                tap_highlight_text("readerhighlight_pdf_scroll_ocr_tap.png",
                                   Geom:new{ x = 500, y = 125 },
                                   Geom:new{ x = 105, y = 150 },
                                   Geom:new{ x = 520, y = 130 })
                assert.Equals(1, #readerui.annotation.annotations)
                --- @fixme: OCR should automatically kicks in.
                -- assert.Equals("objects of knowledge", readerui.annotation.annotations[1].text)
            end)
        end)
        describe("for reflowed page", function()
            before_each(function()
                readerui.document.configurable.text_wrap = 1
                readerui.paging:onGotoPage(31)
            end)
            after_each(function()
                readerui.document.configurable.text_wrap = 0
            end)
            it("should highlight word", function()
                highlight_single_word("reader_highlight_single_word_pdf_reflowed_scroll.png",
                                      Geom:new{ x = 260, y = 70 })
                assert.Equals(1, #readerui.annotation.annotations)
                assert.Equals("hedging", readerui.annotation.annotations[1].text)
            end)
            it("should highlight text", function()
                highlight_text("reader_highlight_text_pdf_reflowed_scroll.png",
                               Geom:new{ x = 260, y = 70 }, Geom:new{ x = 260, y = 150 })
                assert.truthy(#readerui.annotation.annotations == 1)
            end)
            it("should response on tap gesture", function()
                tap_highlight_text("reader_tap_highlight_text_pdf_reflowed_scroll.png",
                                   Geom:new{ x = 239, y = 72 },
                                   Geom:new{ x = 383, y = 75 },
                                   Geom:new{ x = 312, y = 66 })
                assert.Equals('hedging using futures', readerui.annotation.annotations[1].text)
            end)
        end)
    end)

end)
