-- Copyright (C) 2021 Aleksa Sarai <cyphar@cyphar.com>
-- Licensed under the GPLv3 or later.
--
-- This deinflection logic is heavily modelled after Yomichan
-- <https://github.com/FooSoft/yomichan>, up to and including the deinflection
-- table.

local JSON = require("rapidjson")
local Utf8Proc = require("ffi/utf8proc")
local bit = require("bit")
local logger = require("logger")
local util = require("util")

local Deinflector = {}

local ruleTypes = {}
-- These need to be outside of the definition because "adj-i" cannot be set
-- using {} initialisation.
ruleTypes["v1"]    = 0x01 -- Verb ichidan (so-called ru-verb)
ruleTypes["v5"]    = 0x02 -- Verb godan (so-called u-verb)
ruleTypes["vs"]    = 0x04 -- Verb suru
ruleTypes["vk"]    = 0x08 -- Verb kuru
ruleTypes["vz"]    = 0x0A -- Verb zuru
ruleTypes["adj-i"] = 0x10 -- Adjectival verb (i-adjective)
ruleTypes["iru"]   = 0x20 -- Intermediate -iru endings for progressive or perfect tense

local function toRuleTypes(...)
    final = 0
    for _, ruleType in ipairs({...}) do
        if ruleTypes[ruleType] then
            final = bit.bor(final, ruleTypes[ruleType])
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
        local ok, parsed = pcall(JSON.decode, contents)
        if ok then
            return parsed
        else
            logger.err("failed to parse plugin json", filename)
        end
    else
        logger.err("failed to open plugin json", filename, err)
    end
    return {}
end

local function makeDeinflectionResult(term, rules, reasons)
    return { term = term, rules = rules, reasons = reasons }
end

--- Deinflect some text without trying any possible conversions between types
--- of kana or any other such modifications. You probably want to use
--- Deinflector:deinflect() because it is more thorough.
function Deinflector:deinflectVerbatim(text)
    self:init() -- in case this is being called directly
    local results = {makeDeinflectionResult(text, 0, {})}
    local seen = {}
    seen[text] = true
    for _, current in ipairs(results) do
        for reason, rules in pairs(self.rules) do
            for variant, rule in ipairs(rules) do
                local rulesMatch = current.rules == 0 or bit.band(current.rules, rule.rulesIn) ~= 0
                local endsWithKana = current.term:find(rule.kanaIn.."$") ~= nil
                local longEnough = #current.term - #rule.kanaIn + #rule.kanaOut > 0
                if rulesMatch and endsWithKana and longEnough then
                    -- Check if we've already found this deinflection. If so,
                    -- that means there was a shorter reason path to it and
                    -- this deinflection is almost certainly theoretical.
                    new_term = current.term:gsub(rule.kanaIn.."$", rule.kanaOut)
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
    -- Remove the first entry because it's the original term.
    table.remove(results, 1)
    return results
end

-- These are all in 五十音 order, with variants (小書き, 濁点, 感濁点) listed
-- in subsequent rows.
-- XXX: Maybe add historic (ゐ, ゑ) or lingustic (う゚, か゚, さ゚, ら゚) kana too?

local FULLWIDTH_HIRAGANA = {
    "あ", "い", "う", "え", "お",
    "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
    "か", "き", "く", "け", "こ",
    "ゕ",             "ゖ",
    "が", "ぎ", "ぐ", "げ", "ご",
    "さ", "し", "す", "せ", "そ",
    "ざ", "じ", "ず", "ぜ", "ぞ",
    "た", "ち", "つ", "て", "と",
                "っ",
    "だ", "ぢ", "づ", "で", "ど",
    "な", "に", "ぬ", "ね", "の",
    "は", "ひ", "ふ", "へ", "ほ",
    "ば", "び", "ぶ", "べ", "ぼ",
    "ぱ", "ぴ", "ぷ", "ぺ", "ぽ",
    "ま", "み", "む", "め", "も",
    "や",       "ゆ",       "よ",
    "ゃ",       "ゅ",       "ょ",
    "わ",                   "を",
    "ゎ",
    "わ゙",       "ゔ",       "を゙",
    "ん", "ー",
}

local FULLWIDTH_KATAKANA = {
    "ア", "イ", "ウ", "エ", "オ",
    "ァ", "ィ", "ゥ", "ェ", "ォ",
    "カ", "キ", "ク", "ケ", "コ",
    "ヵ",             "ヶ",
    "ガ", "ギ", "グ", "ゲ", "ゴ",
    "サ", "シ", "ス", "セ", "ソ",
    "ザ", "ジ", "ズ", "ゼ", "ゾ",
    "タ", "チ", "ツ", "テ", "ト",
                "ッ",
    "ダ", "ヂ", "ヅ", "デ", "ド",
    "ナ", "ニ", "ヌ", "ネ", "ノ",
    "ハ", "ヒ", "フ", "ヘ", "ホ",
    "バ", "ビ", "ブ", "ベ", "ボ",
    "パ", "ピ", "プ", "ペ", "ポ",
    "マ", "ミ", "ム", "メ", "モ",
    "ヤ",       "ユ",       "ヨ",
    "ャ",       "ュ",       "ョ",
    "ワ",                   "ヲ",
    "ヮ",
    "ヷ",       "ヴ",       "ヺ",
    "ン", "ー",
}

