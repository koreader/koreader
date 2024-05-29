-- performance benchmark utility
-- usage: ./luajit tools/benchmark.lua test/sample.pdf

require "defaults"
package.path = "common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "common/?.so;common/?.dll;/usr/lib/lua/?.so;" .. package.cpath

local DataStorage = require("datastorage")
--G_reader_settings = require("docsettings"):open(".reader")
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir().."/settings.reader.lua")

-- global einkfb for Screen (do not show SDL window)
einkfb = require("ffi/framebuffer")
einkfb.dummy = true

local DocumentRegistry = require("document/documentregistry")
local Koptinterface = require("document/koptinterface")
local util = require("ffi/util")
local DEBUG = require("dbg")
DEBUG:turnOn()

DEBUG("args", arg)

function logDuration(filename, pageno, dur)
    local file = io.open(filename, "a+")
    if file then
        file:write(string.format("%s\t%s\n", pageno, dur))
        file:close()
    end
end

function doAutoBBox(doc, page)
    Koptinterface:getAutoBBox(doc, page)
end

function doReflow(doc, page)
    Koptinterface:getCachedContext(doc, page)
end

function benchmark(filename, doForOnePage)
    local doc = DocumentRegistry:openDocument(filename)
    for i = 1, doc:getPageCount() do
        local secs, usecs = util.gettime()
        doForOnePage(doc, i)
        local nsecs, nusecs = util.gettime()
        local dur = nsecs - secs + (nusecs - usecs) / 1000000
        DEBUG("duration for page", i, dur)
        logDuration("benchmark.txt", i, dur)
    end
end

--benchmark(arg[1], doAutoBBox)
benchmark(arg[1], doReflow)

