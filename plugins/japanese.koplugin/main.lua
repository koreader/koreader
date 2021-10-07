-- Copyright (C) 2021 Aleksa Sarai <cyphar@cyphar.com>
-- Licensed under the GPLv3 or later.
--
-- The deinflection logic is heavily modelled after Yomichan
-- <https://github.com/FooSoft/yomichan>, up to and including the deinflection
-- table. The way we try to find candidate words is also fairly similar (the
-- naive approach), though because dictionary lookups are quite expensive (we
-- have to call sdcv each time) we batch as many candidates as possible
-- together in order to reduce the impact we have on text selection.

local LanguageSupport = require("languagesupport")
local logger = require("logger")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local JSON = require("json")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Deinflector = require("deinflector")

local Japanese = WidgetContainer:new({
    name = "japanese_support",
})

function Japanese:init()
    self.deinflector = Deinflector:new()
    self.dictionary = (self.ui and self.ui.dictionary) or ReaderDictionary:new()
    self.maximum_expansions = 20
    LanguageSupport:registerPlugin("ja", self)
end

function Japanese:onWordLookup(args)
    -- TODO: If no deinflections are found, try to repeatedly reduce the text
    --       by one character in case the user selected too much text by
    --       accident.

    results = self.deinflector:deinflect(args.text)
    logger.dbg("japanese deinflector results", results)

    -- TODO: Pass up the reasons list (formatted Yomichan style) to the
    --       dictionary pop-up so you can get some more information about the
    --       inflection. But this would require adding some kind of tag
    --       metadata that we have to pass through from the lookup to the
    --       dictionary pop-up.

    candidates = {}
    for i, result in ipairs(results) do
        candidates[i] = result.term
    end
    return candidates
end

function Japanese:onWordSelection(args)
    local document = args.document
    local selection = args.selection

    -- We try to advance the end position until we hit a word. Unfortunately
    -- it's possible for the complete word to be longer than the first match
    -- (obvious examples include 読み込む or similar compound verbs where it
    -- would be less than ideal to match 読み as the full word, but there are
    -- more subtle kana-only cases as well) so we need to keep looking forward,
    -- but unfortunately there isn't a great endpoint defined either (aside
    -- from punctuation). So we just set a hard limit (100 characters) and stop
    -- early if we ever hit punctuation. We then select the longest word.

    -- TODO: Picking the longest word found in any dictionary is not always the
    --       right thing to do. JEDict likes to create entries for "words"
    --       which monolingual dictionaries consider to be obvious compounds
    --       not deserving of a dictionary entry. However, Yomichan does the
    --       same thing here -- we can improve this by making onWordLookup
    --       return all shorter candidates too.

    local all_candidates = {}
    local all_words = {}

    local current_end = selection.pos1
    local num_expansions = 0
    while current_end ~= nil and num_expansions < self.maximum_expansions do
        -- Get the selection and try to deinflect it.
        local text = document:getTextFromXPointers(selection.pos0, current_end)
        -- TODO: Check if the text ends with punctuation and end early.
        local candidates = self.deinflector:deinflect(text)
        local words = {text}
        for _, candidate in ipairs(candidates) do
            table.insert(words, candidate.term)
        end

        -- Add the candidates to the set of words to attempt.
        for _, text in ipairs(words) do
            table.insert(all_candidates, {
                pos0 = selection.pos0,
                pos1 = current_end,
                text = text,
            })
            table.insert(all_words, text)
        end

        current_end = document:getNextVisibleChar(current_end)
        num_expansions = num_expansions + 1
    end

    -- Calling sdcv is fairly expensive, so amortise the cost by trying every
    -- candidate in one shot and then picking the longest one which gave us a
    -- result.
    -- TODO: Given there is a limit to how many command-line arguments you can
    --       pass, we should split up the candidate list if it's too long.
    local best_word
    local cancelled, all_results = self.dictionary:rawSdcv(all_words)
    if not cancelled and all_results ~= nil then
        for i, term_results in ipairs(all_results) do
            if #term_results ~= 0 then
                best_word = all_candidates[i]
            end
        end
    end

    if best_word ~= nil then
        return {best_word.pos0, best_word.pos1}
    end
end

return Japanese
