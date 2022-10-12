--- Yomichan deinflector implementation in pure Lua.
-- This is very heavily modelled after Yomichan's deinflection code, with some
-- minor changes to make it slightly more performant in the more restricted
-- environment KOReader tends to run in.
--
-- @module koplugin.japanese.deinflector
-- @alias Deinflector

-- Copyright (C) 2021 Aleksa Sarai <cyphar@cyphar.com>
-- Licensed under the GPLv3 or later.
--
-- This deinflection logic is heavily modelled after Yomichan
-- <https://github.com/FooSoft/yomichan>, up to and including the deinflection
-- table.

local InfoMessage = require("ui/widget/infomessage")
local JSON = require("rapidjson")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local bit = require("bit")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local Deinflector = {}

local RULE_TYPES = {
    ["v1"]    = 0x01, -- Verb ichidan (so-called ru-verb)
    ["v5"]    = 0x02, -- Verb godan (so-called u-verb)
    ["vs"]    = 0x04, -- Verb suru
    ["vk"]    = 0x08, -- Verb kuru
    ["vz"]    = 0x0A, -- Verb zuru
    ["adj-i"] = 0x10, -- Adjectival verb (i-adjective)
    ["iru"]   = 0x20, -- Intermediate -iru endings for progressive or perfect tense
}

local function toRuleTypes(...)
    local final = 0
    for i = 1, select("#", ...) do
        local ruleType = select(i, ...)
        if RULE_TYPES[ruleType] then
            final = bit.bor(final, RULE_TYPES[ruleType])
        end
    end
    return final
end

local function getSourceDir()
    local callerSource = debug.getinfo(2, "S").source
    if callerSource:find("^@") then
        return callerSource:gsub("^@(.*)/[^/]*", "%1")
    end
end

local function parsePluginJson(filename)
    local jsonPath = getSourceDir().."/"..filename
    local file, err = io.open(jsonPath, "r")
    if file then
        local contents = file:read("*all")
        file:close()
        local ok, parsed = pcall(JSON.decode, contents)
        if ok then
            return parsed
        else
            logger.err("japanese.koplugin: failed to parse plugin json", filename)
        end
    else
        logger.err("japanese.koplugin: failed to open plugin json", filename, err)
    end
    return {}
end

--- A single deinflection result.
-- @field term Deinflected form of the term (string).
-- @field rules Rules bitmask the term has applied (int).
-- @field reasons Array of reasons applied to reach the term ({string,...}).
-- @table DeinflectResult

local function makeDeinflectionResult(term, rules, reasons)
    return { term = term, rules = rules, reasons = reasons }
end

