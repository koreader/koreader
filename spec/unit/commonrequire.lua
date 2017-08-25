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

-- init output device
local Screen = require("device").screen
Screen:init()

-- init input device (do not show SDL window)
local Input = require("device").input
Input.dummy = true

function assertAlmostEquals(expected, actual, margin)
    if type(actual) ~= 'number' or type(expected) ~= 'number'
        or type(margin) ~= 'number' then
        error('assertAlmostEquals: must supply only number arguments.', 2)
    end

    assert(math.abs(expected - actual) <= margin,
        'Values are not almost equal\n'
            .. 'Expected: ' .. expected .. ' with margin of ' .. margin
            .. ', received: ' .. actual
    )
end

function assertNotAlmostEquals(expected, actual, margin)
    if type(actual) ~= 'number' or type(expected) ~= 'number'
        or type(margin) ~= 'number' then
        error('assertAlmostEquals: must supply only number arguments.', 2)
    end

    assert(math.abs(expected - actual) > margin,
        'Values are almost equal\n'
            .. 'Expected: ' .. expected .. ' with margin of ' .. margin
            .. ', received: ' .. actual
    )
end

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
