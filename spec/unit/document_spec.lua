describe("PDF document module", function()
    local DocumentRegistry

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
    end)

    local doc
    it("should open document", function()
        local sample_pdf = "spec/front/unit/data/tall.pdf"
        doc = DocumentRegistry:openDocument(sample_pdf)
        assert.truthy(doc)
    end)
    it("should get page dimensions", function()
        local dimen = doc:getPageDimensions(1, 1, 0)
        assert.are.same(dimen.w, 567)
        assert.are.same(dimen.h, 1418)
    end)
    it("should get cover image", function()
        local image = doc:getCoverPageImage()
        assert.truthy(image)
        assert.are.same(320, image:getWidth())
        assert.are.same(800, image:getHeight())
    end)
    local pos0 = {page = 1, x = 0, y = 20}
    local pos1 = {page = 1, x = 300, y = 120}
    local pboxes = {
        {x = 26, y = 42, w = 240, h = 22},
        {x = 48, y = 82, w = 185, h = 22},
    }
    it("should clip page rect to PNG file", function()
        doc:clipPagePNGFile(pos0, pos1, nil, nil, "/tmp/clip0.png")
        doc:clipPagePNGFile(pos0, pos1, pboxes, "lighten", "/tmp/clip1.png")
    end)
    it("should clip page rect to PNG string", function()
        local clip0 = doc:clipPagePNGString(pos0, pos1, nil, nil)
        assert.truthy(clip0)
        local clip1 = doc:clipPagePNGString(pos0, pos1, pboxes, "lighten")
        assert.truthy(clip1)
    end)
    it("should calculate fast digest", function()
        assert.is_equal(doc:fastDigest(), "41cce710f34e5ec21315e19c99821415")
    end)
    it("should close document", function()
        doc:close()
    end)
end)

describe("EPUB document module", function()
    local DocumentRegistry

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
    end)

    local doc
    it("should open document", function()
        local sample_epub = "spec/front/unit/data/leaves.epub"
        doc = DocumentRegistry:openDocument(sample_epub)
        assert.truthy(doc)
    end)
    it("should get cover image", function()
        local image = doc:getCoverPageImage()
        assert.truthy(image)
        assert.are.same(image:getWidth(), 442)
        assert.are.same(image:getHeight(), 616)
    end)
    it("should calculate fast digest", function()
        assert.is_equal(doc:fastDigest(), "59d481d168cca6267322f150c5f6a2a3")
    end)
    it("should register droid sans fallback", function()
        local fonts_registry = {
            "Droid Sans Mono",
            "FreeSans",
            "FreeSerif",
            "Noto Naskh Arabic",
            "Noto Sans",
            "Noto Sans Arabic UI",
            "Noto Sans CJK SC",
            "Noto Sans Devanagari UI",
            "Noto Serif",
        }
        local face_list = cre.getFontFaces()
        assert.are.same(fonts_registry, face_list)
    end)
    it("should close document", function()
        doc:close()
    end)
end)
