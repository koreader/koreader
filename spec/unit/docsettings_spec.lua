describe("docsettings module", function()
    local docsettings

    setup(function()
        require("commonrequire")
        docsettings = require("docsettings")
    end)
    it("should generate sidecar directory path", function()
        assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)
    it("should read legacy history file", function()
        local file = "file.pdf"
        local d = docsettings:open(file)
        d:saveSetting("a", "b")
        d:close()
        -- Now the sidecar file should be written.

        assert.False(os.rename(d.sidecar_file, d.history_file) == nil)
        d = docsettings:open(file)
        assert.Equals(d:readSetting("a"), "b")
        d:close()
        -- history_file should be removed as sidecar_file is preferred.
        assert.False(os.remove(d.sidecar_file) == nil)
        assert.True(os.remove(d.history_file) == nil)

        assert.False(os.rename(d.sidecar_file, d.sidecar .. "/file.lua") == nil)
        d = docsettings:open(file)
        assert.Equals(d:readSetting("a"), "b")
        d:close()

        assert.False(os.rename(d.sidecar_file, "file.kpdfview.lua") == nil)
        d = docsettings:open(file)
        assert.Equals(d:readSetting("a"), "b")
        d:close()

        d:purge()
    end)
end)
