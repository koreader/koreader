--[[--
Kazakh language support for KOReader.

Kazakh is agglutinative: `мектептерімізде` carries plural, possessive and
locative on top of `мектеп`. Dictionaries are keyed on lemmas, so tapping an
inflected word in a book finds nothing, and StarDict's fuzzy search does not
help — it measures edit distance, and a four-suffix word is nowhere near its
root by that measure.

This plugin hooks `LanguageSupport`'s WordLookup handler (the same mechanism
the Japanese plugin uses for deinflection) and supplies extra dictionary-form
candidates for the tapped word.

It deliberately does *not* try to pick the single correct stem. Any scorer gets
it wrong in both directions — for `маманда` it strips past the real root
`маман` down to `мама`; for `жанышта` it strips nothing and never reaches
`жаныш`. Instead every morphologically legal analysis is offered and the
dictionary decides which ones exist. That also means no lexicon has to be
shipped or held in memory.

@module koplugin.kazakh
--]]

local LanguageSupport = require("languagesupport")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Stemmer = require("stemmer")
local UIManager = require("ui/uimanager")
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

-- U+0400–U+04FF (Cyrillic, including the Kazakh-specific ә ғ қ ң ө ұ ү һ і)
-- is exactly the two-byte UTF-8 sequences with a lead byte of 0xD0–0xD3.
local function hasCyrillic(text)
    return text:find("[\208-\211]") ~= nil
end

function Kazakh:init()
    self.max_candidates = G_reader_settings:readSetting("language_kazakh_max_candidates")
        or DEFAULT_MAX_CANDIDATES
    self.dictionary = (self.ui and self.ui.dictionary) or ReaderDictionary:new()
    LanguageSupport:registerPlugin(self)
end

function Kazakh:supportsLanguage(language_code)
    return language_code == "kk" or language_code == "kaz" or language_code == "kk-KZ"
end

--- Called from @{languagesupport.extraDictionaryFormCandidates} for Kazakh
-- text. Returns every morphologically legal analysis of the tapped word.
-- @param args arguments from language support ({ text = [string] })
-- @treturn {string,...} extra dictionary form candidates (or nil)
-- @see languagesupport.extraDictionaryFormCandidates
function Kazakh:onWordLookup(args)
    local text = args.text
    if not text or text == "" then return end
    if not hasCyrillic(text) then return end

    local lower = text:lower()
    local rungs = Stemmer.ladder(lower)
    if #rungs == 0 then return end

    local candidates = {}
    for i = 1, math.min(#rungs, self.max_candidates) do
        -- KOReader already looks the tapped word up itself; offering it again
        -- would only duplicate a result.
        if rungs[i] ~= text and rungs[i] ~= lower then
            candidates[#candidates + 1] = rungs[i]
        end
    end
    if #candidates == 0 then return end

    candidates = self:_keepRealHeadwords(candidates)
    logger.dbg("kazakh.koplugin: candidates for", text, "->", candidates)
    if #candidates == 0 then return end
    return candidates
end

--- Drop candidates that are not actually headwords.
--
-- Intermediate rungs are usually not words. `мектептерімізде` yields
-- `мектептері` and `мектептер`, neither of which is a dictionary entry — but
-- KOReader looks candidates up with **fuzzy** search enabled, so each of those
-- returns a handful of near-spelling matches (МЕКТЕПТЕС, МЕКЕТТЕР, …). Results
-- are concatenated in query order, so that noise lands *above* the real
-- article and the correct entry ends up ninth in the list.
--
-- So the plugin resolves its own candidates first, with exact search, and
-- passes on only the ones that exist. Order is preserved, which means the
-- shallowest surviving analysis comes first: for `маманда` that is `маман`
-- rather than the over-stripped `мама`.
--
-- On any failure the unfiltered list is returned, so this can only ever add
-- precision, never remove a result that would otherwise have been found.
function Kazakh:_keepRealHeadwords(candidates)
    if not self.dictionary or not self.dictionary.rawSdcv then
        return candidates
    end
    -- fuzzy_search = false, and no progress message: this must be invisible.
    local ok, cancelled, results =
        pcall(self.dictionary.rawSdcv, self.dictionary, candidates, nil, false, false)
    if not ok then
        logger.dbg("kazakh.koplugin: candidate check failed:", cancelled)
        return candidates
    end
    if cancelled or type(results) ~= "table" or #results == 0 then
        return candidates
    end

    local kept = {}
    for i, cand in ipairs(candidates) do
        local r = results[i]
        if type(r) == "table" and #r > 0 then
            kept[#kept + 1] = cand
        end
    end
    return kept
end

function Kazakh:genMenuItem()
    return {
        text = _("Kazakh"),
        help_text = _([[
Kazakh is agglutinative, so an inflected word in a book does not match the lemma a dictionary is keyed on.

This plugin offers every morphologically legal analysis of the tapped word to the dictionary, letting the dictionary decide which ones exist.]]),
        sub_item_table = {
            {
                text_func = function()
                    return T(_("Maximum candidates: %1"), self.max_candidates)
                end,
                help_text = _("How many dictionary-form candidates to offer per lookup. Deeper analyses are shorter and less likely to be the intended word; lowering this makes lookups faster."),
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
