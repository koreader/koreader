require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local Koptinterface = require("document/koptinterface")
local Cache = require("cache")
local DEBUG = require("dbg")
DEBUG:turnOn()

describe("Koptinterface module", function()
    local sample_pdf = "spec/front/unit/data/tall.pdf"
    local doc

    before_each(function()
        doc = DocumentRegistry:openDocument(sample_pdf)
        Cache:clear()
    end)

    after_each(function()
        doc:close()
    end)

    it("should get auto bbox", function()
        local auto_bbox = Koptinterface:getAutoBBox(doc, 1)
        assertAlmostEquals(22, auto_bbox.x0, 0.5)
        assertAlmostEquals(38, auto_bbox.y0, 0.5)
        assertAlmostEquals(548, auto_bbox.x1, 0.5)
        assertAlmostEquals(1387, auto_bbox.y1, 0.5)
    end)

    it("should get semi auto bbox", function()
        local semiauto_bbox = Koptinterface:getSemiAutoBBox(doc, 1)
        local page_bbox = doc:getPageBBox(1)
        doc.bbox[1] = {
            x0 = page_bbox.x0 + 10,
            y0 = page_bbox.y0 + 10,
            x1 = page_bbox.x1 - 10,
            y1 = page_bbox.y1 - 10,
        }

        local bbox = Koptinterface:getSemiAutoBBox(doc, 1)
        assertNotAlmostEquals(semiauto_bbox.x0, bbox.x0, 0.5)
        assertNotAlmostEquals(semiauto_bbox.y0, bbox.y0, 0.5)
        assertNotAlmostEquals(semiauto_bbox.x1, bbox.x1, 0.5)
        assertNotAlmostEquals(semiauto_bbox.y1, bbox.y1, 0.5)
    end)

    it("should render optimized page to de-watermark", function()
        local page_dimen = doc:getPageDimensions(1, 1.0, 0)
        local tile = Koptinterface:renderOptimizedPage(doc, 1, nil,
            1.0, 0, 0)
        assert.truthy(tile)
        assert.are.same(page_dimen, tile.excerpt)
    end)

    it("should reflow page in foreground", function()
        doc.configurable.text_wrap = 1
        local kc = Koptinterface:getCachedContext(doc, 1)
        assert.truthy(kc)
    end)

    it("should hint reflowed page in background", function()
        doc.configurable.text_wrap = 1
        Koptinterface:hintReflowedPage(doc, 1, 1.0, 0, 1.0, 0)
        -- and wait for reflowing to complete
        local kc = Koptinterface:getCachedContext(doc, 1)
        assert.truthy(kc)
    end)

    it("should get native text boxes", function()
        local kc = Koptinterface:getCachedContext(doc, 1)
        local boxes = Koptinterface:getNativeTextBoxes(doc, 1)
        local lines_in_native_page = #boxes
        assert.truthy(lines_in_native_page == 60)
    end)

    it("should get reflow text boxes", function()
        doc.configurable.text_wrap = 1
        local kc = Koptinterface:getCachedContext(doc, 1)
        local boxes = Koptinterface:getReflowedTextBoxes(doc, 1)
        local lines_in_reflowed_page = #boxes
        assert.truthy(lines_in_reflowed_page > 60)
    end)

end)
