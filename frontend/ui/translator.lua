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
local Trapper = require("ui/trapper")
local JSON = require("json")
local Screen = require("device").screen
local ffiUtil  = require("ffi/util")
local logger = require("logger")
local util = require("util")
local T = ffiUtil.template
local _ = require("gettext")

-- From https://cloud.google.com/translate/docs/languages
-- 20230514: 132 supported languages
local AUTODETECT_LANGUAGE = "auto"
local SUPPORTED_LANGUAGES = {
    -- @translators Many of the names for languages can be conveniently found pre-translated in the relevant language of this Wikipedia article: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    af = _("Afrikaans"),
    sq = _("Albanian"),
    am = _("Amharic"),
    ar = _("Arabic"),
    hy = _("Armenian"),
    as = _("Assamese"),
    ay = _("Aymara"),
    az = _("Azerbaijani"),
    bm = _("Bambara"),
    eu = _("Basque"),
    be = _("Belarusian"),
    bn = _("Bengali"),
    bho = _("Bhojpuri"),
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
    dv = _("Dhivehi"),
    doi = _("Dogri"),
    nl = _("Dutch"),
    en = _("English"),
    eo = _("Esperanto"),
    et = _("Estonian"),
    ee = _("Ewe"),
    fil = _("Filipino (Tagalog)"),
    fi = _("Finnish"),
    fr = _("French"),
    fy = _("Frisian"),
    gl = _("Galician"),
    ka = _("Georgian"),
    de = _("German"),
    el = _("Greek"),
    gn = _("Guarani"),
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
    ilo = _("Ilocano"),
    id = _("Indonesian"),
    ga = _("Irish"),
    it = _("Italian"),
    ja = _("Japanese"),
    jw = _("Javanese"),
    -- @translators Many of the names for languages can be conveniently found pre-translated in the relevant language of this Wikipedia article: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    kn = _("Kannada"),
    kk = _("Kazakh"),
    km = _("Khmer"),
    rw = _("Kinyarwanda"),
    gom = _("Konkani"),
    ko = _("Korean"),
    kri = _("Krio"),
    ku = _("Kurdish"),
    ckb = _("Kurdish (Sorani)"),
    ky = _("Kyrgyz"),
    lo = _("Lao"),
    la = _("Latin"),
    lv = _("Latvian"),
    ln = _("Lingala"),
    lt = _("Lithuanian"),
    lg = _("Luganda"),
    lb = _("Luxembourgish"),
    mk = _("Macedonian"),
    mai = _("Maithili"),
    mg = _("Malagasy"),
    ms = _("Malay"),
    ml = _("Malayalam"),
    mt = _("Maltese"),
    mi = _("Maori"),
    mr = _("Marathi"),
    lus = _("Mizo"),
    mn = _("Mongolian"),
    my = _("Myanmar (Burmese)"),
    ne = _("Nepali"),
    no = _("Norwegian"),
    ny = _("Nyanja (Chichewa)"),
    ["or"] = _("Odia (Oriya)"),
    om = _("Oromo"),
    ps = _("Pashto"),
    fa = _("Persian"),
    pl = _("Polish"),
    pt = _("Portuguese"),
    pa = _("Punjabi"),
    qu = _("Quechua"),
    ro = _("Romanian"),
    ru = _("Russian"),
    sm = _("Samoan"),
    sa = _("Sanskrit"),
    gd = _("Scots Gaelic"),
    nso = _("Sepedi"),
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
    tt = _("Tatar"),
    te = _("Telugu"),
    th = _("Thai"),
    ti = _("Tigrinya"),
    ts = _("Tsonga"),
    tr = _("Turkish"),
    tk = _("Turkmen"),
    ak = _("Twi (Akan)"),
    uk = _("Ukrainian"),
    ur = _("Urdu"),
    ug = _("Uyghur"),
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
        return SUPPORTED_LANGUAGES[lang], true
    elseif ALT_LANGUAGE_CODES[lang] then
        return SUPPORTED_LANGUAGES[ALT_LANGUAGE_CODES[lang]], true
    elseif lang then
        return lang:upper(), false
    end
    return default_string, false
end

-- Will be called by ReaderHighlight to make it available in Reader menu
function Translator:genSettingsMenu()
    local function genLanguagesItems(setting_name, default_checked_item)
        local items_table = {}
        for lang_key, lang_name in ffiUtil.orderedPairs(SUPPORTED_LANGUAGES) do
            table.insert(items_table, {
                text_func = function()
                    return T("%1 (%2)", lang_name, lang_key)
                end,
                checked_func = function()
                    return lang_key == (G_reader_settings:readSetting(setting_name) or default_checked_item)
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
                text_func = function()
                    local __, name = self:getDocumentLanguage()
                    return T(_("Translate from book language: %1"), name or _("N/A"))
                end,
                help_text = _([[
With books that specify their main language in their metadata (most EPUBs and FB2s), enabling this option will make this language the source language. Otherwise, auto-detection or the selected language will be used.
This is useful:
- For books in a foreign language, where consistent translation is needed and words in other languages are rare.
- For books in familiar languages, to get definitions for words from the translation service.]]),
                enabled_func = function()
                    return self:getDocumentLanguage() ~= nil
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("translator_from_doc_lang")
                end,
                callback = function()
                    G_reader_settings:flipTrue("translator_from_doc_lang")
                end,
            },
            {
                text = _("Auto-detect source language"),
                help_text = _("This setting is best suited for foreign text found in books written in your native language."),
                enabled_func = function()
                    return not (G_reader_settings:isTrue("translator_from_doc_lang") and self:getDocumentLanguage() ~= nil)
                end,
                checked_func = function()
                    return G_reader_settings:nilOrTrue("translator_from_auto_detect")
                        and not (G_reader_settings:isTrue("translator_from_doc_lang") and self:getDocumentLanguage() ~= nil)
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("translator_from_auto_detect")
                end,
            },
            {
                text = _("Show romanizations"),
                help_text = _("Displays source language text in Latin characters. This is useful for reading languages with non-Latin scripts."),
                checked_func = function()
                    return G_reader_settings:isTrue("translator_with_romanizations")
                end,
                callback = function()
                    G_reader_settings:flipTrue("translator_with_romanizations")
                end,
            },
            {
                text_func = function()
                    local lang = G_reader_settings:readSetting("translator_from_language")
                    return T(_("Translate from: %1"), self:getLanguageName(lang, ""))
                end,
                help_text = _("If a specific source language is manually selected, it will be used everywhere, in all your books."),
                enabled_func = function()
                    return not G_reader_settings:nilOrTrue("translator_from_auto_detect")
                        and not (G_reader_settings:isTrue("translator_from_doc_lang") and self:getDocumentLanguage() ~= nil)
                end,
                sub_item_table = genLanguagesItems("translator_from_language"),
                separator = true,
            },
            {
                text_func = function()
                    local lang = self:getTargetLanguage()
                    return T(_("Translate to: %1"), self:getLanguageName(lang, ""))
                end,
                sub_item_table = genLanguagesItems("translator_to_language", self:getTargetLanguage()),
            },
        },
    }
