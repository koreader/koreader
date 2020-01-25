describe("Evernote plugin module", function()
    local readerui, match
    local sample_clippings, sample_epub
    local DocumentRegistry
    setup(function()
        require("commonrequire")
        match = require("luassert.match")
        local ReaderUI = require("apps/reader/readerui")
        DocumentRegistry = require("document/documentregistry")
        sample_epub = "spec/front/unit/data/juliet.epub"
        readerui = ReaderUI:new{
                document = DocumentRegistry:openDocument(sample_epub),
            }

        sample_clippings = {
            ["Title1"] = {
                [1] = {
                    [1] = {
                        ["page"] = 6,
                        ["time"] = 1578946897,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 1"
                    }
                },
                [2] = {
                    [1] = {
                        ["page"] = 13,
                        ["time"] = 1578946903,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 2"
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
                        ["text"] = "Some important stuff 3"
                    }
                },
                [2] = {
                    [1] = {
                        ["page"] = 237,
                        ["time"] = 1578947501,
                        ["sort"] = "highlight",
                        ["text"] = "",
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

    it("should write clippings to txt file", function ()
        local file_mock = mock( {
            write = function() return end,
            close = function() return end
        })
        local old_io = _G.io
        _G.io = mock({
           open = function(file, mode)
            if file == readerui.evernote.text_clipping_file then
                return file_mock
            else
                return old_io.open(file, mode)
            end
        end
        })

        readerui.evernote:exportBooknotesToTXT("Title1", sample_clippings.Title1)
        assert.spy(io.open).was.called()
        assert.spy(file_mock.write).was.called_with(match.is_ref(file_mock), "Some important stuff 1")
        _G.io = old_io

    end)

    it("should not export booknotes with exported_stamp", function()
        readerui.evernote.html_export = true
        stub(readerui.evernote, "exportBooknotesToHTML")
        readerui.evernote:exportClippings(sample_clippings)
        assert.stub(readerui.evernote.exportBooknotesToHTML).was_called_with(match.is_truthy(), "Title2", match.is_truthy())
        assert.stub(readerui.evernote.exportBooknotesToHTML).was_not_called_with(match.is_truthy(), "Title1", match.is_truthy())
    end)


end)