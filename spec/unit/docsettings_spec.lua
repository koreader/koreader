describe("docsettings module", function()
    local DataStorage, docsettings, docsettings_dir -- , ffiutil, lfs

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        docsettings = require("docsettings")
--        ffiutil = require("ffi/util")
--        lfs = require("libs/libkoreader-lfs")

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

    it("open", function()
        G_reader_settings:delSetting("document_metadata_folder")
        local file = "/books/file.pdf"
        local d = docsettings:open(file)
        assert.Equals(d:readSetting("e"), nil)
    end)

    it("open close", function()
        G_reader_settings:delSetting("document_metadata_folder")
        local file = "/books/file.pdf"
        local d = docsettings:open(file)
        assert.Equals(d:readSetting("e"), nil)
        d:flush()
    end)

end)
