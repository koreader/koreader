package.path = "?.lua;common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;" .. package.cpath

-- turn off debug by default and set log level to warning
require("dbg"):turnOff()
local logger = require("logger")
logger:setLevel(logger.levels.warn)

local DataStorage = require("datastorage")
require("libs/libkoreader-lfs").mkdir(DataStorage:getHistoryDir()) -- for legacy history tests

-- global defaults
os.remove(DataStorage:getDataDir() .. "/defaults.tests.lua")
os.remove(DataStorage:getDataDir() .. "/defaults.tests.lua.old")
G_defaults = require("luadefaults"):open(DataStorage:getDataDir() .. "/defaults.tests.lua")

-- global reader settings
os.remove(DataStorage:getDataDir() .. "/settings.tests.lua")
os.remove(DataStorage:getDataDir() .. "/settings.tests.lua.old")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.tests.lua")
G_reader_settings:saveSetting("document_metadata_folder", "dir")

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
