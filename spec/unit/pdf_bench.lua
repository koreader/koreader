require("commonrequire")
local DocumentRegistry = require("document/documentregistry")
local util = require("ffi/util")

local function logDuration(filename, pageno, dur)
    local file = io.open(filename, "a+")
    if file then
        if file:seek("end") == 0 then -- write the header only once
            file:write("PAGE\tDUR\n")
        end
        file:write(string.format("%s\t%s\n", pageno, dur))
        file:close()
    end
end

describe("PDF benchmark:", function()

    local function benchmark(logfile, reflow)
        local sample_pdf = "spec/front/unit/data/sample.pdf"
        local doc = DocumentRegistry:openDocument(sample_pdf)
        if reflow then
            doc.configurable.text_wrap = 1
        end
        for pageno = 1, math.min(9, doc.info.number_of_pages) do
            local secs, usecs = util.gettime()
            assert.truthy(doc:renderPage(pageno, nil, 1, 0, 1.0, 0x000000, 0xFFFFFF))
            local nsecs, nusecs = util.gettime()
            local dur = nsecs - secs + (nusecs - usecs) / 1000000
            logDuration(logfile, pageno, dur)
        end
        doc:close()
        if reflow then
            doc.configurable.text_wrap = 0
        end
    end

    it("rendering", function()
        benchmark("pdf_rendering.log", false)
    end)

    it("reflowing", function()
        benchmark("pdf_reflowing.log", true)
    end)

end)
