describe("Readerfooter module", function()
    local DocumentRegistry, ReaderUI, DocSettings, UIManager, DEBUG
    local purgeDir, Screen

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        DocSettings = require("docsettings")
        UIManager = require("ui/uimanager")
        DEBUG = require("dbg")
        purgeDir = require("ffi/util").purgeDir
        Screen = require("device").screen
    end)

    before_each(function()
        G_reader_settings:saveSetting("footer", {
            disabled = false,
            all_at_once = true,
            progress_bar = true,
            toc_markers = true,
            battery = true,
            time = true,
            page_progress = true,
            pages_left = true,
            percentage = true,
            book_time_to_read = true,
            chapter_time_to_read = true,
        })
    end)

    it("should setup footer for epub without error", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        footer:onPageUpdate(1)
        footer:updateFooter()
        timeinfo = footer:getTimeInfo()
        -- stats has not been initialized here, so we get na TB and TC
        assert.are.same('B:0% | '..timeinfo..' | 1 / 204 | => 1 | R:0% | TB: na | TC: na',
                        footer.progress_text.text)
    end)

    it("should setup footer for pdf without error", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui.view.footer:updateFooter()
        timeinfo = readerui.view.footer:getTimeInfo()
        assert.are.same('B:0% | '..timeinfo..' | 1 / 2 | => 1 | R:50% | TB: na | TC: na',
                        readerui.view.footer.progress_text.text)
    end)

    it("should switch between different modes", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        footer:resetLayout()
        footer:updateFooter()
        timeinfo = readerui.view.footer:getTimeInfo()
        assert.are.same('B:0% | '..timeinfo..' | 1 / 2 | => 1 | R:50% | TB: na | TC: na',
                        footer.progress_text.text)
        footer.mode = 1
        footer.settings.all_at_once = false
        footer:updateFooter()
        assert.are.same('1 / 2', footer.progress_text.text)

        footer.mode = 3
        footer:updateFooter()
        assert.are.same('=> 1', footer.progress_text.text)

        footer.mode = 4
        footer:updateFooter()
        assert.are.same('B:0%', footer.progress_text.text)

        footer.mode = 5
        footer:updateFooter()
        assert.are.same('R:50%', footer.progress_text.text)

        footer.mode = 6
        footer:updateFooter()
        assert.are.same('TB: na', footer.progress_text.text)

        footer.mode = 7
        footer:updateFooter()
        assert.are.same('TC: na', footer.progress_text.text)
    end)

    it("should pick up screen resize in resetLayout", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local horizontal_margin = Screen:scaleBySize(10)*2
        footer:updateFooter()
        assert.is.same(357, footer.text_width)
        assert.is.same(600, footer.progress_bar.width
                            + footer.text_width
                            + horizontal_margin)
        assert.is.same(223, footer.progress_bar.width)

        local old_screen_getwidth = Screen.getWidth
        Screen.getWidth = function() return 900 end
        footer:resetLayout()
        assert.is.same(357, footer.text_width)
        assert.is.same(900, footer.progress_bar.width
                            + footer.text_width
                            + horizontal_margin)
        assert.is.same(523, footer.progress_bar.width)
        Screen.getWidth = old_screen_getwidth
    end)

    it("should update width on PosUpdate event", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        footer:onPageUpdate(1)
        assert.are.same(215, footer.progress_bar.width)
        assert.are.same(365, footer.text_width)

        footer:onPageUpdate(100)
        assert.are.same(191, footer.progress_bar.width)
        assert.are.same(389, footer.text_width)
    end)

    it("should support chapter markers", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        footer:onPageUpdate(1)
        assert.are.same({
            3, 6, 9, 10, 26, 33, 40, 47, 57, 58, 61, 73, 79, 94, 99, 102, 115,
            123, 133, 136, 151, 159, 163, 167, 170, 179, 184, 186,
        }, footer.progress_bar.ticks)
        assert.are.same(204, footer.progress_bar.last)
    end)

    it("should schedule/unschedule auto refresh time task", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("footer", {
            page_progress = true,
            auto_refresh_time = true,
        })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshTime then
                found = found + 1
            end
        end
        assert.is.same(1, found)

        footer:onCloseDocument()
        found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshTime then
                found = found + 1
            end
        end
        assert.is.same(0, found)
    end)

    it("should not schedule auto refresh time task if footer is disabled", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("footer", {
            disabled = true,
            page_progress = true,
            auto_refresh_time = true,
        })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshTime then
                found = found + 1
            end
        end
        assert.is.same(0, found)
    end)
end)
