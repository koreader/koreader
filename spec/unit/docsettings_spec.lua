describe("docsettings module", function()
    local DataStorage, docsettings, docsettings_dir, ffiutil, lfs

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        docsettings = require("docsettings")
        ffiutil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")

        docsettings_dir = DataStorage:getDocSettingsDir()
    end)

    it("should generate sidecar folder path in book folder (by default)", function()
        G_reader_settings:delSetting("document_metadata_folder")
        assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar folder path in book folder", function()
        G_reader_settings:saveSetting("document_metadata_folder", "doc")
        assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar folder path in docsettings folder", function()
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        assert.Equals(docsettings_dir.."/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals(docsettings_dir.."baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar metadata file (book folder)", function()
        G_reader_settings:saveSetting("document_metadata_folder", "doc")
        assert.Equals("../../foo.sdr/metadata.pdf.lua",
                      docsettings:getSidecarFile("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr/metadata.pdf.lua",
                      docsettings:getSidecarFile("/foo/bar.pdf"))
        assert.Equals("baz.sdr/metadata.epub.lua",
                      docsettings:getSidecarFile("baz.epub"))
    end)

    it("should generate sidecar metadata file (docsettings folder)", function()
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        assert.Equals(docsettings_dir.."/foo/bar.sdr/metadata.pdf.lua",
                      docsettings:getSidecarFile("/foo/bar.pdf"))
        assert.Equals(docsettings_dir.."baz.sdr/metadata.epub.lua",
                      docsettings:getSidecarFile("baz.epub"))
    end)

    it("should read legacy history file", function()
        G_reader_settings:delSetting("document_metadata_folder")
        local file = "/books/file.pdf"
        local d = docsettings:open(file)
        d:saveSetting("a", "b")
        d:saveSetting("c", "d")
        d:close()
        -- Now the sidecar file should be written.

        local legacy_files = {
--            docsettings:getHistoryPath(file),
            d.doc_sidecar_dir .. "/file.pdf.lua",
            "/books/file.pdf.kpdfview.lua",
        }

--        for _, f in ipairs(legacy_files) do
--            assert.False(os.rename(d.doc_sidecar_file, f) == nil)
            d = docsettings:open(file)
--            assert.True(os.remove(d.doc_sidecar_file) == nil)
            -- Legacy history files should not be removed before flush has been
            -- called.
--            assert.Equals(lfs.attributes(f, "mode"), "file")
--            assert.Equals(d:readSetting("a"), "b")
--            assert.Equals(d:readSetting("c"), "d")
            assert.Equals(d:readSetting("e"), nil)
            d:close()
            -- legacy history files should be removed as sidecar_file is
            -- preferred.
--            assert.True(os.remove(f) == nil)
--        end

--        assert.False(os.remove(d.doc_sidecar_file) == nil)
--        d:purge()
    end)

end)
