require "defaults"
package.path = "?.lua;common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" .. package.cpath

-- global reader settings
local DataStorage = require("datastorage")
os.remove(DataStorage:getDataDir().."/settings.reader.lua")
local DocSettings = require("docsettings")
G_reader_settings = DocSettings:open(".reader")

-- global einkfb for Screen (do not show SDL window)
einkfb = require("ffi/framebuffer")
einkfb.dummy = true

-- init output device
local Screen = require("device").screen
Screen:init()

-- init input device (do not show SDL window)
local Input = require("device").input
Input.dummy = true

-- turn on debug
--require("dbg"):turnOn()

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
