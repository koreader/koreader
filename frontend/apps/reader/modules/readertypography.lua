local BD = require("ui/bidi")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template
local Screen = Device.screen

-- Mostly for migrating hyph settings, and to know the dict
-- left and right hyph min values (2/2 when not specified)
local HYPH_DICT_NAME_TO_LANG_NAME_TAG = {
    ["@none"]                = { "@none",           "en" },
    ["@softhyphens"]         = { "@softhyphens",    "en" },
    ["@algorithm"]           = { "@algorithm",      "en" },
    ["Bulgarian.pattern"]    = { _("Bulgarian"),    "bg" },
    ["Catalan.pattern"]      = { _("Catalan"),      "ca" },
    ["Czech.pattern"]        = { _("Czech"),        "cs" },
    ["Danish.pattern"]       = { _("Danish"),       "da" },
    ["Dutch.pattern"]        = { _("Dutch"),        "nl" },
    ["English_GB.pattern"]   = { _("English (UK)"), "en-GB" },
    ["English_US.pattern"]   = { _("English (US)"), "en-US" },
    ["Finnish.pattern"]      = { _("Finnish"),      "fi" },
    ["French.pattern"]       = { _("French"),       "fr", 2, 1 },
    ["Galician.pattern"]     = { _("Galician"),     "gl" },
    ["German.pattern"]       = { _("German"),       "de" },
    ["Greek.pattern"]        = { _("Greek"),        "el" },
    ["Hungarian.pattern"]    = { _("Hungarian"),    "hu" },
    ["Icelandic.pattern"]    = { _("Icelandic"),    "is" },
    ["Irish.pattern"]        = { _("Irish"),        "ga" },
    ["Italian.pattern"]      = { _("Italian"),      "it" },
    ["Norwegian.pattern"]    = { _("Norwegian"),    "no" },
    ["Polish.pattern"]       = { _("Polish"),       "pl" },
    ["Portuguese.pattern"]   = { _("Portuguese"),   "pt" },
    ["Roman.pattern"]        = { _("Romanian"),     "ro" },
    ["Russian_EnGB.pattern"] = { _("Russian + English (UK)"), "ru-GB" },
    ["Russian_EnUS.pattern"] = { _("Russian + English (US)"), "ru-US" },
    ["Russian.pattern"]      = { _("Russian"),      "ru" },
    ["Slovak.pattern"]       = { _("Slovak"),       "sk" },
    ["Slovenian.pattern"]    = { _("Slovenian"),    "sl" },
    ["Spanish.pattern"]      = { _("Spanish"),      "es" },
    ["Swedish.pattern"]      = { _("Swedish"),      "sv" },
    ["Turkish.pattern"]      = { _("Turkish"),      "tr" },
    ["Ukrain.pattern"]       = { _("Ukrainian"),    "uk" },
}

-- Languages to be shown in the menu.
-- Aliases are language tags that could possibly be found in the book
-- language metadata, that we wish to map to the correct lang tag.
-- Features:
--   H = language specific hyphenation dictionary
--   b = language specific line breaking rules
--   B = language specific additional line breaking tweaks
-- Update them when language tweaks and features are added to crengine/src/textlang.cpp
local LANGUAGES = {
    -- lang-tag          aliases    features    menu title
    { "bg",               {"bul"},   "H   ",   _("Bulgarian") },
    { "ca",               {"cat"},   "H   ",   _("Catalan") },
    { "zh-CN",  {"zh", "zh-Hans"},   " b  ",   _("Chinese (Simplified)") },
    { "zh-TW",        {"zh-Hant"},   " b  ",   _("Chinese (Traditional)") },
    { "cs",               {"ces"},   "HB  ",   _("Czech") },
    { "da",               {"dan"},   "H   ",   _("Danish") },
    { "nl",               {"nld"},   "H   ",   _("Dutch") },
    { "en-GB",                 {},   "Hb  ",   _("English (UK)") },
    { "en-US",      {"en", "eng"},   "Hb  ",   _("English (US)") },
    { "fi",               {"fin"},   "H   ",   _("Finnish") },
    { "fr",        {"fra", "fre"},   "Hb  ",   _("French") },
    { "gl",               {"glg"},   "H   ",   _("Galician") },
    { "de",               {"deu"},   "Hb  ",   _("German") },
    { "el",               {"ell"},   "H   ",   _("Greek") },
    { "hu",               {"hun"},   "H   ",   _("Hungarian") },
    { "is",               {"isl"},   "H   ",   _("Icelandic") },
    { "ga",               {"gle"},   "H   ",   _("Irish") },
    { "it",               {"ita"},   "H   ",   _("Italian") },
    { "ja",                    {},   "    ",   _("Japanese") },
    { "ko",                    {},   "    ",   _("Korean") },
    { "no",               {"nor"},   "H   ",   _("Norwegian") },
    { "pl",               {"pol"},   "HB  ",   _("Polish") },
    { "pt",               {"por"},   "HB  ",   _("Portuguese") },
    { "ro",               {"ron"},   "H   ",   _("Romanian") },
    { "ru-GB",                 {},   "Hb  ",   _("Russian + English (UK)") },
    { "ru-US",                 {},   "Hb  ",   _("Russian + English (US)") },
    { "ru",               {"rus"},   "Hb  ",   _("Russian") },
    { "sk",               {"slk"},   "HB  ",   _("Slovak") },
    { "sl",               {"slv"},   "H   ",   _("Slovenian") },
    { "es",               {"spa"},   "Hb  ",   _("Spanish") },
    { "sv",               {"swe"},   "H   ",   _("Swedish") },
    { "tr",               {"tur"},   "H   ",   _("Turkish") },
    { "uk",               {"ukr"},   "H   ",   _("Ukrainian") }
}

