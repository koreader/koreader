describe("Japanese deinflector", function()
    local Deinflector

    setup(function()
        require("commonrequire")
        package.path = "plugins/japanese.koplugin/?.lua;" .. package.path
        Deinflector = require("deinflector"):new()
    end)

    local function deinflectsTo(source, term)
        local results = Deinflector:deinflectVerbatim(source)
        for _, r in ipairs(results) do
            if r.term == term then
                return true
            end
        end
        return false
    end

    local function deinflectsFull(source, term)
        local results = Deinflector:deinflect(source)
        for _, r in ipairs(results) do
            if r.term == term then
                return true
            end
        end
        return false
    end

    -- Each entry: { inflected, dictionary_form, group }
    -- Groups are used to organize tests into describe() blocks.
    local deinflection_tests = {
        -- i-adjectives (adj-i): 高い (takai, expensive/tall)
        { "高い",           "高い",   "i-adjectives" },           -- identity
        { "高くない",       "高い",   "i-adjectives" },           -- negative
        { "高かった",       "高い",   "i-adjectives" },           -- past
        { "高くて",         "高い",   "i-adjectives" },           -- te-form
        { "高く",           "高い",   "i-adjectives" },           -- adverbial
        { "高ければ",       "高い",   "i-adjectives" },           -- conditional
        { "高さ",           "高い",   "i-adjectives" },           -- noun form
        { "高そう",         "高い",   "i-adjectives" },           -- -sou
        { "高すぎる",       "高い",   "i-adjectives" },           -- -sugiru
        { "高かったら",     "高い",   "i-adjectives" },           -- -tara
        { "高かったり",     "高い",   "i-adjectives" },           -- -tari
        { "高くありません", "高い",   "i-adjectives" },           -- polite negative
        { "高き",           "高い",   "i-adjectives" },           -- archaic -ki
        -- i-adjectives: 美しい (utsukushii, beautiful) — multi-kana stems
        { "美しくない",     "美しい", "i-adjectives" },           -- negative
        { "美しかった",     "美しい", "i-adjectives" },           -- past
        { "美しげ",         "美しい", "i-adjectives" },           -- -ge

        -- Ichidan verbs (v1, "ru-verbs"): 食べる (taberu, eat)
        { "食べる",           "食べる", "ichidan verbs" },         -- identity
        { "食べない",         "食べる", "ichidan verbs" },         -- negative
        { "食べた",           "食べる", "ichidan verbs" },         -- past
        { "食べて",           "食べる", "ichidan verbs" },         -- te-form
        { "食べます",         "食べる", "ichidan verbs" },         -- polite
        { "食べません",       "食べる", "ichidan verbs" },         -- polite negative
        { "食べました",       "食べる", "ichidan verbs" },         -- polite past
        { "食べませんでした", "食べる", "ichidan verbs" },         -- polite past negative
        { "食べましょう",     "食べる", "ichidan verbs" },         -- polite volitional
        { "食べれば",         "食べる", "ichidan verbs" },         -- conditional
        { "食べよう",         "食べる", "ichidan verbs" },         -- volitional
        { "食べろ",           "食べる", "ichidan verbs" },         -- imperative
        { "食べよ",           "食べる", "ichidan verbs" },         -- imperative (yo)
        { "食べさせる",       "食べる", "ichidan verbs" },         -- causative
        { "食べられる",       "食べる", "ichidan verbs" },         -- passive/potential
        { "食べたい",         "食べる", "ichidan verbs" },         -- -tai
        { "食べなさい",       "食べる", "ichidan verbs" },         -- -nasai
        { "食べそう",         "食べる", "ichidan verbs" },         -- -sou
        { "食べすぎる",       "食べる", "ichidan verbs" },         -- -sugiru
        { "食べたら",         "食べる", "ichidan verbs" },         -- -tara
        { "食べたり",         "食べる", "ichidan verbs" },         -- -tari
        { "食べず",           "食べる", "ichidan verbs" },         -- -zu
        { "食べぬ",           "食べる", "ichidan verbs" },         -- -nu
        { "食べるな",         "食べる", "ichidan verbs" },         -- imperative negative
        { "食べちゃう",       "食べる", "ichidan verbs" },         -- -chau
        { "食べちまう",       "食べる", "ichidan verbs" },         -- -chimau
        -- Ichidan: 見る (miru, see) — short stem
        { "見ない",           "見る",   "ichidan verbs" },         -- negative
        { "見て",             "見る",   "ichidan verbs" },         -- te-form
        { "見た",             "見る",   "ichidan verbs" },         -- past

        -- Godan verbs (v5, "u-verbs"): 書く (kaku, write) — ku ending
        { "書かない", "書く", "godan verbs: ku-ending 書く" },     -- negative
        { "書いた",   "書く", "godan verbs: ku-ending 書く" },     -- past
        { "書いて",   "書く", "godan verbs: ku-ending 書く" },     -- te-form
        { "書きます", "書く", "godan verbs: ku-ending 書く" },     -- polite
        { "書けば",   "書く", "godan verbs: ku-ending 書く" },     -- conditional
        { "書こう",   "書く", "godan verbs: ku-ending 書く" },     -- volitional
        { "書け",     "書く", "godan verbs: ku-ending 書く" },     -- imperative
        { "書ける",   "書く", "godan verbs: ku-ending 書く" },     -- potential
        { "書かれる", "書く", "godan verbs: ku-ending 書く" },     -- passive
        { "書かせる", "書く", "godan verbs: ku-ending 書く" },     -- causative
        { "書きたい", "書く", "godan verbs: ku-ending 書く" },     -- -tai
        { "書かず",   "書く", "godan verbs: ku-ending 書く" },     -- -zu
        { "書いたら", "書く", "godan verbs: ku-ending 書く" },     -- -tara
        { "書いたり", "書く", "godan verbs: ku-ending 書く" },     -- -tari
        { "書き",     "書く", "godan verbs: ku-ending 書く" },     -- masu stem
        -- 泳ぐ (oyogu, swim) — gu ending
        { "泳がない", "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- negative
        { "泳いだ",   "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- past
        { "泳いで",   "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- te-form
        { "泳ぎます", "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- polite
        { "泳げば",   "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- conditional
        { "泳げる",   "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- potential
        { "泳がせる", "泳ぐ", "godan verbs: gu-ending 泳ぐ" },   -- causative
        -- 話す (hanasu, speak) — su ending
        { "話さない", "話す", "godan verbs: su-ending 話す" },     -- negative
        { "話した",   "話す", "godan verbs: su-ending 話す" },     -- past
        { "話して",   "話す", "godan verbs: su-ending 話す" },     -- te-form
        { "話します", "話す", "godan verbs: su-ending 話す" },     -- polite
        { "話せば",   "話す", "godan verbs: su-ending 話す" },     -- conditional
        { "話せる",   "話す", "godan verbs: su-ending 話す" },     -- potential
        -- 待つ (matsu, wait) — tsu ending
        { "待たない", "待つ", "godan verbs: tsu-ending 待つ" },   -- negative
        { "待った",   "待つ", "godan verbs: tsu-ending 待つ" },   -- past
        { "待って",   "待つ", "godan verbs: tsu-ending 待つ" },   -- te-form
        { "待ちます", "待つ", "godan verbs: tsu-ending 待つ" },   -- polite
        { "待てば",   "待つ", "godan verbs: tsu-ending 待つ" },   -- conditional
        -- 死ぬ (shinu, die) — nu ending
        { "死なない", "死ぬ", "godan verbs: nu-ending 死ぬ" },   -- negative
        { "死んだ",   "死ぬ", "godan verbs: nu-ending 死ぬ" },   -- past
        { "死んで",   "死ぬ", "godan verbs: nu-ending 死ぬ" },   -- te-form
        { "死にます", "死ぬ", "godan verbs: nu-ending 死ぬ" },   -- polite
        { "死ねば",   "死ぬ", "godan verbs: nu-ending 死ぬ" },   -- conditional
        -- 遊ぶ (asobu, play) — bu ending
        { "遊ばない", "遊ぶ", "godan verbs: bu-ending 遊ぶ" },   -- negative
        { "遊んだ",   "遊ぶ", "godan verbs: bu-ending 遊ぶ" },   -- past
        { "遊んで",   "遊ぶ", "godan verbs: bu-ending 遊ぶ" },   -- te-form
        { "遊びます", "遊ぶ", "godan verbs: bu-ending 遊ぶ" },   -- polite
        { "遊べば",   "遊ぶ", "godan verbs: bu-ending 遊ぶ" },   -- conditional
        -- 読む (yomu, read) — mu ending
        { "読まない", "読む", "godan verbs: mu-ending 読む" },   -- negative
        { "読んだ",   "読む", "godan verbs: mu-ending 読む" },   -- past
        { "読んで",   "読む", "godan verbs: mu-ending 読む" },   -- te-form
        { "読みます", "読む", "godan verbs: mu-ending 読む" },   -- polite
        { "読めば",   "読む", "godan verbs: mu-ending 読む" },   -- conditional
        -- 取る (toru, take) — ru ending (godan, not ichidan)
        { "取らない", "取る", "godan verbs: ru-ending 取る" },   -- negative
        { "取った",   "取る", "godan verbs: ru-ending 取る" },   -- past
        { "取って",   "取る", "godan verbs: ru-ending 取る" },   -- te-form
        { "取ります", "取る", "godan verbs: ru-ending 取る" },   -- polite
        { "取れば",   "取る", "godan verbs: ru-ending 取る" },   -- conditional
        -- 買う (kau, buy) — u ending
        { "買わない", "買う", "godan verbs: u-ending 買う" },     -- negative
        { "買った",   "買う", "godan verbs: u-ending 買う" },     -- past
        { "買って",   "買う", "godan verbs: u-ending 買う" },     -- te-form
        { "買います", "買う", "godan verbs: u-ending 買う" },     -- polite
        { "買えば",   "買う", "godan verbs: u-ending 買う" },     -- conditional
        { "買おう",   "買う", "godan verbs: u-ending 買う" },     -- volitional
        { "買える",   "買う", "godan verbs: u-ending 買う" },     -- potential
        -- 行く (iku, go) — irregular te/past forms
        { "行った",   "行く", "godan verbs: irregular 行く" },   -- past
        { "行って",   "行く", "godan verbs: irregular 行く" },   -- te-form
        { "行ったら", "行く", "godan verbs: irregular 行く" },   -- -tara

        -- Suru verbs (vs)
        { "しない",         "する", "suru verbs" },               -- negative
        { "した",           "する", "suru verbs" },               -- past
        { "して",           "する", "suru verbs" },               -- te-form
        { "します",         "する", "suru verbs" },               -- polite
        { "しません",       "する", "suru verbs" },               -- polite negative
        { "しました",       "する", "suru verbs" },               -- polite past
        { "しませんでした", "する", "suru verbs" },               -- polite past negative
        { "しましょう",     "する", "suru verbs" },               -- polite volitional
        { "すれば",         "する", "suru verbs" },               -- conditional
        { "しよう",         "する", "suru verbs" },               -- volitional
        { "しろ",           "する", "suru verbs" },               -- imperative
        { "せよ",           "する", "suru verbs" },               -- imperative (seyo)
        { "させる",         "する", "suru verbs" },               -- causative
        { "される",         "する", "suru verbs" },               -- passive
        { "したい",         "する", "suru verbs" },               -- -tai
        { "しなさい",       "する", "suru verbs" },               -- -nasai
        { "しそう",         "する", "suru verbs" },               -- -sou
        { "しすぎる",       "する", "suru verbs" },               -- -sugiru
        { "せず",           "する", "suru verbs" },               -- -zu
        { "せぬ",           "する", "suru verbs" },               -- -nu
        { "しとく",         "する", "suru verbs" },               -- -toku
        { "しちゃう",       "する", "suru verbs" },               -- -chau
        { "為ろ",           "為る", "suru verbs" },               -- imperative (kanji)

        -- Kuru verbs (vk): くる (hiragana)
        { "こない",     "くる", "kuru verbs" },                   -- negative
        { "きた",       "くる", "kuru verbs" },                   -- past
        { "きて",       "くる", "kuru verbs" },                   -- te-form
        { "きます",     "くる", "kuru verbs" },                   -- polite
        { "きません",   "くる", "kuru verbs" },                   -- polite negative
        { "きました",   "くる", "kuru verbs" },                   -- polite past
        { "くれば",     "くる", "kuru verbs" },                   -- conditional
        { "こよう",     "くる", "kuru verbs" },                   -- volitional
        { "こい",       "くる", "kuru verbs" },                   -- imperative
        { "こさせる",   "くる", "kuru verbs" },                   -- causative
        { "こられる",   "くる", "kuru verbs" },                   -- passive
        { "これる",     "くる", "kuru verbs" },                   -- potential
        { "こず",       "くる", "kuru verbs" },                   -- -zu
        { "きとく",     "くる", "kuru verbs" },                   -- -toku
        { "き",         "くる", "kuru verbs" },                   -- masu stem
        -- 来る (kanji)
        { "来た",       "来る", "kuru verbs" },                   -- past (kanji)
        { "来て",       "来る", "kuru verbs" },                   -- te-form (kanji)
        { "来ない",     "来る", "kuru verbs" },                   -- negative (kanji)
        { "来ます",     "来る", "kuru verbs" },                   -- polite (kanji)
        { "来い",       "来る", "kuru verbs" },                   -- imperative (kanji)

        -- Zuru verbs (vz): 感ずる (kanzuru, to feel)
        { "感じない",         "感ずる", "zuru verbs" },           -- negative
        { "感じた",           "感ずる", "zuru verbs" },           -- past
        { "感じて",           "感ずる", "zuru verbs" },           -- te-form
        { "感じます",         "感ずる", "zuru verbs" },           -- polite
        { "感じません",       "感ずる", "zuru verbs" },           -- polite negative
        { "感じました",       "感ずる", "zuru verbs" },           -- polite past
        { "感じませんでした", "感ずる", "zuru verbs" },           -- polite past negative
        { "感じましょう",     "感ずる", "zuru verbs" },           -- polite volitional
        { "感ずれば",         "感ずる", "zuru verbs" },           -- conditional
        { "感じよう",         "感ずる", "zuru verbs" },           -- volitional
        { "感じろ",           "感ずる", "zuru verbs" },           -- imperative
        { "感ぜよ",           "感ずる", "zuru verbs" },           -- imperative (zeyo)
        { "感じさせる",       "感ずる", "zuru verbs" },           -- causative
        { "感ぜさせる",       "感ずる", "zuru verbs" },           -- causative (ze-)
        { "感じされる",       "感ずる", "zuru verbs" },           -- passive
        { "感ざれる",         "感ずる", "zuru verbs" },           -- potential/passive
        { "感ぜられる",       "感ずる", "zuru verbs" },           -- potential/passive (ze-)
        { "感じたい",         "感ずる", "zuru verbs" },           -- -tai
        { "感じなさい",       "感ずる", "zuru verbs" },           -- -nasai
        { "感じそう",         "感ずる", "zuru verbs" },           -- -sou
        { "感じすぎる",       "感ずる", "zuru verbs" },           -- -sugiru
        { "感じたら",         "感ずる", "zuru verbs" },           -- -tara
        { "感じたり",         "感ずる", "zuru verbs" },           -- -tari
        { "感ぜず",           "感ずる", "zuru verbs" },           -- -zu
        { "感ぜぬ",           "感ずる", "zuru verbs" },           -- -nu
        { "感じとく",         "感ずる", "zuru verbs" },           -- -toku
        { "感じちゃう",       "感ずる", "zuru verbs" },           -- -chau
        { "感じちまう",       "感ずる", "zuru verbs" },           -- -chimau

        -- Heavily inflected forms (multi-step deinflection chains)
        { "食べている",       "食べる", "heavily inflected" },     -- progressive
        { "食べてる",         "食べる", "heavily inflected" },     -- progressive (contracted)
        { "食べておる",       "食べる", "heavily inflected" },     -- progressive (おる)
        { "食べとる",         "食べる", "heavily inflected" },     -- progressive (contracted おる)
        { "書いている",       "書く",   "heavily inflected" },     -- godan progressive
        { "書いてる",         "書く",   "heavily inflected" },     -- godan progressive (contracted)
        { "感じている",       "感ずる", "heavily inflected" },     -- zuru progressive
        { "感じてる",         "感ずる", "heavily inflected" },     -- zuru progressive (contracted)
        { "食べてしまう",     "食べる", "heavily inflected" },     -- -te shimau
        { "食べなかった",     "食べる", "heavily inflected" },     -- negative past
        { "食べませんでした", "食べる", "heavily inflected" },     -- polite negative past
        { "書かされる",       "書く",   "heavily inflected" },     -- causative-passive
        { "食べちゃった",     "食べる", "heavily inflected" },     -- -chau past
        { "食べられない",     "食べる", "heavily inflected" },     -- potential negative
        { "食べさせない",     "食べる", "heavily inflected" },     -- causative negative
        { "食べさせます",     "食べる", "heavily inflected" },     -- causative polite
        { "食べられなければ", "食べる", "heavily inflected" },     -- potential negative conditional
        { "食べたかった",     "食べる", "heavily inflected" },     -- -tai past
        { "食べたくない",     "食べる", "heavily inflected" },     -- -tai negative
        { "食べています",     "食べる", "heavily inflected" },     -- progressive polite
    }

    -- Strings that should NOT be deinflected to the given dictionary form.
    -- These contain grammatical particles or sentence-final elements that are
    -- not inflectional suffixes.
    local no_deinflection_tests = {
        { "食べたんです",       "食べる", "should not deinflect" }, -- explanatory んです
        { "食べたのです",       "食べる", "should not deinflect" }, -- explanatory のです
        { "食べたんだ",         "食べる", "should not deinflect" }, -- explanatory んだ
        { "食べるだろう",       "食べる", "should not deinflect" }, -- conjecture だろう
        { "食べたよ",           "食べる", "should not deinflect" }, -- sentence-final よ
        { "食べたね",           "食べる", "should not deinflect" }, -- sentence-final ね
        { "食べるかもしれない", "食べる", "should not deinflect" }, -- かもしれない (might)
    }

    -- Text conversion tests use deinflect() (with kana conversions enabled).
    local text_conversion_tests = {
        { "タベナイ", "たべない", "text conversions" },           -- katakana → hiragana
        { "タベナイ", "たべる",   "text conversions" },           -- katakana → hiragana + deinflect
        { "ﾀﾍﾞﾙ",   "タベル",    "text conversions" },           -- halfwidth → fullwidth
    }

    -- Group tests by their group field and generate describe/it blocks.
    local grouped = {}
    local group_order = {}
    for _, case in ipairs(deinflection_tests) do
        local group = case[3]
        if not grouped[group] then
            grouped[group] = {}
            table.insert(group_order, group)
        end
        table.insert(grouped[group], case)
    end
    for _, group in ipairs(group_order) do
        describe(group, function()
            for _, case in ipairs(grouped[group]) do
                it(case[1] .. " → " .. case[2], function()
                    assert.is_true(deinflectsTo(case[1], case[2]))
                end)
            end
        end)
    end

    describe("should not deinflect", function()
        for _, case in ipairs(no_deinflection_tests) do
            it(case[1] .. " should not → " .. case[2], function()
                assert.is_false(deinflectsTo(case[1], case[2]))
            end)
        end
    end)

    describe("text conversions", function()
        for _, case in ipairs(text_conversion_tests) do
            it(case[1] .. " → " .. case[2], function()
                assert.is_true(deinflectsFull(case[1], case[2]))
            end)
        end
    end)
end)
