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
local util = require("util")
local _ = require("gettext")

local SingleInstanceDeinflector = Deinflector:new()

local Japanese = WidgetContainer:new({
    name = "japanese_support",
    pretty_name = "Japanese",
})

function Japanese:init()
    self.deinflector = SingleInstanceDeinflector
    self.dictionary = (self.ui and self.ui.dictionary) or ReaderDictionary:new()
    -- Yomichan uses 10 characters as the default look-ahead, but crengine's
    -- getNextVisibleChar counts furigana if any are present, so use a higher
    -- threshold to be able to look-ahead an equivalent number of characters.
    -- TODO: Make this configurable.
    self.maximum_expansions = 20
    LanguageSupport:registerPlugin(self)
end

function Japanese:supportsLanguage(language_code)
    return language_code == "ja" or language_code == "jpn"
end

function Japanese:onWordLookup(args)
    local text = args.text

    -- If there are no CJK characters in the text, there's nothing to do.
    if not util.hasCJKChar(text) then
        return
    end

    -- TODO: Try to repeatedly reduce the text and deinflect the shortened text
    --       to provide more candidates. This is particularly needed because
    --       JMDict has a habit of creating entries for compounds or phrases
    --       that do not exist in monolingual dictionaries (even in 大辞林 or
    --       広辞苑) and our onWordSelection expansion accepts any dictionary's
    --       largest entry. Unfortuantely doing this nicely requires some
    --       fiddling with utf8proc since we need to :sub remove the last
    --       character multiple times.

    results = self.deinflector:deinflect(text)
    logger.dbg("japanese.koplugin: deinflection of", text, "results:", results)

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

-- TODO: Switch this to utf8proc_category or something similar.
local JAPANESE_PUNCTUATION = "「」『』【】〘〙〖〗・･、､,。｡.！!？?　 \n"

local function isPossibleJapaneseWord(str)
    for c in str:gmatch(util.UTF8_CHAR_PATTERN) do
        if not util.isCJKChar(c) or JAPANESE_PUNCTUATION:find(c) ~= nil then
            return false
        end
    end
    return true
end

function Japanese:onWordSelection(args)
    local pos0, pos1 = args.pos0, args.pos1
    local callbacks = args.callbacks
    local current_text = args.text

    -- If the initial selection contains only non-CJK characters, then there's
    -- no point trying to expand it because no Japanese words mix CJK and
    -- non-CJK characters (there are non-CJK words in Japanese -- CM, NG, TKG
    -- and their full-width equivalents for instance -- but they are selected
    -- by crengine correctly already and are full words by themselves).
    if current_text ~= "" and not util.hasCJKChar(current_text) then
        return
    end

    -- We reset the end of the range to pos0+1 because crengine will select
    -- half-width katakana (ｶﾀｶﾅ) in strange ways that often overshoots the
    -- end of words.
    pos1 = callbacks.get_next_char_pos(pos0)

    -- We try to advance the end position until we hit a word.
    --
    -- Unfortunately it's possible for the complete word to be longer than the
    -- first match (obvious examples include 読み込む or similar compound verbs
    -- where it would be less than ideal to match 読み as the full word, but
    -- there are more subtle kana-only cases as well) so we need to keep
    -- looking forward, but unfortunately there isn't a great endpoint defined
    -- either (aside from punctuation). So we just copy Yomichan and set a hard
    -- limit (20 characters) and stop early if we ever hit punctuation. We then
    -- select the longest word present in one of the user's installed
    -- dictionaries (after deinflection).

    local all_candidates = {}
    local all_words = {}

    local current_end = pos1
    local num_expansions = 0
    repeat
        -- Move to the next character.
        current_end = callbacks.get_next_char_pos(current_end)
        current_text = callbacks.get_text_in_range(pos0, current_end)
        num_expansions = num_expansions + 1

        -- If the text could not be a complete Japanese word (i.e. it contains
        -- a punctuation or some other special character), quit early. We test
        -- the whole string rather than the last character because finding the
        -- last character requires a linear walk through the string anyway, and
        -- get_next_char_pos() skips over newlines.
        if not isPossibleJapaneseWord(current_text) then
            logger.dbg("japanese.koplugin: stopping expansion at", current_text, "because in contains non-word characters")
            break
        end

        -- Get the selection and try to deinflect it.
        local candidates = self.deinflector:deinflect(current_text)
        local terms = {}
        for _, candidate in ipairs(candidates) do
            table.insert(terms, candidate.term)
        end

        -- Add the candidates to the set of words to attempt.
        for _, term in ipairs(terms) do
            table.insert(all_candidates, {
                pos0 = pos0,
                pos1 = current_end,
                text = term,
            })
            table.insert(all_words, term)
        end
    until current_end == nil or num_expansions >= self.maximum_expansions
    logger.dbg("japanese.koplugin: attempted", num_expansions, "expansions up to", current_text)

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
                text = self.description,
            }))
        end,
    }
end

return Japanese
