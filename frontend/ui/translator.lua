--[[--
This module translates text using Google Translate.

<https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=fr&dt=t&q=alea%20jacta%20est>

--]]

-- Useful other implementation and discussion:
--  https://github.com/ssut/py-googletrans/blob/master/googletrans/client.py
--  https://stackoverflow.com/questions/26714426/what-is-the-meaning-of-google-translate-query-params

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local Screen = require("device").screen
local ffiutil  = require("ffi/util")
local logger = require("logger")
local util = require("util")
local T = ffiutil.template
local _ = require("gettext")

-- From https://cloud.google.com/translate/docs/languages
-- 20181217: 104 supported languages
local AUTODETECT_LANGUAGE = "auto"
local SUPPORTED_LANGUAGES = {
    -- @translators Many of the names for languages can be conveniently found pre-translated in the relevant language of this Wikipedia article: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    af = _("Afrikaans"),
    sq = _("Albanian"),
    am = _("Amharic"),
    ar = _("Arabic"),
    hy = _("Armenian"),
    az = _("Azerbaijani"),
    eu = _("Basque"),
    be = _("Belarusian"),
    bn = _("Bengali"),
    bs = _("Bosnian"),
    bg = _("Bulgarian"),
    ca = _("Catalan"),
    ceb = _("Cebuano"),
    zh = _("Chinese (Simplified)"), -- "Simplified Chinese may be specified either by zh-CN or zh"
    zh_TW = _("Chinese (Traditional)"), -- converted to "zh-TW" below
    co = _("Corsican"),
    hr = _("Croatian"),
    cs = _("Czech"),
    da = _("Danish"),
    nl = _("Dutch"),
    en = _("English"),
    eo = _("Esperanto"),
    et = _("Estonian"),
    fi = _("Finnish"),
    fr = _("French"),
    fy = _("Frisian"),
    gl = _("Galician"),
    ka = _("Georgian"),
    de = _("German"),
    el = _("Greek"),
    -- @translators Many of the names for languages can be conveniently found pre-translated in the relevant language of this Wikipedia article: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    gu = _("Gujarati"),
    ht = _("Haitian Creole"),
    ha = _("Hausa"),
    haw = _("Hawaiian"),
    he = _("Hebrew"), -- "Hebrew may be specified either by he or iw"
    hi = _("Hindi"),
    hmn = _("Hmong"),
    hu = _("Hungarian"),
    is = _("Icelandic"),
    ig = _("Igbo"),
    id = _("Indonesian"),
    ga = _("Irish"),
    it = _("Italian"),
    ja = _("Japanese"),
    jw = _("Javanese"),
    -- @translators Many of the names for languages can be conveniently found pre-translated in the relevant language of this Wikipedia article: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    kn = _("Kannada"),
    kk = _("Kazakh"),
    km = _("Khmer"),
    ko = _("Korean"),
    ku = _("Kurdish"),
    ky = _("Kyrgyz"),
    lo = _("Lao"),
    la = _("Latin"),
    lv = _("Latvian"),
    lt = _("Lithuanian"),
    lb = _("Luxembourgish"),
    mk = _("Macedonian"),
    mg = _("Malagasy"),
    ms = _("Malay"),
    ml = _("Malayalam"),
    mt = _("Maltese"),
    mi = _("Maori"),
    mr = _("Marathi"),
    mn = _("Mongolian"),
    my = _("Myanmar (Burmese)"),
    ne = _("Nepali"),
    no = _("Norwegian"),
    ny = _("Nyanja (Chichewa)"),
    ps = _("Pashto"),
    fa = _("Persian"),
    pl = _("Polish"),
    pt = _("Portuguese"),
    pa = _("Punjabi"),
    ro = _("Romanian"),
    ru = _("Russian"),
    sm = _("Samoan"),
    gd = _("Scots Gaelic"),
    sr = _("Serbian"),
    st = _("Sesotho"),
    sn = _("Shona"),
    sd = _("Sindhi"),
    si = _("Sinhala (Sinhalese)"),
    sk = _("Slovak"),
    sl = _("Slovenian"),
    so = _("Somali"),
    es = _("Spanish"),
    su = _("Sundanese"),
    sw = _("Swahili"),
    sv = _("Swedish"),
    tl = _("Tagalog (Filipino)"),
    tg = _("Tajik"),
    ta = _("Tamil"),
    te = _("Telugu"),
    th = _("Thai"),
    tr = _("Turkish"),
    uk = _("Ukrainian"),
    ur = _("Urdu"),
    uz = _("Uzbek"),
    vi = _("Vietnamese"),
    cy = _("Welsh"),
    -- @translators Many of the names for languages can be conveniently found pre-translated in the relevant language of this Wikipedia article: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    xh = _("Xhosa"),
    yi = _("Yiddish"),
    yo = _("Yoruba"),
    zu = _("Zulu"),
}
-- Fix zh_TW => zh-TW:
SUPPORTED_LANGUAGES["zh-TW"] = SUPPORTED_LANGUAGES["zh_TW"]
SUPPORTED_LANGUAGES["zh_TW"] = nil

