require "defaults"
package.path = "?.lua;common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so;" .. package.cpath

-- global reader settings
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
local DEBUG = require("dbg")
--DEBUG:turnOn()

-- remove debug hooks in wrapped function for better luacov performance
if LUACOV then
    local function hook_free_call(callback)
        local hook, mask, count = debug.gethook()
        debug.sethook()
        local res = callback()
        debug.sethook(hook, mask)
        return res
    end

    local UIManager = require("ui/uimanager")
    local uimanager_run = UIManager.run
    function UIManager:run()
        hook_free_call(function() return uimanager_run(UIManager) end)
    end

    local screen_shot = Screen.shot
    function Screen:shot(filename)
        hook_free_call(function() return screen_shot(Screen, filename) end)
    end
end