--- Deinflect some text as-is (without trying any possible conversions between
-- types of kana or any other such modifications). You probably want to use
-- Deinflector:deinflect() because it is more thorough.
--
-- @see deinflect
-- @tparam string text Japanese text to deinflect verbatim.
-- @treturn {DeinflectResult,...} An array of possible deinflections (including the text given).
function Deinflector:deinflectVerbatim(text)
    self:init() -- in case this is being called directly
    local results = {makeDeinflectionResult(text, 0, {})}
    local seen = {}
    seen[text] = true
    for _, current in ipairs(results) do
        for reason, rules in pairs(self.rules) do
            for _, rule in ipairs(rules) do
                local rulesMatch = current.rules == 0 or bit.band(current.rules, rule.rulesIn) ~= 0
                local endsWithKana = current.term:sub(-#rule.kanaIn) == rule.kanaIn
                local longEnough = #current.term - #rule.kanaIn + #rule.kanaOut > 0
                if rulesMatch and endsWithKana and longEnough then
                    -- Check if we've already found this deinflection. If so,
                    -- that means there was a shorter reason path to it and
                    -- this deinflection is almost certainly theoretical.
                    local new_term = current.term:sub(1, -#rule.kanaIn-1) .. rule.kanaOut
                    if not seen[new_term] then
                        table.insert(results, makeDeinflectionResult(
                            new_term,
                            rule.rulesOut,
                            {reason, unpack(current.reasons)}
                        ))
                        seen[new_term] = true
                    end
                end
            end
        end
    end
    return results
end

-- These are all in 五十音 order, but we list variants in their 五十音 order
-- before the base kana.
-- @todo Maybe add historic (ゐ, ゑ) or lingustic (う゚, か゚, さ゚, ら゚) kana too?

local FULLWIDTH_HIRAGANA = {
    -- 小書き
    "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
    "ゕ",             "ゖ",
                "っ",
    "ゃ",       "ゅ",       "ょ",
    "ゎ",
    -- 濁点・半濁点 つき
    "が", "ぎ", "ぐ", "げ", "ご",
    "ざ", "じ", "ず", "ぜ", "ぞ",
    "だ", "ぢ", "づ", "で", "ど",
    "ば", "び", "ぶ", "べ", "ぼ",
    "ぱ", "ぴ", "ぷ", "ぺ", "ぽ",
    "わ゙",       "ゔ",       "を゙",
    -- 五十音
    "あ", "い", "う", "え", "お",
    "か", "き", "く", "け", "こ",
    "さ", "し", "す", "せ", "そ",
    "た", "ち", "つ", "て", "と",
    "な", "に", "ぬ", "ね", "の",
    "は", "ひ", "ふ", "へ", "ほ",
    "ま", "み", "む", "め", "も",
    "や",       "ゆ",       "よ",
    "ら", "り", "る", "れ", "ろ",
    "わ",                   "を",
    -- 撥音と長音符
    "ん", "ー",
}

local FULLWIDTH_KATAKANA = {
    -- 小書き
    "ァ", "ィ", "ゥ", "ェ", "ォ",
    "ヵ",             "ヶ",
                "ッ",
    "ャ",       "ュ",       "ョ",
    "ヮ",
    -- 濁点・半濁点 つき
    "ガ", "ギ", "グ", "ゲ", "ゴ",
    "ザ", "ジ", "ズ", "ゼ", "ゾ",
    "ダ", "ヂ", "ヅ", "デ", "ド",
    "バ", "ビ", "ブ", "ベ", "ボ",
    "パ", "ピ", "プ", "ペ", "ポ",
    "ヷ",       "ヴ",       "ヺ",
    -- 五十音
    "ア", "イ", "ウ", "エ", "オ",
    "カ", "キ", "ク", "ケ", "コ",
    "サ", "シ", "ス", "セ", "ソ",
    "タ", "チ", "ツ", "テ", "ト",
    "ナ", "ニ", "ヌ", "ネ", "ノ",
    "ハ", "ヒ", "フ", "ヘ", "ホ",
    "マ", "ミ", "ム", "メ", "モ",
    "ヤ",       "ユ",       "ヨ",
    "ラ", "リ", "ル", "レ", "ロ",
    "ワ",                   "ヲ",
    -- 撥音と長音符
    "ン", "ー",
}

local HALFWIDTH_KATAKANA = {
    -- 小書き
    "ｧ",  "ｨ",  "ｩ",  "ｪ",  "ｫ",
    "",               "",         -- no ヵ・ヶ (small か・け)
                "ｯ",
    "ｬ",        "ｭ",        "ｮ",
    "",                           -- no ゎ (small わ)
    -- 濁点・半濁点 つき
    "ｶﾞ", "ｷﾞ", "ｸﾞ", "ｹﾞ", "ｺﾞ",
    "ｻﾞ", "ｼﾞ", "ｽﾞ", "ｾﾞ", "ｿﾞ",
    "ﾀﾞ", "ﾁﾞ", "ﾂﾞ", "ﾃﾞ", "ﾄﾞ",
    "ﾊﾞ", "ﾋﾞ", "ﾌﾞ", "ﾍﾞ", "ﾎﾞ",
    "ﾊﾟ", "ﾋﾟ", "ﾌﾟ", "ﾍﾟ", "ﾎﾟ",
    "ﾜﾞ",       "ｳﾞ",       "ｦﾞ",
    -- 五十音
    "ｱ",  "ｲ",  "ｳ",  "ｴ",  "ｵ",
    "ｶ",  "ｷ",  "ｸ",  "ｹ",  "ｺ",
    "ｻ",  "ｼ",  "ｽ",  "ｾ",  "ｿ",
    "ﾀ",  "ﾁ",  "ﾂ",  "ﾃ",  "ﾄ",
    "ﾅ",  "ﾆ",  "ﾇ",  "ﾈ",  "ﾉ",
    "ﾊ",  "ﾋ",  "ﾌ",  "ﾍ",  "ﾎ",
    "ﾏ",  "ﾐ",  "ﾑ",  "ﾒ",  "ﾓ",
    "ﾔ",        "ﾕ",        "ﾖ",
    "ﾗ",  "ﾘ",  "ﾙ",  "ﾚ",  "ﾛ",
    "ﾜ",                    "ｦ",
    -- 撥音と長音符
    "ﾝ", "ｰ",
}

-- Ensure all of the tables are normalised.
for i, c in ipairs(HALFWIDTH_KATAKANA) do HALFWIDTH_KATAKANA[i] = Utf8Proc.normalize_NFC(c) end
for i, c in ipairs(FULLWIDTH_KATAKANA) do FULLWIDTH_KATAKANA[i] = Utf8Proc.normalize_NFC(c) end
for i, c in ipairs(FULLWIDTH_HIRAGANA) do FULLWIDTH_HIRAGANA[i] = Utf8Proc.normalize_NFC(c) end
-- Ensure all tables are the same size.
assert(#HALFWIDTH_KATAKANA == #FULLWIDTH_KATAKANA)
assert(#FULLWIDTH_KATAKANA == #FULLWIDTH_HIRAGANA)
-- Create fast conversion tables.
local HALFWIDTH_TO_FULLWIDTH, KATAKANA_TO_HIRAGANA, HIRAGANA_TO_KATAKANA = {}, {}, {}
for i in ipairs(FULLWIDTH_KATAKANA) do
    KATAKANA_TO_HIRAGANA[FULLWIDTH_KATAKANA[i]] = FULLWIDTH_HIRAGANA[i]
    HIRAGANA_TO_KATAKANA[FULLWIDTH_HIRAGANA[i]] = FULLWIDTH_KATAKANA[i]
    -- Some entries are "" but that doesn't matter since we won't hit them during conversion.
    HALFWIDTH_TO_FULLWIDTH[HALFWIDTH_KATAKANA[i]] = FULLWIDTH_KATAKANA[i]
end

local function kana_mapper(map)
    return function(text)
        local new_text = {}
        local last_char
        for c in text:gmatch(util.UTF8_CHAR_PATTERN) do
            if last_char and (c == "ﾞ" or c == "ﾟ") then
                -- Replace the last character with the correct mapping for the
                -- combined character and mark. This is needed specifically for
                -- half-width kana.
                if map[last_char .. c] then
                    new_text[#new_text] = map[last_char .. c]
                end
            else
                table.insert(new_text, map[c] or c)
            end
            last_char = c
        end
        return {table.concat(new_text, "")}
    end
end

local EMPHATIC_SYMBOLS = {
    ["っ"] = true, ["ッ"] = true,
    ["ー"] = true, ["〜"] = true,
}

local function collapse_emphatic(text)
    local complete_collapse, partial_collapse = {}, {}
    local last_char
    for c in text:gmatch(util.UTF8_CHAR_PATTERN) do
        if not EMPHATIC_SYMBOLS[c] then
            table.insert(partial_collapse, c)
            table.insert(complete_collapse, c)
        elseif last_char ~= c then -- first instance of this emphatic marker
            table.insert(partial_collapse, c)
        end
        last_char = c
    end
    return {
        table.concat(partial_collapse, ""),
        table.concat(complete_collapse, ""),
    }
end

--- The set of defined map functions available to the deinflector.
local ALL_TEXT_CONVERSIONS = {
    {
        name = "halfwidth_to_fullwidth",
        pretty_name = _("Halfwidth to fullwidth kana"),
        -- @translators If possible, keep the example Japanese text.
        help_text = _("Convert half-width katakana to full-width katakana (for instance, ｶﾀｶﾅ will be converted to カタカナ)."),
        func = kana_mapper(HALFWIDTH_TO_FULLWIDTH),
    },
    {
        name = "hiragana_to_katakana",
        pretty_name = _("Hiragana to katakana"),
        -- @translators If possible, keep the example Japanese text.
        help_text = _("Convert hiragana to katakana (for instance, ひらがな will be converted to ヒラガナ)."),
        func = kana_mapper(HIRAGANA_TO_KATAKANA),
    },
    {
        name = "katakana_to_hiragana",
        pretty_name = _("Katakana to hiragana"),
        -- @translators If possible, keep the example Japanese text.
        help_text = _("Convert katakana to hiragana (for instance, カタカナ will be converted to かたかな)."),
        func = kana_mapper(KATAKANA_TO_HIRAGANA),
    },
    {
        name = "collapse_emphatic",
        pretty_name = _("Collapse emphatic sequences"),
        -- @translators If possible, keep the example Japanese text.
        help_text = _("Collapse any character sequences which are sometimes used as emphasis in speech (for instance, すっっごーーい will be converted to both すっごーい and すごい)."),
        func = collapse_emphatic,
    },
}

--- Default enabled/disabled settings for ALL_TEXT_CONVERSIONS.
local DEFAULT_TEXT_CONVERSIONS = {
    ["halfwidth_to_fullwidth"] = true,
    ["hiragana_to_katakana"] = false,
    ["katakana_to_hiragana"] = true,
    ["collapse_emphatic"] = false,
}

--- Return the set of deinflections (and the reason path taken) for the
-- provided text. In addition to the verbatim text provided, several cleanups
-- will be attempted on the text (conversion from half-width kana, conversion
-- between katakana and hiragana, and collapsing of any emphatic sequences) and
-- any valid deinflections found will also be returned.
--
-- @tparam string text Japanese text to deinflect.
-- @treturn {DeinflectResult,...} An array of possible deinflections (including the text given).
function Deinflector:deinflect(text)
    -- Normalise the text to ensure that we handle full-width text that
    -- inexplicably uses combining 濁点・半濁点 (◌゙・◌゚) marks.
    text = Utf8Proc.normalize_NFC(util.fixUtf8(text, "�"))
    local seen = {}
    local all_results = {}
    -- Iterate over the powerset of text_conversions by looping over every
    -- possible bitmask for text_conversions then applying the functions which
    -- have their corresponding bit set in the mask.
    local enabled_text_conversions = {}
    for name, enabled in pairs(self.enabled_text_conversions) do
        if enabled then table.insert(enabled_text_conversions, name) end
    end
    local max_mapfn_bitmask = bit.lshift(1, #enabled_text_conversions) - 1 -- (2^n - 1)
    for mapfn_bitmask = 0, max_mapfn_bitmask do
        local func_names = {}
        for i, func_name in ipairs(enabled_text_conversions) do
            local mapfn_bit = bit.lshift(1, i-1) -- the bit for this function
            if bit.band(mapfn_bit, mapfn_bitmask) ~= 0 then
                func_names[func_name] = true
            end
        end
        -- Apply the converters in the order specified in ALL_TEXT_CONVERSIONS.
        local mapped_texts = {text}
        for _, converter in ipairs(ALL_TEXT_CONVERSIONS) do
            if func_names[converter.name] then
                local old_texts = mapped_texts
                mapped_texts = {}
                for _, old_text in ipairs(old_texts) do
                    util.arrayAppend(mapped_texts, converter.func(old_text))
                end
            end
        end
        for _, mapped_text in ipairs(mapped_texts) do
            if not seen[mapped_text] then
                if text ~= mapped_text then
                    logger.dbg("japanese.koplugin deinflector: trying converted variant", text, "->", mapped_text)
                end
                local results = self:deinflectVerbatim(mapped_text)
                if results then
                    util.arrayAppend(all_results, results)
                end
                seen[mapped_text] = true
            end
        end
    end
    return all_results
end

function Deinflector:genTextConversionMenuItems()
    local item_table = {}
    for _, conversion in pairs(ALL_TEXT_CONVERSIONS) do
        local name = conversion.name
        table.insert(item_table, {
            text = conversion.pretty_name,
            help_text = conversion.help_text,
            checked_func = function()
                return self.enabled_text_conversions[name] or false
            end,
            callback = function(touchmenu_instance)
                self.enabled_text_conversions[name] = not self.enabled_text_conversions[name]
                G_reader_settings:saveSetting("language_japanese_text_conversions", self.enabled_text_conversions)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return item_table
end

function Deinflector:genMenuItems()
    return {
        {
            text_func = function()
                local nenabled = 0
                for _, enabled in pairs(self.enabled_text_conversions) do
                    if enabled then nenabled = nenabled + 1 end
                end
                if nenabled == 0 then
                    return _("Text conversions: none enabled")
                else
                    return T(N_("Text conversions: %1 enabled", "Text conversions: %1 enabled", nenabled), nenabled)
                end
            end,
            help_text = _([[
Configure which text conversions to apply when trying to deinflect Japanese text. These primarily include conversions between different kinds of kana, in order to make sure that a word written using different kana to your installed dictionaries can still be looked up.

Not every conversion will be applied at once. Instead, all possible combinations of enabled conversions will be attempted in order to maximise the chance of at least one conversion matching the form used in the dictionary.]]),
            sub_item_table = self:genTextConversionMenuItems(),
        },
        {
            -- @translators A deinflector is a program which converts a word into its dictionary form, similar to deconjugation in European languages. See <https://en.wikipedia.org/wiki/Japanese_verb_conjugation> for more detail.
            text = _("Deinflector information"),
            keep_menu_open = true,
            callback = function()
                local nrules, nvariants = 0, 0
                for _, rules in pairs(self.rules) do
                    nvariants = nvariants + #rules
                    nrules = nrules + 1
                end
                local nrules_str = T(N_("%1 rule", "%1 rules", nrules), nrules)
                local nvariants_str = T(N_("%1 variant", "%1 variants", nvariants), nvariants)
                UIManager:show(InfoMessage:new{
                    -- @translators %1 is the "%1 rule(s)" string, %2 is the "%1 variant(s)" string.
                    text = T(_("Deinflector has %1 and %2 loaded."), nrules_str, nvariants_str),
                })
            end,
        },
    }
end

--- Initialise a Deflector instance with the set of rules defined in
-- yomichan-deflect.json.
function Deinflector:init()
    self.enabled_text_conversions = self.enabled_text_conversions or
                                    G_reader_settings:readSetting("language_japanese_text_conversions") or
                                    DEFAULT_TEXT_CONVERSIONS
    if self.rules ~= nil then return end -- already loaded

    --- @todo Maybe make this location configurable or look in the user-controlled data directory too?
    local inflections = parsePluginJson("yomichan-deinflect.json")

    -- Normalise the reasons and convert the rules to the rule_types bitflags.
    self.rules = {}
    local nrules, nvariants = 0, 0
    for reason, rules in pairs(inflections) do
        local variants = {}
        for i, variant in ipairs(rules) do
            variants[i] = {
                kanaIn = variant.kanaIn,
                kanaOut = variant.kanaOut,
                rulesIn = toRuleTypes(unpack(variant.rulesIn)),
                rulesOut = toRuleTypes(unpack(variant.rulesOut)),
            }
        end
        self.rules[reason] = variants
        nrules = nrules + 1
        nvariants = nvariants + #variants
    end
    logger.dbg("japanese.koplugin deinflector: loaded inflection table with", nrules, "rules and", nvariants, "variants")
end

--- Create a new Deflector instance.
function Deinflector:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    return o
end

return Deinflector