local ALT_LANGUAGE_CODES = {}
ALT_LANGUAGE_CODES["zh-CN"] = "zh"
ALT_LANGUAGE_CODES["iw"] = "he"

local Translator = {
    trans_servers = {
        "https://translate.googleapis.com/",
        -- "http://translate.google.cn",
    },
    trans_path = "/translate_a/single",
    trans_params = {
        client = "gtx", -- (using "t" raises 403 Forbidden)
        ie = "UTF-8", -- input encoding
        oe = "UTF-8", -- output encoding
        sl = "auto",  -- source language (we need to specify "auto" to detect language)
        tl = "en", -- target language
        hl = "en", -- ?
        otf = 1,   -- ?
        ssel = 0,  -- ?
        tsel = 0,  -- ?
        -- tk = "" -- auth token
        dt = { -- what we want in result
            "t",   -- translation of source text
            "at",  -- alternate translations
            -- Next options only give additional results when text is a single word
            -- "bd",  -- dictionary (articles, reverse translations, etc)
            -- "ex",  -- examples
            -- "ld",  -- ?
            "md",  -- definitions of source text
            -- "qca", -- ?
            -- "rw",  -- "see also" list
            -- "rm",  -- transcription / transliteration of source and translated texts
            -- "ss",  -- synonyms of source text, if it's one word
        }
        -- q = text to translate
    },
    default_lang = "en",
}

function Translator:getTransServer()
    return G_reader_settings:readSetting("trans_server") or self.trans_servers[1]
end

function Translator:getLanguageName(lang, default_string)
    if SUPPORTED_LANGUAGES[lang] then
        return SUPPORTED_LANGUAGES[lang]
    elseif ALT_LANGUAGE_CODES[lang] then
        return SUPPORTED_LANGUAGES[ALT_LANGUAGE_CODES[lang]]
    elseif lang then
        return lang:upper()
    end
    return default_string
end

