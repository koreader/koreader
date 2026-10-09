--- Kazakh language support for KOReader.
-- Kazakh is agglutinative, so `мектептерімізде` carries plural, possessive and
-- locative on top of the lemma `мектеп` a dictionary is keyed on. This plugin
-- extends KOReader's dictionary lookup with the morphological forms of the
-- tapped word, in the same way the Japanese plugin does with deinflection.
--
-- It offers every legal analysis rather than picking one stem, and lets the
-- dictionary decide which exist, so no lexicon is shipped or held in memory.
--
-- @module koplugin.kazakh
-- @alias Kazakh

-- Licensed under the AGPLv3 or later.
--
-- The stemmer is ported from kazsearch-py
-- <https://github.com/iDynbek/kazsearch-py>, itself a port of the Rust core of
-- pg-kazsearch <https://github.com/darkhanakh/pg-kazsearch>, LGPLv3 or later.

local LanguageSupport = require("languagesupport")
local Stemmer = require("stemmer")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

-- Offering every rung of a very long word costs a wider sdcv call for
-- diminishing returns; deep rungs are short and rarely the intended lemma.
local DEFAULT_MAX_CANDIDATES = 8

local Kazakh = WidgetContainer:extend{
    name = "kazakh",
    pretty_name = "Kazakh",
}

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- U+0400–U+04FF (Cyrillic, including the Kazakh-specific ә ғ қ ң ө ұ ү һ і)
-- is exactly the two-byte UTF-8 sequences with a lead byte of 0xD0–0xD3.
local function hasCyrillic(text)
    return text:find("[\208-\211]") ~= nil
end

-- The nine letters Kazakh adds to the Russian alphabet.
local KAZAKH_LETTERS = {}
for c in ("әғқңөұүһі"):gmatch(UTF8_CHAR) do KAZAKH_LETTERS[c] = true end

-- A stem-final ы/і elides before the -у ending: оқы -> оқу, not оқыу.
local ELIDES_BEFORE_U = { ["ы"] = true, ["і"] = true }

--- The -у verbal noun of a verb stem: жаз -> жазу, сөйле -> сөйлеу, оқы -> оқу.
--
-- This is the form many dictionaries key a verb on, while the ladder can only
-- strip suffixes and so bottoms out at the bare stem. Whether the stem really
-- is a verb is left to the dictionary, as everywhere else here: candidates are
-- resolved with exact search, so a word that does not exist costs nothing but
-- its place in the query.
local function verbalNoun(stem)
    local last = stem:match(UTF8_CHAR .. "$")
    -- Already a -у form; deriving another would only invent `оқуу`.
    if not last or last == "у" then return nil end
    if ELIDES_BEFORE_U[last] then
        return stem:sub(1, #stem - #last) .. "у"
    end
    return stem .. "у"
end

function Kazakh:init()
    self.max_candidates = G_reader_settings:readSetting("language_kazakh_max_candidates")
        or DEFAULT_MAX_CANDIDATES
    LanguageSupport:registerPlugin(self)
end

function Kazakh:supportsLanguage(language_code)
    return language_code == "kk" or language_code == "kaz" or language_code == "kk-KZ"
end

--- Whether this word is ours to analyse.
--
-- Language support calls every plugin as a fallback when none of them claims
-- the document's language, because that metadata is so often missing or wrong.
-- A Russian, Ukrainian or Bulgarian book therefore reaches this plugin too, and
-- "contains Cyrillic" would claim all of them: the script is shared, so it is
-- no more of a signal on its own than "contains Latin" would be for German.
--
-- In a book marked as Kazakh, any Cyrillic word is fair game. Everywhere else
-- the word must carry one of the nine letters Kazakh adds to the Russian
-- alphabet. No Russian or Bulgarian word does, so those readers pay nothing at
-- all; the cost is that a mislabelled Kazakh book loses the analysis of roughly
-- a quarter of its inflected words, which setting the language in Book
-- information restores.
function Kazakh:_isKazakhWord(word)
    if not hasCyrillic(word) then return false end
    local language = self.ui and self.ui.doc_props and self.ui.doc_props.language
    if self:supportsLanguage(language) then return true end
    for c in word:gmatch(UTF8_CHAR) do
        if KAZAKH_LETTERS[c] then return true end
    end
    return false
end

--- Called from @{languagesupport.extraDictionaryFormCandidates} for Kazakh
-- text. Returns every morphologically legal analysis of the tapped word.
-- @param args arguments from language support ({ text = [string] })
-- @treturn {string,...} extra dictionary form candidates (or nil)
-- @see languagesupport.extraDictionaryFormCandidates
function Kazakh:onWordLookup(args)
    local text = args.text
    if not text or text == "" then return end

    -- string.lower only maps ASCII, so Cyrillic has to go through utf8proc: a
    -- capitalised word would otherwise keep its capital through the whole walk
    -- and every rung would miss the lowercase headword it should have matched.
    local lower = Utf8Proc.lowercase(text, false)
    if not self:_isKazakhWord(lower) then return end

    local rungs = Stemmer.ladder(lower)
    if #rungs == 0 then return end

    local candidates = {}
    -- KOReader already looks the tapped word up itself; offering it again
    -- would only duplicate a result.
    local seen = { [text] = true, [lower] = true }
    local function offer(word)
        if word and not seen[word] then
            seen[word] = true
            candidates[#candidates + 1] = word
        end
    end

    for i = 1, math.min(#rungs, self.max_candidates) do
        offer(rungs[i])
    end

    -- Then the verbal nouns, after the analyses themselves so those keep the
    -- lead. Many dictionaries key a verb on its -у form rather than the bare
    -- stem the ladder strips down to, and nothing in the ladder can bridge
    -- that: it only removes suffixes. The tapped word gets one too, so that
    -- tapping `сөйле` still reaches `сөйлеу`.
    local analyses = #candidates
    offer(verbalNoun(lower))
    for i = 1, analyses do
        offer(verbalNoun(candidates[i]))
    end

    if #candidates == 0 then return end

    -- Every rung is offered, including the ones that are not words: language
    -- support resolves candidates with exact search, so an analysis that is not
    -- a headword returns nothing and costs only its place in the sdcv argv.
    logger.dbg("kazakh.koplugin: candidates for", text, "->", candidates)
    return candidates
end

function Kazakh:genMenuItem()
    return {
        -- @translators The Kazakh language, shown under Language support.
        text = _("Kazakh"),
        help_text = _("Offers every morphological form of the tapped word to the dictionary, which then returns whichever ones actually exist."),
        sub_item_table = {
            {
                text_func = function()
                    -- @translators %1 is the number of dictionary forms offered per lookup.
                    return T(_("Maximum candidates: %1"), self.max_candidates)
                end,
                help_text = _("How many analyses of the tapped word to offer per lookup. Each may add a verb form as well. Lowering this makes lookups faster."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local Screen = require("device").screen
                    UIManager:show(SpinWidget:new{
                        title_text = _("Maximum candidates"),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = self.max_candidates,
                        value_min = 1,
                        value_max = 16,
                        value_step = 1,
                        default_value = DEFAULT_MAX_CANDIDATES,
                        callback = function(spin)
                            self.max_candidates = spin.value
                            G_reader_settings:saveSetting(
                                "language_kazakh_max_candidates", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
        },
    }
end

return Kazakh
