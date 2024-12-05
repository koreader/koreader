describe("Exporter plugin module", function()
    local readerui
    local sample_clippings, sample_epub
    local DocumentRegistry, Screen
    setup(function()
        require("commonrequire")
        local ReaderUI = require("apps/reader/readerui")
        DocumentRegistry = require("document/documentregistry")
        Screen = require("device").screen
        sample_epub = "spec/front/unit/data/juliet.epub"
        readerui = ReaderUI:new {
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }

        sample_clippings = {
            ["Title1"] = {
                [1] = {
                    [1] = {
                        ["page"] = 6,
                        ["time"] = 1578946897,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 1",
                        ["drawer"] = "lighten"
                    }
                },
                [2] = {
                    [1] = {
                        ["page"] = 13,
                        ["time"] = 1578946903,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 2",
                        ["drawer"] = "lighten"
                    }
                },
                ["file"] = "path/to/title1",
                ["exported"] = {
                    ["txt"] = true,
                    ["html"] = true,
                },
                ["title"] = "Title1"
            },
            ["Title2"] = {
                [1] = {
                    [1] = {
                        ["page"] = 233,
                        ["time"] = 1578946918,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 3",
                        ["drawer"] = "lighten"
                    }
                },
                [2] = {
                    [1] = {
                        ["page"] = 237,
                        ["time"] = 1578947501,
                        ["sort"] = "highlight",
                        ["text"] = "",
                        ["drawer"] = "lighten",
                        ["image"] = {
                            ["hash"] = "cb7b40a63afc89f0aa452f2b655877e6",
                            ["png"] = "Binary Encoding of image"
                        },
                    }
                },
                ["file"] = "path/to/title2",
                ["exported"] = {
            },
                ["title"] = "Title2"
            },
        }

    end)
    teardown(function()
        readerui:onClose()
    end)

    it("should write clippings to a timestamped txt file", function()
        local timestamp = os.time()
        readerui.exporter.targets["text"].timestamp = timestamp
        local exportable = { sample_clippings.Title1 }
        local file_path = readerui.exporter.targets["text"]:getFilePath(exportable)
        readerui.exporter.targets["text"]:export(exportable)
        local f = io.open(file_path, "r")
        assert.is.truthy(string.find(f:read("*all"), "Some important stuff 1"))
        f:close()
        os.remove(file_path)
    end)

    it("should fail to export to non configured targets", function()
        local ok = readerui.exporter.targets["joplin"]:export(sample_clippings)
        assert.not_truthy(ok)
        ok = readerui.exporter.targets["readwise"]:export(sample_clippings)
        assert.not_truthy(ok)
    end)
end)