-- Will be called by ReaderHighlight to make it available in Reader menu
function Translator:genSettingsMenu()
    local function genLanguagesItems(setting_name, default_checked_item)
        local items_table = {}
        for lang_key, lang_name in ffiutil.orderedPairs(SUPPORTED_LANGUAGES) do
            table.insert(items_table, {
                text_func = function()
                    return T("%1 (%2)", lang_name, lang_key)
                end,
                checked_func = function()
                    if G_reader_settings:has(setting_name) then
                        return lang_key == G_reader_settings:readSetting(setting_name)
                    else
                        return lang_key == default_checked_item
                    end
                end,
                callback = function()
                    G_reader_settings:saveSetting(setting_name, lang_key)
                end,
            })
        end
        return items_table
    end
    return {
        text = _("Translation settings"),
        sub_item_table = {
            {
                text = _("Auto-detect source language"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("translator_from_auto_detect")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("translator_from_auto_detect")
                end,
            },
            {
                text_func = function()
                    local lang = G_reader_settings:readSetting("translator_from_language")
                    return T(_("Translate from: %1"), self:getLanguageName(lang, ""))
                end,
                enabled_func = function()
                    return not G_reader_settings:nilOrTrue("translator_from_auto_detect")
                end,
                sub_item_table = genLanguagesItems("translator_from_language"),
                keep_menu_open = true,
                separator = true,
            },
            {
                text_func = function()
                    local lang = self:getTargetLanguage()
                    return T(_("Translate to: %1"), self:getLanguageName(lang, ""))
                end,
                sub_item_table = genLanguagesItems("translator_to_language", self:getTargetLanguage()),
                keep_menu_open = true,
            },
        },
    }
end

function Translator:getSourceLanguage()
    if G_reader_settings:isFalse("translator_from_auto_detect") and
            G_reader_settings:has("translator_from_language") then
        return G_reader_settings:readSetting("translator_from_language")
    end
    return AUTODETECT_LANGUAGE -- "auto"
end

function Translator:getTargetLanguage()
    local lang = G_reader_settings:readSetting("translator_to_language")
    if not lang then
        -- Fallback to the UI language the user has selected
        lang = G_reader_settings:readSetting("language")
        if lang and lang ~= "" then
            -- convert "zh-CN" and "zh-TW" to "zh"
            lang = lang:match("(.*)-") or lang
            if lang == "C" then
                lang="en"
            end
            lang = lang:lower()
        end
    end
    return lang or "en"
end

--[[--
Returns decoded JSON table from translate server.

@string text
@string target_lang
@string source_lang
@treturn string result, or nil
--]]
function Translator:loadPage(text, target_lang, source_lang)
    local socket = require("socket")
    local socketutil = require("socketutil")
    local url = require("socket.url")
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local query = ""
    self.trans_params.tl = target_lang
    self.trans_params.sl = source_lang
    for k,v in pairs(self.trans_params) do
        if type(v) == "table" then
            for _, v2 in ipairs(v) do
                query = query .. k .. '=' .. v2 .. '&'
            end
        else
            query = query .. k .. '=' .. v .. '&'
        end
    end
    local parsed = url.parse(self:getTransServer())
    parsed.path = self.trans_path
    parsed.query = query .. "q=" .. url.escape(text)

    -- HTTP request
    local sink = {}
    socketutil:set_timeout()
    local request = {
        url     = url.build(parsed),
        method  = "GET",
        sink    = ltn12.sink.table(sink),
    }
    logger.dbg("Calling", request.url)
    -- Skip first argument (body, goes to the sink)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    if code ~= 200 then
        logger.warn("translator HTTP status not okay:", status)
        return
    end

    local content = table.concat(sink)
    -- logger.dbg("translator content:", content)
    local first_char = content:sub(1, 1)
    if content ~= "" and (first_char == "{" or first_char == "[") then
        -- Get nil instead of functions for 'null' by using JSON.decode.simple
        -- (so the result can be fully serialized when used
        -- with Trapper:dismissableRunInSubprocess())
        local ok, result = pcall(JSON.decode, content, JSON.decode.simple)
        if ok and result then
            logger.dbg("translator json:", result)
            return result
        else
            logger.warn("translator error:", result)
        end
    else
        logger.warn("not JSON in translator response:", content)
    end
end
-- The JSON result is a list of 9 to 15 items:
--    1: translation
--    2: all-translations
--    3: original-language
--    6: possible-translations
--    7: confidence
--    8: possible-mistakes
--    9: language
--   12: synonyms
--   13: definitions
--   14: examples
--   15: see-also
-- Depending on the 'dt' parameters used, some may be null or absent.
-- See bottom of this file for some sample results.

--[[--
Tries to automatically detect language of `text`.

@string text
@treturn string lang (`"en"`, `"fr"`, `…`)
--]]
function Translator:detect(text)
    local result = self:loadPage(text, "en", AUTODETECT_LANGUAGE)
    if result and result[3] then
        local src_lang = result[3]
        logger.dbg("detected language:", src_lang)
        return src_lang
    else
        return self.default_lang
    end
end

--[[--
Translate text, returns translation as a single string.

@string text
@string target_lang[opt] (`"en"`, `"fr"`, `…`)
@string source_lang[opt="auto"] (`"en"`, `"fr"`, `…`) or `"auto"` to auto-detect source language
@treturn string translated text, or nil
--]]
function Translator:translate(text, target_lang, source_lang)
    if not target_lang then
        target_lang = self:getTargetLanguage()
    end
    if not source_lang then
        source_lang = self:getSourceLanguage()
    end
    local result = self:loadPage(text, target_lang, source_lang)
    if result and result[1] and type(result[1]) == "table" then
        local translated = {}
        for i, r in ipairs(result[1]) do
            table.insert(translated, r[1])
        end
        return table.concat(translated, "")
    end
    return nil
end

--[[--
Show translated text in TextViewer, with alternate translations

@string text
@string target_lang[opt] (`"en"`, `"fr"`, `…`)
@string source_lang[opt="auto"] (`"en"`, `"fr"`, `…`) or `"auto"` to auto-detect source language
--]]
function Translator:showTranslation(text, target_lang, source_lang)
    if Device:hasClipboard() then
        Device.input.setClipboardText(text)
    end

    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:willRerunWhenOnline(function() self:showTranslation(text, target_lang, source_lang) end) then
        return
    end

    -- Wrap next function with Trapper to be able to interrupt
    -- translation service query.
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        self:_showTranslation(text, target_lang, source_lang)
    end)