end

function Translator:getDocumentLanguage()
    local ui = require("apps/reader/readerui").instance
    local lang = ui and ui.doc_props and ui.doc_props.language
    if not lang then
        return
    end
    lang = lang:match("(.*)-") or lang
    lang = lang:lower()
    local name, supported = self:getLanguageName(lang, "")
    if supported then
        return lang, name
    end
    -- ReaderTypography has a map of lang aliases (that we may meet
    -- in book metadata) to their normalized lang tag: use it
    local ReaderTypography = require("apps/reader/modules/readertypography")
    lang = ReaderTypography.LANG_ALIAS_TO_LANG_TAG[lang]
    if not lang then
        return
    end
    name, supported = self:getLanguageName(lang, "")
    if supported then
        return lang, name
    end
end

function Translator:getSourceLanguage()
    if G_reader_settings:isTrue("translator_from_doc_lang") then
        local lang = self:getDocumentLanguage()
        if lang then
            return lang
        end
        -- No document or metadata lang tag not supported:
        -- fallback to other settings
    end
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
    -- Dependencies for URL parsing and query building (used in main thread)
    local url = require("socket.url")

    local query = ""
    self.trans_params = self.trans_params or {} -- Ensure trans_params exists
    self.trans_params.tl = target_lang
    self.trans_params.sl = source_lang

    -- Build the query string
    for k,v in pairs(self.trans_params) do
        if type(v) == "table" then
            for _, v2 in ipairs(v) do
                query = query .. url.escape(k) .. '=' .. url.escape(tostring(v2)) .. '&'
            end
        else
            query = query .. url.escape(k) .. '=' .. url.escape(tostring(v)) .. '&'
        end
    end
    if G_reader_settings:isTrue("translator_with_romanizations") then
        query = query .. "dt=rm&"
    end

    local parsed_url = url.parse(self:getTransServer())
    parsed_url.path = self.trans_path or "/translate_a/single" -- Default path if not set
    parsed_url.query = query .. "q=" .. url.escape(text)

    -- Construct the HTTP request table
    local request_table = {
        url     = url.build(parsed_url),
        method  = "GET",
        timeout = 10,
    }
    logger.dbg("Calling translation URL:", request_table.url)

    -- Submit the HTTP request to run asynchronously in a separate Lane.
    local future = Trapper:async(
        function(cancel_checker, req_param)
            local socket = require("socket")
            local http = require("socket.http")
            local ltn12 = require("ltn12")

            local sink = {}
            req_param.sink = ltn12.sink.table(sink)

            local success, r, code, headers, status_message = pcall(http.request, req_param)
            if cancel_checker() then
                error("Job Cancelled")
            end
            if not success then
                -- Handle cases where http.request itself throws an error (e.g., invalid URL format).
                error({
                        code = nil, -- No HTTP status code as the request didn't complete
                        headers = nil,
                        http_status = nil,
                        error_message = "HTTP request failed to initialize: " .. tostring(body_source) -- body_source here is the error message
                })
            end
            -- Get the collected content. table.concat handles empty tables gracefully.
            local content = table.concat(sink)

            -- Checking 'status_message' for existence is good, but 'code' is the primary indicator.
            if code and code >= 200 and code < 300 then -- Check for 2xx success codes
                return {
                    code = code,
                    headers = headers,
                    http_status = status_message,
                    content = content
                }
            else
                local error_msg = "HTTP request failed or non-2xx status."
                if status_message then
                    error_msg = error_msg .. " Status: " .. status_message
                elseif not code then
                    error_msg = "HTTP request failed entirely (no status code received)."
                end
                if content ~= "" then
                    error_msg = error_msg .. " Response content: " .. content:sub(1, 200) .. (content:len() > 200 and "..." or "") -- Truncate long content for error message
                end

                error({
                    code = code,
                    headers = headers,
                    http_status = status_message,
                    content = content, -- Include content even on error for debugging
                    error_message = error_msg
                                })
            end
        end,
        request_table) -- Pass the request_table as an argument to the async function

    -- This 'decode_action' function remains the same as previously reviewed.
    local decode_action = function(trapper_status, async_status, async_result)
        logger.dbg("TRANS DECODE", trapper_status, async_status, async_result)
        if trapper_status == "timeout" then
            logger.warn("Translation request timed out.")
            return false, nil
        end

        if trapper_status == "error" then
            logger.warn("Translator async operation failed:", async_result.error_message or "Unknown error")
            logger.dbg("Error details:", async_result.code, async_result.headers, async_result.http_status, async_result.content)
            return false, nil
        end

        if async_status ~= "done" then
            logger.warn("Translation request error:", async_status, async_result)
            return false, nil
        end

        local code = async_result.code
        local headers = async_result.headers
        local http_status = async_result.http_status
        local content = async_result.content

        if not headers then
            logger.warn("Translator: Network unavailable or no headers received.")
            return false, nil
        end

        if code ~= 200 then
            logger.warn("Translator HTTP status not okay:", http_status or code or "network unreachable")
            logger.dbg("Response headers:", headers)
            return false, nil
        end

        local first_char = content:sub(1, 1)
        if content ~= "" and (first_char == "{" or first_char == "[") then
            local ok, result = pcall(JSON.decode, content, JSON.decode.simple)
            if ok and result then
                return "done", result
            else
                logger.warn("Translator JSON decoding error:", result)
                return "error", nil
            end
        else
            logger.warn("Not JSON in translator response:", content)
            return "error", nil
        end
    end

    return future, decode_action
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
    local future, decode = self:loadPage(text, "en", AUTODETECT_LANGUAGE)
    local status, result = Trapper:poll(0.3, 30, true, future, decode)
    if status and result and result[3] then
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
    local future, decode_action = self:loadPage(text, target_lang, source_lang)

    -- Wait for the translation to complete, with a 10-second timeout.
    -- The 'decode_action' will process the raw HTTP response.
    local status, processed_result = Trapper:waitAndThen(10, future, decode_action)

    logger.dbg("TRANSLATE inside:", status, processed_result)

    -- Check if the overall operation was successful and if the result structure is as expected.
    -- Assuming 'processed_result' is the decoded JSON object (table).
    -- And assuming the translated text is found in result[1]
    if status == "done" and processed_result and processed_result[1] and type(processed_result[1]) == "table" then
        local translated_parts = {}
        for _, sentence_obj in ipairs(processed_result[1]) do
            if sentence_obj[1] then
                table.insert(translated_parts, sentence_obj[1])
            end
        end
        logger.dbg("TRANSLATE translatted:", translated_parts)
        return table.concat(translated_parts, "") -- Join translated parts
    elseif status == "timeout" then
        logger.warn("Translation timed out for text:", text)
        return nil
    else
        logger.warn("Translation failed for text:", text, "Status:", status, "Result:", processed_result)
        -- Trapper:check already displayed a UI message if used in the chain
        return nil
    end
