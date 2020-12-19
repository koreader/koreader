describe("Cache module", function()
    local DocumentRegistry, Cache
    local doc
    local max_page = 1
    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Cache = require("cache")

        local sample_pdf = "spec/front/unit/data/sample.pdf"
        doc = DocumentRegistry:openDocument(sample_pdf)
    end)
    teardown(function()
        doc:close()
    end)

    it("should clear cache", function()
        Cache:clear()
    end)

    it("should serialize blitbuffer", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 0)
            Cache:serialize()
        end
        Cache:clear()
    end)

    it("should deserialize blitbuffer", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:hintPage(pageno, 1, 0, 1.0, 0)
        end
        Cache:clear()
    end)

    it("should serialize koptcontext", function()
        doc.configurable.text_wrap = 1
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 0)
            doc:getPageDimensions(pageno)
            Cache:serialize()
        end
        Cache:clear()
        doc.configurable.text_wrap = 0
    end)

    it("should deserialize koptcontext", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 0)
        end
        Cache:clear()
    end)
end)
