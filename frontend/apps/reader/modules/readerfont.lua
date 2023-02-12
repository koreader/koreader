local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FontList = require("fontlist")
local InfoMessage = require("ui/widget/infomessage")
local Input = Device.input
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local cre -- Delayed loading
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local optionsutil = require("ui/data/optionsutil")

local ReaderFont = InputContainer:extend{
    font_face = nil,
    font_size = nil,
    line_space_percent = nil,
    font_menu_title = _("Font"),
    face_table = nil,
    -- default gamma from crengine's lvfntman.cpp
    gamma_index = nil,
    steps = {0,1,1,1,1,1,2,2,2,3,3,3,4,4,5},
}

function ReaderFont:init()
    self:registerKeyEvents()
    -- Build face_table for menu
    self.face_table = {}
    -- Font settings
    table.insert(self.face_table, {
        text = _("Font settings"),
        sub_item_table = self:getFontSettingsTable(),
    })
    table.insert(self.face_table, {
        text_func = function()
            local nb_family_fonts = 0
            local g_font_family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
            for family, name in pairs(g_font_family_fonts) do
                if self.font_family_fonts[family] then
                    nb_family_fonts = nb_family_fonts + 1
                elseif g_font_family_fonts[family] and self.font_family_fonts[family] ~= false then
                    nb_family_fonts = nb_family_fonts + 1
                end
            end
            if nb_family_fonts > 0 then
                -- @translators 'font-family' is a CSS property name, keep it untranslated
                return T(_("Font-family fonts (%1)"), nb_family_fonts)
            end
            return _("Font-family fonts")
        end,
        sub_item_table_func = function() return self:getFontFamiliesTable() end,
        separator = true,
    })
    -- Font list
    cre = require("document/credocument"):engineInit()
    local face_list = cre.getFontFaces()
    for k, v in ipairs(face_list) do
        local font_filename, font_faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(v)
        table.insert(self.face_table, {
            text_func = function()
                -- defaults are hardcoded in credocument.lua
                local default_font = G_reader_settings:readSetting("cre_font") or self.ui.document.default_font
                local fallback_font = G_reader_settings:readSetting("fallback_font") or self.ui.document.fallback_fonts[1]
                local monospace_font = G_reader_settings:readSetting("monospace_font") or self.ui.document.monospace_font
                local text = v
                if font_filename and font_faceindex then
                    text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
                end

                if v == monospace_font then
                    text = text .. " \u{1F13C}" -- Squared Latin Capital Letter M
                elseif is_monospace then
                    text = text .. " \u{1D39}" -- Modified Letter Capital M
                end
                if v == default_font then
                    text = text .. "   ★"
                end
                if v == fallback_font then
                    text = text .. "   �"
                end
                return text
            end,
            font_func = function(size)
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if font_filename and font_faceindex then
                        return Font:getFace(font_filename, size, font_faceindex)
                    end
                end
            end,
            callback = function()
                self:onSetFont(v)
            end,
            hold_callback = function(touchmenu_instance)
                self:makeDefault(v, is_monospace, touchmenu_instance)
            end,
            checked_func = function()
                return v == self.font_face
            end,
            menu_item_id = v,
        })
    end
    self.face_table.open_on_menu_item_id_func = function()
        return self.font_face
    end
    self.ui.menu:registerToMainMenu(self)

    -- NOP our own gesture handling
    self.ges_events = nil
end

function ReaderFont:onGesture() end

function ReaderFont:registerKeyEvents()
    if Device:hasKeyboard() then
        -- add shortcut for keyboard
        self.key_events = {
            ShowFontMenu = { { "F" } },
            IncreaseSize = {
                { "Shift", Input.group.PgFwd },
                event = "ChangeSize",
                args = 0.5
            },
            DecreaseSize = {
                { "Shift", Input.group.PgBack },
                event = "ChangeSize",
                args = -0.5
            },
        }
    end
end

ReaderFont.onPhysicalKeyboardConnected = ReaderFont.registerKeyEvents

function ReaderFont:onSetDimensions(dimen)
    self.dimen = dimen
end

