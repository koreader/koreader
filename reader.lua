#!./luajit
io.stdout:write(string.format([[
---------------------------------------------
                launching...
  _  _____  ____                _
 | |/ / _ \|  _ \ ___  __ _  __| | ___ _ __
 | ' / | | | |_) / _ \/ _` |/ _` |/ _ \ '__|
 | . \ |_| |  _ <  __/ (_| | (_| |  __/ |
 |_|\_\___/|_| \_\___|\__,_|\__,_|\___|_|

 [*] Current time: %s
]], os.date("%x-%X")))
io.stdout:flush()


-- load default settings
require "defaults"
local DataStorage = require("datastorage")
pcall(dofile, DataStorage:getDataDir() .. "/defaults.persistent.lua")

-- set search path for 'require()'
package.path =
    "common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" ..
    package.path
package.cpath =
    "common/?.so;common/?.dll;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" ..
    package.cpath

-- set search path for 'ffi.load()'
local ffi = require("ffi")
local util = require("ffi/util")
ffi.cdef[[
    char *getenv(const char *name);
    int putenv(const char *envvar);
    int _putenv(const char *envvar);
]]
if ffi.os == "Windows" then
    ffi.C._putenv("PATH=libs;common;")
end

local _ = require("gettext")
-- read settings and check for language override
-- has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir().."/settings.reader.lua")
local lang_locale = G_reader_settings:readSetting("language")
if lang_locale then
    _.changeLang(lang_locale)
end

-- option parsing:
local longopts = {
    debug = "d",
    profile = "p",
    help = "h",
}

local function showusage()
    print("usage: ./reader.lua [OPTION] ... path")
    print("Read all the books on your E-Ink reader")
    print("")
    print("-d               start in debug mode")
    print("-v               debug in verbose mode")
    print("-p               enable Lua code profiling")
    print("-h               show this usage help")
    print("")
    print("If you give the name of a directory instead of a file path, a file")
    print("chooser will show up and let you select a file")
    print("")
    print("If you don't pass any path, the last viewed document will be opened")
    print("")
    print("This software is licensed under the AGPLv3.")
    print("See http://github.com/koreader/koreader for more info.")
    return
end

-- should check DEBUG option in arg and turn on DEBUG before loading other
-- modules, otherwise DEBUG in some modules may not be printed.
local DEBUG = require("dbg")

local Profiler = nil
local ARGV = arg
local argidx = 1
while argidx <= #ARGV do
    local arg = ARGV[argidx]
    argidx = argidx + 1
    if arg == "--" then break end
    -- parse longopts
    if arg:sub(1,2) == "--" then
        local opt = longopts[arg:sub(3)]
        if opt ~= nil then arg = "-"..opt end
    end
    -- code for each option
    if arg == "-h" then
        return showusage()
    elseif arg == "-d" then
        DEBUG:turnOn()
    elseif arg == "-v" then
        DEBUG:setVerbose(true)
    elseif arg == "-p" then
        Profiler = require("jit.p")
        Profiler.start("la")
    else
        -- not a recognized option, should be a filename
        argidx = argidx - 1
        break
    end
end

local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Font = require("ui/font")

-- read some global reader setting here:
-- font
local fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
    for k, v in pairs(fontmap) do
        Font.fontmap[k] = v
    end
end
-- last file
local last_file = G_reader_settings:readSetting("lastfile")
if last_file and lfs.attributes(last_file, "mode") ~= "file" then
    last_file = nil
end
-- load last opened file
local open_last = G_reader_settings:readSetting("open_last")
-- night mode
if G_reader_settings:readSetting("night_mode") then
    Device.screen:toggleNightMode()
end

-- restore kobo frontlight settings and probe kobo touch coordinates
if Device:isKobo() then
    if Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        if powerd and powerd.restore_settings then
            -- UIManager:init() should have sanely set up the frontlight_stuff by this point
            local intensity = G_reader_settings:readSetting("frontlight_intensity")
            powerd.fl_intensity = intensity or powerd.fl_intensity
            local is_frontlight_on = G_reader_settings:readSetting("is_frontlight_on")
            if is_frontlight_on then
                -- default powerd.is_fl_on is false, turn it on
                powerd:toggleFrontlight()
            else
                -- the light can still be turned on manually outside of KOReader
                -- or Nickel. so we always set the intensity to 0 here to keep it
                -- in sync with powerd.is_fl_on (false by default)
                -- NOTE: we cant use setIntensity method here because for Kobo the
                -- min intensity is 1 :(
                powerd.fl:setBrightness(0)
            end
        end
    end
end

if Device:needsTouchScreenProbe() then
    Device:touchScreenProbe()
end

if ARGV[argidx] and ARGV[argidx] ~= "" then
    local file = nil
    if lfs.attributes(ARGV[argidx], "mode") == "file" then
        file = ARGV[argidx]
    elseif open_last and last_file then
        file = last_file
    end
    -- if file is given in command line argument or open last document is set
    -- true, the given file or the last file is opened in the reader
    if file then
        local ReaderUI = require("apps/reader/readerui")
        UIManager:nextTick(function()
            ReaderUI:showReader(file)
        end)
    -- we assume a directory is given in command line argument
    -- the filemanger will show the files in that path
    else
        local FileManager = require("apps/filemanager/filemanager")
        local home_dir =
            G_reader_settings:readSetting("home_dir") or ARGV[argidx]
        UIManager:nextTick(function()
            FileManager:showFiles(home_dir)
        end)
    end
    UIManager:run()
elseif last_file then
    local ReaderUI = require("apps/reader/readerui")
    UIManager:nextTick(function()
        ReaderUI:showReader(last_file)
    end)
    UIManager:run()
else
    return showusage()
end

local function exitReader()
    local ReaderActivityIndicator =
        require("apps/reader/modules/readeractivityindicator")

    G_reader_settings:close()

    -- Close lipc handles
    ReaderActivityIndicator:coda()

    -- shutdown hardware abstraction
    Device:exit()
    require("ui/network/manager"):turnOffWifi()

    if Profiler then Profiler.stop() end
    os.exit(0)
end

exitReader()
