-- Copyright (C) 2021 Aleksa Sarai <cyphar@cyphar.com>
-- Licensed under the GPLv3 or later.
--
-- This deinflection logic is heavily modelled after Yomichan
-- <https://github.com/FooSoft/yomichan>, up to and including the deinflection
-- table.

-- TODO: While Yomichan just uses a simple array for all candidate suffix
--       rules, it seems to me that a suffix trie would be more efficient
--       (which probably matters more for us since we run on lower-powered
--       devices).

local bit = require("bit")
local JSON = require("json")
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

-- TODO: Ideally we would try a series of conversions for deinflection (just
--       like Yomichan does) but unfortunately because Lua doesn't easily
--       support doing translation of Unicode codepoints (not to mention we'd
--       need to deal with combining characters for (han)dakuten) this is a bit
--       too much of a pain to do at the moment.

-- Lua 5.1 doesn't support iterating over utf8 strings, so we have to use gsub
-- to do all conversions.

-- (Full-Width) 五十音 Table
-- あア　いイ　うウ　えエ　おオ
-- かカ　きキ　くク　けケ　こコ
-- がガ　ぎギ　ぐグ　げゲ　ごゴ
-- さサ　しシ　すス　せセ　そソ
-- ざザ　じジ　ずズ　ぜゼ　ぞゾ
-- たタ　ちチ　つツ　てテ　とト
-- だダ　ぢヂ　づヅ　でデ　どド
-- なナ　にニ　ぬヌ　ねネ　のノ
-- はハ　ひヒ　ふフ　へヘ　ほホ
-- ばバ　びビ　ぶブ　べベ　ぼボ
-- ぱパ　ぴピ　ぷプ　ぺペ　ぽポ
-- まマ　みミ　むム　めメ　もモ
-- やヤ　　　　ゆユ　　　　よヨ
-- わワ　　　　　　　　　　をヲ
-- んン
-- ぁァ　ぃィ　ぅゥ　ぇェ　ぉォ
-- ゃャ　　　　ゅュ　　　　ょョ
-- 　　　　　　っッ

-- TODO: This table does not handle the peculiar case of combining characters
--       being used for full-width kana (something that shouldn't happen in
--       normal text but is possible).

local function FW_hiraganaToKatakana(text)
    return text
        :gsub("あ","ア"):gsub("い","イ"):gsub("う","ウ"):gsub("え","エ"):gsub("お","オ")
        :gsub("か","カ"):gsub("き","キ"):gsub("く","ク"):gsub("け","ケ"):gsub("こ","コ")
        :gsub("が","ガ"):gsub("ぎ","ギ"):gsub("ぐ","グ"):gsub("げ","ゲ"):gsub("ご","ゴ")
        :gsub("さ","サ"):gsub("し","シ"):gsub("す","ス"):gsub("せ","セ"):gsub("そ","ソ")
        :gsub("ざ","ザ"):gsub("じ","ジ"):gsub("ず","ズ"):gsub("ぜ","ゼ"):gsub("ぞ","ゾ")
        :gsub("た","タ"):gsub("ち","チ"):gsub("つ","ツ"):gsub("て","テ"):gsub("と","ト")
        :gsub("だ","ダ"):gsub("ぢ","ヂ"):gsub("づ","ヅ"):gsub("で","デ"):gsub("ど","ド")
        :gsub("な","ナ"):gsub("に","ニ"):gsub("ぬ","ヌ"):gsub("ね","ネ"):gsub("の","ノ")
        :gsub("は","ハ"):gsub("ひ","ヒ"):gsub("ふ","フ"):gsub("へ","ヘ"):gsub("ほ","ホ")
        :gsub("ば","バ"):gsub("び","ビ"):gsub("ぶ","ブ"):gsub("べ","ベ"):gsub("ぼ","ボ")
        :gsub("ぱ","パ"):gsub("ぴ","ピ"):gsub("ぷ","プ"):gsub("ぺ","ペ"):gsub("ぽ","ポ")
        :gsub("ま","マ"):gsub("み","ミ"):gsub("む","ム"):gsub("め","メ"):gsub("も","モ")
        :gsub("や","ヤ")                :gsub("ゆ","ユ")                :gsub("よ","ヨ")
        :gsub("わ","ワ")                                                :gsub("を","ヲ")
        :gsub("ん","ン")
        :gsub("ぁ","ァ"):gsub("ぃ","ィ"):gsub("ぅ","ゥ"):gsub("ぇ","ェ"):gsub("ぉ","ォ")
        :gsub("ゃ","ャ")                :gsub("ゅ","ュ")                :gsub("ょ","ョ")
                                        :gsub("っ","ッ")
