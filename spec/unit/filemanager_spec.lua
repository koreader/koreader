describe("FileManager module", function()
    local DataStorage, FileManager, lfs, docsettings, UIManager, Screen, makePath, util
    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DataStorage = require("datastorage")
        FileManager = require("apps/filemanager/filemanager")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        docsettings = require("docsettings")
        lfs = require("libs/libkoreader-lfs")
        makePath = require("util").makePath
        util = require("ffi/util")
    end)
    local function findButtonText(buttons, text)
        for _, row in ipairs(buttons) do
            for _, btn in ipairs(row) do
                if btn.text == text then
                    return btn
                end
            end
        end
        return nil
    end
    it("should show file manager", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/front/unit/data",
        }
        UIManager:show(filemanager)
        fastforward_ui_events()
        filemanager:onClose()
        UIManager:quit()
    end)
    it("should show error on non-existent file", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/front/unit/data",
        }
        local old_show = UIManager.show
        local tmp_fn = "/abc/123/test/foo.bar.baz.tmp.epub.pdf"
        local show_called = false
        UIManager.show = function(self, w)
            assert.Equals(w.text, "File not found:\n"..tmp_fn)
            show_called = true
        end
        assert.is_nil(lfs.attributes(tmp_fn))
        filemanager:showDeleteFileDialog(tmp_fn)
        assert.is_truthy(show_called)
        UIManager.show = old_show
        filemanager:onClose()
    end)
    it("should not delete not empty sidecar folder", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/front/unit/data",
        }

        local tmp_fn = DataStorage:getDataDir() .. "/2col.test.tmp.foo"
        util.copyFile("spec/front/unit/data/2col.pdf", tmp_fn)

        local tmp_sidecar = docsettings:getSidecarDir(tmp_fn)
        makePath(tmp_sidecar)
        local tmp_sidecar_file = docsettings.getSidecarFilename(tmp_fn)
        local tmp_sidecar_file_foo = tmp_sidecar_file .. ".foo" -- non-docsettings file
        local tmpsf = io.open(tmp_sidecar_file, "w")
        tmpsf:write("{}")
        tmpsf:close()
        util.copyFile(tmp_sidecar_file, tmp_sidecar_file_foo)

        -- make sure file exists
        assert.is_not_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_sidecar_file))
        assert.is_not_nil(lfs.attributes(tmp_sidecar_file_foo))

        filemanager:deleteFile(tmp_fn, true)
        filemanager:onClose()

        -- make sure sdr folder exists
        assert.is_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        os.remove(tmp_sidecar_file_foo)
        os.remove(tmp_sidecar)
    end)
    it("should delete document with its settings", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/front/unit/data",
        }

        local tmp_fn = DataStorage:getDataDir() .. "/2col.test.tmp.pdf"
        util.copyFile("spec/front/unit/data/2col.pdf", tmp_fn)

        local tmp_sidecar = docsettings:getSidecarDir(tmp_fn)
        makePath(tmp_sidecar)
        local tmp_sidecar_file = docsettings.getSidecarFilename(tmp_fn)
        local tmpsf = io.open(tmp_sidecar_file, "w")
        tmpsf:write("{}")
        tmpsf:close()
        lfs.mkdir(require("datastorage"):getHistoryDir())
        local tmp_history = docsettings:getHistoryPath(tmp_fn)
        local tmpfp = io.open(tmp_history, "w")
        tmpfp:write("{}")
        tmpfp:close()

        -- make sure file exists
        assert.is_not_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_history))

        filemanager:deleteFile(tmp_fn, true)
        filemanager:onClose()

        assert.is_nil(lfs.attributes(tmp_fn))
        assert.is_nil(lfs.attributes(tmp_sidecar))
        assert.is_nil(lfs.attributes(tmp_history))
    end)
    it("should only show \"New text file\" when the texteditor plugin is enabled", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/front/unit/data",
        }
        UIManager:show(filemanager)
        fastforward_ui_events()

        filemanager.texteditor = nil
        local _, buttons_without = filemanager:getPlusDialogButtons()
        assert.is_nil(findButtonText(buttons_without, "New text file"))

        filemanager.texteditor = {} -- stub: presence is all getPlusDialogButtons checks
        local _, buttons_with = filemanager:getPlusDialogButtons()
        assert.is_not_nil(findButtonText(buttons_with, "New text file"))

        filemanager:onClose()
        UIManager:quit()
    end)
end)
