-- Check if we're running a busted version recent enough that we don't need to deal with the LuaJIT hacks...
-- That currently means > 2.0.0 (i.e., scm-2, which isn't on LuaRocks...).
local busted_ok = false
for name, _ in pairs(package.loaded) do
    if name == "busted.luajit" then
        busted_ok = true
        break
    end
end

-- Don't try to overwrite metatables so we can use --auto-insulate-tests
-- Shamelessly copied from https://github.com/Olivine-Labs/busted/commit/2dfff99bda01fd3da56fd23415aba5a2a4cc0ffd
if not busted_ok then
    local ffi = require "ffi"

    local original_metatype = ffi.metatype
    local original_store = {}
    ffi.metatype = function (primary, ...)
        if original_store[primary] then
            return original_store[primary]
        end
        local success, result, err = pcall(original_metatype, primary, ...)
        if not success then
            -- hard error was thrown
            error(result, 2)
        end
        if not result then
            -- soft error was returned
            return result, err
        end
        -- it worked, store and return
        original_store[primary] = result
        return result
    end
end

require "defaults"
package.path = "?.lua;common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" .. package.cpath

-- turn off debug by default and set log level to warning
require("dbg"):turnOff()
local logger = require("logger")
logger:setLevel(logger.levels.warn)

-- global reader settings
local DataStorage = require("datastorage")
os.remove(DataStorage:getDataDir().."/settings.reader.lua")
G_reader_settings = require("luasettings"):open(".reader")

-- global einkfb for Screen (do not show SDL window)
einkfb = require("ffi/framebuffer") --luacheck: ignore
einkfb.dummy = true --luacheck: ignore

local Device = require("device")

-- init output device
local Screen = Device.screen
Screen:init()

local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)

-- init input device (do not show SDL window)
local Input = Device.input
Input.dummy = true

package.unload = function(module)
    if type(module) ~= "string" then return false end
    package.loaded[module] = nil
    _G[module] = nil
    return true
end

package.replace = function(name, module)
    if type(name) ~= "string" then return false end
    assert(package.unload(name))
    package.loaded[name] = module
    return true
end

package.reload = function(name)
    if type(name) ~= "string" then return false end
    assert(package.unload(name))
    return require(name)
end

package.unloadAll = function()
    local candidates = {
        "spec/",
        "frontend/",
        "plugins/",
        "datastorage.lua",
        "defaults.lua",
    }
    local pending = {}
    for name, _ in pairs(package.loaded) do
        local path = package.searchpath(name, package.path)
        if path ~= nil then
            for _, candidate in ipairs(candidates) do
                if path:find(candidate) == 1 then
                    table.insert(pending, name)
                end
            end
        end
    end
    for _, name in ipairs(pending) do
        if name ~= "commonrequire" then
            assert(package.unload(name))
        end
    end
    return #pending
end

local background_runner
requireBackgroundRunner = function()
    require("pluginshare").stopBackgroundRunner = nil
    if background_runner == nil then
        local package_path = package.path
        package.path = "plugins/backgroundrunner.koplugin/?.lua;" .. package.path
        background_runner = dofile("plugins/backgroundrunner.koplugin/main.lua")
        package.path = package_path
    end
    return background_runner
end

stopBackgroundRunner = function()
    background_runner = nil
    require("pluginshare").stopBackgroundRunner = true
end

notifyBackgroundJobsUpdated = function()
    if background_runner then
        background_runner:onBackgroundJobsUpdated()
    end
end