end
--[[--
Show translated text in TextViewer, with alternate translations

@string text
@bool detailed_view "true" to show alternate translation, definition, additional buttons
@string source_lang[opt="auto"] (`"en"`, `"fr"`, `…`) or `"auto"` to auto-detect source language
@string target_lang[opt] (`"en"`, `"fr"`, `…`)
--]]
function Translator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
    if Device:hasClipboard() then
        Device.input.setClipboardText(text)
    end

    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:willRerunWhenOnline(function()
                self:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
            end) then
        return
    end

    -- Wrap next function with Trapper to be able to interrupt
    -- translation service query.
    Trapper:wrap(function()
        self:_showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
    end)
end

function Translator:_showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
  -- Fallback languages
  target_lang = target_lang or self:getTargetLanguage()
  source_lang = source_lang or self:getSourceLanguage()

  -- Fire off the page‐load & decode future
  local future, decode_fn = self:loadPage(text, target_lang, source_lang)

  -- Build the “extract text” step
  local function extract_text(status, ...)
    local parts = {...}
    if not status or type(parts) ~= "table" then
      return false  -- bail on parse failure
    end

    -- Adopt new source_lang if provided by service
    if parts[3] then
      source_lang = parts[3]
    end

    local function is_valid(slice)
      return slice and type(slice) == "table" and #slice > 0
    end

    local output = {}
    local main_pieces = {}

    -- Main translation is in parts[1]
    if is_valid(parts[1]) then
      local romanized = {}
      for _, row in ipairs(parts[1]) do
        -- row[1]=translated, row[2]=original, row[4]=roman
        table.insert(main_pieces, tostring(row[1] or ""))
        if detailed_view then
          table.insert(romanized, tostring(row[4] or ""))
        end
      end

      -- If detailed, also show original segments
      if detailed_view then
        local original_pieces = {}
        for _, row in ipairs(parts[1]) do
          table.insert(original_pieces, tostring(row[2] or ""))
        end
        table.insert(output, "▣ " .. table.concat(original_pieces, " "))
        if #romanized > 0 then
          table.insert(output, table.concat(romanized, " "))
        end
        table.insert(output, "")  -- blank line before main text
      end

      table.insert(output, table.concat(main_pieces, " "))
    end

    -- Alternate translations in parts[6]
    if detailed_view and is_valid(parts[6]) then
      table.insert(output, "")
      table.insert(output, _("Alternate translations:"))
      for _, alt in ipairs(parts[6]) do
        if type(alt[3]) == "table" then
          table.insert(output, "▣ " .. alt[1]:gsub("\n", ""))
          for i, sub in ipairs(alt[3]) do
            local sym = util.unicodeCodepointToUtf8(0x2775 + i)
            table.insert(output, sym .. " " .. sub[1]:gsub("\n", ""))
          end
        end
      end
    end

    -- Definitions in parts[13]
    if detailed_view and is_valid(parts[13]) then
      table.insert(output, "")
      table.insert(output, _("Definition:"))
      for i, def in ipairs(parts[13]) do
        local sym = util.unicodeCodepointToUtf8(0x2775 + i)
        table.insert(output, sym .. " " .. def[1])
        for _, ex in ipairs(def[2] or {}) do
          table.insert(output, "\t● " .. ex[1])
        end
      end
    end

    local all_text = table.concat(output, "\n")
    -- Pass both main text (first piece) and full text
    return true, { main_pieces[1] or "", all_text }
  end

  -- Build the “display” step
  local function display_translation(ok, result)
    if not ok or type(result) ~= "table" then
      return false
    end
    local main_text, all_text = unpack(result)

    local opts = {
      title               = T(_("Translation from %1"), self:getLanguageName(source_lang, "?")),
      text                = all_text,
      text_type           = "lookup",
      add_default_buttons = true,
    }

    if detailed_view then
      opts.height = math.floor(Screen:getHeight() * 0.8)
      local btns, closecb = {}, nil

      if from_highlight then
        local ui = require("apps/reader/readerui").instance
        table.insert(btns, {
          {
            text = _("Save main translation to note"),
            callback = function()
              UIManager:close(tv); UIManager:close(ui.highlight.highlight_dialog)
              ui.highlight.highlight_dialog = nil
              if index then
                ui.highlight:editNote(index, false, main_text)
              else
                ui.highlight:addNote(main_text)
              end
            end,
          },
          {
            text = _("Save all to note"),
            callback = function()
              UIManager:close(tv); UIManager:close(ui.highlight.highlight_dialog)
              ui.highlight.highlight_dialog = nil
              if index then
                ui.highlight:editNote(index, false, all_text)
              else
                ui.highlight:addNote(all_text)
              end
            end,
          },
        })
        closecb = function()
          if not ui.highlight.highlight_dialog then
            ui.highlight:clear()
          end
        end
      end

      if Device:hasClipboard() then
        table.insert(btns, {
          {
            text = _("Copy main translation"),
            callback = function() Device.input.setClipboardText(main_text) end,
          },
          {
            text = _("Copy all"),
            callback = function() Device.input.setClipboardText(all_text) end,
          },
        })
      end

      opts.buttons_table   = btns
      opts.close_callback  = closecb
    end

    local tv = TextViewer:new(opts)
    UIManager:show(tv)
    return true
  end

  -- A single pipeline that decodes, extracts, then displays
  local function pipeline(status, ...)
    local ok1, decoded = decode_fn(status, ...)
    if not ok1 then return false end

    local ok2, result = extract_text(ok1, table.unpack(decoded or {}))
    if not ok2 then return false end

    return display_translation(ok2, result)
  end

  -- Schedule the poll with our pipeline callback
  return Trapper:poll(
    0.3,    -- delay between polls
    30,     -- max polls
    true,   -- immediate first poll
    future, -- the future to watch
    pipeline
  )
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
