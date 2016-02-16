require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DocSettings = require("docsettings")
local DEBUG = require("dbg")
local purgeDir = require("ffi/util").purgeDir

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
        readerui.view.footer:updateFooterPage()
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
        readerui.view.footer:updateFooterPage()
        timeinfo = readerui.view.footer:getTimeInfo()
        assert.are.same('B:0% | '..timeinfo..' | 1 / 2 | => 1 | R:50% | TB: na | TC: na',
                        readerui.view.footer.progress_text.text)
    end)
end)
