-- Copyright (C) 2021 Aleksa Sarai <cyphar@cyphar.com>
-- Licensed under the GPLv3 or later.
--
-- The deinflection logic is heavily modelled after Yomichan
-- <https://github.com/FooSoft/yomichan>, up to and including the deinflection
-- table. The way we try to find candidate words is also fairly similar (the
-- naive approach), though because dictionary lookups are quite expensive (we
-- have to call sdcv each time) we batch as many candidates as possible
-- together in order to reduce the impact we have on text selection.

local Deinflector = require("deinflector")
local InfoMessage = require("ui/widget/infomessage")
local LanguageSupport = require("languagesupport")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local SingleInstanceDeinflector = Deinflector:new()

local Japanese = WidgetContainer:new({
    name = "japanese_support",
    pretty_name = "Japanese",
})

function Japanese:init()
    self.deinflector = SingleInstanceDeinflector
    self.dictionary = (self.ui and self.ui.dictionary) or ReaderDictionary:new()
    -- TODO: Make this configurable.
    self.maximum_expansions = 20
    LanguageSupport:registerPlugin(self)
end

function Japanese:supportsLanguage(language_code)
    return language_code == "ja" or language_code == "jpn"
end

function Japanese:onWordLookup(args)
    local text = args.text

    -- TODO: Try to repeatedly reduce the text and deinflect the shortened text
    --       to provide more candidates. This is particularly needed because
    --       JMDict has a habit of creating entries for compounds or phrases
    --       that do not exist in monolingual dictionaries (even in 大辞林 or
    --       広辞苑) and our onWordSelection expansion accepts any dictionary's
    --       largest entry. Unfortuantely doing this nicely requires some
    --       fiddling with utf8proc since we need to :sub remove the last
    --       character multiple times.

    results = self.deinflector:deinflect(text)
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

local JAPANESE_PUNCTUATION = "「」『』【】〘〙〖〗・、。！？?!,."

function Japanese:onWordSelection(args)
    local pos0, pos1 = args.pos0, args.pos1
    local callbacks = args.callbacks

    -- TODO: Check that "word" is actually single character, since currently
    --       the only time we have issues with Japanese text is with CJK text.
    --       There are some Japanese words which are entirely non-CJK (NG and
    --       CM for instance) but those should already be correctly selected by
    --       crengine.

    -- We try to advance the end position until we hit a word. Unfortunately
    -- it's possible for the complete word to be longer than the first match
    -- (obvious examples include 読み込む or similar compound verbs where it
    -- would be less than ideal to match 読み as the full word, but there are
    -- more subtle kana-only cases as well) so we need to keep looking forward,
    -- but unfortunately there isn't a great endpoint defined either (aside
    -- from punctuation). So we just set a hard limit (20 characters) and stop
    -- early if we ever hit punctuation. We then select the longest word.

    local all_candidates = {}
    local all_words = {}

    local current_end = pos1
    local new_char = callbacks.get_text_in_range(pos0, pos1)
    local num_expansions = 0
    while current_end ~= nil and num_expansions < self.maximum_expansions do
        -- If the new character is a punctuation mark, quit early.
        -- TODO: Switch this to utf8proc_category.
        if JAPANESE_PUNCTUATION:find(new_char) ~= nil then
            break
        end

        -- Get the selection and try to deinflect it.
        local text = callbacks.get_text_in_range(pos0, current_end)
        local candidates = self.deinflector:deinflect(text)
        local words = {text}
        for _, candidate in ipairs(candidates) do
            table.insert(words, candidate.term)
        end

        -- Add the candidates to the set of words to attempt.
        for _, text in ipairs(words) do
            table.insert(all_candidates, {
                pos0 = pos0,
                pos1 = current_end,
                text = text,
            })
            table.insert(all_words, text)
        end

        new_char = callbacks.get_text_in_range(current_end, current_end)
        current_end = callbacks.get_next_char_pos(current_end)
        num_expansions = num_expansions + 1
    end

    -- Calling sdcv is fairly expensive, so reduce the cost by trying every
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

function Japanese:genMenuItems()
    -- TODO: Allow configuration through this menu.
    return {
        text = _("Japanese"),
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new({
                text = _("Japanese support for KOReader based on Yomichan."),
            }))
        end,
    }
end

return Japanese
