require "defaults"
require "libs/libkoreader-luagettext"
package.path = "?.lua;common/?.lua;frontend/?.lua"
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so"

-- global einkfb for Screen
einkfb = require("ffi/framebuffer")
-- do not show SDL window
einkfb.dummy = true
Blitbuffer = require("ffi/blitbuffer")
util = require("ffi/util")

local Screen = require("ui/screen")
local DocSettings = require("docsettings")
G_reader_settings = DocSettings:open(".reader")
local DocumentRegistry = require("document/documentregistry")
local DEBUG = require("dbg")

-- screen should be inited for crengine
Screen:init()

function logDuration(filename, pageno, dur)
    local file = io.open(filename, "a+")
    if file then
        if file:seek("end") == 0 then -- write the header only once
            file:write("PAGE\tDUR\n")
        end
        file:write(string.format("%s\t%s\n", pageno, dur))
        file:close()
    end
end

describe("PDF rendering benchmark", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local doc = DocumentRegistry:openDocument(sample_pdf)
    for pageno = 1, doc.info.number_of_pages do
        local secs, usecs = util.gettime()
        assert.truthy(doc:renderPage(pageno, nil, 1, 0, 1.0, 0))
        local nsecs, nusecs = util.gettime()
        local dur = nsecs - secs + (nusecs - usecs) / 1000000
        logDuration("pdf_rendering.log", pageno, dur)
    end
    doc:close()
end)