function ReaderFont:onReadSettings(config)
    self.font_face = config:readSetting("font_face")
                  or G_reader_settings:readSetting("cre_font")
                  or self.ui.document.default_font
    self.ui.document:setFontFace(self.font_face)

    self.header_font_face = config:readSetting("header_font_face")
                         or G_reader_settings:readSetting("header_font")
                         or self.ui.document.header_font
    self.ui.document:setHeaderFont(self.header_font_face)

    self.font_size = config:readSetting("font_size")
                  or G_reader_settings:readSetting("copt_font_size")
                  or G_defaults:readSetting("DCREREADER_CONFIG_DEFAULT_FONT_SIZE")
                  or 22
    self.ui.document:setFontSize(Screen:scaleBySize(self.font_size))

    self.font_base_weight = config:readSetting("font_base_weight")
                      or G_reader_settings:readSetting("copt_font_base_weight")
                      or 0
    self.ui.document:setFontBaseWeight(self.font_base_weight)

    self.font_hinting = config:readSetting("font_hinting")
                     or G_reader_settings:readSetting("copt_font_hinting")
                     or 2 -- auto (default in cre.cpp)
    self.ui.document:setFontHinting(self.font_hinting)

    self.font_kerning = config:readSetting("font_kerning")
                     or G_reader_settings:readSetting("copt_font_kerning")
                     or 3 -- harfbuzz (slower, but needed for proper arabic)
    self.ui.document:setFontKerning(self.font_kerning)

    self.word_spacing = config:readSetting("word_spacing")
                     or G_reader_settings:readSetting("copt_word_spacing")
                     or {95, 75}
    self.ui.document:setWordSpacing(self.word_spacing)

    self.word_expansion = config:readSetting("word_expansion")
                       or G_reader_settings:readSetting("copt_word_expansion")
                       or 0
    self.ui.document:setWordExpansion(self.word_expansion)

    self.cjk_width_scaling = config:readSetting("cjk_width_scaling")
                       or G_reader_settings:readSetting("copt_cjk_width_scaling")
                       or 100
    self.ui.document:setCJKWidthScaling(self.cjk_width_scaling)

    self.line_space_percent = config:readSetting("line_space_percent")
                           or G_reader_settings:readSetting("copt_line_spacing")
                           or G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM")
    self.ui.document:setInterlineSpacePercent(self.line_space_percent)

    self.gamma_index = config:readSetting("gamma_index")
                    or G_reader_settings:readSetting("copt_font_gamma")
                    or 15 -- gamma = 1.0
    self.ui.document:setGammaIndex(self.gamma_index)

    self.font_family_fonts = config:readSetting("font_family_fonts") or {}
    self:updateFontFamilyFonts()

    -- Dirty hack: we have to add following call in order to set
    -- m_is_rendered(member of LVDocView) to true. Otherwise position inside
    -- document will be reset to 0 on first view render.
    -- So far, I don't know why this call will alter the value of m_is_rendered.
    table.insert(self.ui.postInitCallback, function()
        self.ui:handleEvent(Event:new("UpdatePos"))
    end)
end

function ReaderFont:onShowFontMenu()
    -- build menu widget
    local main_menu = Menu:new{
        title = self.font_menu_title,
        item_table = self.face_table,
        width = Screen:getWidth() - 100,
        height = math.floor(Screen:getHeight() * 0.5),
        single_line = true,
        items_per_page = 8,
        items_font_size = Menu.getItemFontSize(8),
    }
    -- build container
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        main_menu,
    }
    main_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    -- show menu

    main_menu.show_parent = menu_container

    UIManager:show(menu_container)

    return true
end

--[[
    UpdatePos event is used to tell ReaderRolling to update pos.
--]]
function ReaderFont:onChangeSize(delta)
    self.font_size = self.font_size + delta
    self.ui:handleEvent(Event:new("SetFontSize", self.font_size))
    return true
end

function ReaderFont:onSetFontSize(new_size)
    if new_size > 255 then new_size = 255 end
    if new_size < 12 then new_size = 12 end

    self.font_size = new_size
    self.ui.document:setFontSize(Screen:scaleBySize(new_size))
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Font size set to: %1."), self.font_size))
    return true
end

function ReaderFont:onSetLineSpace(space)
    self.line_space_percent = math.min(200, math.max(50, space))
    self.ui.document:setInterlineSpacePercent(self.line_space_percent)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Line spacing set to: %1%."), self.line_space_percent))
    return true
end

function ReaderFont:onSetFontBaseWeight(weight)
    self.font_base_weight = weight
    self.ui.document:setFontBaseWeight(weight)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Font weight set to: %1."), optionsutil:getOptionText("SetFontBaseWeight", weight)))
    return true
