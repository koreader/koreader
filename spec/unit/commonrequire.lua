require "defaults"
package.path = "?.lua;common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" .. package.cpath

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

-- turn off debug by default and set log level to warning
package.reload("dbg"):turnOff()
local logger = package.reload("logger")
logger:setLevel(logger.levels.warn)

-- global reader settings
local DataStorage = package.reload("datastorage")
os.remove(DataStorage:getDataDir().."/settings.reader.lua")
local DocSettings = package.reload("docsettings")
G_reader_settings = package.reload("luasettings"):open(".reader")

-- global einkfb for Screen (do not show SDL window)
einkfb = require("ffi/framebuffer")
einkfb.dummy = true

-- init output device
local Screen = package.reload("device").screen
Screen:init()

-- init input device (do not show SDL window)
local Input = package.reload("device").input
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
