describe("Readerfooter module", function()
    local DocumentRegistry, ReaderUI, ReaderFooter, DocSettings, UIManager
    local purgeDir, Screen
    local tapFooterMenu

    local function is_am()
        -- Technically only an issue for 1 digit results from %-H, e.g., anything below 10:00 AM
        return tonumber(os.date("%H")) < 10
    end

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local Device = require("device")
        -- Override powerd for running tests on devices with batteries.
        Device.powerd.isChargingHW = function() return false end
        Device.powerd.getCapacityHW = function() return 0 end
        require("document/canvascontext"):init(Device)
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        ReaderFooter = require("apps/reader/modules/readerfooter")
        UIManager = require("ui/uimanager")
        purgeDir = require("ffi/util").purgeDir
        Screen = require("device").screen

        function tapFooterMenu(menu_items, menu_title)
            local status_bar = menu_items.status_bar

            if status_bar then
                for _, subitem in ipairs(status_bar.sub_item_table) do
                    if subitem.text_func and subitem.text_func() == menu_title then
                        subitem.callback()
                        return
                    end
                    if subitem.text == menu_title then
                        subitem.callback()
                        return
                    end
                    if subitem.sub_item_table then
                        local status_bar_sub_item = subitem.sub_item_table
                        for _, sub_subitem in ipairs(status_bar_sub_item) do
                            if sub_subitem.text_func and sub_subitem.text_func() == menu_title then
                                sub_subitem.callback()
                                return
                            end
                            if sub_subitem.text == menu_title then
                                sub_subitem.callback()
                                return
                            end
                        end
                    end
                end
                error('Menu item not found: "' .. menu_title .. '"!')
            end
            error('Menu item not found: "Status bar"!')
        end
    end)

    teardown(function()
        -- Clean up global settings we played with
        G_reader_settings:delSetting("reader_footer_mode")
        G_reader_settings:delSetting("footer")
        G_reader_settings:flush()
    end)

    before_each(function()
        local settings = {}
        for k, v in pairs(ReaderFooter.default_settings) do
            settings[k] = v
        end
        -- Enforce Battery, the real default is dynamic (Device:hasBattery())
        settings.battery = true
        G_reader_settings:saveSetting("footer", settings)

        -- NOTE: Forcefully disable the statistics plugin, as lj-sqlite3 is horribly broken under Busted,
        --       causing it to erratically fail to load, affecting the results of this test...
        G_reader_settings:saveSetting("plugins_disabled", {
            statistics = true,
        })
        UIManager:run()
    end)

    it("should setup footer as visible in all_at_once mode", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(true, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should setup footer as visible not in all_at_once", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        -- default settings

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(true, readerui.view.footer_visible)
        assert.is.same(1, readerui.view.footer.mode, 1)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should setup footer as invisible in full screen mode", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        -- default settings

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        local cfg = DocSettings:open(sample_pdf)
        cfg:saveSetting("kopt_full_screen", 0)
        cfg:flush()

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(false, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should setup footer as visible in mini progress bar mode", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        -- default settings

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        local cfg = DocSettings:open(sample_pdf)
        cfg:delSetting("kopt_full_screen")
        cfg:flush()

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        assert.is.same(true, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should setup footer as invisible", function()
        G_reader_settings:saveSetting("reader_footer_mode", 1)
        -- default settings

        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        local cfg = DocSettings:open(sample_epub)
        cfg:saveSetting("copt_status_line", 1)
        cfg:flush()

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        assert.is.same(true, readerui.view.footer_visible)
        G_reader_settings:delSetting("reader_footer_mode")
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should setup footer for epub without error", function()
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        footer:onPageUpdate(1)
        footer:onUpdateFooter()
        local timeinfo = footer.textGeneratorMap.time(footer)
        local page_count = readerui.document:getPageCount()
        -- c.f., NOTE above, Statistics are disabled, hence the N/A results
        assert.are.same('1 / '..page_count..' | '..timeinfo..' | ⇒ 0 | 0% | ⤠ 0% | ⏳ N/A | ⤻ N/A',
                        footer.footer_text.text)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should setup footer for pdf without error", function()
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        readerui.view.footer:onUpdateFooter()
        local timeinfo = readerui.view.footer.textGeneratorMap.time(footer)
        assert.are.same('1 / 2 | '..timeinfo..' | ⇒ 1 | 0% | ⤠ 50% | ⏳ N/A | ⤻ N/A',
                        readerui.view.footer.footer_text.text)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should switch between different modes", function()
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local fake_menu = {setting = {}}
        local footer = readerui.view.footer
        footer:addToMainMenu(fake_menu)
        footer:resetLayout()
        footer:onUpdateFooter()
        local timeinfo = footer.textGeneratorMap.time(footer)
        assert.are.same('1 / 2 | '..timeinfo..' | ⇒ 1 | 0% | ⤠ 50% | ⏳ N/A | ⤻ N/A',
                        footer.footer_text.text)

        -- disable show all at once, page progress should be on the first
        tapFooterMenu(fake_menu, "Show all at once")
        assert.are.same('1 / 2', footer.footer_text.text)

        -- disable page progress, time should follow
        tapFooterMenu(fake_menu, "Current page".." (/)")
        assert.are.same(timeinfo, footer.footer_text.text)

        -- disable time, page left should follow
        tapFooterMenu(fake_menu, "Current time".." (⌚)")
        assert.are.same('⇒ 1', footer.footer_text.text)

        -- disable page left, battery should follow
        tapFooterMenu(fake_menu, "Pages left in chapter".." (⇒)")
        assert.are.same('0%', footer.footer_text.text)

        -- disable battery, percentage should follow
        tapFooterMenu(fake_menu, "Battery status".." ()")
        assert.are.same('⤠ 50%', footer.footer_text.text)

        -- disable percentage, book time to read should follow
        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        assert.are.same('⏳ N/A', footer.footer_text.text)

        -- disable book time to read, chapter time to read should follow
        tapFooterMenu(fake_menu, "Book time to read".." (⏳)")
        assert.are.same('⤻ N/A', footer.footer_text.text)

        -- disable chapter time to read, text should be empty
        tapFooterMenu(fake_menu, "Chapter time to read".." (⤻)")
        assert.are.same('', footer.footer_text.text)

        -- reenable chapter time to read, text should be chapter time to read
        tapFooterMenu(fake_menu, "Chapter time to read".." (⤻)")
        assert.are.same('⤻ N/A', footer.footer_text.text)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should rotate through different modes", function()
        -- default settings (we'll poke at footer.settings directly post-instantiation)

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        footer.mode = 0
        footer:onTapFooter()
        assert.is.same(1, footer.mode)
        footer:onTapFooter()
        -- 2 is pages_left_book, an alternate variant of page_progress, disabled by default (#7047)
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
        assert.is.same(8, footer.mode)
        footer:onTapFooter()
        assert.is.same(0, footer.mode)

        footer.settings.all_at_once = true
        footer:updateFooterTextGenerator()
        footer.mode = 5
        footer:onTapFooter()
        assert.is.same(0, footer.mode)
        footer:onTapFooter()
        assert.is.same(1, footer.mode)
        footer:onTapFooter()
        assert.is.same(0, footer.mode)
        -- Make it visible again to make the following tests behave...
        footer:onTapFooter()
        assert.is.same(1, footer.mode)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should pick up screen resize in resetLayout", function()
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local horizontal_margin = Screen:scaleBySize(10)*2
        footer:onUpdateFooter()
        -- Account for trimming of the leading 0 in the AM
        local expected = is_am() and 362 or 370
        assert.is.same(expected, footer.text_width)
        assert.is.same(600, footer.progress_bar.width
                            + footer.text_width
                            + horizontal_margin)
        expected = is_am() and 218 or 210
        assert.is.same(expected, footer.progress_bar.width)

        local old_screen_getwidth = Screen.getWidth
        Screen.getWidth = function() return 900 end
        footer:resetLayout()
        expected = is_am() and 362 or 370
        assert.is.same(expected, footer.text_width)
        assert.is.same(900, footer.progress_bar.width
                            + footer.text_width
                            + horizontal_margin)
        expected = is_am() and 518 or 510
        assert.is.same(expected, footer.progress_bar.width)
        Screen.getWidth = old_screen_getwidth
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should update width on PosUpdate event", function()
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        footer:onPageUpdate(1)
        local expected = is_am() and 210 or 202
        assert.are.same(expected, footer.progress_bar.width)
        expected = is_am() and 370 or 378
        assert.are.same(expected, footer.text_width)

        footer:onPageUpdate(100)
        expected = is_am() and 186 or 178
        assert.are.same(expected, footer.progress_bar.width)
        expected = is_am() and 394 or 402
        assert.are.same(expected, footer.text_width)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should support chapter markers", function()
        -- default settings (we'll poke at footer.settings directly post-instantiation)

        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
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
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should schedule/unschedule auto refresh time task", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)

        local settings = G_reader_settings:readSetting("footer")
        settings.auto_refresh_time = true
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(1, found)

        footer:onCloseDocument()
        found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(0, found)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should not schedule auto refresh time task if footer is disabled", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)

        local settings = G_reader_settings:readSetting("footer")
        settings.disabled = true
        settings.auto_refresh_time = true
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(0, found)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should toggle auto refresh time task by toggling the menu", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)

        local settings = G_reader_settings:readSetting("footer")
        settings.disabled = false
        settings.auto_refresh_time = true
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(1, found)

        -- disable auto refresh time
        tapFooterMenu(fake_menu, "Auto refresh")
        found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(0, found)

        -- enable auto refresh time again
        tapFooterMenu(fake_menu, "Auto refresh")
        found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(1, found)
        readerui:closeDocument()
        readerui:onClose()
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
        -- default settings

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
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
        assert.is.same(3, footer.mode)

        DTAP_ZONE_MINIBAR = saved_tap_zone_minibar --luacheck: ignore
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should remove and add modes to footer text in all_at_once mode", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)

        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        settings.battery = false
        settings.time = false
        settings.percentage = false
        settings.book_time_to_read = false
        settings.chapter_time_to_read = false
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        assert.are.same('1 / 2 | ⇒ 1', footer.footer_text.text)

        -- remove mode from footer text
        tapFooterMenu(fake_menu, "Pages left in chapter".." (⇒)")
        assert.are.same('1 / 2', footer.footer_text.text)

        -- add mode to footer text
        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        assert.are.same('1 / 2 | ⤠ 50%', footer.footer_text.text)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should initialize text mode in all_at_once mode", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)

        G_reader_settings:saveSetting("reader_footer_mode", 0)
        local settings = G_reader_settings:readSetting("footer")
        settings.all_at_once = true
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf)
        }
        local footer = readerui.view.footer

        assert.is.truthy(footer.settings.all_at_once)
        assert.is.truthy(0, footer.mode)
        assert.is.falsy(readerui.view.footer_visible)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should support disabling all the modes", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        assert.are.same({}, UIManager._task_queue)

        local settings = G_reader_settings:readSetting("footer")
        settings.battery = false
        settings.time = false
        settings.page_progress = false
        settings.pages_left = false
        settings.percentage = false
        settings.book_time_to_read = false
        settings.chapter_time_to_read = false
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer
        local fake_menu = {setting = {}}
        footer:addToMainMenu(fake_menu)

        assert.is.same(true, footer.has_no_mode)
        assert.is.same(0, footer.text_width)

        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        assert.are.same('⤠ 0%', footer.footer_text.text)
        assert.is.same(false, footer.has_no_mode)
        assert.is.same(footer.footer_text:getSize().w + footer.horizontal_margin,
                       footer.text_width)
        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        assert.is.same(true, footer.has_no_mode)

        -- test in all at once mode
        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        tapFooterMenu(fake_menu, "Show all at once")
        assert.is.same(false, footer.has_no_mode)
        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        assert.is.same(true, footer.has_no_mode)
        tapFooterMenu(fake_menu, "Progress percentage".." (⤠)")
        assert.is.same(false, footer.has_no_mode)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should return correct footer height in time mode", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        G_reader_settings:saveSetting("reader_footer_mode", 2)
        -- default settings

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.falsy(footer.has_no_mode)
        assert.truthy(readerui.view.footer_visible)
        assert.is.same(15, footer:getHeight())
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should return correct footer height when all modes are disabled", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local settings = G_reader_settings:readSetting("footer")
        settings.battery = false
        settings.time = false
        settings.page_progress = false
        settings.pages_left = false
        settings.percentage = false
        settings.book_time_to_read = false
        settings.chapter_time_to_read = false
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.truthy(footer.has_no_mode)
        assert.truthy(readerui.view.footer_visible)
        assert.is.same(15, footer:getHeight())
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should disable footer when all modes + progressbar are disabled", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        G_reader_settings:saveSetting("reader_footer_mode", 1)
        local settings = G_reader_settings:readSetting("footer")
        settings.battery = false
        settings.time = false
        settings.page_progress = false
        settings.pages_left = false
        settings.percentage = false
        settings.book_time_to_read = false
        settings.chapter_time_to_read = false
        settings.disable_progress_bar = true
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.truthy(footer.has_no_mode)
        assert.falsy(readerui.view.footer_visible)
        readerui:closeDocument()
        readerui:onClose()
    end)

    it("should disable footer if settings.disabled is true", function()
        local sample_epub = "spec/front/unit/data/juliet.epub"
        purgeDir(DocSettings:getSidecarDir(sample_epub))
        os.remove(DocSettings:getHistoryPath(sample_epub))
        UIManager:quit()

        local settings = G_reader_settings:readSetting("footer")
        settings.disabled = true
        G_reader_settings:saveSetting("footer", settings)

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        local footer = readerui.view.footer

        assert.falsy(readerui.view.footer_visible)
        assert.truthy(footer.mode == 0)

        local found = 0
        for _,task in ipairs(UIManager._task_queue) do
            if task.action == footer.autoRefreshFooter then
                found = found + 1
            end
        end
        assert.is.same(0, found)

        readerui:closeDocument()
        readerui:onClose()
    end)

    --[[ This toggling behaviour has been removed:
    it("should toggle between full and min progress bar for cre documents", function()
        local sample_txt = "spec/front/unit/data/sample.txt"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
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
        readerui:closeDocument()
        readerui:onClose()
    end)
    ]]--
end)
