describe("DjVu document module", function()
    local DjvuDocument

    setup(function()
        require("commonrequire")
        DjvuDocument = require("document/djvudocument")
    end)

    local function get_words(lines)
        local words = {}
        for i = 1, #lines do
            words[i] = {}
            for j = 1, #lines[i] do
                words[i][j] = lines[i][j].word
            end
        end
        return words
    end

    local function make_doc(page_text)
        return {
            _document = {
                getPageText = function(_, pageno)
                    assert.is_equal(1, pageno)
                    return page_text
                end,
            },
        }
    end

    it("should flatten nested line nodes without reordering words by x", function()
        local page_text = {
            {
                {
                    line = true,
                    { word = "Strategie", x0 = 50, y0 = 10, x1 = 90, y1 = 20 },
                    { word = "del", x0 = 10, y0 = 10, x1 = 30, y1 = 20 },
                    { word = "terrore", x0 = 100, y0 = 10, x1 = 150, y1 = 20 },
                },
            },
        }

        local lines = DjvuDocument.getPageTextBoxes(make_doc(page_text), 1)

        assert.are_same({ { "Strategie", "del", "terrore" } }, get_words(lines))
    end)

    it("should preserve source order for direct word children", function()
        local page_text = {
            {
                word = false,
                { word = "draw", x0 = 45, y0 = 10, x1 = 70, y1 = 20 },
                { word = "attention,", x0 = 10, y0 = 10, x1 = 40, y1 = 20 },
                { word = "in", x0 = 75, y0 = 10, x1 = 85, y1 = 20 },
            },
        }

        local lines = DjvuDocument.getPageTextBoxes(make_doc(page_text), 1)

        assert.are_same({ { "draw", "attention,", "in" } }, get_words(lines))
    end)

    it("should still fall back to geometric grouping when only loose words exist", function()
        local page_text = {
            { word = "first", x0 = 40, y0 = 30, x1 = 60, y1 = 40 },
            { word = "line", x0 = 70, y0 = 30, x1 = 90, y1 = 40 },
            { word = "second", x0 = 10, y0 = 60, x1 = 40, y1 = 70 },
            { word = "line", x0 = 45, y0 = 60, x1 = 65, y1 = 70 },
        }

        local lines = DjvuDocument.getPageTextBoxes(make_doc(page_text), 1)

        assert.are_same({
            { "first", "line" },
            { "second", "line" },
        }, get_words(lines))
    end)
end)
