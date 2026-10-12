describe("BookList module", function()
    local BookList
    setup(function()
        require("commonrequire")
        BookList = require("ui/widget/booklist")
    end)

    describe("getSortTitle()", function()
        it("should skip English leading articles", function()
            assert.are.same("Hobbit", BookList.getSortTitle("The Hobbit", "en"))
            assert.are.same("Tale of Two Cities", BookList.getSortTitle("A Tale of Two Cities", "en"))
            assert.are.same("Unquiet Mind", BookList.getSortTitle("An Unquiet Mind", "en"))
            assert.are.same("hobbit", BookList.getSortTitle("the  hobbit", "en"))
        end)
        it("should only skip whole words", function()
            assert.are.same("Theory of Everything", BookList.getSortTitle("Theory of Everything", "en"))
            assert.are.same("Another Country", BookList.getSortTitle("Another Country", "en"))
            assert.are.same("A-Team", BookList.getSortTitle("A-Team", "en"))
        end)
        it("should only skip one article", function()
            assert.are.same("The End", BookList.getSortTitle("The The End", "en"))
        end)
        it("should not return an empty string", function()
            assert.are.same("The", BookList.getSortTitle("The", "en"))
            assert.are.same("The ", BookList.getSortTitle("The ", "en"))
        end)
        it("should use the articles of the given language", function()
            assert.are.same("Apfel", BookList.getSortTitle("Der Apfel", "de"))
            assert.are.same("The Englisch", BookList.getSortTitle("The Englisch", "de"))
            assert.are.same("Der Englisch", BookList.getSortTitle("Der Englisch", "en"))
            assert.are.same("Chat", BookList.getSortTitle("Le Chat", "fr"))
            assert.are.same("Comte de Monte-Cristo", BookList.getSortTitle("Le Comte de Monte-Cristo", "fr"))
            assert.are.same("Perro", BookList.getSortTitle("El Perro", "es"))
            assert.are.same("Nome della rosa", BookList.getSortTitle("Il Nome della rosa", "it"))
            assert.are.same("Kat", BookList.getSortTitle("De Kat", "nl"))
        end)
        it("should skip elided articles", function()
            assert.are.same("Orange", BookList.getSortTitle("L'Orange", "fr"))
            assert.are.same("Étranger", BookList.getSortTitle("L’Étranger", "fr"))
            assert.are.same("amica geniale", BookList.getSortTitle("L'amica geniale", "it"))
        end)
        it("should skip multi-word articles", function()
            assert.are.same("Terre à la Lune", BookList.getSortTitle("De la Terre à la Lune", "fr"))
        end)
        it("should accept language codes found in metadata", function()
            assert.are.same("Apfel", BookList.getSortTitle("Der Apfel", "de-DE"))
            assert.are.same("Apfel", BookList.getSortTitle("Der Apfel", "deu"))
            assert.are.same("Hobbit", BookList.getSortTitle("The Hobbit", "en_US"))
        end)
        it("should fall back to English for unknown languages", function()
            assert.are.same("Hobbit", BookList.getSortTitle("The Hobbit", "xx"))
            assert.are.same("Hobbit", BookList.getSortTitle("The Hobbit"))
        end)
        it("should use the UI language only when no language is given", function()
            G_reader_settings:saveSetting("language", "de")
            assert.are.same("Apfel", BookList.getSortTitle("Der Apfel"))
            assert.are.same("Der Apfel", BookList.getSortTitle("Der Apfel", "xx"))
            assert.are.same("Hobbit", BookList.getSortTitle("The Hobbit", "xx"))
            G_reader_settings:delSetting("language")
        end)
        it("should not skip anything for languages without articles", function()
            assert.are.same("The Hobbit", BookList.getSortTitle("The Hobbit", "pl"))
        end)
    end)

    describe("getStringCompareFunc()", function()
        local titles = { "The Silmarillion", "Animal Farm", "The Count of Monte Cristo", "Stoner", "Silmarillion" }
        it("should compare full strings when disabled", function()
            G_reader_settings:delSetting("sort_ignore_articles")
            local compare = BookList.getStringCompareFunc()
            local sorted = { unpack(titles) }
            table.sort(sorted, compare)
            assert.are.same({ "Animal Farm", "Silmarillion", "Stoner", "The Count of Monte Cristo", "The Silmarillion" }, sorted)
        end)
        it("should skip leading articles when enabled", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            local compare = BookList.getStringCompareFunc()
            local sorted = { unpack(titles) }
            table.sort(sorted, compare)
            assert.are.same({ "Animal Farm", "The Count of Monte Cristo", "Silmarillion", "The Silmarillion", "Stoner" }, sorted)
            G_reader_settings:delSetting("sort_ignore_articles")
        end)
        it("should give a consistent order for titles differing only in case", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            local compare = BookList.getStringCompareFunc()
            local titles = { "hobbit", "Hobbit", "The Hobbit", "the hobbit" }
            for _, a in ipairs(titles) do
                for _, b in ipairs(titles) do
                    for _, c in ipairs(titles) do
                        if compare(a, b) and compare(b, c) then
                            assert.is_true(compare(a, c))
                        end
                        if not compare(a, b) and not compare(b, a) and not compare(b, c) and not compare(c, b) then
                            assert.is_false(compare(a, c))
                        end
                    end
                end
            end
            G_reader_settings:delSetting("sort_ignore_articles")
        end)
        it("should use the given languages", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            local compare = BookList.getStringCompareFunc()
            assert.is_true(compare("Der Apfel", "Birne", "de", "de"))
            assert.is_false(compare("Der Apfel", "Birne", "en", "en"))
            G_reader_settings:delSetting("sort_ignore_articles")
        end)
    end)

    describe("collates", function()
        local function sortItems(collate_id, items)
            table.sort(items, BookList.collates[collate_id].init_sort_func())
            local texts = {}
            for _, item in ipairs(items) do
                table.insert(texts, item.doc_props and item.doc_props.display_title or item.text)
            end
            return texts
        end

        it("should sort by title without leading articles in the book language", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            local items = {
                { doc_props = { display_title = "The Silmarillion", language = "en" } },
                { doc_props = { display_title = "Der Prozess", language = "de" } },
                { doc_props = { display_title = "Stoner", language = "en" } },
                { doc_props = { display_title = "The Count of Monte Cristo", language = "en" } },
                { doc_props = { display_title = "Le Comte de Monte-Cristo", language = "fr" } },
            }
            assert.are.same({ "Le Comte de Monte-Cristo", "The Count of Monte Cristo", "Der Prozess", "The Silmarillion", "Stoner" },
                sortItems("title", items))
            G_reader_settings:delSetting("sort_ignore_articles")
        end)
        it("should keep natural sorting of numbers", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            local items = {
                { text = "The Book 10.epub" },
                { text = "Book 2.epub" },
                { text = "A Book 1.epub" },
                { text = "Atlas.epub" },
            }
            assert.are.same({ "Atlas.epub", "A Book 1.epub", "Book 2.epub", "The Book 10.epub" }, sortItems("natural", items))
            G_reader_settings:delSetting("sort_ignore_articles")
        end)
    end)
end)
