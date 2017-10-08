#!./luajit
io.stdout:write([[
---------------------------------------------
                launching...
  _  _____  ____                _
 | |/ / _ \|  _ \ ___  __ _  __| | ___ _ __
 | ' / | | | |_) / _ \/ _` |/ _` |/ _ \ '__|
 | . \ |_| |  _ <  __/ (_| | (_| |  __/ |
 |_|\_\___/|_| \_\___|\__,_|\__,_|\___|_|

 [*] Current time: ]], os.date("%x-%X"), "\n\n")
io.stdout:flush()

-- load default settings
require("defaults")
local DataStorage = require("datastorage")
pcall(dofile, DataStorage:getDataDir() .. "/defaults.persistent.lua")

require("setupkoenv")

-- read settings and check for language override
-- has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir().."/settings.reader.lua")
local lang_locale = G_reader_settings:readSetting("language")
local _ = require("gettext")
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
end

-- should check DEBUG option in arg and turn on DEBUG before loading other
-- modules, otherwise DEBUG in some modules may not be printed.
local dbg = require("dbg")
if G_reader_settings:readSetting("debug") then dbg:turnOn() end

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
        dbg:turnOn()
    elseif arg == "-v" then
        dbg:setVerbose(true)
    elseif arg == "-p" then
        Profiler = require("jit.p")
        Profiler.start("la")
    else
        -- not a recognized option, should be a filename
        argidx = argidx - 1
        break
    end
end

local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local QuickStart = require("ui/quickstart")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local function retryLastFile()
    return ConfirmBox:new{
        text = _("Cannot open last file.\nThis could be because it was deleted or because external storage is still being mounted.\nDo you want to retry?"),
        ok_callback = function()
            local last_file = G_reader_settings:readSetting("lastfile")
            if lfs.attributes(last_file, "mode") == "file" then
                local ReaderUI = require("apps/reader/readerui")
                UIManager:nextTick(function()
                    ReaderUI:showReader(last_file)
                end)
            else
                UIManager:show(retryLastFile())
            end
        end,
    }
end

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
local start_with = G_reader_settings:readSetting("start_with")
-- load last opened file
local open_last = start_with == "last"
if open_last and last_file and lfs.attributes(last_file, "mode") ~= "file" then
    UIManager:show(retryLastFile())
    last_file = nil
elseif not QuickStart:isShown() then
    open_last = true
    last_file = QuickStart:getQuickStart()
end
-- night mode
if G_reader_settings:readSetting("night_mode") then
    Device.screen:toggleNightMode()
end

if Device:needsTouchScreenProbe() then
    Device:touchScreenProbe()
end

-- Inform once about color rendering on newly supported devices
-- (there are some android devices that may not have a color screen,
-- and we are not (yet?) able to guess that fact)
if Device.hasColorScreen() and not G_reader_settings:has("color_rendering") then
    -- enable it to prevent further display of this message
    G_reader_settings:saveSetting("color_rendering", true)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Documents will be rendered in color on this device.\nIf your device is grayscale, you can disable color rendering in the screen sub-menu for reduced memory usage."),
    })
end

local exit_code

if ARGV[argidx] and ARGV[argidx] ~= "" then
    local file
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
        -- always open history on top of filemanager so closing history
        -- doesn't result in exit
        if start_with == "history" then
            local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
            UIManager:nextTick(function()
                FileManagerHistory:onShowHist(last_file)
            end)
        end
    end
    exit_code = UIManager:run()
elseif last_file then
    local ReaderUI = require("apps/reader/readerui")
    UIManager:nextTick(function()
        ReaderUI:showReader(last_file)
    end)
    exit_code = UIManager:run()
else
    return showusage()
end

local function exitReader()
    local ReaderActivityIndicator =
        require("apps/reader/modules/readeractivityindicator")

    -- Save any device settings before closing G_reader_settings
    Device:saveSettings()

    G_reader_settings:close()

    -- Close lipc handles
    ReaderActivityIndicator:coda()

    -- shutdown hardware abstraction
    Device:exit()

    if Profiler then Profiler.stop() end

    if type(exit_code) == "number" then
        os.exit(exit_code)
    else
        os.exit(0)
    end
end

exitReader()
