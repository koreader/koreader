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

local ReaderTypography = InputContainer:new{}

-- This is used to migrate old hyph settings, and to show the currently
-- used hyph dict language in the hyphenation menu.
-- It will be completed with info from the LANGUAGES table below.
-- NOTE: Actual migration is handled in ui/data/onetime_migration,
--       which is why this hash is public.
ReaderTypography.HYPH_DICT_NAME_TO_LANG_NAME_TAG = {
    ["@none"]                = { "@none",           "en" },
    ["@softhyphens"]         = { "@softhyphens",    "en" },
    ["@algorithm"]           = { "@algorithm",      "en" },
    -- Old filenames with typos, before they were renamed
    ["Roman.pattern"]        = { _("Romanian"),     "ro" },
    ["Ukrain.pattern"]       = { _("Ukrainian"),    "uk" },
}

-- Languages to be shown in the menu.
-- Aliases are language tags that could possibly be found in the book
-- language metadata, that we wish to map to the correct lang tag.
-- Features:
--   H = language specific hyphenation dictionary
--   b = language specific line breaking rules
--   B = language specific additional line breaking tweaks
-- The "hyphenation file name" field is used to
-- update HYPH_DICT_NAME_TO_LANG_NAME_TAG. If multiple
-- languages were to use the same hyphenation pattern,
-- just set it for one language, whose name will be
-- used in the Hyphenation sub-menu.
-- Update them when language tweaks and features are added to crengine/src/textlang.cpp
local LANGUAGES = {
    -- lang-tag          aliases    features    menu title                  hyphenation file name
    { "hy", {"arm", "hye", "hyw"},   "H   ",   _("Armenian"),               "Armenian.pattern" },
    { "eu",                    {},   "H   ",   _("Basque"),                 "Basque.pattern" },
    { "bg",               {"bul"},   "H   ",   _("Bulgarian"),              "Bulgarian.pattern" },
    { "ca",               {"cat"},   "H   ",   _("Catalan"),                "Catalan.pattern" },
    { "zh-CN",  {"zh", "zh-Hans"},   " b  ",   _("Chinese (Simplified)") },
    { "zh-TW",        {"zh-Hant"},   " b  ",   _("Chinese (Traditional)") },
    { "hr",                    {},   "H   ",   _("Croatian"),               "Croatian.pattern" },
    { "cs",               {"ces"},   "HB  ",   _("Czech"),                  "Czech.pattern" },
    { "da",               {"dan"},   "H   ",   _("Danish"),                 "Danish.pattern" },
    { "nl",               {"nld"},   "H   ",   _("Dutch"),                  "Dutch.pattern" },
    { "en-GB",                 {},   "Hb  ",   _("English (UK)"),           "English_GB.pattern" },
    { "en-US",      {"en", "eng"},   "Hb  ",   _("English (US)"),           "English_US.pattern" },
    { "eo",               {"epo"},   "H   ",   _("Esperanto"),              "Esperanto.pattern" },
    { "et",               {"est"},   "H   ",   _("Estonian"),               "Estonian.pattern" },
    { "fi",               {"fin"},   "H   ",   _("Finnish"),                "Finnish.pattern" },
    { "fr",        {"fra", "fre"},   "Hb  ",   _("French"),                 "French.pattern" },
    { "fur",                   {},   "H   ",   _("Friulian"),               "Friulian.pattern" },
    { "gl",               {"glg"},   "H   ",   _("Galician"),               "Galician.pattern" },
    { "ka",                    {},   "H   ",   _("Georgian"),               "Georgian.pattern" },
    { "de",               {"deu"},   "Hb  ",   _("German"),                 "German.pattern" },
    { "el",               {"ell"},   "H   ",   _("Greek"),                  "Greek.pattern" },
    { "hu",               {"hun"},   "H   ",   _("Hungarian"),              "Hungarian.pattern" },
    { "is",               {"isl"},   "H   ",   _("Icelandic"),              "Icelandic.pattern" },
    { "ga",               {"gle"},   "H   ",   _("Irish"),                  "Irish.pattern" },
    { "it",               {"ita"},   "H   ",   _("Italian"),                "Italian.pattern" },
    { "ja",                    {},   "    ",   _("Japanese") },
    { "ko",                    {},   "    ",   _("Korean") },
    { "la",               {"lat"},   "H   ",   _("Latin"),                  "Latin.pattern" },
    { "la-lit",       {"lat-lit"},   "H   ",   _("Latin (liturgical)"),     "Latin_liturgical.pattern" },
    { "lv",               {"lav"},   "H   ",   _("Latvian"),                "Latvian.pattern" },
    { "lt",               {"lit"},   "H   ",   _("Lithuanian"),             "Lithuanian.pattern" },
    { "mk",                  {""},   "H   ",   _("Macedonian"),             "Macedonian.pattern" },
    { "no",               {"nor"},   "H   ",   _("Norwegian"),              "Norwegian.pattern" },
    { "oc",               {"oci"},   "H   ",   _("Occitan"),                "Occitan.pattern" },
    { "pl",               {"pol"},   "HB  ",   _("Polish"),                 "Polish.pattern" },
    { "pms",                   {},   "H   ",   _("Piedmontese"),            "Piedmontese.pattern" },
    { "pt",               {"por"},   "HB  ",   _("Portuguese"),             "Portuguese.pattern" },
    { "pt-BR",                 {},   "HB  ",   _("Portuguese (BR)"),        "Portuguese_BR.pattern" },
    { "rm",               {"roh"},   "H   ",   _("Romansh"),                "Romansh.pattern" },
    { "ro",               {"ron"},   "H   ",   _("Romanian"),               "Romanian.pattern" },
    { "ru",               {"rus"},   "Hb  ",   _("Russian"),                "Russian.pattern" },
    { "ru-GB",                 {},   "Hb  ",   _("Russian + English (UK)"), "Russian_EnGB.pattern" },
    { "ru-US",                 {},   "Hb  ",   _("Russian + English (US)"), "Russian_EnUS.pattern" },
    { "sr",               {"srp"},   "HB  ",   _("Serbian"),                "Serbian.pattern" },
    { "sk",               {"slk"},   "HB  ",   _("Slovak"),                 "Slovak.pattern" },
    { "sl",               {"slv"},   "H   ",   _("Slovenian"),              "Slovenian.pattern" },
    { "es",               {"spa"},   "Hb  ",   _("Spanish"),                "Spanish.pattern" },
    { "sv",               {"swe"},   "H   ",   _("Swedish"),                "Swedish.pattern" },
    { "tr",               {"tur"},   "H   ",   _("Turkish"),                "Turkish.pattern" },
    { "uk",               {"ukr"},   "H   ",   _("Ukrainian"),              "Ukrainian.pattern" },
    { "cy",               {"cym"},   "H   ",   _("Welsh"),                  "Welsh.pattern" },
    { "zu",               {"zul"},   "H   ",   _("Zulu"),                   "Zulu.pattern" },
}

