#!./koreader-base

require "libs/libkoreader-lfs"
einkfb = require("ffi/framebuffer")
input = require("ffi/input")
freetype = require("ffi/freetype")
Image = require("ffi/mupdfimg")

require "defaults"
package.path = "?.lua;common/?.lua;frontend/?.lua"
package.cpath = "?.so;common/?.so;/usr/lib/lua/?.so"

local DocSettings = require("docsettings")
local _ = require("gettext")
local util = require("ffi/util")

-- read settings and check for language override
-- has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = DocSettings:open(".reader")
local lang_locale = G_reader_settings:readSetting("language")
if lang_locale then
    _.changeLang(lang_locale)
end

local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local InfoMessage = require("ui/widget/infomessage")
local DocumentRegistry = require("document/documentregistry")
local DEBUG = require("dbg")
local Device = require("ui/device")
local Screen = require("ui/screen")

local ReaderUI = require("apps/reader/readerui")

local Profiler = nil

function exitReader()
    G_reader_settings:close()

    input.closeAll()

    if not util.isEmulated() then
        if Device:isKindle3() or (Device:getModel() == "KindleDXG") then
            -- send double menu key press events to trigger screen refresh
            os.execute("echo 'send 139' > /proc/keypad;echo 'send 139' > /proc/keypad")
        end
        if Device:isTouchDevice() and Device.survive_screen_saver then
            -- hack the swipe to unlock screen
            local dev = Device:getTouchInputDev()
            if dev then
                local width, height = Screen:getWidth(), Screen:getHeight()
                input.fakeTapInput(dev,
                    math.min(width, height)/2,
                    math.max(width, height)-30
                )
            end
        end
    end

    if Profiler then Profiler.stop() end
    os.exit(0)
end

function showReaderUI(file, pass)
    DEBUG("opening file", file)
    if lfs.attributes(file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = _("File does not exist")
        })
        return
    end
    UIManager:show(InfoMessage:new{
        text = _("Opening file") .. file,
        timeout = 1,
    })
    UIManager:scheduleIn(0.1, function() doShowReaderUI(file, pass) end)
end

function doShowReaderUI(file, pass)
    local document = DocumentRegistry:openDocument(file)
    if not document then
        UIManager:show(InfoMessage:new{
            text = _("No reader engine for this file")
        })
        return
    end

    G_reader_settings:saveSetting("lastfile", file)
    local reader = ReaderUI:new{
        dialog = readerwindow,
        dimen = Screen:getSize(),
        document = document,
        password = pass
    }
    UIManager:show(reader)
end

function showHomePage(path)
    local FileManager = require("apps/filemanager/filemanager")
    UIManager:show(FileManager:new{
        dimen = Screen:getSize(),
        root_path = path,
        onExit = function()
            exitReader()
            UIManager:quit()
        end
    })
end

-- option parsing:
local longopts = {
    debug = "d",
    profile = "p",
    help = "h",
}

function showusage()
    print("usage: ./reader.lua [OPTION] ... path")
    print("Read all the books on your E-Ink reader")
    print("")
    print("-d               start in debug mode")
    print("-p [rows]        enable Lua code profiling")
    print("-h               show this usage help")
    print("")
    print("If you give the name of a directory instead of a file path, a file")
    print("chooser will show up and let you select a file")
    print("")
    print("If you don't pass any path, the last viewed document will be opened")
    print("")
    print("This software is licensed under the GPLv3.")
    print("See http://github.com/koreader/koreader for more info.")
    return
end

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
    elseif arg == "-p" then
        Profiler = require("jit.p")
        Profiler.start("la")
    else
        -- not a recognized option, should be a filename
        argidx = argidx - 1
        break
    end
end

if Device:hasNoKeyboard() then
    -- remove menu item shortcut for K4
    Menu.is_enable_shortcut = false
end

-- read some global reader setting here:
-- font
local fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
    Font.fontmap = fontmap
end
-- last file
local last_file = G_reader_settings:readSetting("lastfile")


--@TODO we can read version here, refer to commit in master tree:   (houqp)
--87712cf0e43fed624f8a9f610be42b1fe174b9fe

do
    local powerd = Device:getPowerDevice()
    if powerd and powerd.restore_settings then
        local intensity = G_reader_settings:readSetting("frontlight_intensity")
        intensity = intensity or powerd.flIntensity
        powerd:setIntensityWithoutHW(intensity)
        -- powerd:setIntensity(intensity)
    end
end

if ARGV[argidx] and ARGV[argidx] ~= "" then
    if lfs.attributes(ARGV[argidx], "mode") == "directory" then
        showHomePage(ARGV[argidx])
    else
        showReaderUI(ARGV[argidx])
    end
    UIManager:run()
elseif last_file then
    showReaderUI(last_file)
    UIManager:run()
else
    return showusage()
end

exitReader()
