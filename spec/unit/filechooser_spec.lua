describe("FileChooser unreadable directories", function()
    local FileChooser, ffiUtil, lfs
    local settings_keys = { "collate", "collate_mixed", "reverse_collate", "lock_home_folder" }
    local saved_settings

    setup(function()
        require("commonrequire")
        FileChooser = require("ui/widget/filechooser")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
    end)

    before_each(function()
        saved_settings = {}
        for _, key in ipairs(settings_keys) do
            saved_settings[key] = G_reader_settings:readSetting(key)
        end
        G_reader_settings:saveSetting("lock_home_folder", false)
    end)

    after_each(function()
        for _, key in ipairs(settings_keys) do
            G_reader_settings:saveSetting(key, saved_settings[key])
        end
        lfs.dir:revert()
        lfs.attributes:revert()
        ffiUtil.realpath:revert()
    end)

    for _, collate in ipairs({ "date", "access" }) do
        for _, mixed in ipairs({ false, true }) do
            for _, reverse in ipairs({ false, true }) do
                it("keeps the warning outside " .. collate .. " sorting, mixed=" .. tostring(mixed)
                    .. ", reverse=" .. tostring(reverse), function()
                    G_reader_settings:saveSetting("collate", collate)
                    G_reader_settings:saveSetting("collate_mixed", mixed)
                    G_reader_settings:saveSetting("reverse_collate", reverse)
                    local parent = "/unreadable-" .. collate .. tostring(mixed) .. tostring(reverse)
                    local child = parent .. "/known-child"
                    stub(lfs, "dir", function() error("Permission denied") end)
                    stub(lfs, "attributes", function()
                        return { mode = "directory", modification = 100, access = 200 }
                    end)
                    stub(ffiUtil, "realpath", function() return parent end)
                    local chooser = FileChooser:extend{
                        is_fm = false,
                        show_flat_view = false,
                        refreshPath = function() end,
                    }
                    chooser:changeToPath(parent, child)

                    local items = chooser:genItemTableFromPath(parent)
                    local dirs, files = chooser:getList(parent)
                    assert.are.equal(1, #dirs) -- Do not count the warning as a directory.
                    assert.are.equal(0, #files)
                    assert.are.equal(3, #items)
                    assert.is_true(items[1].is_go_up)
                    assert.are.equal(parent, items[2].path) -- Warning before real entries.
                    assert.are.equal(child, items[3].path)
                end)
            end
        end
    end
end)
