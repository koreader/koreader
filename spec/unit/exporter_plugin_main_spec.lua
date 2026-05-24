describe("Exporter plugin module", function()
    local readerui
    local sample_clippings, sample_epub
    local DocumentRegistry, Screen
    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("exporter.koplugin")
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
        readerui.exporter.targets["text"].filepath = readerui.exporter.targets["text"]:getTimeStamp()
        local exportable = { sample_clippings.Title1 }
        local file_path = readerui.exporter.targets["text"]:getFilePath()
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
        ok = readerui.exporter.targets["acorny"]:export(sample_clippings)
        assert.not_truthy(ok)
    end)

    it("should export highlights to Acorny using the Readwise-compatible API", function()
        local acorny = readerui.exporter.targets["acorny"]
        local endpoint, method, body, headers
        acorny.settings.token = "test-token"
        acorny.makeJsonRequest = function(_, request_endpoint, request_method, request_body, request_headers)
            endpoint = request_endpoint
            method = request_method
            body = request_body
            headers = request_headers
            return {}
        end

        local ok = acorny:createHighlights(sample_clippings.Title1)

        assert.is_truthy(ok)
        assert.are.equal("https://acorny.io/api/v2/highlights/", endpoint)
        assert.are.equal("POST", method)
        assert.are.equal("Token test-token", headers["Authorization"])
        assert.are.equal(2, #body.highlights)
        assert.are.equal("Some important stuff 1", body.highlights[1].text)
        assert.are.equal("Title1", body.highlights[1].title)
        assert.are.equal("koreader", body.highlights[1].source_type)
    end)

    it("should show Acorny setup help", function()
        local acorny_menu = readerui.exporter.targets["acorny"]:getMenuTable()
        local help_item = acorny_menu.sub_item_table[3]

        assert.are.equal("Help", help_item.text)
        assert.is_true(help_item.keep_menu_open)
        assert.is_function(help_item.callback)
    end)
end)
