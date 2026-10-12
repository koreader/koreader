describe("ReaderAnnotation export and import", function()
    local ReaderAnnotation, LuaSettings, Notification, lfs, filepath, original_settings, annotation

    setup(function()
        require("commonrequire")
        ReaderAnnotation = require("apps/reader/modules/readerannotation")
        LuaSettings = require("luasettings")
        Notification = require("ui/widget/notification")
        lfs = require("libs/libkoreader-lfs")
        filepath = require("datastorage"):getDataDir() .. "/readerannotation.annotations.lua"
    end)

    before_each(function()
        original_settings = G_reader_settings
        G_reader_settings = LuaSettings:wrap{ device_id = "source" }
        stub(Notification, "notify")
        os.remove(filepath)
        os.remove(filepath .. ".old")
        annotation = ReaderAnnotation:extend{
            annotations = {},
            ui = { paging = true },
            getExportAnnotationsFilepath = function() return filepath end,
        }
    end)

    after_each(function()
        G_reader_settings = original_settings
        Notification.notify:revert()
        os.remove(filepath)
        os.remove(filepath .. ".old")
    end)

    local function export_empty()
        annotation:onExportAnnotations()
        G_reader_settings:saveSetting("device_id", "target")
    end

    it("should replace a previous export after deleting the last annotation", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", false)
        annotation.annotations = {{ page = 1, datetime = "2020-01-01 00:00:00" }}
        annotation:onExportAnnotations()
        assert.are.equal(1, #dofile(filepath).annotations)
        annotation.annotations = {}
        annotation:onExportAnnotations()
        local exported = dofile(filepath)
        assert.are.same({}, exported.annotations)
        assert.are.equal("source", exported.device_id)
        assert.is_string(exported.datetime)
        assert.is_true(exported.paging)
    end)

    it("should not automatically export an empty snapshot on closing when enabled", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", true)
        annotation:onExportAnnotations(true)
        assert.is_nil(lfs.attributes(filepath, "mode"))
    end)

    it("should not export on closing when disabled", function()
        annotation.annotations = {{ page = 1, datetime = "2020-01-01 00:00:00" }}
        annotation:onExportAnnotations(true)
        assert.is_nil(lfs.attributes(filepath, "mode"))
    end)

    it("should preserve the previous export when closing an empty book", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", true)
        annotation.annotations = {{ page = 1, datetime = "2020-01-01 00:00:00" }}
        annotation:onExportAnnotations(true)
        annotation.annotations = {}
        annotation:onExportAnnotations(true)
        assert.are.equal(1, #dofile(filepath).annotations)
    end)

    it("should remove older annotations but preserve newer ones on empty import", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", true)
        export_empty()
        local newer = { page = 2, datetime = "2099-01-01 00:00:00" }
        local updated = { page = 3, datetime = "2020-01-01 00:00:00", datetime_updated = "2099-01-01 00:00:00" }
        annotation.annotations = {
            { page = 1, datetime = "2020-01-01 00:00:00" }, newer, updated,
        }
        assert.is_true(annotation:importAnnotations())
        assert.are.same({ newer, updated }, annotation.annotations)
        assert.is_nil(lfs.attributes(filepath, "mode"))
    end)

    it("should keep all local annotations when importing an empty snapshot in keep-all mode", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", true)
        export_empty()
        G_reader_settings:saveSetting("annotations_export_keep_all_on_import", true)
        annotation.annotations = {{ page = 1, datetime = "2020-01-01 00:00:00" }}
        assert.is_true(annotation:importAnnotations())
        assert.are.equal(1, #annotation.annotations)
    end)

    it("should leave annotations unchanged when no import file exists", function()
        annotation.annotations = {{ page = 1, datetime = "2020-01-01 00:00:00" }}
        assert.is_nil(annotation:importAnnotations())
        assert.are.equal(1, #annotation.annotations)
    end)

    it("should ignore an empty snapshot from the same device", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", true)
        annotation:onExportAnnotations()
        annotation.annotations = {{ page = 1, datetime = "2020-01-01 00:00:00" }}
        assert.is_nil(annotation:importAnnotations())
        assert.are.equal(1, #annotation.annotations)
        assert.are.equal("file", lfs.attributes(filepath, "mode"))
    end)

    it("should import an empty rolling snapshot", function()
        G_reader_settings:saveSetting("annotations_export_on_closing", true)
        annotation.ui = { rolling = true }
        export_empty()
        annotation.annotations = {{ page = "/body/p[1]", datetime = "2020-01-01 00:00:00" }}
        assert.is_true(annotation:importAnnotations())
        assert.are.same({}, annotation.annotations)
    end)

    it("should allow manual export from an empty bookmark menu", function()
        local ReaderBookmark = require("apps/reader/modules/readerbookmark")
        local UIManager = require("ui/uimanager")
        local ButtonDialog = require("ui/widget/buttondialog")
        local Menu = require("ui/widget/menu")
        G_reader_settings:saveSetting("bookmarks_items_per_page", Menu.items_per_page_default)
        local shown
        stub(ButtonDialog, "new", function(_, options) return options end)
        stub(Menu, "new", function(_, options) return options end)
        stub(UIManager, "show", function(_, widget) shown = widget end)
        stub(UIManager, "close")
        local ok, err = pcall(function()
            local bookmark = ReaderBookmark:extend{
                document = {},
                ui = { annotation = annotation },
                getCurrentPageNumber = function() return 1 end,
                getBookmarkPageString = function() return "1" end,
                updateBookmarkList = function() end,
            }
            annotation.getInsertionIndex = function() return 1 end
            bookmark:onShowBookmark()
            bookmark.bookmark_menu[1]:onLeftButtonTap()
            local export_button
            for _, row in ipairs(shown.buttons) do
                for _, button in ipairs(row) do
                    if button.text == require("gettext")("Export annotations") then
                        export_button = button
                    end
                end
            end
            assert.is_not_nil(export_button)
            assert.are_not.equal(false, export_button.enabled)
            export_button.callback()
            assert.are.same({}, dofile(filepath).annotations)
        end)
        ButtonDialog.new:revert()
        Menu.new:revert()
        UIManager.show:revert()
        UIManager.close:revert()
        assert.is_true(ok, err)
    end)
end)
