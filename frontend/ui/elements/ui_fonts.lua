local Font = require("ui/font")
local FontList = require("fontlist")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local UIFonts = {}

-- Helper to get font name from filename
local function getFontName(filename)
    FontList:getFontList()
    for path, info in pairs(FontList.fontinfo) do
        if path:match("([^/]+)$") == filename then
            return info[1] and info[1].name or filename
        end
    end
    if filename == "NotoSans-Regular.ttf" then return "Noto Sans" end
    if filename == "NotoSans-Bold.ttf" then return "Noto Sans Bold" end
    return filename
end

-- Helper for menu text with brackets
local function getMenuText(label, font_file)
    local name = getFontName(font_file)
    return T("%1 (%2)", label, name)
end

function UIFonts:getFontTable(setting_name, default_file)
    local menu_items = {
        {
            text_func = function()
                local name = getFontName(default_file)
                return T(_("Default (%1)"), name)
            end,
            checked_func = function() return not G_reader_settings:has(setting_name) end,
            callback = function()
                G_reader_settings:delSetting(setting_name)
                UIManager:askForRestart()
            end,
        },
    }

    for _, font_path in ipairs(FontList:getFontList()) do
        local font_info = FontList.fontinfo[font_path]
        if font_info and font_info[1] then
            local font_file = font_path:match("([^/]+)$")
            local display_file = #font_file > 20 and ("..." .. font_file:sub(-17)) or font_file
            table.insert(menu_items, {
                text = T("%1 (%2)", font_info[1].name, display_file),
                checked_func = function() return G_reader_settings:readSetting(setting_name) == font_file end,
                callback = function()
                    G_reader_settings:saveSetting(setting_name, font_file)
                    UIManager:askForRestart()
                end,
            })
        end
    end
    return menu_items
end

function UIFonts:getSettingsMenuTable()
    local reg_def = Font.DEFAULT_UI_FONT_REGULAR
    local bold_def = Font.DEFAULT_UI_FONT_BOLD
    return {
        {
            text_func = function()
                return getMenuText(_("Regular font"), G_reader_settings:readSetting("ui_font_regular") or reg_def)
            end,
            sub_item_table_func = function() return self:getFontTable("ui_font_regular", reg_def) end,
        },
        {
            text_func = function()
                return getMenuText(_("Bold font"), G_reader_settings:readSetting("ui_font_bold") or bold_def)
            end,
            sub_item_table_func = function() return self:getFontTable("ui_font_bold", bold_def) end,
        },
    }
end

return UIFonts
