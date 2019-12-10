describe("docsettings module", function()
    local docsettings, lfs, util

    setup(function()
        require("commonrequire")
        docsettings = require("docsettings")
        lfs = require("libs/libkoreader-lfs")
        util = require("ffi/util")
    end)

    it("should generate sidecar directory path", function()
        assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar metadata file", function()
        assert.Equals("../../foo.sdr/metadata.pdf.lua",
                      docsettings:getSidecarFile("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr/metadata.pdf.lua",
                      docsettings:getSidecarFile("/foo/bar.pdf"))
        assert.Equals("baz.sdr/metadata.epub.lua",
                      docsettings:getSidecarFile("baz.epub"))
    end)

    it("should read legacy history file", function()
        local file = "file.pdf"
        local d = docsettings:open(file)
        d:saveSetting("a", "b")
        d:saveSetting("c", "d")
        d:close()
        -- Now the sidecar file should be written.

        local legacy_files = {
            d.history_file,
            d.sidecar .. "/file.pdf.lua",
            "file.pdf.kpdfview.lua",
        }

        for _, f in pairs(legacy_files) do
            assert.False(os.rename(d.sidecar_file, f) == nil)
            d = docsettings:open(file)
            assert.True(os.remove(d.sidecar_file) == nil)
            -- Legacy history files should not be removed before flush has been
            -- called.
            assert.Equals(lfs.attributes(f, "mode"), "file")
            assert.Equals(d:readSetting("a"), "b")
            assert.Equals(d:readSetting("c"), "d")
            assert.Equals(d:readSetting("e"), nil)
            d:close()
            -- legacy history files should be removed as sidecar_file is
            -- preferred.
            assert.True(os.remove(f) == nil)
        end

        assert.False(os.remove(d.sidecar_file) == nil)
        d:purge()
    end)

    it("should respect newest history file", function()
        local file = "file.pdf"
        local d = docsettings:open(file)

        local legacy_files = {
            d.history_file,
            d.sidecar .. "/file.pdf.lua",
            "file.pdf.kpdfview.lua",
        }

        -- docsettings:flush will remove legacy files.
        for i, v in pairs(legacy_files) do
            d:saveSetting("a", i)
            d:flush()
            assert.False(os.rename(d.sidecar_file, v.."1") == nil)
        end

        d:close()
        for _, v in pairs(legacy_files) do
            assert.False(os.rename(v.."1", v) == nil)
        end

        d = docsettings:open(file)
        assert.Equals(d:readSetting("a"), #legacy_files)
        d:close()
        d:purge()
    end)

    it("should build correct legacy history path", function()
        local file = "/a/b/c--d/c.txt"
        local history_path = util.basename(docsettings:getHistoryPath(file))
        local path_from_history = docsettings:getPathFromHistory(history_path)
        local name_from_history = docsettings:getNameFromHistory(history_path)
        assert.is.same(file, path_from_history .. "/" .. name_from_history)
    end)

    it("should reserve last good file", function()
        local file = "file.pdf"
        local d = docsettings:open(file)
        d:saveSetting("a", "a")
        d:flush()
        -- metadata.pdf.lua should be generated.
        assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
        d:flush()
        -- metadata.pdf.lua.old should not yet be generated.
        assert.are.not_equal("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
        -- make metadata.pdf.lua older to bypass 60s age needed for .old rotation
        local minutes_ago = os.time() - 120
        lfs.touch(d.sidecar_file, minutes_ago)
        d:close()
        -- metadata.pdf.lua and metadata.pdf.lua.old should be generated.
        assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
        assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))

        -- write some garbage to sidecar-file.
        local f_out = io.open(d.sidecar_file, "w")
        f_out:write("bla bla bla")
        f_out:close()

        d = docsettings:open(file)
        -- metadata.pdf.lua should be removed.
        assert.are.not_equal("file", lfs.attributes(d.sidecar_file, "mode"))
        assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
        assert.Equals("a", d:readSetting("a"))
        d:saveSetting("a", "b")
        d:close()
        -- metadata.pdf.lua should be generated.
        assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
        assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
        -- The contents in sidecar_file and sidecar_file.old are different.
        -- a:b v.s. a:a

        d = docsettings:open(file)
        -- The content should come from sidecar_file.
        assert.Equals("b", d:readSetting("a"))
        -- write some garbage to sidecar-file.
        f_out = io.open(d.sidecar_file, "w")
        f_out:write("bla bla bla")
        f_out:close()

        -- do not flush the result, open docsettings again.
        d = docsettings:open(file)
        -- metadata.pdf.lua should be removed.
        assert.are.not_equal("file", lfs.attributes(d.sidecar_file, "mode"))
        assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
        -- The content should come from sidecar_file.old.
        assert.Equals("a", d:readSetting("a"))
        d:close()
        -- metadata.pdf.lua should be generated.
        assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
        assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
    end)

    describe("ignore empty sidecar file", function()
        it("should ignore empty file", function()
            local file = "file.pdf"
            local d = docsettings:open(file)
            d:saveSetting("a", "a")
            d:flush()
            -- metadata.pdf.lua should be generated.
            assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
            -- make metadata.pdf.lua older to bypass 60s age needed for .old rotation
            local minutes_ago = os.time() - 120
            lfs.touch(d.sidecar_file, minutes_ago)
            d:close()
            -- metadata.pdf.lua and metadata.pdf.lua.old should be generated.
            assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
            assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))

            -- reset the sidecar_file to an empty file.
            local f_out = io.open(d.sidecar_file, "w")
            f_out:close()

            d = docsettings:open(file)
            -- metadata.pdf.lua should be removed.
            assert.are.not_equal("file", lfs.attributes(d.sidecar_file, "mode"))
            assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
            assert.Equals("a", d:readSetting("a"))
            d:saveSetting("a", "b")
            d:close()
            -- metadata.pdf.lua should be generated.
            assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
            assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
            -- The contents in sidecar_file and sidecar_file.old are different.
            -- a:b v.s. a:a
        end)

        it("should ignore empty table", function()
            local file = "file.pdf"
            local d = docsettings:open(file)
            d:saveSetting("a", "a")
            d:flush()
            -- metadata.pdf.lua should be generated.
            assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
            -- make metadata.pdf.lua older to bypass 60s age needed for .old rotation
            local minutes_ago = os.time() - 120
            lfs.touch(d.sidecar_file, minutes_ago)
            d:close()
            -- metadata.pdf.lua and metadata.pdf.lua.old should be generated.
            assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
            assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))

            -- reset the sidecar_file to an empty file.
            local f_out = io.open(d.sidecar_file, "w")
            f_out:write("{                               }                 ")
            f_out:close()

            d = docsettings:open(file)
            -- metadata.pdf.lua should be removed.
            assert.are.not_equal("file", lfs.attributes(d.sidecar_file, "mode"))
            assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
            assert.Equals("a", d:readSetting("a"))
            d:saveSetting("a", "b")
            d:close()
            -- metadata.pdf.lua should be generated.
            assert.Equals("file", lfs.attributes(d.sidecar_file, "mode"))
            assert.Equals("file", lfs.attributes(d.sidecar_file .. ".old", "mode"))
            -- The contents in sidecar_file and sidecar_file.old are different.
            -- a:b v.s. a:a
        end)
    end)
end)
