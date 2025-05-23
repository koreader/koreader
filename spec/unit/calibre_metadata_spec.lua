local function count_keys(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function ends_with(str, ending)
    return string.sub(str, -#ending) == ending
end

describe("Calibre Metadata", function()
    local CalibreMetadata
    local sample_pdf = "spec/base/unit/data/simple.pdf"
    local book = {
        lpath = sample_pdf,
        uuid = "test_uuid",
    }

    setup(function()
        require("commonrequire")
        CalibreMetadata = dofile("plugins/calibre.koplugin/metadata.lua")
    end)

    describe("removing books", function()
        before_each(function()
            CalibreMetadata.books[1] = book
        end)

        it("clean() should remove books", function()
            assert.is.same(1, #CalibreMetadata.books)

            CalibreMetadata:clean()

            assert.is.same(0, #CalibreMetadata.books)
        end)
        it("remove the given book", function()
            assert.is.same(1, #CalibreMetadata.books)

            CalibreMetadata:removeBook(sample_pdf)

            assert.is.same(0, #CalibreMetadata.books)
        end)
    end)

    describe("adding books", function()
        after_each(function()
            CalibreMetadata:clean()
        end)

        it("should add a book to the map books", function()
            CalibreMetadata:addBook(book)

            assert.is.same(sample_pdf, CalibreMetadata.books[1].lpath)
            assert.is.same(1, #CalibreMetadata.books)
        end)
        it("should not result in duplicates", function()
            CalibreMetadata:addBook(book)

            assert.is.same(1, #CalibreMetadata.books)
        end)
        it("should be added to sidecar map by default", function()
            CalibreMetadata:addBook(book)

            assert.is.same(1, count_keys(CalibreMetadata.book_to_sidecar_map))
            assert.is.is_true(ends_with(CalibreMetadata.book_to_sidecar_map["test_uuid"], ".sdr"))
        end)
        it("should not be added to sidecar map when disabled", function()
            CalibreMetadata.keep_sidecar_path_map = false
            CalibreMetadata:addBook(book)

            assert.is.same(0, count_keys(CalibreMetadata.book_to_sidecar_map))
        end)
    end)
end)