end

function Translator:_showTranslation(text, target_lang, source_lang)
    if not target_lang then
        target_lang = self:getTargetLanguage()
    end
    if not source_lang then
        source_lang = self:getSourceLanguage()
    end

    local Trapper = require("ui/trapper")
    local completed, result = Trapper:dismissableRunInSubprocess(function()
        return self:loadPage(text, target_lang, source_lang)
    end, _("Querying translation service…"))
    if not completed then
        UIManager:show(InfoMessage:new{
            text = _("Translation interrupted.")
        })
        return
    end
    if not result or type(result) ~= "table" then
        UIManager:show(InfoMessage:new{
            text = _("Translation failed.")
        })
        return
    end

    if result[3] then
        source_lang = result[3]
    end
    local output = {}

    -- For both main and alternate translations, we may get multiple slices
    -- of the original text and its translations.
    if result[1] and type(result[1]) == "table" and #result[1] > 0 then
        -- Main translation: we can make a single string from the multiple parts
        -- for easier quick reading
        local source = {}
        local translated = {}
        for i, r in ipairs(result[1]) do
            local s = type(r[2]) == "string" and r[2] or ""
            local t = type(r[1]) == "string" and r[1] or ""
            table.insert(source, s)
            table.insert(translated, t)
        end
        table.insert(output, "▣ " .. table.concat(source, " "))
        table.insert(output, "● " .. table.concat(translated, " "))
    end

    if result[6] and type(result[6]) == "table" and #result[6] > 0 then
        -- Alternative translations:
        table.insert(output, "________")
        for i, r in ipairs(result[6]) do
            if type(r[3]) == "table" then
                local s = type(r[1]) == "string" and r[1]:gsub("\n", "") or ""
                table.insert(output, "▣ " .. s)
                for j, rt in ipairs(r[3]) do
                    -- Use number in solid black circle symbol (U+2776...277F)
                    local symbol = util.unicodeCodepointToUtf8(10101 + (j < 10 and j or 10))
                    local t = type(rt[1]) == "string" and rt[1]:gsub("\n", "") or ""
                    table.insert(output, symbol .. " " .. t)
                end
            end
        end
    end

    if result[13] and type(result[13]) == "table" and #result[13] > 0 then
        -- Definition(word)
        table.insert(output, "________")
        for i, r in ipairs(result[13]) do
            if r[2] and type(r[2]) == "table" then
                local symbol = util.unicodeCodepointToUtf8(10101 + (i < 10 and i or 10))
                table.insert(output, symbol.. " ".. r[1])
                for j, res in ipairs(r[2]) do
                    table.insert(output, "\t● ".. res[1])
                end
            end
        end
    end

    -- table.insert(output, require("dump")(result)) -- for debugging
    UIManager:show(TextViewer:new{
        title = T(_("Translation from %1"), self:getLanguageName(source_lang, "?")),
            -- Showing the translation target language in this title may make
            -- it quite long and wrapped, taking valuable vertical spacing
        text = table.concat(output, "\n"),
        height = math.floor(Screen:getHeight() * 0.8),
        justified = G_reader_settings:nilOrTrue("dict_justify"),
    })
