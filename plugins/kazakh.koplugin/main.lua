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
-- Intermediate rungs are usually not words, and KOReader resolves candidates
-- with fuzzy search on, so each one returns near-spelling matches that sort
-- above the real article. Resolving them here with exact search first keeps
-- only those that exist, in ladder order, so the shallowest analysis leads.
--
-- On any failure the unfiltered list is returned: this can only add precision,
-- never lose a result.
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
        -- @translators The Kazakh language, shown under Language support.
        text = _("Kazakh"),
        help_text = _("Offers every morphological form of the tapped word to the dictionary, which then returns whichever ones actually exist."),
        sub_item_table = {
            {
                text_func = function()
                    -- @translators %1 is the number of dictionary forms offered per lookup.
                    return T(_("Maximum candidates: %1"), self.max_candidates)
                end,
                help_text = _("How many dictionary-form candidates to offer per lookup. Lowering this makes lookups faster."),
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
