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
DEBUG:turnOn()