end

return Translator

-- Sample JSON results:
--
-- Multiple words result:
-- {
--     [1] = {
--         [1] = {
--             [1] = "I know you did not destroy your King's house, because then you had none. ",
--             [2] = "Ich weiß, dass ihr nicht eures Königs Haus zerstört habt, denn damals hattet ihr ja keinen.",
--             [5] = 3,
--             ["n"] = 5
--         },
--         [2] = {
--             [1] = "But you can not deny that you destroyed a royal palace. ",
--             [2] = "Aber ihr könnt nicht leugnen, dass ihr einen Königspalast zerstört habt.",
--             [5] = 3,
--             ["n"] = 5
--         },
--         [3] = {
--             [1] = "If the king is dead, then the kingdom remains, just as a ship remains, whose helmsman has fallen",
--             [2] = "Ist der König tot, so bleibt doch das Reich bestehen, ebenso wie ein Schiff bleibt, dessen Steuermann gefallen ist",
--             [5] = 3,
--             ["n"] = 5
--         }
--     },
--     [3] = "de",
--     [6] = {
--         [1] = {
--             [1] = "Ich weiß, dass ihr nicht eures Königs Haus zerstört habt, denn damals hattet ihr ja keinen.",
--             [3] = {
--                 [1] = {
--                     [1] = "I know you did not destroy your King's house, because then you had none.",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 },
--                 [2] = {
--                     [1] = "I know that you have not destroyed your king house, because at that time you had not any.",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 }
--             },
--             [4] = {
--                 [1] = {
--                     [1] = 0,
--                     [2] = 91
--                 }
--             },
--             [5] = "Ich weiß, dass ihr nicht eures Königs Haus zerstört habt, denn damals hattet ihr ja keinen.",
--             [6] = 0,
--             [7] = 0
--         },
--         [2] = {
--             [1] = "Aber ihr könnt nicht leugnen, dass ihr einen Königspalast zerstört habt.",
--             [3] = {
--                 [1] = {
--                     [1] = "But you can not deny that you destroyed a royal palace.",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 },
--                 [2] = {
--                     [1] = "But you can not deny that you have destroyed a royal palace.",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 }
--             },
--             [4] = {
--                 [1] = {
--                     [1] = 0,
--                     [2] = 72
--                 }
--             },
--             [5] = "Aber ihr könnt nicht leugnen, dass ihr einen Königspalast zerstört habt.",
--             [6] = 0,
--             [7] = 0
--         },
--         [3] = {
--             [1] = "Ist der König tot, so bleibt doch das Reich bestehen, ebenso wie ein Schiff bleibt, dessen Steuermann gefallen ist",
--             [3] = {
--                 [1] = {
--                     [1] = "If the king is dead, then the kingdom remains, just as a ship remains, whose helmsman has fallen",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 },
--                 [2] = {
--                     [1] = "yet the king dead, remains the kingdom stand remains as a ship the helmsman has fallen",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 }
--             },
--             [4] = {
--                 [1] = {
--                     [1] = 0,
--                     [2] = 114
--                 }
--             },
--             [5] = "Ist der König tot, so bleibt doch das Reich bestehen, ebenso wie ein Schiff bleibt, dessen Steuermann gefallen ist",
--             [6] = 0,
--             [7] = 0
--         }
--     },
--     [7] = 1,
--     [9] = {
--         [1] = {
--             [1] = "de"
--         },
--         [3] = {
--             [1] = 1
--         },
--         [4] = {
--             [1] = "de"
--         }
--     },
--     ["n"] = 9
-- }
--
-- Single word result with all dt= enabled:
-- {
--     [1] = {
--         [1] = {
--             [1] = "fork",
--             [2] = "fourchette",
--             [5] = 0,
--             ["n"] = 5
--         }
--     },
--     [2] = {
--         [1] = {
--             [1] = "noun",
--             [2] = {
--                 [1] = "fork"
--             },
--             [3] = {
--                 [1] = {
--                     [1] = "fork",
--                     [2] = {
--                         [1] = "fourche",
--                         [2] = "fourchette",
--                         [3] = "embranchement",
--                         [4] = "chariot",
--                         [5] = "chariot à fourche"
--                     },
--                     [4] = 0.21967085
--                 }
--             },
--             [4] = "fourchette",
--             [5] = 1
--         }
--     },
--     [3] = "fr",
--     [6] = {
--         [1] = {
--             [1] = "fourchette",
--             [3] = {
--                 [1] = {
--                     [1] = "fork",
--                     [2] = 1000,
--                     [3] = true,
--                     [4] = false
--                 },
--                 [2] = {
--                     [1] = "band",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 },
--                 [3] = {
--                     [1] = "bracket",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 },
--                 [4] = {
--                     [1] = "range",
--                     [2] = 0,
--                     [3] = true,
--                     [4] = false
--                 }
--             },
--             [4] = {
--                 [1] = {
--                     [1] = 0,
--                     [2] = 10
--                 }
--             },
--             [5] = "fourchette",
--             [6] = 0,
--             [7] = 1
--         }
--     },
--     [7] = 1,
--     [9] = {
--         [1] = {
--             [1] = "fr"
--         },
--         [3] = {
--             [1] = 1
--         },
--         [4] = {
--             [1] = "fr"
--         }
--     },
--     [12] = {
--         [1] = {
--             [1] = "noun",
--             [2] = {
--                 [1] = {
--                     [1] = {
--                         [1] = "ramification",
--                         [2] = "enfourchure"
--                     },
--                     [2] = ""
--                 },
--                 [2] = {
--                     [1] = {
--                         [1] = "échéance",
--                         [2] = "bande"
--                     },
--                     [2] = ""
--                 },
--                 [3] = {
--                     [1] = {
--                         [1] = "ramification",
--                         [2] = "jambe"
--                     },
--                     [2] = ""
--                 },
--                 [4] = {
--                     [1] = {
--                         [1] = "bifurcation"
--                     },
--                     [2] = ""
--                 },
--                 [5] = {
--                     [1] = {
--                         [1] = "fourche",
--                         [2] = "bifurcation",
--                         [3] = "entrejambe"
--                     },
--                     [2] = ""
--                 },
--                 [6] = {
--                     [1] = {
--                         [1] = "fourche",
--                         [2] = "bifurcation"
--                     },
--                     [2] = ""
--                 }
--             },
--             [3] = "fourchette"
--         }
--     },
--     [13] = {
--         [1] = {
--             [1] = "noun",
--             [2] = {
--                 [1] = {
--                     [1] = "Ustensile de table.",
--                     [2] = "12518.0",
--                     [3] = "Des fourchettes, des couteaux et des cuillères ."
--                 },
--                 [2] = {
--                     [1] = "Ecart entre deux valeurs.",
--                     [2] = "12518.1",
--                     [3] = "La fourchette des prix ."
--                 }
--             },
--             [3] = "fourchette"
--         }
--     },
--     [14] = {
--         [1] = {
--             [1] = {
--                 [1] = "La <b>fourchette</b> des prix .",
--                 [5] = 3,
--                 [6] = "12518.1",
--                 ["n"] = 6
--             }
--         }
--     },
--     ["n"] = 14
-- }
