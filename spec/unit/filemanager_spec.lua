describe("FileManager module", function()
    local FileManager, lfs, docsettings, UIManager, Screen, util
    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        FileManager = require("apps/filemanager/filemanager")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        docsettings = require("docsettings")
        lfs = require("libs/libkoreader-lfs")
        util = require("ffi/util")
    end)
    it("should show file manager", function()
        UIManager:quit()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "../../test",
        }
        UIManager:show(filemanager)
        UIManager:scheduleIn(1, function() filemanager:onClose() end)
        UIManager:run()
    end)
    it("should show error on non-existent file", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "../../test",
        }
        local old_show = UIManager.show
        local tmp_fn = "/abc/123/test/foo.bar.baz.tmp.epub.pdf"
        UIManager.show = function(self, w)
            assert.Equals(w.text, "File not found:\n"..tmp_fn)
        end
        assert.is_nil(lfs.attributes(tmp_fn))
        filemanager:deleteFile(tmp_fn)
        UIManager.show = old_show
        filemanager:onClose()
    end)
    it("should not delete settings for non-document file", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "../../test",
        }

        local tmp_fn = "../../test/2col.test.tmp.foo"
        util.copyFile("../../test/2col.pdf", tmp_fn)

        local tmp_sidecar = docsettings:getSidecarDir(util.realpath(tmp_fn))
        lfs.mkdir(tmp_sidecar)
        local tmp_history = docsettings:getHistoryPath(tmp_fn)
        local tmpfp = io.open(tmp_history, "w")
        tmpfp:write("{}")
        tmpfp:close()
        local old_show = UIManager.show

        -- make sure file exists
        assert.is_not_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_history))

        UIManager.show = function(self, w)
            assert.Equals(w.text, "Deleted file:\n"..tmp_fn)
        end
        filemanager:deleteFile(tmp_fn)
        UIManager.show = old_show
        filemanager:onClose()

        -- make sure history file exists
        assert.is_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_history))
        os.remove(tmp_sidecar)
        os.remove(tmp_history)
    end)
    it("should delete document with its settings", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "../../test",
        }

        local tmp_fn = "../../test/2col.test.tmp.pdf"
        util.copyFile("../../test/2col.pdf", tmp_fn)

        local tmp_sidecar = docsettings:getSidecarDir(util.realpath(tmp_fn))
        lfs.mkdir(tmp_sidecar)
        local tmp_history = docsettings:getHistoryPath(tmp_fn)
        local tmpfp = io.open(tmp_history, "w")
        tmpfp:write("{}")
        tmpfp:close()
        local old_show = UIManager.show

        -- make sure file exists
        assert.is_not_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_history))

        UIManager.show = function(self, w)
            assert.Equals(w.text, "Deleted file:\n"..tmp_fn)
        end
        filemanager:deleteFile(tmp_fn)
        UIManager.show = old_show
        filemanager:onClose()

        assert.is_nil(lfs.attributes(tmp_fn))
        assert.is_nil(lfs.attributes(tmp_sidecar))
        assert.is_nil(lfs.attributes(tmp_history))
    end)
end)
