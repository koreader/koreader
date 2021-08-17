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

-- Apply the JIT opt tweaks ASAP when the C BB is disabled,
-- because we want to avoid the jit.flush() from bb:enableCBB,
-- which only makes the mcode allocation issues worse on Android...
local is_cbb_enabled = G_reader_settings:nilOrFalse("dev_no_c_blitter")
if not is_cbb_enabled then
    jit.opt.start("loopunroll=45")
end

local lang_locale = G_reader_settings:readSetting("language")
-- Allow quick switching to Arabic for testing RTL/UI mirroring
if os.getenv("KO_RTL") then lang_locale = "ar_AA" end
local _ = require("gettext")
if lang_locale then
    _.changeLang(lang_locale)
end

-- Try to turn the C blitter on/off, and synchronize setting so that UI config reflects real state
local bb = require("ffi/blitbuffer")
bb:setUseCBB(is_cbb_enabled)
is_cbb_enabled = bb:enableCBB(G_reader_settings:nilOrFalse("dev_no_c_blitter"))
G_reader_settings:saveSetting("dev_no_c_blitter", not is_cbb_enabled)

-- Should check DEBUG option in arg and turn on DEBUG before loading other
-- modules, otherwise DEBUG in some modules may not be printed.
local dbg = require("dbg")
if G_reader_settings:isTrue("debug") then dbg:turnOn() end
if G_reader_settings:isTrue("debug") and G_reader_settings:isTrue("debug_verbose") then dbg:setVerbose(true) end

-- Option parsing:
local longopts = {
    debug = "d",
    verbose = "d",
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
    print("If you don't pass any path, the File Manager will be opened")
    print("")
    print("This software is licensed under the AGPLv3.")
    print("See http://github.com/koreader/koreader for more info.")
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

local lfs = require("libs/libkoreader-lfs")
local file
local directory
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
        -- not a recognized option, should be a filename or directory
        local sanitized_path = getPathFromURI(arg)
        local mode = lfs.attributes(sanitized_path, "mode")
        if mode == "file" then
            file = sanitized_path
        elseif mode == "directory" or mode == "link" then
            directory = sanitized_path
        end
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
-- Ensure the proper rotation on startup.
-- We default to the rotation KOReader closed with.
-- If the rotation is not locked it will be overridden by a book or the FM when opened.
local rotation_mode = G_reader_settings:readSetting("closed_rotation_mode")
if rotation_mode and rotation_mode ~= Device.screen:getRotationMode() then
    Device.screen:setRotationMode(rotation_mode)
end
-- Dithering
if Device:hasEinkScreen() then
    Device.screen:setupDithering()
    if Device.screen.hw_dithering and G_reader_settings:isTrue("dev_no_hw_dither") then
        Device.screen:toggleHWDithering(false)
    end
    if Device.screen.sw_dithering and G_reader_settings:isTrue("dev_no_sw_dither") then
        Device.screen:toggleSWDithering(false)
    end
    -- NOTE: If device can HW dither (i.e., after setupDithering(), hw_dithering is true, but sw_dithering is false),
    --       but HW dither is explicitly disabled, and SW dither enabled, don't leave SW dither disabled (i.e., re-enable sw_dithering)!
    if Device:canHWDither() and G_reader_settings:isTrue("dev_no_hw_dither") and G_reader_settings:nilOrFalse("dev_no_sw_dither") then
        Device.screen:toggleSWDithering(true)
    end
end

-- Document renderers canvas
local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)

-- Handle one time migration stuff (settings, deprecation, ...) in case of an upgrade...
require("ui/data/onetime_migration")

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
    G_reader_settings:makeTrue("color_rendering")
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

-- Get which file to start with
local last_file = G_reader_settings:readSetting("lastfile")
local start_with = G_reader_settings:readSetting("start_with") or "filemanager"

-- Helpers
local function retryLastFile()
    local ConfirmBox = require("ui/widget/confirmbox")
    return ConfirmBox:new{
        text = _("Cannot open last file.\nThis could be because it was deleted or because external storage is still being mounted.\nDo you want to retry?"),
        ok_callback = function()
            if lfs.attributes(last_file, "mode") ~= "file" then
                UIManager:show(retryLastFile())
            end
        end,
        cancel_callback = function()
            start_with = "filemanager"
        end,
    }
end

-- Start app
local exit_code
if file then
    local ReaderUI = require("apps/reader/readerui")
    UIManager:nextTick(function()
        ReaderUI:showReader(file)
    end)
    exit_code = UIManager:run()
elseif directory then
    local FileManager = require("apps/filemanager/filemanager")
    UIManager:nextTick(function()
        FileManager:showFiles(directory)
    end)
    exit_code = UIManager:run()
else
    local QuickStart = require("ui/quickstart")
    if not QuickStart:isShown() then
        start_with = "last"
        last_file = QuickStart:getQuickStart()
    end

    if start_with == "last" and last_file and lfs.attributes(last_file, "mode") ~= "file" then
        UIManager:show(retryLastFile())
        -- no exit code as something else will be run after this.
        UIManager:run()
    end
    if start_with == "last" and last_file then
        local ReaderUI = require("apps/reader/readerui")
        UIManager:nextTick(function()
            -- Instantiate RD
            ReaderUI:showReader(last_file)
        end)
        exit_code = UIManager:run()
    else
        local FileManager = require("apps/filemanager/filemanager")
        local home_dir =
            G_reader_settings:readSetting("home_dir") or Device.home_dir or lfs.currentdir()
        UIManager:nextTick(function()
            -- Instantiate FM
            FileManager:showFiles(home_dir)
        end)
        -- Always open FM modules on top of filemanager, so closing 'em doesn't result in an exit
        -- because of an empty widget stack, and so they can interact with the FM instance as expected.
        if start_with == "history" then
            local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
            UIManager:nextTick(function()
                FileManagerHistory:new{
                    ui = FileManager.instance,
                }:onShowHist()
            end)
        elseif start_with == "favorites" then
            local FileManagerCollection = require("apps/filemanager/filemanagercollection")
            UIManager:nextTick(function()
                FileManagerCollection:new{
                    ui = FileManager.instance,
                }:onShowColl("favorites")
            end)
        elseif start_with == "folder_shortcuts" then
            local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
            UIManager:nextTick(function()
                FileManagerShortcuts:new{
                    ui = FileManager.instance,
                }:onShowFolderShortcutsDialog()
            end)
        end
        exit_code = UIManager:run()
    end
end

-- Exit
local function exitReader()
    -- Exit code can be shoddy on some platforms due to broken library dtors calling _exit(0) from os.exit(N)
    local ko_exit = os.getenv("KO_EXIT_CODE")
    if ko_exit then
        local fo = io.open(ko_exit, "w+")
        fo:write(tostring(exit_code))
        fo:close()
    end

    local ReaderActivityIndicator =
        require("apps/reader/modules/readeractivityindicator")

    -- Save any device settings before closing G_reader_settings
    Device:saveSettings()

    -- Save current rotation (or the original rotation if ScreenSaver temporarily modified it) to remember it for next startup
    G_reader_settings:saveSetting("closed_rotation_mode", Device.orig_rotation_mode or Device.screen:getRotationMode())
    G_reader_settings:close()

    -- Close lipc handles
    ReaderActivityIndicator:coda()

    -- shutdown hardware abstraction
    Device:exit()

    if Profiler then Profiler.stop() end

    if type(exit_code) == "number" then
        return exit_code
    else
        return true
    end
end

local ret = exitReader()
-- Close the Lua state on exit
os.exit(ret, true)
