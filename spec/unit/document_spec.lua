require "defaults"
package.path = "?.lua;common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;" .. package.cpath

-- global einkfb for Screen
einkfb = require("ffi/framebuffer")
-- do not show SDL window
einkfb.dummy = true

local Screen = require("ui/screen")
local DocSettings = require("docsettings")
G_reader_settings = DocSettings:open(".reader")
local DocumentRegistry = require("document/documentregistry")
local DEBUG = require("dbg")

-- screen should be inited for crengine
Screen:init()

describe("PDF document module", function()
    local sample_pdf = "spec/front/unit/data/tall.pdf"
    it("should open document", function()
        doc = DocumentRegistry:openDocument(sample_pdf)
        assert.truthy(doc)
    end)
    it("should get page dimensions", function()
        local dimen = doc:getPageDimensions(1, 1, 0)
        assert.are.same(dimen.w, 567)
        assert.are.same(dimen.h, 1418)
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
    it("should close document", function()
        doc:close()
    end)
end)

describe("EPUB document module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    it("should open document", function()
        doc = DocumentRegistry:openDocument(sample_epub)
        assert.truthy(doc)
    end)
    it("should get cover image", function()
        local image = doc:getCoverPageImage()
        assert.truthy(image)
        assert.are.same(image:getWidth(), 442)
        assert.are.same(image:getHeight(), 616)
    end)
    it("should close document", function()
        doc:close()
    end)
end)
