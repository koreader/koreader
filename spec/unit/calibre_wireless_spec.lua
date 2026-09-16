describe("CalibreWireless collections", function()
    local CalibreWireless
    local ReadCollection
    local original_readcollection
    local original_lfs
    local original_package_path
    local original_extensions
    local original_metadata
    local original_search

    local HOME = "/koreader/home"

    setup(function()
        require("commonrequire")
        original_package_path = package.path
        original_extensions = package.loaded["extensions"]
        original_metadata = package.loaded["metadata"]
        original_search = package.loaded["search"]
        original_readcollection = require("readcollection")
        original_lfs = require("libs/libkoreader-lfs")
    end)

    before_each(function()
        local readcollection_mock = {
            coll = {},
            coll_settings = {},
            coll_default = nil,
            written = nil,
        }

        function readcollection_mock:addCollection(name)
            self.coll[name] = {}
            self.coll_settings[name] = { order = 99 }
        end

        function readcollection_mock:removeCollection(name)
            self.coll[name] = nil
            self.coll_settings[name] = nil
        end

        function readcollection_mock:addItem(file, collection_name)
            self.coll[collection_name][file] = { file = file, order = 123 }
        end

        function readcollection_mock:isFileInCollection(file, collection_name)
            return self.coll[collection_name]
                and self.coll[collection_name][file]
                and true
                or false
        end

        function readcollection_mock:removeItem(file, collection_name)
            if self.coll[collection_name]
                and self.coll[collection_name][file]
            then
                self.coll[collection_name][file] = nil
                return true
            end
        end

        function readcollection_mock:write(updated_collections)
            self.written = updated_collections
        end

        local lfs_mock = { attributes_results = {} }

        function lfs_mock.attributes(path, key)
            local attrs = lfs_mock.attributes_results[path]
            if not attrs then
                return nil
            end

            if key then
                return attrs[key]
            end

            return attrs
        end

        package.replace("readcollection", readcollection_mock)
        package.replace("libs/libkoreader-lfs", lfs_mock)
        package.path = "plugins/calibre.koplugin/?.lua;" .. original_package_path
        CalibreWireless = dofile("plugins/calibre.koplugin/wireless.lua")
        ReadCollection = readcollection_mock
    end)

    after_each(function()
        package.path = original_package_path
        package.loaded["extensions"] = original_extensions
        package.loaded["metadata"] = original_metadata
        package.loaded["search"] = original_search
        package.replace("readcollection", original_readcollection)
        package.replace("libs/libkoreader-lfs", original_lfs)
    end)

    local function new_wireless()
        local wireless = setmetatable({}, { __index = CalibreWireless })
        wireless.responses = {}
        function wireless:sendJsonData(status, data)
            table.insert(self.responses, { status = status, data = data })
        end

        return wireless
    end

    describe("GET_COLLECTIONS", function()
        it("returns all collections including empty collections", function()
            ReadCollection.coll = {
                fiction = { [HOME .. "/books/one.epub"] = { file = HOME .. "/books/one.epub" } },
                empty = {},
            }

            local wireless = new_wireless()
            wireless:getCollections()

            assert.equals(1, #wireless.responses)
            assert.equals("OK", wireless.responses[1].status)

            local collections = wireless.responses[1].data.collections

            assert.is_table(collections.fiction)
            assert.equals(1, #collections.fiction)
            assert.equals(HOME .. "/books/one.epub", collections.fiction[1])
            assert.is_table(collections.empty)
            assert.equals(0, #collections.empty)
        end)
    end)

    describe("UPDATE_COLLECTIONS", function()
        it("removes requested collections", function()
            ReadCollection.coll = { fiction = {}, history = {} }
            ReadCollection.coll_settings = { fiction = { order = 1 }, history = { order = 2 } }

            local wireless = new_wireless()
            wireless:updateCollections{ remove_collections = {"fiction"} }

            assert.is_nil(ReadCollection.coll.fiction)
            assert.is_not_nil(ReadCollection.coll.history)
            assert.is_nil(ReadCollection.coll_settings.fiction)
            assert.is_not_nil(ReadCollection.coll_settings.history)
            assert.is_true(ReadCollection.written.fiction)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("creates empty collections", function()
            ReadCollection.coll = {}
            ReadCollection.coll_settings = {}
            local wireless = new_wireless()
            wireless:updateCollections{ add_collections = {"new collection"} }

            assert.is_not_nil(ReadCollection.coll["new collection"])
            assert.same({}, ReadCollection.coll["new collection"])
            assert.is_not_nil(ReadCollection.coll_settings["new collection"])
            assert.is_true(ReadCollection.written["new collection"])
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("creates a collection and adds book memberships in one update", function()
            ReadCollection.coll = {}
            ReadCollection.coll_settings = {}
            local lfs = require("libs/libkoreader-lfs")
            lfs.attributes_results[HOME .. "/books/one.epub"] = { mode = "file" }

            local wireless = new_wireless()
            wireless:updateCollections{
                add_collections = {"fiction"},
                add = { fiction = { HOME .. "/books/one.epub" } },
            }

            assert.is_not_nil(ReadCollection.coll.fiction)
            assert.is_not_nil(ReadCollection.coll.fiction[HOME .. "/books/one.epub"])
            assert.is_not_nil(ReadCollection.coll_settings.fiction)
            assert.is_true(ReadCollection.written.fiction)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("removes a collection even when membership changes are also requested", function()
            ReadCollection.coll = { fiction = { [HOME .. "/books/one.epub"] = { file = HOME .. "/books/one.epub" } } }
            ReadCollection.coll_settings = { fiction = { order = 7 } }

            local wireless = new_wireless()
            wireless:updateCollections{ remove_collections = {"fiction"}, remove = { fiction = { "books/one.epub" } } }

            assert.is_nil(ReadCollection.coll.fiction)
            assert.is_nil(ReadCollection.coll_settings.fiction)
            assert.is_true(ReadCollection.written.fiction)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("does not write when requested memberships already match", function()
            ReadCollection.coll = { fiction = { [HOME .. "/books/one.epub"] = { file = HOME .. "/books/one.epub" } } }
            ReadCollection.coll_settings = { fiction = { order = 7 } }
            local lfs = require("libs/libkoreader-lfs")
            lfs.attributes_results[HOME .. "/books/one.epub"] = { mode = "file" }

            local wireless = new_wireless()
            wireless:updateCollections{ add = { fiction = { HOME .. "/books/one.epub" } } }

            assert.same({ [HOME .. "/books/one.epub"] = {file = HOME .. "/books/one.epub"} }, ReadCollection.coll.fiction)
            assert.is_nil(ReadCollection.written)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("adds book memberships", function()
            ReadCollection.coll = { fiction = {} }
            ReadCollection.coll_settings = { fiction = { order = 7 } }
            local lfs = require("libs/libkoreader-lfs")
            lfs.attributes_results[HOME .. "/books/one.epub"] = { mode = "file" }

            local wireless = new_wireless()
            wireless:updateCollections{
                add = {
                    fiction = {
                        HOME .. "/books/one.epub",
                    },
                },
            }

            local item = ReadCollection.coll.fiction[HOME .. "/books/one.epub"]

            assert.is_not_nil(item)
            assert.equals(HOME .. "/books/one.epub", item.file)
            assert.is_true(ReadCollection.written.fiction)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("removes book memberships", function()
            ReadCollection.coll = { fiction = { [HOME .. "/books/one.epub"] = { file = HOME .. "/books/one.epub" } } }
            ReadCollection.coll_settings = { fiction = { order = 7 } }

            local wireless = new_wireless()
            wireless:updateCollections{ remove = { fiction = { HOME .. "/books/one.epub" } } }

            assert.is_nil(ReadCollection.coll.fiction[HOME .. "/books/one.epub"])
            assert.is_true(ReadCollection.written.fiction)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("preserves collection metadata when changing memberships", function()
            ReadCollection.coll = { fiction = {} }
            ReadCollection.coll_settings = { fiction = { order = 42, collate = true, custom = "preserve me" } }

            local wireless = new_wireless()
            local lfs = require("libs/libkoreader-lfs")
            lfs.attributes_results[HOME .. "/books/one.epub"] = { mode = "file" }
            wireless:updateCollections{ add = { fiction = { HOME .. "/books/one.epub" } } }

            assert.same({ order = 42, collate = true, custom = "preserve me" }, ReadCollection.coll_settings.fiction)
        end)

        it("does not modify unrelated collections", function()
            ReadCollection.coll = {
                fiction = {},
                history = { [HOME .. "/books/history.epub"] = { file = HOME .. "/books/history.epub" } },
            }
            ReadCollection.coll_settings = { fiction = { order = 1 }, history = { order = 2 } }

            local wireless = new_wireless()
            wireless:updateCollections{ add_collections = {"new"} }

            assert.is_not_nil(ReadCollection.coll.history)
            assert.is_not_nil(ReadCollection.coll.history[HOME .. "/books/history.epub"])
            assert.same({ order = 2 }, ReadCollection.coll_settings.history)
            assert.is_not_nil(ReadCollection.coll.fiction)
            assert.is_not_nil(ReadCollection.coll["new"])
        end)

        it("ignores invalid or nonexistent files", function()
            ReadCollection.coll = { fiction = {} }
            ReadCollection.coll_settings = { fiction = { order = 1 } }

            local wireless = new_wireless()
            wireless:updateCollections{
                add = { fiction = { HOME .. "/books/missing.epub", HOME .. "/outside.epub", "/absolute/path.epub" } },
            }

            assert.same({}, ReadCollection.coll.fiction)
            assert.is_nil(ReadCollection.written)
            assert.equals("OK", wireless.responses[1].status)
        end)

        it("does not fail on an invalid payload", function()
            local wireless = new_wireless()
            wireless:updateCollections(nil)

            assert.equals(0, #wireless.responses)
        end)
    end)
end)
