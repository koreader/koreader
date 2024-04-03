local FFIUtil = require("ffi/util")
local Font = require("ui/font")
local FontList = require("fontlist")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

-- Some "Noto Sans *" fonts are already in ui/font.lua Font.fallbacks,
-- because they are required to display supported UI languages.
-- Don't allow them to be disabled.
-- Duplicated from (and should be kept in sync with) ui/font.lua, but here
-- by face name and there by font file/path name.
local hardcoded_fallbacks = {
    "Noto Sans CJK SC",
    "Noto Sans Arabic UI",
    "Noto Sans Devanagari UI",
    "Noto Sans Bengali UI",
}
-- Add any user font after Noto Sans CJK SC in the menu
local additional_fallback_insert_indice = 2 -- (indice in the above list)

local alt_name = {
    -- Make it clear this "CJK SC" font actually supports all other CJK variant
    ["Noto Sans CJK SC"] = "Noto Sans CJK SC (TC, JA, KO)"
}

local fallback_candidates = nil
local fallback_candidates_path_to_name = nil

local genFallbackCandidates = function()
    if fallback_candidates then
        return
    end
    fallback_candidates = {}
    fallback_candidates_path_to_name = {}
    for _, font_path in ipairs(FontList:getFontList()) do
        local fontinfo = FontList.fontinfo[font_path] -- (NotoColorEmoji.tff happens to get no fontinfo)
        if fontinfo and #fontinfo == 1 then -- Ignore font files with multiple faces
            fontinfo = fontinfo[1]
            if (util.stringStartsWith(fontinfo.name, "Noto Sans ") or
                        fontinfo.name == "Noto Emoji") and
                        not fontinfo.bold and not fontinfo.italic and
                        not fontinfo.serif and not fontinfo.mono then
                fallback_candidates[fontinfo.name] = fontinfo
                fallback_candidates_path_to_name[font_path] = fontinfo.name
            end
        end
    end
end

local more_info_text = T(_([[
If some book titles, dictionary entries and such are not displayed well but shown as %1 or %2, it may be necessary to download the required fonts for those languages. They can then be enabled as additional UI fallback fonts.
Fonts for many languages can be downloaded at:

https://fonts.google.com/noto

Only fonts named "Noto Sans xyz" or "Noto Sans xyz UI" (regular, not bold nor italic, not Serif) will be available in this menu. However, bold fonts will be used if their corresponding regular fonts exist.]]), "￾￾", "��")

local getSubMenuItems = function()
    genFallbackCandidates()
    -- Order the menu items in the order the fallback fonts are used
    local seen_names = {}
    local ordered_names = {}
    local checked_names = {}
    local enabled_names = {}
    for _, name in ipairs(hardcoded_fallbacks) do
        table.insert(ordered_names, name)
        seen_names[name] = true
        checked_names[name] = true
        enabled_names[name] = false
    end
    if G_reader_settings:has("font_ui_fallbacks") then
        local additional_fallbacks = G_reader_settings:readSetting("font_ui_fallbacks")
        for i=#additional_fallbacks, 1, -1 do
            local path = additional_fallbacks[i]
            local name = fallback_candidates_path_to_name[path]
            if not name or seen_names[name] then
                -- No longer found, or made hardcoded: remove it
                table.remove(additional_fallbacks, i)
            else
                table.insert(ordered_names, additional_fallback_insert_indice, name)
                seen_names[name] = true
                checked_names[name] = true
                enabled_names[name] = true
            end
        end
        if #additional_fallbacks == 0 then -- all removed
            G_reader_settings:delSetting("font_ui_fallbacks")
        end
    end
    local add_separator_idx = #ordered_names
    for name, fontinfo in FFIUtil.orderedPairs(fallback_candidates) do
        if not seen_names[name] then
            table.insert(ordered_names, name)
            checked_names[name] = false
            enabled_names[name] = true
        end
    end

    local menu_items = {
        {
            text = _("About additional UI fallback fonts"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = more_info_text,
                })
            end,
            keep_menu_open = true,
            separator = true,
        }
    }
    for idx, name in ipairs(ordered_names) do
        local fontinfo = fallback_candidates[name]
        local item = {
            text = alt_name[name] or name,
            separator = idx == add_separator_idx,
            checked_func = function()
                return checked_names[name]
            end,
            enabled_func = function()
                return enabled_names[name]
            end,
            callback = function()
                local additional_fallbacks = G_reader_settings:readSetting("font_ui_fallbacks", {})
                if checked_names[name] then -- enabled: remove it
                    for i=#additional_fallbacks, 1, -1 do
                        if additional_fallbacks[i] == fontinfo.path then
                            table.remove(additional_fallbacks, i)
                            if #additional_fallbacks == 0 then
                                G_reader_settings:delSetting("font_ui_fallbacks")
                            end
                            break
                        end
                    end
                    checked_names[name] = false
                else -- disabled: add it
                    if #additional_fallbacks < Font.additional_fallback_max_nb then
                        table.insert(additional_fallbacks, 1, fontinfo.path)
                        checked_names[name] = true
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("The number of allowed additional fallback fonts is limited to %1.\nUncheck some of them if you want to add this one."), Font.additional_fallback_max_nb),
                        })
                        return
                    end
                end
                UIManager:askForRestart()
            end,
        }
        table.insert(menu_items, item)
    end
    return menu_items
end

return {
    text = _("Additional UI fallback fonts"),
    sub_item_table_func = getSubMenuItems,
}