end

local function FW_katakanaToHiragana(text)
    return text
        :gsub("ア","あ"):gsub("イ","い"):gsub("ウ","う"):gsub("エ","え"):gsub("オ","お")
        :gsub("カ","か"):gsub("キ","き"):gsub("ク","く"):gsub("ケ","け"):gsub("コ","こ")
        :gsub("ガ","が"):gsub("ギ","ぎ"):gsub("グ","ぐ"):gsub("ゲ","げ"):gsub("ゴ","ご")
        :gsub("サ","さ"):gsub("シ","し"):gsub("ス","す"):gsub("セ","せ"):gsub("ソ","そ")
        :gsub("ザ","ざ"):gsub("ジ","じ"):gsub("ズ","ず"):gsub("ゼ","ぜ"):gsub("ゾ","ぞ")
        :gsub("タ","た"):gsub("チ","ち"):gsub("ツ","つ"):gsub("テ","て"):gsub("ト","と")
        :gsub("ダ","だ"):gsub("ヂ","ぢ"):gsub("ヅ","づ"):gsub("デ","で"):gsub("ド","ど")
        :gsub("ナ","な"):gsub("ニ","に"):gsub("ヌ","ぬ"):gsub("ネ","ね"):gsub("ノ","の")
        :gsub("ハ","は"):gsub("ヒ","ひ"):gsub("フ","ふ"):gsub("ヘ","へ"):gsub("ホ","ほ")
        :gsub("バ","ば"):gsub("ビ","び"):gsub("ブ","ぶ"):gsub("ベ","べ"):gsub("ボ","ぼ")
        :gsub("パ","ぱ"):gsub("ピ","ぴ"):gsub("プ","ぷ"):gsub("ペ","ぺ"):gsub("ポ","ぽ")
        :gsub("マ","ま"):gsub("ミ","み"):gsub("ム","む"):gsub("メ","め"):gsub("モ","も")
        :gsub("ヤ","や")                :gsub("ユ","ゆ")                :gsub("ヨ","よ")
        :gsub("ワ","わ")                                                :gsub("ヲ","を")
        :gsub("ン","ん")
        :gsub("ァ","ぁ"):gsub("ィ","ぃ"):gsub("ゥ","ぅ"):gsub("ェ","ぇ"):gsub("ォ","ぉ")
        :gsub("ャ","ゃ")                :gsub("ュ","ゅ")                :gsub("ョ","ょ")
                                        :gsub("ッ","っ")
end

function Deinflector:deinflect(text)
    local map_functions = {
        function(text) return text end, -- no-op mapping
        FW_katakanaToHiragana,
        --FW_hiraganaToKatakana, -- Doesn't make sense since deinflectVerbatim
                                 -- doesn't handle katakana okurigana.
        -- TODO: Add some more of the mappings Yomichan supports (collapsing
        --       emphatic markers, converting between full/half-width kana).
    }
    local seen = {}
    local all_results = {}
    for _, func in ipairs(map_functions) do
        mapped_text = func(text)
        if not seen[mapped_text] then
            if text ~= mapped_text then
                logger.dbg("trying to deinflect mapped variant", text, "->", mapped_text)
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
