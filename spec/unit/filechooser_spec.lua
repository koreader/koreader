describe("FileChooser unreadable directories", function()
    local FileChooser, ffiUtil, lfs, InfoMessage, UIManager, Screen
    local messages
    local settings_keys = { "collate", "collate_mixed", "reverse_collate", "lock_home_folder" }
    local saved_settings

    setup(function()
        require("commonrequire")
        FileChooser = require("ui/widget/filechooser")
        ffiUtil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")
        InfoMessage = require("ui/widget/infomessage")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
    end)

    before_each(function()
        messages = {}
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
        it("keeps the unreadable-folder warning out of " .. collate .. " sorting", function()
            G_reader_settings:saveSetting("collate", collate)
            G_reader_settings:saveSetting("collate_mixed", false)
            G_reader_settings:saveSetting("reverse_collate", false)
            local parent = "/unreadable-" .. collate
            local child = parent .. "/known-child"
            stub(lfs, "dir", function() error("Permission denied") end)
            stub(lfs, "attributes", function()
                return { mode = "directory", modification = 100, access = 200 }
            end)
            stub(ffiUtil, "realpath", function(path) return path end)
            local chooser = FileChooser:extend{
                is_fm = false,
                refreshPath = function() end,
            }
            chooser:changeToPath(parent, child)

            local items = chooser:genItemTableFromPath(parent)
            assert.are.equal(2, #items)
            assert.is_true(items[1].is_go_up)
            assert.are.equal(child, items[2].path)
        end)
    end

    describe("unreadable-folder notification", function()
        before_each(function()
            stub(InfoMessage, "new", function(_, options) return options end)
            stub(UIManager, "show", function(_, message) table.insert(messages, message) end)
            stub(Screen, "setWindowTitle", function() end)
        end)

        after_each(function()
            InfoMessage.new:revert()
            UIManager.show:revert()
            Screen.setWindowTitle:revert()
        end)

        it("warns on entering an unreadable folder, but not on refresh or child counting", function()
            local readable = false
            stub(lfs, "dir", function()
                if not readable then error("Permission denied") end
                return function() end
            end)
            stub(lfs, "attributes", function() return { mode = "directory" } end)
            stub(ffiUtil, "realpath", function(path) return path end)
            local chooser = FileChooser:extend{
                is_fm = true,
                path_items = {},
                ui = { handleEvent = function() end },
                switchItemTable = function(self, _, items) self.item_table = items end,
            }
            chooser:changeToPath("/denied-dialog")
            assert.are.equal(1, #messages)
            assert.are.equal(1, #chooser.item_table)
            assert.is_true(chooser.item_table[1].is_go_up)
            chooser:refreshPath()
            chooser:getList("/another-denied-folder")
            assert.are.equal(1, #messages)

            readable = true
            chooser:changeToPath("/readable-folder")
            assert.are.equal(1, #messages)
            readable = false
            chooser:changeToPath("/denied-dialog")
            assert.are.equal(2, #messages)
        end)
    end)
end)