end

function ReaderFont:onSetFontHinting(mode)
    self.font_hinting = mode
    self.ui.document:setFontHinting(mode)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Font hinting set to: %1"), optionsutil:getOptionText("SetFontHinting", mode)))
    return true
end

function ReaderFont:onSetFontKerning(mode)
    self.font_kerning = mode
    self.ui.document:setFontKerning(mode)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Font kerning set to: %1"), optionsutil:getOptionText("SetFontKerning", mode)))
    return true
end

function ReaderFont:onSetWordSpacing(values)
    self.word_spacing = values
    self.ui.document:setWordSpacing(values)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Word spacing set to: %1%, %2%"), values[1], values[2]))
    return true
end

function ReaderFont:onSetWordExpansion(value)
    self.word_expansion = value
    self.ui.document:setWordExpansion(value)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("Word expansion set to: %1%."), value))
    return true
end

function ReaderFont:onSetCJKWidthScaling(value)
    self.cjk_width_scaling = value
    self.ui.document:setCJKWidthScaling(value)
    self.ui:handleEvent(Event:new("UpdatePos"))
    Notification:notify(T(_("CJK width scaling set to: %1%."), value))
    return true
end

function ReaderFont:onSetFontGamma(gamma)
    self.gamma_index = gamma
    self.ui.document:setGammaIndex(self.gamma_index)
    local gamma_level = self.ui.document:getGammaLevel()
    self.ui:handleEvent(Event:new("RedrawCurrentView"))
    Notification:notify(T(_("Font gamma set to: %1."), gamma_level))
    return true
end

function ReaderFont:onSaveSettings()
    self.ui.doc_settings:saveSetting("font_face", self.font_face)
    self.ui.doc_settings:saveSetting("header_font_face", self.header_font_face)
    self.ui.doc_settings:saveSetting("font_size", self.font_size)
    self.ui.doc_settings:saveSetting("font_base_weight", self.font_base_weight)
    self.ui.doc_settings:saveSetting("font_hinting", self.font_hinting)
    self.ui.doc_settings:saveSetting("font_kerning", self.font_kerning)
    self.ui.doc_settings:saveSetting("word_spacing", self.word_spacing)
    self.ui.doc_settings:saveSetting("word_expansion", self.word_expansion)
    self.ui.doc_settings:saveSetting("cjk_width_scaling", self.cjk_width_scaling)
    self.ui.doc_settings:saveSetting("line_space_percent", self.line_space_percent)
    self.ui.doc_settings:saveSetting("gamma_index", self.gamma_index)
    self.ui.doc_settings:saveSetting("font_family_fonts", self.font_family_fonts)
end

