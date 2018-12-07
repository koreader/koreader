describe("Readerfooter module", function()
    local DocumentRegistry, ReaderUI, DocSettings, UIManager
    local purgeDir, Screen
    local tapFooterMenu

    setup(function()
        require("commonrequire")
        package.unloadAll()
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        purgeDir = require("ffi/util").purgeDir
        Screen = require("device").screen

        function tapFooterMenu(menu_items, menu_title)
            local status_bar = menu_items.status_bar

            if status_bar then
                for _, subitem in ipairs(status_bar.sub_item_table) do
                    if subitem.text == menu_title then
                        subitem.callback()
                        return
                    end
                end
                error('Menu item not found: "' .. menu_title .. '"!')
            end
            error('Menu item not found: "Status bar"!')
        end
    end)

    before_each(function()
        G_reader_settings:saveSetting("footer", {
            disabled = false,
            all_at_once = true,
            toc_markers = true,
            battery = true,
            time = true,
            page_progress = true,
            pages_left = true,
            percentage = true,
            book_time_to_read = true,
            chapter_time_to_read = true,
        })
        UIManager:run()
    end)

    it("should setup footer as visible in all_at_once mode", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(true, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
    end)

    it("should setup footer as visible not in all_at_once", function()
        G_reader_settings:saveSetting("footer", {
            disabled = false,
            all_at_once = false,
            toc_markers = true,
            battery = true,
            time = true,
            page_progress = true,
            pages_left = true,
            percentage = true,
            book_time_to_read = true,
            chapter_time_to_read = true,
        })
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(true, readerui.view.footer_visible)
        assert.is.same(1, readerui.view.footer.mode, 1)
        G_reader_settings:delSetting("reader_footer_mode")
    end)

    it("should setup footer as invisible in full screen mode", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        local cfg = DocSettings:open(sample_pdf)
        cfg:saveSetting("kopt_full_screen", 0)
        cfg:flush()

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(false, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
    end)

    it("should setup footer as visible in mini progress bar mode", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        local cfg = DocSettings:open(sample_pdf)
        cfg:saveSetting("kopt_full_screen", 0)
        cfg:flush()

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(false, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
    end)

    it("should setup footer as invisible", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        local cfg = DocSettings:open(sample_epub)
        cfg:saveSetting("copt_status_line", 1)
        cfg:flush()

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        assert.is.same(true, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
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
        local timeinfo = footer.textGeneratorMap.time()
        local page_count = readerui.document:getPageCount()
        -- stats has not been initialized here, so we get na TB and TC
        assert.are.same('1 / '..page_count..' | '..timeinfo..' | => 1 | B:0% | R:0% | TB: na | TC: na',
                        footer.footer_text.text)
    end)

    it("should setup footer for pdf without error", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        readerui.view.footer:updateFooter()
        local timeinfo = readerui.view.footer.textGeneratorMap.time()
        assert.are.same('1 / 2 | '..timeinfo..' | => 1 | B:0% | R:50% | TB: na | TC: na',
                        readerui.view.footer.footer_text.text)
    end)

    it("should switch between different modes", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local fake_menu = {setting = {}}
        local footer = readerui.view.footer
        footer:addToMainMenu(fake_menu)
        footer:resetLayout()
        footer:updateFooter()
        local timeinfo = footer.textGeneratorMap.time()
        assert.are.same('1 / 2 | '..timeinfo..' | => 1 | B:0% | R:50% | TB: na | TC: na',
                        footer.footer_text.text)

        -- disable show all at once, page progress should be on the first
        tapFooterMenu(fake_menu, "Show all at once")
        assert.are.same('1 / 2', footer.footer_text.text)

        -- disable page progress, time should follow
        tapFooterMenu(fake_menu, "Current page")
        assert.are.same(timeinfo, footer.footer_text.text)

        -- disable time, page left should follow
        tapFooterMenu(fake_menu, "Current time")
        assert.are.same('=> 1', footer.footer_text.text)

        -- disable page left, battery should follow
        tapFooterMenu(fake_menu, "Pages left in chapter")
        assert.are.same('B:0%', footer.footer_text.text)

        -- disable battery, percentage should follow
        tapFooterMenu(fake_menu, "Battery status")
        assert.are.same('R:50%', footer.footer_text.text)

        -- disable percentage, book time to read should follow
        tapFooterMenu(fake_menu, "Progress percentage")
        assert.are.same('TB: na', footer.footer_text.text)

        -- disable book time to read, chapter time to read should follow
        tapFooterMenu(fake_menu, "Book time to read")
        assert.are.same('TC: na', footer.footer_text.text)

        -- disable chapter time to read, text should be empty
        tapFooterMenu(fake_menu, "Chapter time to read")
        assert.are.same('', footer.footer_text.text)

        -- reenable chapter time to read, text should be chapter time to read
        tapFooterMenu(fake_menu, "Chapter time to read")
        assert.are.same('TC: na', footer.footer_text.text)
    end)

    it("should rotate through different modes", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        footer.settings.all_at_once = false
        footer.mode = 0
        footer:onTapFooter()
        assert.is.same(1, footer.mode)
        footer:onTapFooter()
        assert.is.same(2, footer.mode)
        footer:onTapFooter()
        assert.is.same(3, footer.mode)
        footer:onTapFooter()
        assert.is.same(4, footer.mode)
        footer:onTapFooter()
        assert.is.same(5, footer.mode)
        footer:onTapFooter()
        assert.is.same(6, footer.mode)
        footer:onTapFooter()
        assert.is.same(7, footer.mode)
        footer:onTapFooter()
        assert.is.same(0, footer.mode)

        footer.settings.all_at_once = true
        footer.mode = 5
        footer:onTapFooter()
        assert.is.same(0, footer.mode)
        footer:onTapFooter()
        assert.is.same(1, footer.mode)
        footer:onTapFooter()
        assert.is.same(0, footer.mode)
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
        assert.are.same(183, footer.progress_bar.width)
        assert.are.same(397, footer.text_width)
    end)

    it("should support chapter markers", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        G_reader_settings:saveSetting("footer", {
            toc_markers = true,
        })

        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        footer:onPageUpdate(1)
        local page_count = readerui.document:getPageCount()
        assert.are.same(28, #footer.progress_bar.ticks)
        assert.are.same(page_count, footer.progress_bar.last)

        -- test toggle TOC markers
        footer.settings.toc_markers = false
        footer:setTocMarkers()
        assert.are.same(nil, footer.progress_bar.ticks)
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

    it("should toggle auto refresh time task by toggling the menu", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("footer", {
            disabled = false,
            page_progress = true,
            auto_refresh_time = true,
        })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshTime then
                found = found + 1
            end
        end
        assert.is.same(1, found)

        -- disable auto refresh time
        tapFooterMenu(fake_menu, "Auto refresh time")
        found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshTime then
                found = found + 1
            end
        end
        assert.is.same(0, found)

        -- enable auto refresh time again
        tapFooterMenu(fake_menu, "Auto refresh time")
        found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshTime then
                found = found + 1
            end
        end
        assert.is.same(1, found)
    end)

    it("should support toggle footer through menu if tap zone is disabled", function()
        local saved_tap_zone_minibar = DTAP_ZONE_MINIBAR
        DTAP_ZONE_MINIBAR.w = 0 --luacheck: ignore
        DTAP_ZONE_MINIBAR.h = 0 --luacheck: ignore

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        G_reader_settings:saveSetting("footer", {
            disabled = false,
            page_progress = true,
            time = true,
        })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        local has_toggle_menu = false

        if fake_menu.status_bar then
            for _, subitem in ipairs(fake_menu.status_bar.sub_item_table) do
                if subitem.text == 'Toggle mode' then
                    has_toggle_menu = true
                    break
                end
            end
        end

        assert.is.truthy(has_toggle_menu)

        assert.is.same(1, footer.mode)
        tapFooterMenu(fake_menu, "Toggle mode")
        assert.is.same(2, footer.mode)

        DTAP_ZONE_MINIBAR = saved_tap_zone_minibar --luacheck: ignore
    end)

    it("should remove and add modes to footer text in all_at_once mode", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("footer", {
            all_at_once = true,
            page_progress = true,
            pages_left = true,
        })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        assert.are.same('1 / 2 | => 1', footer.footer_text.text)

        -- remove mode from footer text
        tapFooterMenu(fake_menu, "Pages left in chapter")
        assert.are.same('1 / 2', footer.footer_text.text)

        -- add mode to footer text
        tapFooterMenu(fake_menu, "Progress percentage")
        assert.are.same('1 / 2 | R:50%', footer.footer_text.text)
    end)

    it("should initialize text mode in all_at_once mode", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("reader_footer_mode", 0)
        G_reader_settings:saveSetting("footer", {
            all_at_once = true,
            page_progress = true,
            pages_left = true,
        })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_pdf)
        }
        local footer = readerui.view.footer

        assert.is.truthy(footer.settings.all_at_once)
        assert.is.truthy(0, footer.mode)
        assert.is.falsy(readerui.view.footer_visible)
    end)

    it("should support disabling all the modes", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)
        G_reader_settings:saveSetting("footer", {})
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        assert.is.same(true, footer.has_no_mode)
        assert.is.same(0, footer.text_width)

        tapFooterMenu(fake_menu, "Progress percentage")
        assert.are.same('R:0%', footer.footer_text.text)
        assert.is.same(false, footer.has_no_mode)
        assert.is.same(footer.footer_text:getSize().w + footer.text_left_margin,
                       footer.text_width)
        tapFooterMenu(fake_menu, "Progress percentage")
        assert.is.same(true, footer.has_no_mode)

        -- test in all at once mode
        tapFooterMenu(fake_menu, "Progress percentage")
        tapFooterMenu(fake_menu, "Show all at once")
        assert.is.same(false, footer.has_no_mode)
        tapFooterMenu(fake_menu, "Progress percentage")
        assert.is.same(true, footer.has_no_mode)
        tapFooterMenu(fake_menu, "Progress percentage")
        assert.is.same(false, footer.has_no_mode)
    end)

    it("should return correct footer height in time mode", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        G_reader_settings:saveSetting("reader_footer_mode", 2)
        G_reader_settings:saveSetting("footer", { time = true })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.falsy(footer.has_no_mode)
        assert.truthy(readerui.view.footer_visible)
        assert.is.same(15, footer:getHeight())
    end)

    it("should return correct footer height when all modes are disabled", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        G_reader_settings:saveSetting("reader_footer_mode", 1)
        G_reader_settings:saveSetting("footer", {})
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.truthy(footer.has_no_mode)
        assert.falsy(readerui.view.footer_visible)
        assert.is.same(15, footer:getHeight())
    end)

    it("should disable footer if settings.disabled is true", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        G_reader_settings:saveSetting("footer", { disabled = true })
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.falsy(readerui.view.footer_visible)
        assert.truthy(footer.onCloseDocument == nil)
        assert.truthy(footer.mode == 0)
    end)

    it("should toggle between full and min progress bar for cre documents", function()
        local sample_txt = "spec/front/unit/data/sample.txt"
        local readerui = ReaderUI:new{
            document = DocumentRegistry:openDocument(sample_txt),
        }
        local footer = readerui.view.footer

        footer:applyFooterMode(0)
        assert.is.same(0, footer.mode)
        assert.falsy(readerui.view.footer_visible)
        readerui.rolling:onSetStatusLine(1)
        assert.is.same(1, footer.mode)
        assert.truthy(readerui.view.footer_visible)

        footer.mode = 1
        readerui.rolling:onSetStatusLine(1)
        assert.is.same(1, footer.mode)
        assert.truthy(readerui.view.footer_visible)

        readerui.rolling:onSetStatusLine(0)
        assert.is.same(0, footer.mode)
        assert.falsy(readerui.view.footer_visible)
    end)
end)
