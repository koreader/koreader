local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local FontSettings = require("ui/elements/font_settings")
local FontList = require("fontlist")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local BD = require("ui/bidi")
local T = require("ffi/util").template
local _ = require("gettext")

if not G_reader_settings:has("font_ui_custom") then
    G_reader_settings:makeFalse("font_ui_custom")
end
if not G_reader_settings:has("font_ui_custom_font_filenames") then
    G_reader_settings:saveSetting("font_ui_custom_font_filenames", {primary=nil, content=nil, title=nil, monospace=nil})
end
if not G_reader_settings:has("font_ui_custom_font_size_offsets") then
    G_reader_settings:saveSetting("font_ui_custom_font_size_offsets", {primary=0, content=0, title=0, monospace=0})
end

local custom_filenames = {}
local custom_offsets = {}
local custom_fonts = {}
local all_fonts = {}
local preview_fonts = {
    primary = "smallinfofont", -- default for top menu
    title = "smalltfont",
    content = "cfont",
    monospace = "infont"
}

local function getFontEntryByFilename(new_filename)
    return {
        name = FontList:getLocalizedFontName(new_filename) or new_filename,
        filename = new_filename,
        from_file = true, -- don't know if it's bold or mono
    }
end

local function saveFont(category, font, use_bold)
    if use_bold then
        custom_filenames[category] = font and (font.bold_filename or font.filename)
    else
        custom_filenames[category] = font and font.filename
    end
    custom_fonts[category] = font
    local copy = {}
    for k,v in pairs(custom_filenames) do copy[k] = v end
    G_reader_settings:saveSetting("font_ui_custom_font_filenames", copy)
end

local function saveOffset(category, offset)
    custom_offsets[category] = offset or 0
    local copy = {}
    for k,v in pairs(custom_offsets) do copy[k] = v end
    G_reader_settings:saveSetting("font_ui_custom_font_size_offsets", copy)
end

-- font size for preview
local function prevSize(face, offset)
    -- we can't use the size arg from font_func because it's based on possibly outdated font metrics
    local size = Font:getFace(face or "smallinfofont", nil, nil, true).orig_size
    size = size + (offset or 0)
    if size < 8 then size = 8 end
    if size > 40 then size = 40 end
    return size
end

local function genFontSelectMenu(category)
    local select_menu = {}
    local show_bold = custom_fonts[category] and (custom_fonts[category].bold_filename == custom_filenames[category])
    table.insert(select_menu, {
        text_func = function()
            if category == "content" or category == "title" then
                return _("Same setting as primary font")
            end
            return _("Default")
        end,
        font_func = function()
            if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                if (category == "content" or category == "title") and custom_filenames.primary then
                    return Font:getFace(custom_filenames.primary, prevSize(preview_fonts[category], 0))
                end
                return Font:getFace(preview_fonts[category], prevSize(preview_fonts[category], 0), nil, true)
            end
        end,
        checked_func = function()
            return custom_filenames[category] == nil
        end,
        callback = function()
            saveFont(category, nil)
        end,
    })

    local tmi
    -- appending "/..." makes the browser open inside the dir since it expects a file
    local default_path = (FontSettings:getPath() or FontList.fontdir or "") .. "/..."
    local filemanager_callback = function(new_path)
        if new_path == default_path then
            -- user pressed "use default"
            saveFont(category, nil)
        else
            -- truetype needs a relative path for fonts in the koreader fonts dir
            -- NOTE: on the emulator, this will be an invalid path unless you choose from the debug dir
            local adjusted_path = string.gsub(new_path, "^"..DataStorage:getFullDataDir(), "%.")
            if Font:getFace(adjusted_path) then
                local new_entry = getFontEntryByFilename(adjusted_path)
                table.insert(all_fonts, new_entry)
                saveFont(category, new_entry)
            else
                UIManager:show(InfoMessage:new{
                    text = T(_("The chosen file is not a supported font file, or it is not in KOReader's or your system's fonts folders. To install fonts, put them in %1"), BD.wrap(string.gsub(FontList.fontdir, "^%.", DataStorage:getFullDataDir())))
                })
            end
        end
        if tmi then tmi:updateItems() end
    end
    table.insert(select_menu, {
        text = _("Choose file"),
        callback = function(touchmenu_instance)
            tmi = touchmenu_instance -- we might (always?) finish before filemanager_callback
            filemanagerutil.showChooseDialog(_("Current font file:"), filemanager_callback, custom_filenames[category], default_path, function() return true end)
            if tmi then tmi:updateItems() end
        end,
        keep_menu_open = true
    })

    table.insert(select_menu, {
        text = _("Show bold variants"),
        checked_func = function()
            return show_bold
        end,
        callback = function(touchmenu_instance)
            show_bold = not show_bold
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        separator = true
    })
    local get_filename = function(font, use_bold) return (use_bold and font.bold_filename) or font.filename end

    -- first, show the current font so it's easy to switch regular<->bold
    local curfont = custom_fonts[category]
    if not curfont and (category == "title" or category == "content") then
        curfont = custom_fonts.primary
    end
    if curfont then
        table.insert(select_menu, {
            ignored_by_menu_search = true,
            text = curfont.name,
            font_func = function()
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    return Font:getFace(get_filename(curfont, show_bold), prevSize(nil, 0))
                end
            end,
            checked_func = function()
                return custom_filenames[category] == get_filename(curfont, show_bold)
            end,
            callback = function()
                saveFont(category, curfont, show_bold)
            end,
            enabled_func = function()
                -- no bold available -> grayed out
                return curfont.from_file or not show_bold or curfont.bold_filename ~= nil
            end,
            separator = true
        })
    end

    for i, font in ipairs(all_fonts) do
        if font.from_file then goto continue end
        if category == "monospace" and not font.is_monospace then goto continue end
        table.insert(select_menu, {
            ignored_by_menu_search = true,
            text = font.name,
            font_func = function()
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    return Font:getFace(get_filename(font, show_bold), prevSize(nil, 0))
                end
            end,
            checked_func = function()
                return custom_filenames[category] == get_filename(font, show_bold)
            end,
            callback = function()
                saveFont(category, font, show_bold)
            end,
            enabled_func = function()
                -- no bold available -> grayed out
                return not show_bold or font.bold_filename ~= nil
            end,
        })
        ::continue::
    end

    return select_menu
