require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local util = require("ffi/util")

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
    for pageno = 1, math.min(10, doc.info.number_of_pages) do
        local secs, usecs = util.gettime()
        assert.truthy(doc:renderPage(pageno, nil, 1, 0, 1.0, 0))
        local nsecs, nusecs = util.gettime()
        local dur = nsecs - secs + (nusecs - usecs) / 1000000
        logDuration("pdf_rendering.log", pageno, dur)
    end
    doc:close()
end)

describe("PDF reflowing benchmark", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local doc = DocumentRegistry:openDocument(sample_pdf)
    doc.configurable.text_wrap = 1
    for pageno = 1, math.min(10, doc.info.number_of_pages) do
        local secs, usecs = util.gettime()
        assert.truthy(doc:renderPage(pageno, nil, 1, 0, 1.0, 0))
        local nsecs, nusecs = util.gettime()
        local dur = nsecs - secs + (nusecs - usecs) / 1000000
        logDuration("pdf_reflowing.log", pageno, dur)
    end
    doc:close()
end)

