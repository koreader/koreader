local Device = require("device")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

--[[ Font settings for desktop linux and mac ]]--

local function getUserDir()
    local home = os.getenv("HOME")
    if home then
        return home.."/.local/share/fonts"
    end
end

-- System fonts are common in linux
local function getSystemDir()
    local path = "/usr/share/fonts"
    if util.pathExists(path) then
        return path
    else
        -- mac doesn't use ttf fonts
        return nil
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

function FontSettings:getMenuTable()
    return {
        text = _("Font settings"),
        separator = true,
        sub_item_table = {
            {
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
            },
            {
                text = _("Open fonts folder"),
                keep_menu_open = true,
                callback = openFontDir,
            },
        }
    }
end

return FontSettings
