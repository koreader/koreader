require "defaults"
package.path = "?.lua;common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;" .. package.cpath

require "libs/libkoreader-lfs"
-- global einkfb for Screen
einkfb = require("ffi/framebuffer")
-- do not show SDL window
einkfb.dummy = true
Blitbuffer = require("ffi/blitbuffer")

local Screen = require("ui/screen")
local DocSettings = require("docsettings")
G_reader_settings = DocSettings:open(".reader")
local DocumentRegistry = require("document/documentregistry")
local Cache = require("cache")
local DEBUG = require("dbg")
--DEBUG:turnOn()

-- screen should be inited for crengine
Screen:init()

describe("Cache module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local doc = DocumentRegistry:openDocument(sample_pdf)
    it("should clear cache", function()
        Cache:clear()
    end)
    local max_page = 1
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
    end)
    it("should deserialize koptcontext", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 0)
        end
        Cache:clear()
    end)
end)
