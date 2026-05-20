--[[--
Unit tests for model/notebook.lua.
Run with: busted spec/notebook_spec.lua
--]]--

local plugin_dir = (debug.getinfo(1,"S").source:match("@(.+)/spec/") or "..")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/lib/?.lua;" ..
               plugin_dir .. "/model/?.lua;" .. package.path

local Notebook = require("model/notebook")

describe("Notebook", function()

    local base_dir

    before_each(function()
        base_dir = os.tmpname()
        os.remove(base_dir)
        os.execute("mkdir -p " .. base_dir)
    end)

    after_each(function()
        os.execute("rm -rf " .. base_dir)
    end)

    describe("Notebook.create", function()
        it("creates a directory with notebook.lua", function()
            local nb = Notebook.create("Test", base_dir)
            assert.truthy(nb)
            assert.equal("Test", nb.name)
            assert.equal(1, nb:pageCount())

            local f = io.open(nb.dir .. "/notebook.lua", "r")
            assert.truthy(f)
            f:close()
        end)

        it("sets created_at to a recent timestamp", function()
            local before = os.time()
            local nb = Notebook.create("T", base_dir)
            local after = os.time()
            assert.truthy(nb.created_at >= before and nb.created_at <= after)
        end)

        it("generates a unique uuid directory name", function()
            local nb1 = Notebook.create("A", base_dir)
            local nb2 = Notebook.create("B", base_dir)
            assert.not_equal(nb1.uuid, nb2.uuid)
        end)
    end)

    describe("Notebook.load", function()
        it("round-trips create → load", function()
            local nb = Notebook.create("Hello", base_dir)
            local nb2, err = Notebook.load(nb.uuid, base_dir)
            assert.is_nil(err)
            assert.equal("Hello", nb2.name)
            assert.equal(nb.uuid, nb2.uuid)
            assert.equal(1, nb2:pageCount())
        end)

        it("returns nil for a missing directory", function()
            local nb, err = Notebook.load("nonexistent-uuid", base_dir)
            assert.is_nil(nb)
            assert.truthy(err)
        end)
    end)

    describe("Notebook:pagePath", function()
        it("returns a path ending in page_001.svg", function()
            local nb = Notebook.create("X", base_dir)
            local p = nb:pagePath(1)
            assert.truthy(p:find("page_001.svg$"))
        end)

        it("returns nil for out-of-range index", function()
            local nb = Notebook.create("X", base_dir)
            assert.is_nil(nb:pagePath(0))
            assert.is_nil(nb:pagePath(2))
        end)
    end)

    describe("Notebook:addPage", function()
        it("increments pageCount and returns new path", function()
            local nb = Notebook.create("X", base_dir)
            local idx, path = nb:addPage()
            assert.equal(2, idx)
            assert.equal(2, nb:pageCount())
            assert.truthy(path:find("page_002.svg$"))
        end)

        it("persists across load", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()
            local nb2 = Notebook.load(nb.uuid, base_dir)
            assert.equal(2, nb2:pageCount())
        end)
    end)

    describe("Notebook:deletePage", function()
        it("removes a page from the list", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()
            assert.equal(2, nb:pageCount())
            nb:deletePage(1)
            assert.equal(1, nb:pageCount())
        end)

        it("no-ops for out-of-range index", function()
            local nb = Notebook.create("X", base_dir)
            nb:deletePage(99)
            assert.equal(1, nb:pageCount())
        end)
    end)

    describe("Notebook:rename", function()
        it("changes the name and persists", function()
            local nb = Notebook.create("Old", base_dir)
            nb:rename("New")
            assert.equal("New", nb.name)
            local nb2 = Notebook.load(nb.uuid, base_dir)
            assert.equal("New", nb2.name)
        end)
    end)

end)
