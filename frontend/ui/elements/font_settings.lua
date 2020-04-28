local Device = require("device")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

--[[ Font settings for desktop linux, mac and android ]]--

local ANDROID_SYSTEM_FONT_DIR = "/system/fonts"
local LINUX_SYSTEM_FONT_DIR = "/usr/share/fonts"
local DESKTOP_USER_FONT_DIR = "/.local/share/fonts"

-- get primary storage on Android
local function getAndroidPrimaryStorage()
    local A, android = pcall(require, "android")
    if not A then return end
    local path = android.getExternalStoragePath()
    if path ~= "Unknown" then
        -- use the external storage identified by the app
        return path
    else
        -- unable to identify external storage. Use defaults
        return "/sdcard"
    end
end

-- user font path, should be rw. On linux/mac it goes under $HOME.
-- on Android it goes in the primary storage (internal/sd)
local function getUserDir()
    if Device:isDesktop() or Device:isEmulator() then
        local home = os.getenv("HOME")
        if home then return home..DESKTOP_USER_FONT_DIR end
    elseif Device:isAndroid() then
        local p = getAndroidPrimaryStorage()
        return p.."/koreader/fonts;"..p.."/fonts"
    end
end

-- system (ttf) fonts are available on linux and android but not on mac
local function getSystemDir()
    if Device:isDesktop() or Device:isEmulator() then
        if util.pathExists(LINUX_SYSTEM_FONT_DIR) then
            return LINUX_SYSTEM_FONT_DIR
        else return nil end
    elseif Device:isAndroid() then
        return ANDROID_SYSTEM_FONT_DIR
    end
end

local function usesSystemFonts()
    return G_reader_settings:isTrue("system_fonts")
end

local function openFontDir()
    if not Device:canOpenLink() then return end
    local user_dir = getUserDir()
    local openable = util.pathExists(user_dir)
    if not openable and user_dir then
        logger.info("Font path not found, making one in ", user_dir)
        openable = util.makePath(user_dir)
    end
    if not openable then
        logger.warn("Unable to create the folder ", user_dir)
        return
    end
    Device:openLink(user_dir)
end

local FontSettings = {}

function FontSettings:getPath()
    if usesSystemFonts() then
        local system_path = getSystemDir()
        if system_path ~= nil then
            return getUserDir()..";"..system_path
        end
    end
    return getUserDir()
end

function FontSettings:getSystemFontMenuItems()
    local t = {{
        text = _("Enable system fonts"),
        checked_func = usesSystemFonts,
        callback = function()
            G_reader_settings:saveSetting("system_fonts", not usesSystemFonts())
            local UIManager = require("ui/uimanager")
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("This will take effect on next restart.")
            })
        end,
    }}

    if Device:isDesktop() or Device:isEmulator() then table.insert(t, 2, {
            text = _("Open fonts folder"),
            keep_menu_open = true,
            callback = openFontDir,
        })
    end

    return t
end

return FontSettings
