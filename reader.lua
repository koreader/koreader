#!./luajit
io.stdout:write([[
---------------------------------------------
                launching...
  _  _____  ____                _
 | |/ / _ \|  _ \ ___  __ _  __| | ___ _ __
 | ' / | | | |_) / _ \/ _` |/ _` |/ _ \ '__|
 | . \ |_| |  _ <  __/ (_| | (_| |  __/ |
 |_|\_\___/|_| \_\___|\__,_|\__,_|\___|_|

 It's a scroll... It's a codex... It's KOReader!

 [*] Current time: ]], os.date("%x-%X"), "\n")
io.stdout:flush()

-- Load default settings
require("defaults")
local DataStorage = require("datastorage")
pcall(dofile, DataStorage:getDataDir() .. "/defaults.persistent.lua")

-- Set up Lua and ffi search paths
require("setupkoenv")

io.stdout:write(" [*] Version: ", require("version"):getCurrentRevision(), "\n\n")
io.stdout:flush()

-- Read settings and check for language override
-- Has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir().."/settings.reader.lua")
local lang_locale = G_reader_settings:readSetting("language")
-- Allow quick switching to Arabic for testing RTL/UI mirroring
if os.getenv("KO_RTL") then lang_locale = "ar_AA" end
local _ = require("gettext")
if lang_locale then
    _.changeLang(lang_locale)
end

-- Make the C blitter optional (ffi/blitbuffer.lua will check that env var)
local ffi = require("ffi")
local dummy = require("ffi/posix_h")
local C = ffi.C
if G_reader_settings:isTrue("dev_no_c_blitter") then
    if ffi.os == "Windows" then
        C._putenv("KO_NO_CBB=true")
    else
        C.setenv("KO_NO_CBB", "true", 1)
    end
else
    if ffi.os == "Windows" then
        C._putenv("KO_NO_CBB=false")
    else
        C.unsetenv("KO_NO_CBB")
    end
end

-- Should check DEBUG option in arg and turn on DEBUG before loading other
-- modules, otherwise DEBUG in some modules may not be printed.
local dbg = require("dbg")
if G_reader_settings:isTrue("debug") then dbg:turnOn() end
if G_reader_settings:isTrue("debug") and G_reader_settings:isTrue("debug_verbose") then dbg:setVerbose(true) end

-- Option parsing:
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

-- Setup device
local Device = require("device")
-- DPI
local dpi_override = G_reader_settings:readSetting("screen_dpi")
if dpi_override ~= nil then
    Device:setScreenDPI(dpi_override)
end
-- Night mode
if G_reader_settings:isTrue("night_mode") then
    Device.screen:toggleNightMode()
end
-- Dithering
if Device:hasEinkScreen() then
    Device.screen:setupDithering()
    if Device.screen.hw_dithering and G_reader_settings:isTrue("dev_no_hw_dither") then
        Device.screen:toggleHWDithering()
    end
    if Device.screen.sw_dithering and G_reader_settings:isTrue("dev_no_sw_dither") then
        Device.screen:toggleSWDithering()
    end
end

-- Handle global settings migration
local SettingsMigration = require("ui/data/settings_migration")
SettingsMigration:migrateSettings(G_reader_settings)

-- Document renderers canvas
local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)

-- Touch screen (this may display some widget, on first install on Kobo Touch,
-- so have it done after CanvasContext:init() but before Bidi.setup() to not
-- have mirroring mess x/y probing).
if Device:needsTouchScreenProbe() then
    Device:touchScreenProbe()
end

-- UI mirroring for RTL languages, and text shaping configuration
local Bidi = require("ui/bidi")
Bidi.setup(lang_locale)
-- Avoid loading UIManager and widgets before here, as they may
-- cache Bidi mirroring settings. Check that with:
-- for name, _ in pairs(package.loaded) do print(name) end

-- User fonts override
local fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
    local Font = require("ui/font")
    for k, v in pairs(fontmap) do
        Font.fontmap[k] = v
    end
end

local UIManager = require("ui/uimanager")

-- Inform once about color rendering on newly supported devices
-- (there are some android devices that may not have a color screen,
-- and we are not (yet?) able to guess that fact)
if Device:hasColorScreen() and not G_reader_settings:has("color_rendering") then
    -- enable it to prevent further display of this message
    G_reader_settings:saveSetting("color_rendering", true)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Documents will be rendered in color on this device.\nIf your device is grayscale, you can disable color rendering in the screen sub-menu for reduced memory usage."),
    })
end

-- Conversely, if color is enabled on a Grayscale screen (e.g., after importing settings from a color device), warn that it'll break stuff and adversely affect performance.
if G_reader_settings:isTrue("color_rendering") and not Device:hasColorScreen() then
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = _("Color rendering is mistakenly enabled on your grayscale device.\nThis will subtly break some features, and adversely affect performance."),
        cancel_text = _("Ignore"),
        cancel_callback = function()
                return
        end,
        ok_text = _("Disable"),
        ok_callback = function()
                local Event = require("ui/event")
                G_reader_settings:delSetting("color_rendering")
                CanvasContext:setColorRenderingEnabled(false)
                UIManager:broadcastEvent(Event:new("ColorRenderingUpdate"))
        end,
    })
end

-- Helpers
local lfs = require("libs/libkoreader-lfs")
local function retryLastFile()
    local ConfirmBox = require("ui/widget/confirmbox")
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

local function getPathFromURI(str)
    local hexToChar = function(x)
        return string.char(tonumber(x, 16))
    end

    local unescape = function(url)
       return url:gsub("%%(%x%x)", hexToChar)
    end

    local prefix = "file://"
    if str:sub(1, #prefix) ~= prefix then
        return str
    end
    return unescape(str):sub(#prefix+1)
end

-- Get which file to start with
local last_file = G_reader_settings:readSetting("lastfile")
local start_with = G_reader_settings:readSetting("start_with")
local open_last = start_with == "last"

if open_last and last_file and lfs.attributes(last_file, "mode") ~= "file" then
    UIManager:show(retryLastFile())
    last_file = nil
else
    local QuickStart = require("ui/quickstart")
    if not QuickStart:isShown() then
        open_last = true
        last_file = QuickStart:getQuickStart()
    end
end

-- Start app
local exit_code
if ARGV[argidx] and ARGV[argidx] ~= "" then
    local file
    local sanitized_path = getPathFromURI(ARGV[argidx])
    if lfs.attributes(sanitized_path, "mode") == "file" then
        file = sanitized_path
    elseif open_last and last_file then
        file = last_file
    end
    -- if file is given in command line argument or open last document is set
    -- true, the given file or the last file is opened in the reader
    if file and file ~= "" then
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
        elseif start_with == "folder_shortcuts" then
            local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
            UIManager:nextTick(function()
                FileManagerShortcuts:new{
                    ui = FileManager.instance,
                }:onShowFolderShortcutsDialog()
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

-- Exit
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