end

local function genAdjustMenuItem(category)
    return {
        text_func = function()
            local str
            if custom_offsets[category] and custom_offsets[category] ~= 0 then
                str = string.format("(%+.2g)", custom_offsets[category])
            else
                str = ""
            end
            return T(_("Adjust size %1"), BD.wrap(str))
        end,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new {
                title_text = _("Font Size Offset"),
                value = custom_offsets[category] or 0,
                value_min = -10,
                value_max = 15,
                -- rounding is too wonky with fractional sizes
                value_step = 1,
                precision = "%+.2g",
                value_hold_step = 4,
                default_value = 0,
                keep_shown_on_apply = true,
                callback = function(spin)
                    saveOffset(category, spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
        font_func = function()
            return Font:getFace("smallinfofont", nil, nil, true) -- always default
        end,
        enabled_func = function()
            if (category == "title" or category == "content") and not custom_filenames[category] then
                return false
            end
            return G_reader_settings:isTrue("font_ui_custom")
        end,
        keep_menu_open = true,
        separator = true,
    }
end

-- Table of font files for each customizable font category
-- make a shallow copy to avoid non-obviously modifying a global setting by reference
local global = G_reader_settings:readSetting("font_ui_custom_font_filenames")
if global then
    for k,v in pairs(G_reader_settings:readSetting("font_ui_custom_font_filenames")) do
        custom_filenames[k] = v
    end
end
-- Table of font size offsets to adjust fonts which are too big or small by default
for k,v in pairs(G_reader_settings:readSetting("font_ui_custom_font_size_offsets")) do
    custom_offsets[k] = v
end

-- Build a list of info about available fonts
local cre = require("document/credocument"):engineInit()
for i, face in ipairs(cre.getFontFaces()) do
    local filename, faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(face)
    if not filename then
        filename, faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(face, nil, true)
    end
    if not filename then goto continue end

    local name = FontList:getLocalizedFontName(filename, faceindex) or face
    local entry = {
        name = name,
        filename = filename,
        -- faceindex = faceindex,
        is_monospace = is_monospace
    }
    -- get bold too, if it exists
    local bold_filename = cre.getFontFaceFilenameAndFaceIndex(face, true)
    if not bold_filename then
        bold_filename = cre.getFontFaceFilenameAndFaceIndex(face, true, true)
    end
    if bold_filename ~= entry.filename then
        entry.bold_filename = bold_filename
        -- entry.bold_faceindex = bold_faceindex
    end

    for category, curfilename in pairs(custom_filenames) do
        if curfilename == entry.filename or curfilename == entry.bold_filename then
            -- for use in the menus
            custom_fonts[category] = entry
        end
    end
    table.insert(all_fonts, entry)
    ::continue::
end

-- also track any filenames previously chosen by file
for category, filename in pairs(custom_filenames) do
    if filename and not custom_fonts[category] then
        -- font was added by file
        local new_entry = getFontEntryByFilename(filename)
        custom_fonts[category] = new_entry
        table.insert(all_fonts, new_entry)
    end
end

return {
    text = _("UI fonts"),
    sub_item_table = {
        {
            text = _("Custom UI fonts"),
            checked_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("font_ui_custom")
                if not G_reader_settings:isTrue("font_ui_custom") then
                    UIManager:askForRestart()
                end
            end,
            help_text = _([[
Primary: Top menu, info messages, status bar.
Title: Various headings.
Content: Buttons, bottom menu, miscellaneous.
Mono: Keyboard keys, terminal.

You can adjust fonts that look too big or small, but text may still be resized to fit the UI. To change the size of the whole UI instead, go to Gear → Screen → Screen DPI.
                ]])
        },
        {
            text = _("Apply and restart KOReader"),
            callback = function()
                UIManager:askForRestart(_("Are you sure you want to restart KOReader?"))
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            keep_menu_open = true,
            separator = true,
        },
        {
            text_func = function()
                local name = custom_fonts.primary and custom_fonts.primary.name
                return T(_("Primary font: %1"), BD.wrap(name or _("Default")))
            end,
            font_func = function()
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if custom_filenames.primary or custom_offsets.primary ~= 0 then
                        local ret = Font:getFace(custom_filenames.primary or preview_fonts.primary, prevSize(preview_fonts.primary, custom_offsets.primary), nil, not custom_filenames.primary)
                        return  ret
                    else
                        return Font:getFace(preview_fonts.primary, prevSize(preview_fonts.primary, 0), nil, true)
                    end
                end
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            sub_item_table_func = function() return genFontSelectMenu("primary") end,
        },
        genAdjustMenuItem("primary"),
        {
            text_func = function()
                local name = custom_fonts.title and custom_fonts.title.name
                return T(_("Title font: %1"), BD.wrap(name or _("Same setting as primary font")))
            end,
            font_func = function()
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if custom_filenames.title then
                        return Font:getFace(custom_filenames.title, prevSize(preview_fonts.title, custom_offsets.title))
                    elseif custom_filenames.primary or custom_offsets.primary ~= 0 then
                        return Font:getFace(custom_filenames.primary or preview_fonts.title, prevSize(preview_fonts.primary, custom_offsets.primary), nil, not custom_filenames.primary)
                    else
                        return Font:getFace(preview_fonts.title, nil, nil, true)
                    end
                end
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            sub_item_table_func = function() return genFontSelectMenu("title") end,
        },
        genAdjustMenuItem("title"),
        {
            text_func = function()
                local name = custom_fonts.content and custom_fonts.content.name
                return T(_("Content font: %1"), BD.wrap(name or _("Same setting as primary font")))
            end,
            font_func = function()
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if custom_filenames.content then
                        return Font:getFace(custom_filenames.content, prevSize(preview_fonts.content, custom_offsets.content))
                    elseif custom_filenames.primary or custom_offsets.primary ~= 0 then
                        return Font:getFace(custom_filenames.primary or preview_fonts.content, prevSize(preview_fonts.primary, custom_offsets.primary), nil, not custom_filenames.primary)
                    else
                        return Font:getFace(preview_fonts.content, nil, nil, true)
                    end
                end
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            sub_item_table_func = function() return genFontSelectMenu("content") end,
        },
        genAdjustMenuItem("content"),
        {
            text_func = function()
                local name = custom_fonts.monospace and custom_fonts.monospace.name
                return T(_("Monospace font: %1"), BD.wrap(name or _("Default")))
            end,
            font_func = function()
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if custom_filenames.monospace or custom_offsets.monospace ~= 0 then
                        return Font:getFace(custom_filenames.monospace or preview_fonts.monospace, prevSize(preview_fonts.monospace, custom_offsets.monospace), nil, not custom_filenames.monospace)
                    else
                        return Font:getFace(preview_fonts.monospace, nil, nil, true)
                    end
                end
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            sub_item_table_func = function() return genFontSelectMenu("monospace") end,
        },
        genAdjustMenuItem("monospace"),
        {
            text = _("Reset"),
            callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = _("Reset all fonts and size adjustments?"),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        for k,v in pairs(custom_filenames) do
                            saveFont(k,nil)
                        end
                        for k,v in pairs(custom_offsets) do
                            saveOffset(k,0)
                        end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
            enabled_func = function()
                return G_reader_settings:isTrue("font_ui_custom")
            end,
            keep_menu_open = true
        },
        -- {
        --     text = "Test",
        --     callback = function()
        --         logger.dbg("custom_filenames:",custom_filenames)
        --         logger.dbg("custom_fonts:",custom_fonts)
        --         logger.dbg("custom_offsets:",custom_offsets)
        --     end,
        --     keep_menu_open = true
        -- },
    }
}
