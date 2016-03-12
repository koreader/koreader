require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
local purgeDir = require("ffi/util").purgeDir
local Screen = require("device").screen

describe("Readerfooter module", function()
    it("should setup footer for epub without error", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.view.footer.settings.page_progress = true
        readerui.view.footer.settings.all_at_once = true
        readerui.view.footer:updateFooter()
        timeinfo = readerui.view.footer:getTimeInfo()
        -- stats has not been initialized here, so we get na TB and TC
        assert.are.same('B:0% | '..timeinfo..' | 1 / 1 | => 0 | R:100% | TB: na | TC: na',
                        readerui.view.footer.progress_text.text)
    end)

    it("should setup footer for pdf without error", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui.view.footer.settings.page_progress = true
        readerui.view.footer.settings.all_at_once = true
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
        footer.settings.page_progress = true
        footer.settings.all_at_once = true
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
        footer.settings.page_progress = true
        footer.settings.all_at_once = true
        footer:resetLayout()
        assert.are.same(529, footer.progress_bar.width)

        local old_screen_getwidth = Screen.getWidth
        Screen.getWidth = function() return 900 end
        footer:resetLayout()
        assert.are.same(829, footer.progress_bar.width)
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
        footer.settings.page_progress = true
        footer.settings.all_at_once = true
        readerui.view.document.info.number_of_pages = 5000
        footer:onPageUpdate(1)
        assert.are.same(207, footer.progress_bar.width)
        assert.are.same(373, footer.text_width)

        footer:onPageUpdate(1000)
        assert.are.same(151, footer.progress_bar.width)
        assert.are.same(429, footer.text_width)
    end)


    it("should schedule/unschedule auto refresh time task", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
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
end)
