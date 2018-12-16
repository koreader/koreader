--[[--
This module translates text using Google Translate.

<https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=fr&dt=t&q=alea%20jacta%20est>

--]]

-- Useful other implementation and discussion:
--  https://github.com/ssut/py-googletrans/blob/master/googletrans/client.py
--  https://stackoverflow.com/questions/26714426/what-is-the-meaning-of-google-translate-query-params

local JSON = require("json")
local logger = require("logger")

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
            -- "md",  -- definitions of source text
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

function Translator:getTargetLanguage()
    -- One can manually set his prefered target language
    local lang = G_reader_settings:readSetting("translator_target_language")
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
    local socket = require('socket')
    local url = require('socket.url')
    local http = require('socket.http')
    local https = require('ssl.https')
    local ltn12 = require('ltn12')

    local request, sink = {}, {}
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
    request['url'] = url.build(parsed)
    logger.dbg("Calling", request.url)
    request['method'] = 'GET'
    request['sink'] = ltn12.sink.table(sink)
    -- We may try to set a common User-Agent if it happens we're 403 Forbidden
    -- request['headers'] = {
    --     ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    -- }
    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    -- first argument returned by skip is code
    local _, headers, status = socket.skip(1, httpRequest(request))

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    if status ~= "HTTP/1.1 200 OK" then
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
    local result = self:loadPage(text, "en", "auto")
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
        source_lang = "auto"
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
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn()
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
    local InfoMessage = require("ui/widget/infomessage")
    local TextViewer = require("ui/widget/textviewer")
    local Trapper = require("ui/trapper")
    local UIManager = require("ui/uimanager")
    local util = require("util")
    local Screen = require("device").screen
    local T = require("ffi/util").template
    local _ = require("gettext")

    if not target_lang then
        target_lang = self:getTargetLanguage()
    end
    if not source_lang then
        source_lang = "auto"
    end

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
            table.insert(output, "")
        end
    end

    -- table.insert(output, require("dump")(result)) -- for debugging
    UIManager:show(TextViewer:new{
        title = T(_("Translation from %1 to %2"), source_lang:upper(), target_lang:upper()),
        text = table.concat(output, "\n"),
        height = Screen:getHeight() * 3/4,
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
