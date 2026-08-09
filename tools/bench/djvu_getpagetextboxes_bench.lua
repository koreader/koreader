---@diagnostic disable
-- Benchmark DjVu page text flattening
-- Usage:
--   luajit tools/bench/djvu_getpagetextboxes_bench.lua /path/to/file.djvu [--pages=1-10,12] [--iters=20]
-- Tips:
--   Run from emulator root with ../../tools/bench/djvu_getpagetextboxes_bench.lua

local function usage()
    io.stderr:write(("Usage: %s <file.djvu> [--pages=1-10,12] [--iters=20]\n"):format(arg[0]))
    os.exit(1)
end

local file = arg[1]
if not file then usage() end

local pages_arg = nil
local iters = 20
for i = 2, #arg do
    local a = arg[i]
    local key, val = a:match("^%-%-(%w+)=?(.*)$")
    if key == "pages" and val ~= "" then pages_arg = val end
    if key == "iters" and val ~= "" then
        local n = tonumber(val)
        if n and n > 0 then iters = math.max(1, math.floor(n)) end
    end
end

package.path = "base/?.lua;" .. package.path
local ok_env, err_env = pcall(dofile, "setupkoenv.lua")
if not ok_env then
    io.stderr:write("Failed to initialize KOReader environment: " .. tostring(err_env) .. "\n")
    os.exit(3)
end

-- Minimal runtime globals expected by frontend/document/* at require-time
local DataStorage = require("datastorage")
-- Global defaults and settings (tests variants, stored under KO_HOME or current dir)
G_defaults = require("luadefaults"):open(DataStorage:getDataDir() .. "/defaults.tests.lua")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.tests.lua")

-- Stub CanvasContext to avoid Device and Device.screen (and ffi/mupdf)
if not package.loaded["document/canvascontext"] then
    package.loaded["document/canvascontext"] = {
        is_color_rendering_enabled = false,
        getWidth = function() return 1080 end,
        getHeight = function() return 1440 end,
    }
end

local djvu = require("libs/libkoreader-djvu")
local DjvuDocument = require("frontend/document/djvudocument")

local ok, doc = pcall(djvu.openDocument, file, false, nil)
if not ok then
    io.stderr:write("Failed to open djvu: " .. tostring(doc) .. "\n")
    os.exit(2)
end

local function parse_pages(spec, maxp)
    if not spec or spec == "" then
        if not maxp then error("No --pages and page count unavailable") end
        local t = {}
        for i = 1, maxp do t[#t + 1] = i end
        return t
    end
    local list = {}
    for part in spec:gmatch("[^,]+") do
        local a, b = part:match("^(%d+)%-(%d+)$")
        if a and b then
            local s, e = tonumber(a), tonumber(b)
            if s <= e then
                for i = s, e do list[#list + 1] = i end
            end
        else
            local n = tonumber(part)
            if n then list[#list + 1] = n end
        end
    end
    table.sort(list)
    return list
end

local max_pages = doc:getPages()
local pages = parse_pages(pages_arg, max_pages)

local function now_cpu()
    return os.clock()
end

local function bench(label, fn)
    collectgarbage() collectgarbage()
    local mem0 = collectgarbage("count")
    local t0 = now_cpu()
    fn()
    local t1 = now_cpu()
    collectgarbage() collectgarbage()
    local mem1 = collectgarbage("count")
    local dt = t1 - t0
    print(('%-12s: %.3f s, Δmem: %.1f KiB'):format(label, dt, mem1 - mem0))
    return dt
end

-- Minimal self to call DjvuDocument:getPageTextBoxes
local self = {
    _document = doc,
}

-- Warmup to let LuaJIT compile hot paths
local function warmup()
    for _, p in ipairs(pages) do
        DjvuDocument.getPageTextBoxes(self, p)
    end
end

warmup()

bench("DjvuDocument.getPageTextBoxes", function()
    for _ = 1, iters do
        for _, p in ipairs(pages) do
            DjvuDocument.getPageTextBoxes(self, p)
        end
    end
end)

print(("Pages: %s; iters: %d; file: %s"):format(
    (#pages <= 20 and table.concat(pages, ",") or (#pages .. " pages")),
    iters,
    file
))