local DEFAULT_LANG_TAG = "en-US" -- English_US.pattern is loaded by default in crengine

local LANG_TAG_TO_LANG_NAME = {}
local LANG_ALIAS_TO_LANG_TAG = {}
for __, v in ipairs(LANGUAGES) do
    local lang_tag, lang_aliases, lang_features, lang_name = unpack(v) -- luacheck: no unused
    LANG_TAG_TO_LANG_NAME[lang_tag] = lang_name
    if lang_aliases and #lang_aliases > 0 then
        for ___, alias in ipairs(lang_aliases) do
            LANG_ALIAS_TO_LANG_TAG[alias] = lang_tag
        end
    end
end

local ReaderTypography = InputContainer:new{}

function ReaderTypography:init()
    self.menu_table = {}
    self.language_submenu = {}
    self.book_lang_tag = nil
    self.text_lang_tag = nil
    self.text_lang_embedded_langs = true
    self.hyphenation = true
    self.hyph_trust_soft_hyphens = false
    self.hyph_soft_hyphens_only = false
    self.hyph_force_algorithmic = false

    -- Migrate old readerhyphenation settings (but keep them in case one
    -- go back to a previous version)
    if not G_reader_settings:readSetting("text_lang_default") and not G_reader_settings:readSetting("text_lang_fallback") then
        local g_text_lang_set = false
        local hyph_alg_default = G_reader_settings:readSetting("hyph_alg_default")
        if hyph_alg_default then
            local dict_info = HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg_default]
            if dict_info then
                G_reader_settings:saveSetting("text_lang_default", dict_info[2])
                g_text_lang_set = true
                -- Tweak the other settings if the default hyph algo happens
                -- to be one of these:
                if hyph_alg_default == "@none" then
                    G_reader_settings:saveSetting("hyphenation", false)
                elseif hyph_alg_default == "@softhyphens" then
                    G_reader_settings:saveSetting("hyph_soft_hyphens_only", true)
                elseif hyph_alg_default == "@algorithm" then
                    G_reader_settings:saveSetting("hyph_force_algorithmic", true)
                end
            end
        end
        local hyph_alg_fallback = G_reader_settings:readSetting("hyph_alg_fallback")
        if not g_text_lang_set and hyph_alg_fallback then
            local dict_info = HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg_fallback]
            if dict_info then
                G_reader_settings:saveSetting("text_lang_fallback", dict_info[2])
                g_text_lang_set = true
                -- We can't really tweak other settings if the hyph algo fallback
                -- happens to be @none, @softhyphens, @algortihm...
            end
        end
        if not g_text_lang_set then
            -- If nothing migrated, set the fallback to DEFAULT_LANG_TAG,
            -- as we'll always have one of text_lang_default/_fallback set.
            G_reader_settings:saveSetting("text_lang_fallback", DEFAULT_LANG_TAG)
        end
    end

    local info_text = _([[
Some languages have specific typographic rules: these include hyphenation, line breaking rules, and language specific glyph variants.
KOReader will chose one according to the language tag from the book's metadata, but you can select another one.
You can also set a default language or a fallback one with a long-press.

Features available per language are marked with:
‐ : language specific hyphenation dictionary
 : specific line breaking rules (mostly related to quotation marks)
 : more line breaking rules (e.g., single letter prepositions not allowed at end of line)

Note that when a language does not come with its own hyphenation dictionary, the English (US) one will be used.
When the book's language tag is not among our presets, no specific features will be enabled, but it might be enough to get language specific glyph variants (when supported by the fonts).]])
    table.insert(self.menu_table, {
        text = _("About typography rules"),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = info_text,
            })
        end,
        hold_callback = function()
            -- Show infos about TextLangMan seen lang_tags and loaded hyph dicts
            local lang_infos = {}
            local seen_hyph_dicts = {} -- to avoid outputing count and size for shared hyph dicts
            local main_lang_tag, main_lang_active_hyph_dict, loaded_lang_infos = cre.getTextLangStatus() -- luacheck: no unused
            -- First output main lang tag
            local main_lang_info = loaded_lang_infos[main_lang_tag]
            table.insert(lang_infos, _("Current main language tag:"))
            table.insert(lang_infos, string.format("%s\t\t(%s - %s - %s)",
                            main_lang_tag,
                            main_lang_info.hyph_dict_name,
                            util.getFormattedSize(main_lang_info.hyph_nb_patterns),
                            util.getFriendlySize(main_lang_info.hyph_mem_size)))
            seen_hyph_dicts[main_lang_info.hyph_dict_name] = true
            -- Sort list of lang_tags
            local has_other_lang_tags = false
            local lang_tags = {}
            for k in pairs(loaded_lang_infos) do
                has_other_lang_tags = true
                table.insert(lang_tags, k)
            end
            if has_other_lang_tags then
                table.sort(lang_tags)
                table.insert(lang_infos, "") -- empty line as separator
                table.insert(lang_infos, _("Other language tags:"))
                -- Output other lang tags
                for __, lang_tag in ipairs(lang_tags) do
                    local lang_info = loaded_lang_infos[lang_tag]
                    if lang_tag == main_lang_tag then
                        -- Already included
                        do end -- luacheck: ignore 541
                    elseif seen_hyph_dicts[lang_info.hyph_dict_name] then
                        table.insert(lang_infos, string.format("%s\t\t(%s)",
                                        lang_tag,
                                        lang_info.hyph_dict_name))
                    else
                        table.insert(lang_infos, string.format("%s\t\t(%s - %s - %s)",
                                        lang_tag,
                                        lang_info.hyph_dict_name,
                                        util.getFormattedSize(lang_info.hyph_nb_patterns),
                                        util.getFriendlySize(lang_info.hyph_mem_size)))
                        seen_hyph_dicts[lang_info.hyph_dict_name] = true
                    end
                end
            end
            -- Text might be too long for InfoMessage
            local status_text = table.concat(lang_infos, "\n")
            local TextViewer = require("ui/widget/textviewer")
            local Font = require("ui/font")
            UIManager:show(TextViewer:new{
                title = _("Language tags (and hyphenation dictionaries) used since start up"),
                text = status_text,
                text_face = Font:getFace("smallinfont"),
                height = math.floor(Screen:getHeight() * 0.8),
            })
        end,
        keep_menu_open = true,
        separator = true,
    })

    for __, v in ipairs(LANGUAGES) do
        local lang_tag, lang_aliases, lang_features, lang_name = unpack(v) -- luacheck: no unused

        table.insert(self.language_submenu, {
            text_func = function()
                local text = lang_name
                local feat = ""
                if lang_features:find("H") then
                    feat = feat .. "‐ "
                end
                if lang_features:find("b") then
                    feat = feat .. ""
                elseif lang_features:find("B") then
                    feat = feat .. ""
                end
                -- Other usable nerdfont glyphs in case of need:
                -- feat = feat .. "       "
                text = text .. "   " .. feat
                if lang_tag == G_reader_settings:readSetting("text_lang_default") then
                    text = text .. "   ★"
                end
                if lang_tag == G_reader_settings:readSetting("text_lang_fallback") then
                    text = text .. "   �"
                end
                return text
            end,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = T(_("Changed language for typography rules to %1."), BD.wrap(lang_name)),
                })
                self.text_lang_tag = lang_tag
                self.ui.document:setTextMainLang(lang_tag)
                self.ui:handleEvent(Event:new("UpdatePos"))
            end,
            hold_callback = function(touchmenu_instance)
                UIManager:show(MultiConfirmBox:new{
                    -- No real need for a way to remove default one, we can just
                    -- toggle between setting a default OR a fallback (if a default
                    -- one is set, no fallback will ever be used - if a fallback one
                    -- is set, no default is wanted; so when we set one below, we
                    -- remove the other).
                    text = T( _("Would you like %1 to be used as the default (★) or fallback (�) language for typography rules?\n\nDefault will always take precedence while fallback will only be used if the language of the book can't be automatically determined."), BD.wrap(lang_name)),
                    choice1_text = _("Default"),
                    choice1_callback = function()
                        G_reader_settings:saveSetting("text_lang_default", lang_tag)
                        G_reader_settings:delSetting("text_lang_fallback")
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    choice2_text = C_("Typography", "Fallback"),
                    choice2_callback = function()
                        G_reader_settings:saveSetting("text_lang_fallback", lang_tag)
                        G_reader_settings:delSetting("text_lang_default")
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
            checked_func = function()
                return self.text_lang_tag == lang_tag
            end,
        })
    end

    self.language_submenu.max_per_page = 5
    table.insert(self.menu_table, {
        text_func = function()
            local lang_name = LANG_TAG_TO_LANG_NAME[self.text_lang_tag] or self.text_lang_tag
            return T(_("Typography rules: %1"), lang_name)
        end,
        sub_item_table = self.language_submenu,
    })

    table.insert(self.menu_table, {
        text = _("Respect embedded lang tags"),
        callback = function()
            self.text_lang_embedded_langs = not self.text_lang_embedded_langs
            self.ui.document:setTextEmbeddedLangs(self.text_lang_embedded_langs)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        hold_callback = function()
            local text_lang_embedded_langs = G_reader_settings:nilOrTrue("text_lang_embedded_langs")
            UIManager:show(MultiConfirmBox:new{
                text = text_lang_embedded_langs and _("Would you like to respect or ignore embedded lang tags by default?\n\nRespecting them will use relevant typographic rules to render their content, while ignoring them will always use the main language typography rules.\n\nThe current default (★) is to respect them.")
                or _("Would you like to respect or ignore embedded lang tags by default?\n\nRespecting them will use relevant typographic rules to render their content, while ignoring them will always use the main language typography rules\n\nThe current default (★) is to ignore them."),
                choice1_text_func =  function()
                    return text_lang_embedded_langs and _("Ignore") or _("Ignore (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:saveSetting("text_lang_embedded_langs", false)
                end,
                choice2_text_func = function()
                    return text_lang_embedded_langs and _("Respect (★)") or _("Respect")
                end,
                choice2_callback = function()
                    G_reader_settings:saveSetting("text_lang_embedded_langs", true)
                end,
            })
        end,
        checked_func = function()
            return self.text_lang_embedded_langs
        end,
        separator = true,
    })

    local hyphenation_submenu = {}
    table.insert(hyphenation_submenu, {
        text = _("Enable hyphenation"),
        callback = function()
            self.hyphenation = not self.hyphenation
            self.ui.document:setTextHyphenation(self.hyphenation)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        hold_callback = function()
            local hyphenation = G_reader_settings:nilOrTrue("hyphenation")
            UIManager:show(MultiConfirmBox:new{
                text = hyphenation and _("Would you like to enable or disable hyphenation by default?\n\nThe current default (★) is enabled.")
                or _("Would you like to enable or disable hyphenation by default?\n\nThe current default (★) is disabled."),
                choice1_text_func =  function()
                    return hyphenation and _("Disable") or _("Disable (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:saveSetting("hyphenation", false)
                end,
                choice2_text_func = function()
                    return hyphenation and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:saveSetting("hyphenation", true)
                end,
            })
        end,
        checked_func = function()
            return self.hyphenation
        end,
    })
    table.insert(hyphenation_submenu, {
        text_func = function()
            -- Note: with our callback, we either get hyph_left_hyphen_min and
            -- hyph_right_hyphen_min both nil, or both defined.
            if G_reader_settings:readSetting("hyph_left_hyphen_min") or
                        G_reader_settings:readSetting("hyph_right_hyphen_min") then
                -- @translators to RTL language translators: %1/left is the min length of the start of a hyphenated word, %2/right is the min length of the end of a hyphenated word (note that there is yet no support for hyphenation with RTL languages, so this will mostly apply to LTR documents)
                return T(_("Left/right minimal sizes: %1 - %2"),
                    G_reader_settings:readSetting("hyph_left_hyphen_min"),
                    G_reader_settings:readSetting("hyph_right_hyphen_min"))
            end
            return _("Left/right minimal sizes: language defaults")
        end,
        callback = function()
            local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
            -- We will show the defaults for the current main language hyph dict
            local alg_left_hyphen_min = 2
            local alg_right_hyphen_min = 2
            local hyph_alg = cre.getSelectedHyphDict()
            local hyph_dict_info = HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg]
            if hyph_dict_info then
                alg_left_hyphen_min = hyph_dict_info[3] or 2
                alg_right_hyphen_min = hyph_dict_info[4] or 2
            end
            local hyph_limits_widget = DoubleSpinWidget:new{
                -- Min (1) and max (10) values are enforced by crengine
                -- Note that when hitting "Use language defaults", we show the default
                -- values from languages.json, but we give 0 to crengine, which will
                -- use its own default hardcoded values (in textlang.cpp). Try to keep
                -- these values in sync.
                left_value = G_reader_settings:readSetting("hyph_left_hyphen_min") or alg_left_hyphen_min,
                left_min = 1,
                left_max = 10,
                right_value = G_reader_settings:readSetting("hyph_right_hyphen_min") or alg_right_hyphen_min,
                right_min = 1,
                right_max = 10,
                left_default = alg_left_hyphen_min,
                right_default = alg_right_hyphen_min,
                -- let room on the widget sides so we can see
                -- the hyphenation changes happening
                width = math.floor(Screen:getWidth() * 0.6),
                default_values = true,
                default_text = _("Use language defaults"),
                title_text = _("Hyphenation limits"),
                info_text = _([[
Set minimum length before hyphenation occurs.
These settings will apply to all books with any hyphenation dictionary.
'Use language defaults' resets them.]]),
                keep_shown_on_apply = true,
                callback = function(left_hyphen_min, right_hyphen_min)
                    G_reader_settings:saveSetting("hyph_left_hyphen_min", left_hyphen_min)
                    G_reader_settings:saveSetting("hyph_right_hyphen_min", right_hyphen_min)
                    self.ui.document:setHyphLeftHyphenMin(G_reader_settings:readSetting("hyph_left_hyphen_min") or 0)
                    self.ui.document:setHyphRightHyphenMin(G_reader_settings:readSetting("hyph_right_hyphen_min") or 0)
                    -- signal readerrolling to update pos in new height, and redraw page
                    self.ui:handleEvent(Event:new("UpdatePos"))
                end
            }
            UIManager:show(hyph_limits_widget)
        end,
        enabled_func = function()
            return self.hyphenation
        end,
    })
    table.insert(hyphenation_submenu, {
        text = _("Trust soft hyphens"),
        callback = function()
            self.hyph_trust_soft_hyphens = not self.hyph_trust_soft_hyphens
            self.ui.document:setTrustSoftHyphens(self.hyph_trust_soft_hyphens)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        hold_callback = function()
            local hyph_trust_soft_hyphens = G_reader_settings:isTrue("hyph_trust_soft_hyphens")
            UIManager:show(MultiConfirmBox:new{
                text = hyph_trust_soft_hyphens and _("Would you like to enable or disable trusting soft hyphens by default?\n\nThe current default (★) is enabled.")
                or _("Would you like to enable or disable trusting soft hyphens by default?\n\nThe current default (★) is disabled."),
                choice1_text_func =  function()
                    return hyph_trust_soft_hyphens and _("Disable") or _("Disable (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:saveSetting("hyph_trust_soft_hyphens", false)
                end,
                choice2_text_func = function()
                    return hyph_trust_soft_hyphens and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:saveSetting("hyph_trust_soft_hyphens", true)
                end,
            })
        end,
        checked_func = function()
            return self.hyphenation and (self.hyph_trust_soft_hyphens or self.hyph_soft_hyphens_only)
        end,
        enabled_func = function()
            return self.hyphenation and not self.hyph_soft_hyphens_only
        end,
        separator = true,
    })
    table.insert(hyphenation_submenu, {
        text_func = function()
            -- Show the current language default hyph dict (ie: English_US for zh)
            return T(_("Hyphenation dictionary: %1"), self:getCurrentDefaultHyphDictLanguage())
        end,
        callback = function()
            self.hyph_soft_hyphens_only = false
            self.hyph_force_algorithmic = false
            self.ui.document:setTextHyphenationSoftHyphensOnly(self.hyph_soft_hyphens_only)
            self.ui.document:setTextHyphenationForceAlgorithmic(self.hyph_force_algorithmic)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        -- no hold_callback
        checked_func = function()
            return self.hyphenation and not self.hyph_soft_hyphens_only
                                    and not self.hyph_force_algorithmic
        end,
        enabled_func = function()
            return self.hyphenation
        end,
    })
    table.insert(hyphenation_submenu, {
        text = _("Algorithmic hyphenation"),
        callback = function()
            self.hyph_force_algorithmic = not self.hyph_force_algorithmic
            self.hyph_soft_hyphens_only = false
            self.ui.document:setTextHyphenationSoftHyphensOnly(self.hyph_soft_hyphens_only)
            self.ui.document:setTextHyphenationForceAlgorithmic(self.hyph_force_algorithmic)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        hold_callback = function()
            local hyph_force_algorithmic = G_reader_settings:isTrue("hyph_force_algorithmic")
            UIManager:show(MultiConfirmBox:new{
                text = hyph_force_algorithmic and _("Would you like to enable or disable algorithmic hyphenation by default?\n\nThe current default (★) is enabled.")
                or _("Would you like to enable or disable algorithmic hyphenation by default?\n\nThe current default (★) is disabled."),
                choice1_text_func =  function()
                    return hyph_force_algorithmic and _("Disable") or _("Disable (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:saveSetting("hyph_force_algorithmic", false)
                end,
                choice2_text_func = function()
                    return hyph_force_algorithmic and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:saveSetting("hyph_force_algorithmic", true)
                end,
            })
        end,
        checked_func = function()
            -- (When both enabled, soft-hyphens-only has precedence over force-algorithmic in crengine,
            -- so have that check even if we reset them above)
            return self.hyphenation and not self.hyph_soft_hyphens_only and self.hyph_force_algorithmic
        end,
        enabled_func = function()
            return self.hyphenation
        end,
    })
    table.insert(hyphenation_submenu, {
        text = _("Soft-hyphens only"),
        callback = function()
            self.hyph_soft_hyphens_only = not self.hyph_soft_hyphens_only
            self.hyph_force_algorithmic = false
            self.ui.document:setTextHyphenationSoftHyphensOnly(self.hyph_soft_hyphens_only)
            self.ui.document:setTextHyphenationForceAlgorithmic(self.hyph_force_algorithmic)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        hold_callback = function()
            local hyph_soft_hyphens_only = G_reader_settings:isTrue("hyph_soft_hyphens_only")
            UIManager:show(MultiConfirmBox:new{
                text = hyph_soft_hyphens_only and _("Would you like to enable or disable hyphenation with soft hyphens only by default?\n\nThe current default (★) is enabled.")
                or _("Would you like to enable or disable hyphenation with soft hyphens only by default?\n\nThe current default (★) is disabled."),
                choice1_text_func =  function()
                    return hyph_soft_hyphens_only and _("Disable") or _("Disable (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:saveSetting("hyph_soft_hyphens_only", false)
                end,
                choice2_text_func = function()
                    return hyph_soft_hyphens_only and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:saveSetting("hyph_soft_hyphens_only", true)
                end,
            })
        end,
        checked_func = function()
            return self.hyphenation and self.hyph_soft_hyphens_only
        end,
        enabled_func = function()
            return self.hyphenation
        end,
    })

    table.insert(self.menu_table, {
        text_func = function()
            local method
            -- text = text .. "  ✓"
            -- text = text .. "  ✕"
            if not self.hyphenation then
                method = _("disabled")
            elseif self.hyph_soft_hyphens_only then
                method = _("soft-hyphens only")
            elseif self.hyph_force_algorithmic then
                method = _("algorithmic")
            else
                method = self:getCurrentDefaultHyphDictLanguage()
            end
            return T(_("Hyphenation: %1"), method)
        end,
        sub_item_table = hyphenation_submenu,
    })

    self.ui.menu:registerToMainMenu(self)
end

function ReaderTypography:addToMainMenu(menu_items)
    self.menu_table.max_per_page = 7
    -- insert table to main reader menu
    menu_items.typography = {
        text_func = function()
            local lang_name = LANG_TAG_TO_LANG_NAME[self.text_lang_tag] or self.text_lang_tag
            return T(_("Typography rules: %1"), lang_name)
        end,
        sub_item_table = self.menu_table,
    }
end

function ReaderTypography:getCurrentDefaultHyphDictLanguage()
    local hyph_dict_name = self.ui.document:getTextMainLangDefaultHyphDictionary()
    local dict_info = HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_dict_name]
    if dict_info then
        hyph_dict_name = dict_info[1]
    else -- shouldn't happen
        hyph_dict_name = hyph_dict_name:gsub(".pattern$", "")
    end
    return hyph_dict_name
end

function ReaderTypography:parseLanguageTag(lang_tag)
    -- Parse an RFC 5646 language tag, like "en-US" or "en".
    -- https://tools.ietf.org/html/rfc5646

    -- We are mostly interested in the language and region parts.
    local language = nil
    local region = nil

    for part in util.gsplit(lang_tag, "-", false) do
        if not language then
            language = string.lower(part)
        elseif string.len(part) == 2 and not string.match(part, "[^%a]") then
            region = string.upper(part)
        end
    end
    return language, region
end

function ReaderTypography:fixLangTag(lang_tag)
    -- EPUB language is an RFC 5646 language tag.
    --   http://www.idpf.org/epub/301/spec/epub-publications.html#sec-opf-dclanguage
    --   https://tools.ietf.org/html/rfc5646
    -- FB2 language is a two-letter language code (which is also a valid RFC 5646 language tag).
    --   http://fictionbook.org/index.php/%D0%AD%D0%BB%D0%B5%D0%BC%D0%B5%D0%BD%D1%82_lang (in Russian)

    if not lang_tag or lang_tag == "" then
        return nil
    end

    -- local language, region = self:parseLanguageTag(lang_tag)

    -- Trust book lang tag, even if it does not map to one we know
    -- (Harfbuzz and fonts might have more ability than us at
    -- dealing with this tag)
    -- But just look it up in the aliases if it can be mapped to
    -- a known tag
    if LANG_ALIAS_TO_LANG_TAG[lang_tag] then
        lang_tag = LANG_ALIAS_TO_LANG_TAG[lang_tag]
    end

    return lang_tag
end

-- Setting the text lang before loading the document may save crengine
-- from re-doing some expensive work at render time (the main text lang
-- is accounted in the nodeStyleHash, and would cause a mismatch if it is
-- different at render time from how it was at load time - "en-US" by
-- default - causing a full re-init of the nodes styles.)
-- We will only re-set it on pre-render (only then, after loading, we
-- know the document language) if it's really needed: when no lan saved
-- in book settings, no default lang, and book has some language defined.
function ReaderTypography:onReadSettings(config)
    -- Migrate old readerhyphenation setting, if one was set
    if not config:readSetting("text_lang") and config:readSetting("hyph_alg") then
        local hyph_alg = config:readSetting("hyph_alg")
        local dict_info = HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg]
        if dict_info then
            config:saveSetting("text_lang", dict_info[2])
            -- Set the other settings if the default hyph algo happens
            -- to be one of these:
            if hyph_alg == "@none" then
                config:saveSetting("hyphenation", false)
            elseif hyph_alg == "@softhyphens" then
                config:saveSetting("hyph_soft_hyphens_only", true)
            elseif hyph_alg == "@algorithm" then
                config:saveSetting("hyph_force_algorithmic", true)
            end
        end
    end

    -- Enable text lang tags attributes by default
    self.text_lang_embedded_langs = config:readSetting("text_lang_embedded_langs")
    if self.text_lang_embedded_langs == nil then
        self.text_lang_embedded_langs = G_reader_settings:nilOrTrue("text_lang_embedded_langs")
    end
    self.ui.document:setTextEmbeddedLangs(self.text_lang_embedded_langs)

    -- Enable hyphenation by default
    self.hyphenation = config:readSetting("hyphenation")
    if self.hyphenation == nil then
        self.hyphenation = G_reader_settings:nilOrTrue("hyphenation")
    end
    self.ui.document:setTextHyphenation(self.hyphenation)

    -- Checking for soft-hyphens adds a bit of overhead, so have it disabled by default
    self.hyph_trust_soft_hyphens = config:readSetting("hyph_trust_soft_hyphens")
    if self.hyph_trust_soft_hyphens == nil then
        self.hyph_trust_soft_hyphens = G_reader_settings:isTrue("hyph_trust_soft_hyphens")
    end
    self.ui.document:setTrustSoftHyphens(self.hyph_trust_soft_hyphens)

    -- Alternative hyphenation method (available with all dicts) to use soft hyphens only
    self.hyph_soft_hyphens_only = config:readSetting("hyph_soft_hyphens_only")
    if self.hyph_soft_hyphens_only == nil then
        self.hyph_soft_hyphens_only = G_reader_settings:isTrue("hyph_soft_hyphens_only")
    end
    self.ui.document:setTextHyphenationSoftHyphensOnly(self.hyph_soft_hyphens_only)

    -- Alternative hyphenation method (available with all dicts) to use algorithmic hyphenation
    self.hyph_force_algorithmic = config:readSetting("hyph_force_algorithmic")
    if self.hyph_force_algorithmic == nil then
        self.hyph_force_algorithmic = G_reader_settings:isTrue("hyph_force_algorithmic")
    end
    self.ui.document:setTextHyphenationForceAlgorithmic(self.hyph_force_algorithmic)

    -- These are global only settings (a bit complicated to make them per-document)
    self.ui.document:setHyphLeftHyphenMin(G_reader_settings:readSetting("hyph_left_hyphen_min") or 0)
    self.ui.document:setHyphRightHyphenMin(G_reader_settings:readSetting("hyph_right_hyphen_min") or 0)

    -- Decide and set the text main lang tag according to settings
    self.allow_doc_lang_tag_override = false
    -- Use the one manually set for this document
    self.text_lang_tag = config:readSetting("text_lang")
    if self.text_lang_tag then
        logger.dbg("Typography lang: using", self.text_lang_tag, "from doc settings")
        self.ui.document:setTextMainLang(self.text_lang_tag)
        return
    end
    -- Use the one manually set as default (with Hold)
    self.text_lang_tag = G_reader_settings:readSetting("text_lang_default")
    if self.text_lang_tag then
        logger.dbg("Typography lang: using default ", self.text_lang_tag)
        self.ui.document:setTextMainLang(self.text_lang_tag)
        return
    end
    -- Document language will be allowed to override the one we set from now on
    self.allow_doc_lang_tag_override = true
    -- Use the one manually set as fallback (with Hold)
    self.text_lang_tag = G_reader_settings:readSetting("text_lang_fallback")
    if self.text_lang_tag then
        logger.dbg("Typography lang: using fallback ", self.text_lang_tag, ", might be overriden by doc language")
        self.ui.document:setTextMainLang(self.text_lang_tag)
        return
    end
    -- None decided, use default (shouldn't be reached)
    self.text_lang_tag = DEFAULT_LANG_TAG
    logger.dbg("Typography lang: no lang set, using", self.text_lang_tag)
    self.ui.document:setTextMainLang(self.text_lang_tag)
end

function ReaderTypography:onPreRenderDocument(config)
    -- This is called after the document has been loaded,
    -- when we know and can access the document language.
    local doc_language = self.ui.document:getProps().language
    self.book_lang_tag = self:fixLangTag(doc_language)

    local is_known_lang_tag = self.book_lang_tag and LANG_TAG_TO_LANG_NAME[self.book_lang_tag] ~= nil
    -- Add a menu item to language sub-menu, whether the lang is known or not, so the
    -- user can see it and switch from and back to it easily
    table.insert(self.language_submenu, 1, {
        text = T(_("Book language: %1"), self.book_lang_tag or _("n/a")),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = T(_("Changed language for typography rules to book language: %1."), BD.wrap(self.book_lang_tag)),
            })
            self.text_lang_tag = self.book_lang_tag
            self.ui.doc_settings:saveSetting("text_lang", self.text_lang_tag)
            self.ui.document:setTextMainLang(self.text_lang_tag)
            self.ui:handleEvent(Event:new("UpdatePos"))
        end,
        enabled_func = function()
            return self.book_lang_tag ~= nil
        end,
        checked_func = function()
            return self.text_lang_tag == self.book_lang_tag
        end,
        separator = true,
    })

    if not self.allow_doc_lang_tag_override then
        logger.dbg("Typography lang: not overriding", self.text_lang_tag, "with doc language:",
            (self.book_lang_tag and self.book_lang_tag or "none"))
    elseif not self.book_lang_tag then
        logger.dbg("Typography lang: no doc language, keeping", self.text_lang_tag)
    else
        if is_known_lang_tag then
            if self.book_lang_tag == self.text_lang_tag then
                logger.dbg("Typography lang: current", self.text_lang_tag, "is same as doc language")
            else
                logger.dbg("Typography lang: updating for doc language", doc_language, ":", self.text_lang_tag, "=>", self.book_lang_tag)
            end
        else
            -- Log it as info, so users can see that too in crash.log
            logger.info("Typography lang: updating for doc language", doc_language, ":", self.book_lang_tag, "(not a preset)")
        end
        self.text_lang_tag = self.book_lang_tag
        self.ui.document:setTextMainLang(self.text_lang_tag)
    end
end

function ReaderTypography:onSaveSettings()
    self.ui.doc_settings:saveSetting("text_lang", self.text_lang_tag)
    self.ui.doc_settings:saveSetting("text_lang_embedded_langs", self.text_lang_embedded_langs)
    self.ui.doc_settings:saveSetting("hyphenation", self.hyphenation)
    self.ui.doc_settings:saveSetting("hyph_trust_soft_hyphens", self.hyph_trust_soft_hyphens)
    self.ui.doc_settings:saveSetting("hyph_soft_hyphens_only", self.hyph_soft_hyphens_only)
    self.ui.doc_settings:saveSetting("hyph_force_algorithmic", self.hyph_force_algorithmic)
end

return ReaderTypography