local HALFWIDTH_KATAKANA = {
    "ｱ",  "ｲ",  "ｳ",  "ｴ",  "ｵ",
    "ｧ",  "ｨ",  "ｩ",  "ｪ",  "ｫ",
    "ｶ",  "ｷ",  "ｸ",  "ｹ",  "ｺ",
    "ｶﾞ", "ｷﾞ", "ｸﾞ", "ｹﾞ", "ｺﾞ",
    "",               "",         -- no ヵ・ヶ (small か・け)
    "ｻ",  "ｼ",  "ｽ",  "ｾ",  "ｿ",
    "ｻﾞ", "ｼﾞ", "ｽﾞ", "ｾﾞ", "ｿﾞ",
    "ﾀ",  "ﾁ",  "ﾂ",  "ﾃ",  "ﾄ",
                "ｯ",
    "ﾀﾞ", "ﾁﾞ", "ﾂﾞ", "ﾃﾞ", "ﾄﾞ",
    "ﾅ",  "ﾆ",  "ﾇ",  "ﾈ",  "ﾉ",
    "ﾊ",  "ﾋ",  "ﾌ",  "ﾍ",  "ﾎ",
    "ﾊﾞ", "ﾋﾞ", "ﾌﾞ", "ﾍﾞ", "ﾎﾞ",
    "ﾊﾟ", "ﾋﾟ", "ﾌﾟ", "ﾍﾟ", "ﾎﾟ",
    "ﾏ",  "ﾐ",  "ﾑ",  "ﾒ",  "ﾓ",
    "ﾔ",        "ﾕ",        "ﾖ",
    "ｬ",        "ｭ",        "ｮ",
    "ﾜ",                    "ｦ",
    "",                           -- no ゎ (small わ)
    "ﾜﾞ",       "ｳﾞ",       "ｦﾞ",
    "ﾝ", "ｰ",
}

assert(#HALFWIDTH_KATAKANA == #FULLWIDTH_KATAKANA)
assert(#FULLWIDTH_KATAKANA == #FULLWIDTH_HIRAGANA)

-- Lua 5.1 doesn't support iterating over utf8 strings (and utf8proc_iterate
-- and utf8proc_map_custom are a bit unweildy to use for charaacter
-- conversion), so we have to use gsub to do all conversions.

local function kana_mapper(from_map, to_map)
    assert(#from_map == #to_map, "kana_mapper needs both maps to be the same length")
    return function(text)
        for i, from in ipairs(from_map) do
            to = to_map[i]
            if from ~= "" and to ~= "" then -- skip characters with no mapping
                text = text:gsub(from, to)
            end
        end
        return text
    end
end

local function collapse_emphatic(text, full)
    return text:gsub("っ+", full and "" or "っ")
               :gsub("ッ+", full and "" or "ッ")
               :gsub("ー+", full and "" or "ー")
               :gsub("〜+", full and "" or "〜")
end

function Deinflector:deinflect(text)
    -- Normalise the text to ensure that we handle full-width text that
    -- inexplicably uses combining 濁点・半濁点 (◌゙・◌゚) marks.
    text = Utf8Proc.normalise(util.fixUtf8(text, "�"))
    local seen = {}
    local all_results = {}
    local map_functions = {
        kana_mapper(HALFWIDTH_KATAKANA, FULLWIDTH_KATAKANA),
        kana_mapper(FULLWIDTH_HIRAGANA, FULLWIDTH_KATAKANA),
        kana_mapper(FULLWIDTH_KATAKANA, FULLWIDTH_HIRAGANA),
        -- XXX: There's no point applying this twice, maybe figure out a nice
        --      way to only apply one or the other?
        function(text) return collapse_emphatic(text, false) end,
        function(text) return collapse_emphatic(text, true) end,
    }
    -- Iterate over the powerset of map_functions by looping over every
    -- possible bitmask for map_functions then applying the functions which
    -- have their corresponding bit set in the mask.
    local max_mapfn_bitmask = bit.lshift(1, #map_functions) - 1 -- (2^n - 1)
    for mapfn_bitmask = 0, max_mapfn_bitmask do
        local mapped_text = text
        for i, func in ipairs(map_functions) do
            local mapfn_bit = bit.lshift(1, i-1) -- the bit for this function
            if bit.band(mapfn_bit, mapfn_bitmask) ~= 0 then
                mapped_text = func(mapped_text)
            end
        end
        if not seen[mapped_text] then
            if text ~= mapped_text then
                logger.dbg("japanese deinflector trying mapped variant", text, "->", mapped_text)
            end
            local results = self:deinflectVerbatim(mapped_text)
            if results then
                util.arrayAppend(all_results, results)
            end
            seen[mapped_text] = true
        end
    end
    return all_results
end

function Deinflector:init()
    if self.rules ~= nil then return end -- already loaded
    -- TODO: Maybe make this location configurable?
    inflections = parsePluginJson("yomichan-deinflect.json")
    -- Normalise the reasons and convert the rules to the rule_types bitflags.
    self.rules = {}
    local nrules, nvariants = 0, 0
    for reason, rules in pairs(inflections) do
        variants = {}
        for i, variant in ipairs(rules) do
            variants[i] = {
                kanaIn = variant.kanaIn,
                kanaOut = variant.kanaOut,
                rulesIn = toRuleTypes(unpack(variant.rulesIn)),
                rulesOut = toRuleTypes(unpack(variant.rulesOut)),
            }
            nvariants = nvariants + 1
        end
        nrules = nrules + 1
        self.rules[reason] = variants
    end
    logger.dbg("japanese deinflector loaded inflection table with", nrules, "rules and", nvariants, "variants")
end

function Deinflector:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    return o
end

return Deinflector