function ReaderFont:onSetFont(face)
    if face and self.font_face ~= face then
        self.font_face = face
        self.ui.document:setFontFace(face)
        -- signal readerrolling to update pos in new height
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderFont:makeDefault(face, is_monospace, touchmenu_instance)
    if face then
        if is_monospace then
            -- If the font is monospace, assume it wouldn't be a candidate
            -- to be set as a fallback font, and allow it to be set as the
            -- default monospace font.
            UIManager:show(MultiConfirmBox:new{
                text = T(_("Would you like %1 to be used as the default font (★), or the monospace font (\u{1F13C})?"), face),
                choice1_text = _("Default"),
                choice1_callback = function()
                    G_reader_settings:saveSetting("cre_font", face)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                choice2_text = C_("Font", "Monospace"),
                choice2_callback = function()
                    G_reader_settings:saveSetting("monospace_font", face)
                    -- We need to reset the main font for the biases to be re-set correctly
                    local current_face = self.font_face
                    self.font_face = nil
                    self:onSetFont(current_face)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            return
        end
        UIManager:show(MultiConfirmBox:new{
            text = T(_("Would you like %1 to be used as the default font (★), or the fallback font (�)?\n\nCharacters not found in the active font are shown in the fallback font instead."), face),
            choice1_text = _("Default"),
            choice1_callback = function()
                G_reader_settings:saveSetting("cre_font", face)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            choice2_text = C_("Font", "Fallback"),
            choice2_callback = function()
                G_reader_settings:saveSetting("fallback_font", face)
                self.ui.document:setupFallbackFontFaces()
                self.ui:handleEvent(Event:new("UpdatePos"))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
end

function ReaderFont:addToMainMenu(menu_items)
    -- Have TouchMenu show half of the usual nb of items, so we
    -- have more room to see how the text looks with that font
    self.face_table.max_per_page = 5
    -- insert table to main reader menu
    menu_items.change_font = {
        text_func = function()
            return T(_("Font: %1"), BD.wrap(self.font_face))
        end,
        sub_item_table = self.face_table,
    }
end

function ReaderFont:gesToFontSize(ges)
    -- Dispatcher feeds us a number, not a gesture
    if type(ges) ~= "table" then return ges end

    if ges.distance == nil then
        ges.distance = 1
    end
    -- Compute the scaling based on the gesture's direction (for pinch/spread)
    local step
    if ges.direction and ges.direction == "vertical" then
        step = math.ceil(2 * #self.steps * ges.distance / Screen:getHeight())
    elseif ges.direction and ges.direction == "horizontal" then
        step = math.ceil(2 * #self.steps * ges.distance / Screen:getWidth())
    elseif ges.direction and ges.direction == "diagonal" then
        local screen_diagonal = math.sqrt(Screen:getWidth()^2 + Screen:getHeight()^2)
        step = math.ceil(2 * #self.steps * ges.distance / screen_diagonal)
    else
        step = math.ceil(2 * #self.steps * ges.distance / math.min(Screen:getWidth(), Screen:getHeight()))
    end
    local delta_int = self.steps[step] or self.steps[#self.steps]
    return delta_int
end

function ReaderFont:onIncreaseFontSize(ges)
    local delta_int = self:gesToFontSize(ges)
    Notification:notify(_("Increasing font size…"), nil, true)
    self:onChangeSize(delta_int)
    return true
end

function ReaderFont:onDecreaseFontSize(ges)
    local delta_int = self:gesToFontSize(ges)
    Notification:notify(_("Decreasing font size…"), nil, true)
    self:onChangeSize(-delta_int)
    return true
end

local font_family_info_text = _([[
In HTML/CSS based documents like EPUBs, stylesheets can specify to use fonts by family instead of a specific font name.
Except for monospace and math, KOReader uses your default font for any family name.
You can associate a specific font to each family if you care about the distinction.
A long-press on a font name will make the association global (★), so it applies to all your books. This is the preferred approach.
A tap will only affect the current book.
If you encounter a book where such families are abused to the point where your default font is hardly used, you can quickly disable a family font for this book by unchecking the association.]])

local FONT_FAMILIES = {
    -- On 1st page
    -- @translators These are typography font family names as used in CSS, they can be kept untranslated if they are used more commonly than their translation
    { "serif", _("Serif") },
    { "sans-serif", _("Sans-serif") },
    { "monospace", _("Monospace") },
    -- On 2nd page
    { "cursive", _("Cursive") },
    { "fantasy", _("Fantasy") },
    { "emoji", _("Emoji \u{1F60A}") },
    { "fangsong", _("Fang Song \u{4EFF}\u{5B8B}") },
    { "math", _("Math") },
}

function ReaderFont:updateFontFamilyFonts()
    -- Note: when no font is specified for a family, we provide an empty string to
    -- crengine, which is enough to have it kill any "css_ff_inherit" and have the
    -- font picking code select a new font for a node - which will pick the main
    -- font (we have here in self.font_face) because of its increased bias (or the
    -- monospace font we also added with bias).
    -- So, we don't need to insert self.font_face in the list for unset family fonts,
    -- which would otherwise need us to call updateFontFamilyFonts() everytime we
    -- change the main font face.
    local g_font_family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
    local family_fonts = {}
    for i, family in ipairs(FONT_FAMILIES) do
        local family_tag = family[1]
        if self.font_family_fonts[family_tag] then
            family_fonts[family_tag] = self.font_family_fonts[family_tag]
        elseif g_font_family_fonts[family_tag] and self.font_family_fonts[family_tag] ~= false then
            family_fonts[family_tag] = g_font_family_fonts[family_tag]
        elseif family_tag == "math" then
            -- If no math font set, force using our math-enabled shipped FreeSerif (which
            -- saves crengine some work iterating its hardcoded list of math fonts).
            family_fonts[family_tag] = "FreeSerif"
        end
    end
    self.ui.document:setFontFamilyFontFaces(family_fonts, G_reader_settings:isTrue("cre_font_family_ignore_font_names"))
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderFont:getFontFamiliesTable()
    local g_font_family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
    local families_table = {
        {
            text = _("About font-family fonts"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = font_family_info_text,
                })
            end,
            keep_menu_open = true,
            separator = true,
        },
        {
            text = _("Ignore publisher font names when font-family is set"),
            checked_func = function()
                return G_reader_settings:isTrue("cre_font_family_ignore_font_names")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("cre_font_family_ignore_font_names")
                self:updateFontFamilyFonts()
            end,
            help_text = _([[
In a CSS font-family declaration, publishers may precede a family name with one or more font names, that are to be used if found among embedded fonts or your own fonts.
Enabling this will ignore such font names and make sure your preferred family fonts are used.]]),
            keep_menu_open = true,
            separator = true,
        },
        max_per_page = 5,
    }
    local face_to_filename = {}
    local face_list = cre.getFontFaces()
    for i, family in ipairs(FONT_FAMILIES) do
        local family_tag, family_name = family[1], family[2]
        -- If none family font is set, crengine will use the main user set font,
        -- except for 2 specific cases.
        local unset_font_main_text = _("(main font)")
        local unset_font_choice_text = _("Use main font")
        if family_tag == "monospace" then
            local monospace_font = G_reader_settings:readSetting("monospace_font") or self.ui.document.monospace_font
            unset_font_main_text = _("(default monospace font)")
            unset_font_choice_text = T(_("Use default monospace font: %1"), monospace_font)
        elseif family_tag == "math" then
            unset_font_main_text = _("(default math font)")
            unset_font_choice_text = _("Use default math font")
            -- The default math font would be FreeSerif, but crengine would pick a better
            -- one among a hardcoded list if any is found. So, don't say more than that.
        end
        local family_table = {
            menu_item_id = family_tag,
            text_func = function()
                local text
                if self.font_family_fonts[family_tag] then
                    text = BD.wrap(self.font_family_fonts[family_tag])
                elseif g_font_family_fonts[family_tag] then
                    -- Show it even if self.font_family_fonts[family_tag]==false,
                    -- the checkbox will indicate whether it is used or not
                    text = BD.wrap(g_font_family_fonts[family_tag]) .. " ★"
                else
                    text = unset_font_main_text .. " ★"
                end
                return T("%1: %2", family_name, text)
            end,
            font_func = function(size)
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    local font_name
                    if self.font_family_fonts[family_tag] then
                        font_name = self.font_family_fonts[family_tag]
                    elseif g_font_family_fonts[family_tag] then
                        font_name = g_font_family_fonts[family_tag]
                    end
                    if font_name and face_to_filename[font_name] then
                        local filename_idx = face_to_filename[font_name]
                        return Font:getFace(filename_idx[1], size, filename_idx[2])
                    end
                end
            end,
            checked_func = function()
                if self.font_family_fonts[family_tag] then
                    return true
                elseif g_font_family_fonts[family_tag] and self.font_family_fonts[family_tag] ~= false then
                    return true
                end
                return false
            end,
            checkmark_callback = function()
                if self.font_family_fonts[family_tag] then
                    if g_font_family_fonts[family_tag] then
                        self.font_family_fonts[family_tag] = false
                    else
                        self.font_family_fonts[family_tag] = nil
                    end
                else
                    if g_font_family_fonts[family_tag] and self.font_family_fonts[family_tag] ~= false then
                        self.font_family_fonts[family_tag] = false
                    else
                        self.font_family_fonts[family_tag] = nil
                    end
                end
                self:updateFontFamilyFonts()
            end,
            sub_item_table = {
                ignored_by_menu_search = true, -- those would be duplicated
                {
                    text = T(_("Font for %1"), BD.wrap(T("'font-family: %1'", family_tag))),
                    separator = true,
                },
                {
                    text_func = function()
                        local text = unset_font_choice_text
                        if not g_font_family_fonts[family_tag] then
                            text = text .. "   ★"
                        end
                        return text
                    end,
                    callback = function()
                        self.font_family_fonts[family_tag] = false
                        self:updateFontFamilyFonts()
                    end,
                    hold_callback = function(touchmenu_instance)
                        g_font_family_fonts[family_tag] = nil
                        self.font_family_fonts[family_tag] = nil
                        self:updateFontFamilyFonts()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    checked_func = function()
                        if self.font_family_fonts[family_tag] == false then
                            return true
                        end
                        return not self.font_family_fonts[family_tag] and not g_font_family_fonts[family_tag]
                    end,
                    separator = true,
                },
                max_per_page = 5,
            },
        }
        for k, v in ipairs(face_list) do
            local font_filename, font_faceindex, is_monospace, has_ot_math, has_emojis = cre.getFontFaceFilenameAndFaceIndex(v)
            if i == 1 then
                face_to_filename[v] = { font_filename, font_faceindex }
            end
            local ignore = false
            if family_tag == "monospace" and not is_monospace then
                ignore = true
            end
            if family_tag == "math" and not has_ot_math then
                ignore = true
            end
            if family_tag == "emoji" and not has_emojis then
                ignore = true
            end
            if not ignore then
                table.insert(family_table.sub_item_table, {
                    text_func = function()
                        local text = v
                        if font_filename and font_faceindex then
                            text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
                        end
                        if g_font_family_fonts[family_tag] == v then
                            text = text .. "   ★"
                        end
                        return text
                    end,
                    font_func = function(size)
                        if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                            if font_filename and font_faceindex then
                                return Font:getFace(font_filename, size, font_faceindex)
                            end
                        end
                    end,
                    callback = function()
                        if g_font_family_fonts[family_tag] == v then
                            self.font_family_fonts[family_tag] = nil
                        else
                            self.font_family_fonts[family_tag] = v
                            -- We don't use :notify() as we don't want this notification to be masked,
                            -- to let the user know it's not global (so he has to use long-press)
                            UIManager:show(Notification:new{ text = _("Font family font set for this book only.") })
                            -- Be sure it is shown before the re-rendering (which may take some time)
                            UIManager:forceRePaint()
                        end
                        self:updateFontFamilyFonts()
                    end,
                    hold_callback = function(touchmenu_instance)
                        g_font_family_fonts[family_tag] = v
                        self.font_family_fonts[family_tag] = nil
                        self:updateFontFamilyFonts()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    checked_func = function()
                        if self.font_family_fonts[family_tag] then
                            return self.font_family_fonts[family_tag] == v
                        elseif g_font_family_fonts[family_tag] == v and self.font_family_fonts[family_tag] ~= false then
                            return true
                        end
                        return false
                    end,
                    menu_item_id = family_tag .. "_" .. v,
                })
            end
        end
        family_table.sub_item_table.open_on_menu_item_id_func = function()
            if self.font_family_fonts[family_tag] then
                return family_tag .. "_" .. self.font_family_fonts[family_tag]
            elseif g_font_family_fonts[family_tag] and self.font_family_fonts[family_tag] ~= false then
                return family_tag .. "_" .. g_font_family_fonts[family_tag]
            end
        end
        table.insert(families_table, family_table)
    end
    return families_table
end

function ReaderFont:getFontSettingsTable()
    local settings_table = {}

    if Device:isAndroid() or Device:isDesktop() or Device:isEmulator() or Device:isPocketBook() then
        for _, item in ipairs(require("ui/elements/font_settings"):getSystemFontMenuItems()) do
            table.insert(settings_table, item)
        end
        settings_table[#settings_table].separator = true
    end

    table.insert(settings_table, {
        text = _("Display font names with their own font"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("font_menu_use_font_face")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("font_menu_use_font_face")
        end,
        help_text = _([[In the font menu, display each font name with its own font face.]]),
        separator = true,
    })

    table.insert(settings_table, {
        text = _("Use additional fallback fonts"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("additional_fallback_fonts")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("additional_fallback_fonts")
            self.ui.document:setupFallbackFontFaces()
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        help_text = T(_([[
Enable additional fallback fonts, for the most complete script and language coverage.
These fonts will be used in this order:

%1

You can set a preferred fallback font with a long-press on a font name, and it will be used before these.
If that font happens to be part of this list already, it will be used first.]]),
            table.concat(self.ui.document.fallback_fonts, "\n")),
    })
    table.insert(settings_table, {
        text = _("Adjust fallback font sizes"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("cre_adjusted_fallback_font_sizes")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("cre_adjusted_fallback_font_sizes")
            self.ui.document:setAdjustedFallbackFontSizes(G_reader_settings:nilOrTrue("cre_adjusted_fallback_font_sizes"))
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        help_text = _([[
Adjust the size of each fallback font so they all get the same x-height, and lowercase characters picked in them look similarly sized as those from the defaut font.
This may help with Greek words among Latin text (as Latin fonts often do not have all the Greek characters), but may make Chinese or Indic characters smaller when picked from fallback fonts.]]),
        separator = true,
    })

    table.insert(settings_table, {
        text_func = function()
            local scale = G_reader_settings:readSetting("cre_monospace_scaling") or 100
            return T(_("Monospace fonts scaling: %1 %"), scale)
        end,
        callback = function()
            local SpinWidget = require("ui/widget/spinwidget")
            UIManager:show(SpinWidget:new{
                value = G_reader_settings:readSetting("cre_monospace_scaling") or 100,
                value_min = 30,
                value_step = 1,
                value_hold_step = 5,
                value_max = 150,
                unit = "%",
                title_text = _("Monospace font scaling"),
                -- no info_text: we want this widget to stay small, so we can move it
                -- around to see the effect of the scaling
                keep_shown_on_apply = true,
                callback = function(spin)
                    local scale = spin.value
                    G_reader_settings:saveSetting("cre_monospace_scaling", scale)
                    self.ui.document:setMonospaceFontScaling(scale)
                    self.ui:handleEvent(Event:new("UpdatePos"))
                end,
            })
        end,
        help_text = _([[
Monospace fonts may look big when inline with your main font if it has a small x-height.
This setting allows scaling all monospace fonts by this percentage so they can fit your preferred font height, or you can make them be a bit smaller to distinguish them more easily.]]),
        separator = true,
    })

    table.insert(settings_table, {
        text = _("Generate font test document"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Would you like to generate an HTML document showing some sample text rendered with each available font?"),
                ok_callback = function()
                    self:buildFontsTestDocument()
                end,
            })
        end,
    })
    return settings_table
end

-- Default sample file
local FONT_TEST_DEFAULT_SAMPLE_PATH = "frontend/ui/elements/font-test-sample-default.template"
-- Users can set their own sample file, that will be used if found
local FONT_TEST_USER_SAMPLE_PATH = require("datastorage"):getSettingsDir() .. "/font-test-sample.html"
-- This document will be generated in the home or default directory
local FONT_TEST_FINAL_FILENAME = "font-test.html"

function ReaderFont:buildFontsTestDocument()
    local html_sample
    local f = io.open(FONT_TEST_USER_SAMPLE_PATH, "r")
    if f then
        html_sample = f:read("*all")
        f:close()
    end
    if not html_sample then
        f = io.open(FONT_TEST_DEFAULT_SAMPLE_PATH, "r")
        if not f then return nil end
        html_sample = f:read("*all")
        f:close()
    end
    local dir = G_reader_settings:readSetting("home_dir")
             or require("apps/filemanager/filemanagerutil").getDefaultDir()
             or "."
    local font_test_final_path = dir .. "/" .. FONT_TEST_FINAL_FILENAME
    f = io.open(font_test_final_path, "w")
    if not f then return end
    -- Using <section><title>...</title></section> allows for a TOC to be built by crengine
    f:write(string.format([[
<?xml version="1.0" encoding="UTF-8"?>
<html>
<head>
<title>%s</title>
<style>
h1 {
  font-size: large;
  font-weight: bold;
  text-align: center;
  page-break-before: always;
  margin-top: 0;
  margin-bottom: 0.5em;
}
a { color: black; }
</style>
</head>
<body>
<h1>%s</h1>
]], _("Available fonts test document"), _("AVAILABLE FONTS")))
    local face_list = cre.getFontFaces()
    f:write("<div style='margin: 2em'>\n")
    for _, font_name in ipairs(face_list) do
        local font_id = font_name:gsub(" ", "_"):gsub("'", "_")
        f:write(string.format("  <div><a href='#%s'>%s</a></div>\n", font_id, font_name))
    end
    f:write("</div>\n\n")
    for _, font_name in ipairs(face_list) do
        local font_id = font_name:gsub(" ", "_"):gsub("'", "_")
        f:write(string.format("<h1 id='%s'>%s</h1>\n", font_id, font_name))
        f:write(string.format("<div style='font-family: %s'>\n", font_name))
        f:write(html_sample)
        f:write("\n</div>\n\n")
    end
    f:write("</body></html>\n")
    f:close()
    UIManager:show(ConfirmBox:new{
        text = T(_("Document created as:\n%1\n\nWould you like to read it now?"), BD.filepath(font_test_final_path)),
        ok_callback = function()
            UIManager:scheduleIn(1.0, function()
                self.ui:switchDocument(font_test_final_path)
            end)
        end,
    })
end

return ReaderFont
