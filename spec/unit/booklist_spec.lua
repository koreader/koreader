describe("BookList module", function()
    local BookList
    setup(function()
        require("commonrequire")
        BookList = require("ui/widget/booklist")
    end)

    describe("removeLeadingArticle()", function()
        it("should skip English leading articles", function()
            assert.are.same("Hobbit", BookList.removeLeadingArticle("The Hobbit", "en"))
            assert.are.same("Tale of Two Cities", BookList.removeLeadingArticle("A Tale of Two Cities", "en"))
            assert.are.same("Unquiet Mind", BookList.removeLeadingArticle("An Unquiet Mind", "en"))
            assert.are.same("hobbit", BookList.removeLeadingArticle("the  hobbit", "en"))
        end)
        it("should only skip whole words", function()
            assert.are.same("Theory of Everything", BookList.removeLeadingArticle("Theory of Everything", "en"))
            assert.are.same("Another Country", BookList.removeLeadingArticle("Another Country", "en"))
            assert.are.same("A-Team", BookList.removeLeadingArticle("A-Team", "en"))
        end)
        it("should only skip one article", function()
            assert.are.same("The End", BookList.removeLeadingArticle("The The End", "en"))
        end)
        it("should not return an empty string", function()
            assert.are.same("The", BookList.removeLeadingArticle("The", "en"))
            assert.are.same("The ", BookList.removeLeadingArticle("The ", "en"))
        end)
        it("should use the articles of the given language", function()
            assert.are.same("Apfel", BookList.removeLeadingArticle("Der Apfel", "de"))
            assert.are.same("The Englisch", BookList.removeLeadingArticle("The Englisch", "de"))
            assert.are.same("Der Englisch", BookList.removeLeadingArticle("Der Englisch", "en"))
            assert.are.same("Chat", BookList.removeLeadingArticle("Le Chat", "fr"))
            assert.are.same("Comte de Monte-Cristo", BookList.removeLeadingArticle("Le Comte de Monte-Cristo", "fr"))
            assert.are.same("Perro", BookList.removeLeadingArticle("El Perro", "es"))
            assert.are.same("Nome della rosa", BookList.removeLeadingArticle("Il Nome della rosa", "it"))
            assert.are.same("Kat", BookList.removeLeadingArticle("De Kat", "nl"))
        end)
        it("should skip elided articles", function()
            assert.are.same("Orange", BookList.removeLeadingArticle("L'Orange", "fr"))
            assert.are.same("Étranger", BookList.removeLeadingArticle("L’Étranger", "fr"))
            assert.are.same("amica geniale", BookList.removeLeadingArticle("L'amica geniale", "it"))
        end)
        it("should skip multi-word articles", function()
            assert.are.same("Terre à la Lune", BookList.removeLeadingArticle("De la Terre à la Lune", "fr"))
        end)
        it("should accept language codes found in metadata", function()
            assert.are.same("Apfel", BookList.removeLeadingArticle("Der Apfel", "de-DE"))
            assert.are.same("Apfel", BookList.removeLeadingArticle("Der Apfel", "deu"))
            assert.are.same("Hobbit", BookList.removeLeadingArticle("The Hobbit", "en_US"))
        end)
        it("should fall back to English for unknown languages", function()
            assert.are.same("Hobbit", BookList.removeLeadingArticle("The Hobbit", "xx"))
            assert.are.same("Hobbit", BookList.removeLeadingArticle("The Hobbit"))
        end)
        it("should use the UI language only when no language is given", function()
            G_reader_settings:saveSetting("language", "de")
            package.unload("ui/widget/booklist")
            local BookListDe = require("ui/widget/booklist")
            assert.are.same("Apfel", BookListDe.removeLeadingArticle("Der Apfel"))
            assert.are.same("Der Apfel", BookListDe.removeLeadingArticle("Der Apfel", "xx"))
            assert.are.same("Hobbit", BookListDe.removeLeadingArticle("The Hobbit", "xx"))
            G_reader_settings:delSetting("language")
            package.unload("ui/widget/booklist")
            BookList = require("ui/widget/booklist")
        end)
        it("should not skip anything for languages without articles", function()
            assert.are.same("The Hobbit", BookList.removeLeadingArticle("The Hobbit", "pl"))
        end)
    end)

    describe("compareSortTitles()", function()
        local function key(str)
            return BookList.removeLeadingArticle(str, "en")
        end

        it("should compare full strings when there are no sort titles", function()
            assert.is_true(BookList.compareSortTitles(nil, nil, "Stoner", "The Hobbit"))
            assert.is_false(BookList.compareSortTitles(nil, nil, "The Hobbit", "Stoner"))
        end)
        it("should compare sort titles first, then full strings", function()
            assert.is_true(BookList.compareSortTitles(key("The Hobbit"), key("Stoner"), "The Hobbit", "Stoner"))
            assert.is_true(BookList.compareSortTitles(key("Silmarillion"), key("The Silmarillion"),
                "Silmarillion", "The Silmarillion"))
        end)
        it("should give a consistent order for titles differing only in case", function()
            local titles = { "hobbit", "Hobbit", "The Hobbit", "the hobbit" }
            local function compare(a, b)
                return BookList.compareSortTitles(key(a), key(b), a, b)
            end
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
        end)
    end)

    describe("collates", function()
        local ui = {
            bookinfo = {
                getDocProps = function(_, file)
                    return { display_title = file.title, language = file.language }
                end,
            },
        }
        local function sortItems(collate_id, items)
            local collate = BookList.collates[collate_id]
            for _, item in ipairs(items) do
                collate.item_func(item, ui)
            end
            table.sort(items, collate.init_sort_func())
            local texts = {}
            for _, item in ipairs(items) do
                table.insert(texts, item.doc_props and item.doc_props.display_title or item.text)
            end
            return texts
        end
        local function titleItems()
            return {
                { file = { title = "The Silmarillion", language = "en" } },
                { file = { title = "Der Prozess", language = "de" } },
                { file = { title = "Stoner", language = "en" } },
                { file = { title = "The Count of Monte Cristo", language = "en" } },
                { file = { title = "Le Comte de Monte-Cristo", language = "fr" } },
            }
        end
        local function nameItems()
            return {
                { text = "The Silmarillion.epub" },
                { text = "Animal Farm.epub" },
                { text = "The Count of Monte Cristo.epub" },
                { text = "Stoner.epub" },
                { text = "Silmarillion.epub" },
            }
        end

        it("should sort by full title when disabled", function()
            G_reader_settings:delSetting("sort_ignore_articles")
            BookList.updateSortTextFunc()
            assert.are.same({ "Der Prozess", "Le Comte de Monte-Cristo", "Stoner", "The Count of Monte Cristo", "The Silmarillion" },
                sortItems("title", titleItems()))
        end)
        it("should sort by title without leading articles in the book language", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            BookList.updateSortTextFunc()
            assert.are.same({ "Le Comte de Monte-Cristo", "The Count of Monte Cristo", "Der Prozess", "The Silmarillion", "Stoner" },
                sortItems("title", titleItems()))
            G_reader_settings:delSetting("sort_ignore_articles")
            BookList.updateSortTextFunc()
        end)
        it("should sort by full name when disabled", function()
            G_reader_settings:delSetting("sort_ignore_articles")
            BookList.updateSortTextFunc()
            assert.are.same({ "Animal Farm.epub", "Silmarillion.epub", "Stoner.epub", "The Count of Monte Cristo.epub",
                "The Silmarillion.epub" }, sortItems("strcoll", nameItems()))
        end)
        it("should sort by name without leading articles when enabled", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            BookList.updateSortTextFunc()
            assert.are.same({ "Animal Farm.epub", "The Count of Monte Cristo.epub", "Silmarillion.epub",
                "The Silmarillion.epub", "Stoner.epub" }, sortItems("strcoll", nameItems()))
            G_reader_settings:delSetting("sort_ignore_articles")
            BookList.updateSortTextFunc()
        end)
        it("should keep natural sorting of numbers", function()
            G_reader_settings:saveSetting("sort_ignore_articles", true)
            BookList.updateSortTextFunc()
            local items = {
                { text = "The Book 10.epub" },
                { text = "Book 2.epub" },
                { text = "A Book 1.epub" },
                { text = "Atlas.epub" },
            }
            assert.are.same({ "Atlas.epub", "A Book 1.epub", "Book 2.epub", "The Book 10.epub" }, sortItems("natural", items))
            G_reader_settings:delSetting("sort_ignore_articles")
            BookList.updateSortTextFunc()
        end)
    end)
end)
