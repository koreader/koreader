--[[--
Unit tests for model/library.lua.
Run with: busted spec/library_spec.lua
--]]--

local plugin_dir = (debug.getinfo(1,"S").source:match("@(.+)/spec/") or "..")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/lib/?.lua;" ..
               plugin_dir .. "/model/?.lua;" .. package.path

local Library = require("model/library")

describe("Library", function()

    local base_dir

    before_each(function()
        base_dir = os.tmpname()
        os.remove(base_dir)
        os.execute("mkdir -p " .. base_dir)
    end)

    after_each(function()
        os.execute("rm -rf " .. base_dir)
    end)

    describe("Library.new", function()
        it("creates notebooks/ directory", function()
            Library.new(base_dir)
            local f = io.open(base_dir .. "/notebooks", "r")
            assert.truthy(f); f:close()
        end)

        it("starts empty on first use", function()
            local lib = Library.new(base_dir)
            assert.equal(0, lib:notebookCount())
        end)

        it("rescans notebooks on construction", function()
            local lib1 = Library.new(base_dir)
            lib1:createNotebook("A")
            lib1:createNotebook("B")

            local lib2 = Library.new(base_dir)
            assert.equal(2, lib2:notebookCount())
        end)
    end)

    describe("Library:createNotebook", function()
        it("adds to the in-memory list", function()
            local lib = Library.new(base_dir)
            local nb = lib:createNotebook("X")
            assert.equal(1, lib:notebookCount())
            assert.equal("X", nb.name)
        end)

        it("defaults name to Untitled", function()
            local lib = Library.new(base_dir)
            local nb = lib:createNotebook()
            assert.equal("Untitled", nb.name)
        end)
    end)

    describe("Library:byUUID / Library:byIndex", function()
        it("finds notebook by UUID", function()
            local lib = Library.new(base_dir)
            local nb = lib:createNotebook("Find me")
            assert.equal(nb, lib:byUUID(nb.uuid))
        end)

        it("returns nil for unknown UUID", function()
            local lib = Library.new(base_dir)
            assert.is_nil(lib:byUUID("nope"))
        end)

        it("finds by index", function()
            local lib = Library.new(base_dir)
            lib:createNotebook("First")
            assert.equal("First", lib:byIndex(1).name)
        end)
    end)

    describe("Library:deleteNotebook", function()
        it("removes from count", function()
            local lib = Library.new(base_dir)
            local nb = lib:createNotebook("Del")
            lib:deleteNotebook(nb.uuid)
            assert.equal(0, lib:notebookCount())
        end)

        it("deletes the directory on disk", function()
            local lib = Library.new(base_dir)
            local nb = lib:createNotebook("Del")
            local dir = nb.dir
            lib:deleteNotebook(nb.uuid)
            local f = io.open(dir .. "/notebook.lua", "r")
            assert.is_nil(f)
        end)

        it("no-ops for unknown uuid", function()
            local lib = Library.new(base_dir)
            lib:createNotebook("A")
            lib:deleteNotebook("nope")
            assert.equal(1, lib:notebookCount())
        end)
    end)

    describe("Library state persistence", function()
        it("round-trips readState / writeState", function()
            local lib = Library.new(base_dir)
            lib:writeState({last_notebook_uuid = "abc-123", last_page_index = 3})
            local s = lib:readState()
            assert.equal("abc-123", s.last_notebook_uuid)
            assert.equal(3, s.last_page_index)
        end)

        it("returns empty table for missing state file", function()
            local lib = Library.new(base_dir)
            local s = lib:readState()
            assert.same({}, s)
        end)
    end)

    describe("Library:all", function()
        it("returns all notebooks", function()
            local lib = Library.new(base_dir)
            lib:createNotebook("First")
            lib:createNotebook("Second")
            lib:createNotebook("Third")
            local all = lib:all()
            assert.equal(3, #all)
            -- Order is by last_edited desc; just verify all names are present.
            local names = {}
            for _, nb in ipairs(all) do names[nb.name] = true end
            assert.truthy(names["First"])
            assert.truthy(names["Second"])
            assert.truthy(names["Third"])
        end)
    end)

    describe("Library sort by last_edited", function()
        it("returns most-recently-edited notebook first", function()
            local lib = Library.new(base_dir)
            local nb1 = lib:createNotebook("Old")
            nb1.last_edited = 100
            nb1:save()
            local nb2 = lib:createNotebook("New")
            nb2.last_edited = 200
            nb2:save()

            -- Re-scan from disk to pick up persisted last_edited values.
            local lib2 = Library.new(base_dir)
            local all  = lib2:all()
            assert.equal(2,     #all)
            assert.equal("New", all[1].name)
            assert.equal("Old", all[2].name)
        end)
    end)

end)
