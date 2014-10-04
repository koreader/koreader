-- trace package loading flow with require call
-- usage: ./luajit -lutils/trace_require reader.lua ../../test

local math = require("math")
local _require = require

local loaded_modules = {}
local highlight = "*"
-- timing threshold for highlight annotation
local threshold = 0.001
-- whether to trace loaded packages
local trace_loaded = false
local indent = string.rep(" ", 4)

local level = 0
function require(module)
    level = level + 1
    local x = os.clock()
    local info = debug.getinfo(2)
    -- this is a protected call of require
    if info.short_src == "[C]" then
        info = debug.getinfo(3)
    end
    local loaded = loaded_modules[module]
    if not loaded then
        print(string.format("%s%s:%s => %s",
            indent:rep(level), info.short_src, info.currentline, module))
    elseif trace_loaded then
        print(string.format("%s%s:%s -> %s",
            indent:rep(level), info.short_src, info.currentline, module))
    end
    -- protect require call in case we cannot raise call level when errors happen
    local ok, loaded_module = pcall(_require, module)
    if not ok then
        level = level - 1
        error(loaded_module)
    end
    local elapse = os.clock() - x
    local annot = highlight:rep(math.ceil(math.log10(elapse/threshold))) or ""
    if not loaded then
        print(string.format("%s%s loading time: %.3f",
            annot .. indent:rep(level):sub(#annot + 1), module, elapse))
    end
    loaded_modules[module] = true
    level = level - 1
    return loaded_module
end
