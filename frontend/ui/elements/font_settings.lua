local Device = require("device")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

--[[ Font settings for desktop linux, mac and android ]]--

local function getDir(isUser)
    local home = Device.home_dir
    if isUser and not home then return end
    if Device:isAndroid() then
        if isUser then
            return home .. "/fonts;" .. home .. "/koreader/fonts"
        else
            return "/system/fonts"
        end
    elseif Device:isDesktop() or Device:isEmulator() then
        if jit.os == "OSX" then
            return isUser and home .. "/Library/fonts" or "/Library/fonts"
        else
            return isUser and home .. "/.local/share/fonts" or "/usr/share/fonts"
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
