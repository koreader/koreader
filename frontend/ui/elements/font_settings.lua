local Device = require("device")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

--[[ Font settings for systems with multiple font dirs ]]--

local function getDir(isUser)
    local home = Device.home_dir

    local XDG_DATA_HOME = os.getenv("XDG_DATA_HOME")
    local LINUX_FONT_PATH = XDG_DATA_HOME and XDG_DATA_HOME .. "/fonts"
                                           or home .. "/.local/share/fonts"
    local LINUX_SYS_FONT_PATH = "/usr/share/fonts"
    local MACOS_FONT_PATH = "Library/fonts"

    if isUser and not home then return end

    if Device:isAndroid() then
        return isUser and home .. "/fonts;" .. home .. "/koreader/fonts"
                       or "/system/fonts"
    elseif Device:isPocketBook() then
        return isUser and "/mnt/ext1/system/fonts"
                       or "/ebrmain/adobefonts;/ebrmain/fonts"
    elseif Device:isRemarkable() then
        return isUser and LINUX_FONT_PATH
                       or LINUX_SYS_FONT_PATH
    elseif Device:isDesktop() or Device:isEmulator() then
        if jit.os == "OSX" then
            return isUser and home .. "/" .. MACOS_FONT_PATH
                           or "/" .. MACOS_FONT_PATH
        else
            return isUser and LINUX_FONT_PATH
                           or LINUX_SYS_FONT_PATH
        end
    end
end

local function openFontDir()
    if not Device:canOpenLink() then return end
    local user_dir = getDir(true)
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

local function usesSystemFonts()
    return G_reader_settings:isTrue("system_fonts")
end

local FontSettings = {}

function FontSettings:getPath()
    local user, system = getDir(true), getDir()
    if usesSystemFonts() then
        if user and system then
            return user .. ";" .. system
        elseif system then
            return system
        end
    end
    return user
end

function FontSettings:getSystemFontMenuItems()
    local t = {{
        text = _("Enable system fonts"),
        checked_func = usesSystemFonts,
        callback = function()
            G_reader_settings:saveSetting("system_fonts", not usesSystemFonts())
            local UIManager = require("ui/uimanager")
            UIManager:askForRestart()
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