ReaderTypography.DEFAULT_LANG_TAG = "en-US" -- English_US.pattern is loaded by default in crengine

local LANG_TAG_TO_LANG_NAME = {}
local LANG_ALIAS_TO_LANG_TAG = {}
for __, v in ipairs(LANGUAGES) do
    local lang_tag, lang_aliases, lang_features, lang_name, hyph_filename = unpack(v) -- luacheck: no unused
    LANG_TAG_TO_LANG_NAME[lang_tag] = lang_name
    if lang_aliases and #lang_aliases > 0 then
        for ___, alias in ipairs(lang_aliases) do
            LANG_ALIAS_TO_LANG_TAG[alias] = lang_tag
        end
    end
    if hyph_filename then
        ReaderTypography.HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_filename] = { lang_name, lang_tag }
    end
end

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
    self.floating_punctuation = 0

    local info_text = _([[
Some languages have specific typographic rules: these include hyphenation, line breaking rules, and language specific glyph variants.
KOReader will choose one according to the language tag from the book's metadata, but you can select another one.
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
                self.ui:handleEvent(Event:new("TypographyLanguageChanged"))
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
                    G_reader_settings:makeFalse("text_lang_embedded_langs")
                end,
                choice2_text_func = function()
                    return text_lang_embedded_langs and _("Respect (★)") or _("Respect")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("text_lang_embedded_langs")
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
                    G_reader_settings:makeFalse("hyphenation")
                end,
                choice2_text_func = function()
                    return hyphenation and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("hyphenation")
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
            if G_reader_settings:has("hyph_left_hyphen_min") or
                        G_reader_settings:has("hyph_right_hyphen_min") then
                -- @translators to RTL language translators: %1/left is the min length of the start of a hyphenated word, %2/right is the min length of the end of a hyphenated word (note that there is yet no support for hyphenation with RTL languages, so this will mostly apply to LTR documents)
                return T(_("Left/right minimal sizes: %1 - %2"),
                    G_reader_settings:readSetting("hyph_left_hyphen_min"),
                    G_reader_settings:readSetting("hyph_right_hyphen_min"))
            end
            return _("Left/right minimal sizes: language defaults")
        end,
        callback = function()
            local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
            local hyph_alg, alg_left_hyphen_min, alg_right_hyphen_min = cre.getSelectedHyphDict() -- luacheck: no unused
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
                    G_reader_settings:makeFalse("hyph_trust_soft_hyphens")
                end,
                choice2_text_func = function()
                    return hyph_trust_soft_hyphens and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("hyph_trust_soft_hyphens")
                end,
            })
        end,
        checked_func = function()
            return self.hyphenation and (self.hyph_trust_soft_hyphens or self.hyph_soft_hyphens_only)
        end,
        enabled_func = function()
            return self.hyphenation and not self.hyph_soft_hyphens_only
        end,
    })
    table.insert(hyphenation_submenu, self.ui.userhyph:getMenuEntry())
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
                    G_reader_settings:makeFalse("hyph_force_algorithmic")
                end,
                choice2_text_func = function()
                    return hyph_force_algorithmic and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("hyph_force_algorithmic")
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
        text = _("Soft hyphens only"),
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
                    G_reader_settings:makeFalse("hyph_soft_hyphens_only")
                end,
                choice2_text_func = function()
                    return hyph_soft_hyphens_only and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("hyph_soft_hyphens_only")
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

    table.insert(self.menu_table, {
        -- @translators See https://en.wikipedia.org/wiki/Hanging_punctuation
        text = _("Hanging punctuation"),
        checked_func = function() return self.floating_punctuation == 1 end,
        callback = function()
            self.floating_punctuation = self.floating_punctuation == 1 and 0 or 1
            self:onToggleFloatingPunctuation(self.floating_punctuation)
        end,
        hold_callback = function() self:makeDefaultFloatingPunctuation() end,
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

function ReaderTypography:onToggleFloatingPunctuation(toggle)
    -- for some reason the toggle value read from history files may stay boolean
    -- and there seems no more elegant way to convert boolean values to numbers
    if toggle == true then
        toggle = 1
    elseif toggle == false then
        toggle = 0
    end
    self.ui.document:setFloatingPunctuation(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypography:makeDefaultFloatingPunctuation()
    local floating_punctuation = G_reader_settings:isTrue("floating_punctuation")
    UIManager:show(MultiConfirmBox:new{
        text = floating_punctuation and _("Would you like to enable or disable hanging punctuation by default?\n\nThe current default (★) is enabled.")
        or _("Would you like to enable or disable hanging punctuation by default?\n\nThe current default (★) is disabled."),
        choice1_text_func =  function()
            return floating_punctuation and _("Disable") or _("Disable (★)")
        end,
        choice1_callback = function()
            G_reader_settings:makeFalse("floating_punctuation")
        end,
        choice2_text_func = function()
            return floating_punctuation and _("Enable (★)") or _("Enable")
        end,
        choice2_callback = function()
            G_reader_settings:makeTrue("floating_punctuation")
        end,
    })
end


function ReaderTypography:getCurrentDefaultHyphDictLanguage()
    local hyph_dict_name = self.ui.document:getTextMainLangDefaultHyphDictionary()
    local dict_info = self.HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_dict_name]
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
    if config:hasNot("text_lang") and config:has("hyph_alg") then
        local hyph_alg = config:readSetting("hyph_alg")
        local dict_info = self.HYPH_DICT_NAME_TO_LANG_NAME_TAG[hyph_alg]
        if dict_info then
            config:saveSetting("text_lang", dict_info[2])
            -- Set the other settings if the default hyph algo happens
            -- to be one of these:
            if hyph_alg == "@none" then
                config:makeFalse("hyphenation")
            elseif hyph_alg == "@softhyphens" then
                config:makeTrue("hyph_soft_hyphens_only")
            elseif hyph_alg == "@algorithm" then
                config:makeTrue("hyph_force_algorithmic")
            end
        end
    end

    -- Enable text lang tags attributes by default
    if config:has("text_lang_embedded_langs") then
        self.text_lang_embedded_langs = config:isTrue("text_lang_embedded_langs")
    else
        self.text_lang_embedded_langs = G_reader_settings:nilOrTrue("text_lang_embedded_langs")
    end
    self.ui.document:setTextEmbeddedLangs(self.text_lang_embedded_langs)

    -- Enable hyphenation by default
    if config:has("hyphenation") then
        self.hyphenation = config:isTrue("hyphenation")
    else
        self.hyphenation = G_reader_settings:nilOrTrue("hyphenation")
    end
    self.ui.document:setTextHyphenation(self.hyphenation)

    -- Checking for soft-hyphens adds a bit of overhead, so have it disabled by default
    if config:has("hyph_trust_soft_hyphens") then
        self.hyph_trust_soft_hyphens = config:isTrue("hyph_trust_soft_hyphens")
    else
        self.hyph_trust_soft_hyphens = G_reader_settings:isTrue("hyph_trust_soft_hyphens")
    end
    self.ui.document:setTrustSoftHyphens(self.hyph_trust_soft_hyphens)

    -- Alternative hyphenation method (available with all dicts) to use soft hyphens only
    if config:has("hyph_soft_hyphens_only") then
        self.hyph_soft_hyphens_only = config:isTrue("hyph_soft_hyphens_only")
    else
        self.hyph_soft_hyphens_only = G_reader_settings:isTrue("hyph_soft_hyphens_only")
    end
    self.ui.document:setTextHyphenationSoftHyphensOnly(self.hyph_soft_hyphens_only)

    -- Alternative hyphenation method (available with all dicts) to use algorithmic hyphenation
    if config:has("hyph_force_algorithmic") then
        self.hyph_force_algorithmic = config:isTrue("hyph_force_algorithmic")
    else
        self.hyph_force_algorithmic = G_reader_settings:isTrue("hyph_force_algorithmic")
    end
    self.ui.document:setTextHyphenationForceAlgorithmic(self.hyph_force_algorithmic)

    -- These are global only settings (a bit complicated to make them per-document)
    self.ui.document:setHyphLeftHyphenMin(G_reader_settings:readSetting("hyph_left_hyphen_min") or 0)
    self.ui.document:setHyphRightHyphenMin(G_reader_settings:readSetting("hyph_right_hyphen_min") or 0)

    -- Default to disable hanging/floating punctuation
    -- (Stored as 0/1 in docsetting for historical reasons, but as true/false
    -- in global settings.)
    if config:has("floating_punctuation") then
        self.floating_punctuation = config:readSetting("floating_punctuation")
    else
        self.floating_punctuation = G_reader_settings:isTrue("floating_punctuation") and 1 or 0
    end
    self:onToggleFloatingPunctuation(self.floating_punctuation)

    -- Decide and set the text main lang tag according to settings
    if config:has("text_lang") then
        self.allow_doc_lang_tag_override = false
        -- Use the one manually set for this document
        self.text_lang_tag = config:readSetting("text_lang")
        logger.dbg("Typography lang: using", self.text_lang_tag, "from doc settings")
    elseif G_reader_settings:has("text_lang_default") then
        self.allow_doc_lang_tag_override = false
        -- Use the one manually set as default (with Hold)
        self.text_lang_tag = G_reader_settings:readSetting("text_lang_default")
        logger.dbg("Typography lang: using default ", self.text_lang_tag)
    elseif G_reader_settings:has("text_lang_fallback") then
        -- Document language will be allowed to override the one we set from now on
        self.allow_doc_lang_tag_override = true
        -- Use the one manually set as fallback (with Hold)
        self.text_lang_tag = G_reader_settings:readSetting("text_lang_fallback")
        logger.dbg("Typography lang: using fallback ", self.text_lang_tag, ", might be overriden by doc language")
    else
        self.allow_doc_lang_tag_override = true
        -- None decided, use default (shouldn't be reached)
        self.text_lang_tag = self.DEFAULT_LANG_TAG
        logger.dbg("Typography lang: no lang set, using", self.text_lang_tag)
    end
    self.ui.document:setTextMainLang(self.text_lang_tag)
    self.ui:handleEvent(Event:new("TypographyLanguageChanged"))
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
        text = T(_("Book language: %1"), self.book_lang_tag or _("N/A")),
        callback = function()
            UIManager:show(InfoMessage:new{
                text = T(_("Changed language for typography rules to book language: %1."), BD.wrap(self.book_lang_tag)),
            })
            self.text_lang_tag = self.book_lang_tag
            self.ui.doc_settings:saveSetting("text_lang", self.text_lang_tag)
            self.ui.document:setTextMainLang(self.text_lang_tag)
            self.ui:handleEvent(Event:new("TypographyLanguageChanged"))
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
        self.ui:handleEvent(Event:new("TypographyLanguageChanged"))
    end
end

function ReaderTypography:onSaveSettings()
    self.ui.doc_settings:saveSetting("text_lang", self.text_lang_tag)
    self.ui.doc_settings:saveSetting("text_lang_embedded_langs", self.text_lang_embedded_langs)
    self.ui.doc_settings:saveSetting("hyphenation", self.hyphenation)
    self.ui.doc_settings:saveSetting("hyph_trust_soft_hyphens", self.hyph_trust_soft_hyphens)
    self.ui.doc_settings:saveSetting("hyph_soft_hyphens_only", self.hyph_soft_hyphens_only)
    self.ui.doc_settings:saveSetting("hyph_force_algorithmic", self.hyph_force_algorithmic)
    self.ui.doc_settings:saveSetting("floating_punctuation", self.floating_punctuation)
end

return ReaderTypography
