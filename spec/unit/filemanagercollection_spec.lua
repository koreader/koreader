describe("FileManagerCollection module", function()
    local FileManagerCollection
    setup(function()
        require("commonrequire")
        FileManagerCollection = require("apps/filemanager/filemanagercollection")
    end)

    describe("isItemMatch()", function()
        local books = {
            ["a.epub"] = { keywords = "Fantasy\nAdventure", authors = "Alice\nBob", language = "en-US", series = "Saga\nTome" },
            ["b.epub"] = { keywords = "Fantasy" },
            ["c.epub"] = { keywords = "Science\n" },
        }
        local function genColl(props)
            return setmetatable({
                match_table = { props = props },
                ui = { bookinfo = { getDocProps = function(_, file) return books[file] end } },
            }, { __index = FileManagerCollection })
        end
        local function matchingFiles(coll)
            local files = {}
            for _, file in ipairs({ "a.epub", "b.epub", "c.epub" }) do
                if coll:isItemMatch({ file = file }) then
                    table.insert(files, file)
                end
            end
            return files
        end

        it("should match a book having the keyword among others", function()
            assert.are.same({ "a.epub", "b.epub" }, matchingFiles(genColl({ keywords = "Fantasy" })))
        end)
        it("should match a book having the author among others", function()
            assert.are.same({ "a.epub" }, matchingFiles(genColl({ authors = "Bob" })))
        end)
        it("should match the lowercased language listed in the filter", function()
            assert.are.same({ "a.epub" }, matchingFiles(genColl({ language = "en-us" })))
        end)
        it("should match books without the property", function()
            assert.are.same({ "b.epub", "c.epub" }, matchingFiles(genColl({ authors = FileManagerCollection.empty_prop })))
        end)
        it("should ignore a trailing newline", function()
            assert.are.same({ "c.epub" }, matchingFiles(genColl({ keywords = "Science" })))
        end)
        it("should not split series", function()
            assert.are.same({}, matchingFiles(genColl({ series = "Saga" })))
        end)
    end)
end)
