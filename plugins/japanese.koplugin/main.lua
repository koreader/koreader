--- Japanese language support for KOReader, modelled after Yomichan.
-- This plugin extends KOReader's built-in dictionary and selection system to
-- support Yomichan-style deinflection and text scanning, allowing for one-tap
-- searches of inflected verbs and multi-character words and phrases. As such,
-- this plugin removes the need for synonym-based deinflection rules for
-- StarDict-converted Japanese dictionaries.
--
-- @module koplugin.japanese
-- @alias Japanese

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
local LanguageSupport = require("languagesupport")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local SingleInstanceDeinflector = Deinflector:new{}

local Japanese = WidgetContainer:extend{
    name = "japanese",
    pretty_name = "Japanese",
}

-- Yomichan uses 10 characters as the default look-ahead, but crengine's
-- getNextVisibleChar counts furigana if any are present, so use a higher
-- threshold to be able to look-ahead an equivalent number of characters.
local DEFAULT_TEXT_SCAN_LENGTH = 20
-- Number of characters to look back from the initially selected character
-- when attempting to find the largest word containing that character.
local DEFAULT_TEXT_SCAN_LOOKBACK = 1

function Japanese:init()
    self.deinflector = SingleInstanceDeinflector
    self.dictionary = (self.ui and self.ui.dictionary) or ReaderDictionary:new()
    self.max_scan_length = G_reader_settings:readSetting("language_japanese_text_scan_length") or DEFAULT_TEXT_SCAN_LENGTH
    self.max_scan_lookback = G_reader_settings:readSetting("language_japanese_text_scan_lookback") or DEFAULT_TEXT_SCAN_LOOKBACK
    LanguageSupport:registerPlugin(self)
end

function Japanese:supportsLanguage(language_code)
    return language_code == "ja" or language_code == "jpn"
end

--- Called from @{languagesupport.extraDictionaryFormCandidates} for Japanese
-- text. Tries to find and return any possible deinflections for the given text.
-- @param args arguments from language support
-- @treturn {string,...} extra dictionary form candiadates found (or nil)
-- @see languagesupport.extraDictionaryFormCandidates
-- @see languagesupport.registerPlugin
function Japanese:onWordLookup(args)
    local text = args.text

    -- If there are no CJK characters in the text, there's nothing to do.
    if not util.hasCJKChar(text) then
        return
    end

    --- @todo Try to repeatedly reduce the text and deinflect the shortened text
    --       to provide more candidates. This is particularly needed because
    --       JMDict has a habit of creating entries for compounds or phrases
    --       that do not exist in monolingual dictionaries (even in 大辞林 or
    --       広辞苑) and our onWordSelection expansion accepts any dictionary's
    --       largest entry. Unfortunately doing this nicely requires a bit of
    --       extra work to be efficient (since we need to remove the last
    --       character in the string).

    local results = self.deinflector:deinflect(text)
    logger.dbg("japanese.koplugin: deinflection of", text, "results:", results)

    --- @todo Pass up the reasons list (formatted Yomichan style) to the
    --       dictionary pop-up so you can get some more information about the
    --       inflection. But this would require adding some kind of tag
    --       metadata that we have to pass through from the lookup to the
    --       dictionary pop-up.

    local candidates = {}
    for i, result in ipairs(results) do
        candidates[i] = result.term
    end
    return candidates
end

-- @todo Switch this to utf8proc_category or something similar.
local JAPANESE_PUNCTUATION = "「」『』【】〘〙〖〗・･、､,。｡.！!？?　 \n"

local function isPossibleJapaneseWord(str)
    for c in str:gmatch(util.UTF8_CHAR_PATTERN) do
        if not util.isCJKChar(c) or JAPANESE_PUNCTUATION:find(c) ~= nil then
            return false
        end
    end
    return true
end

--- Called from @{languagesupport.improveWordSelection} for Japanese text.
-- Tries to expand the word selection defined by args.
-- @param args arguments from language support
-- @treturn {pos0,pos1} the new selection range (or nil)
-- @see languagesupport.improveWordSelection
-- @see languagesupport.registerPlugin
function Japanese:onWordSelection(args)
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

    -- Helper to check whether target XPointer lies inside [p0, p1) by walking forward.
    local function containsXPointer(p0, p1, target)
        local cur = p0
        while cur ~= nil and cur ~= p1 do
            if cur == target then return true end
            cur = callbacks.get_next_char_pos(cur)
        end
        return false
    end

    -- Define initial position (anchor). If the user selected multiple
    -- characters, anchor on the first character (pos0) and ignore the original
    -- selection end so that we search for the largest word that contains this
    -- specific character.
    local initial_pos = args.pos0

    -- Compute earliest starting position by looking back up to max_scan_lookback characters.
    local earliest_start = initial_pos
    do
        local cur = initial_pos
        local steps = 0
        while steps < (self.max_scan_lookback or 0) do
            local prev = callbacks.get_prev_char_pos(cur)
            if not prev then break end
            earliest_start = prev
            cur = prev
            steps = steps + 1
        end
    end

    -- Build all candidate terms across each start position, expanding right up to
    -- max_scan_length and stopping early if we encounter non-word characters.
    -- We explore multiple left starts (lookback) because CJK words may span
    -- multiple characters before the tapped one; expansion is rightward only
    -- for performance and simplicity.
    -- The complete word can be longer than the earliest match (e.g., compound
    -- verbs or kana-only sequences), so we keep extending the end and rely on
    -- dictionary hits to identify the best (longest) span.
    local all_candidates = {}
    local blocks = {} -- list of {start_pos, first_idx, last_idx}

    -- Iterate from earliest_start forward to initial_pos, one start position per step.
    do
        local start_pos = earliest_start
        while start_pos ~= nil do
            -- Track block boundary for this start.
            local block_first = #all_candidates + 1

            -- Expand right up to max_scan_length or until non-word characters.
            local expansions = 0
            -- Initialize the end to the next character to avoid edge cases with
            -- half-width katakana selection occasionally overshooting word ends.
            -- This makes the first evaluated span two characters long.
            local cur_end = callbacks.get_next_char_pos(start_pos)
            while cur_end ~= nil and expansions < self.max_scan_length do
                cur_end = callbacks.get_next_char_pos(cur_end)
                if not cur_end then break end

                local span_text = callbacks.get_text_in_range(start_pos, cur_end)
                expansions = expansions + 1

                -- If the text could not be a complete Japanese word (i.e. it contains
                -- a punctuation or some other special character), quit early. We test
                -- the whole string rather than the last character because finding the
                -- last character requires a linear walk through the string anyway, and
                -- get_next_char_pos() skips over newlines.
                if not isPossibleJapaneseWord(span_text) then
                    logger.dbg("japanese.koplugin: stopping expansion at", span_text, "because in contains non-word characters")
                    break
                end

                -- Deinflect span and add all terms as candidates for this span.
                local candidates = self.deinflector:deinflect(span_text)
                for _, cand in ipairs(candidates) do
                    table.insert(all_candidates, { pos0 = start_pos, pos1 = cur_end, text = cand.term, span_len = expansions + 1 })
                end
            end

            local block_last = #all_candidates
            if block_last >= block_first then
                table.insert(blocks, { start_pos = start_pos, first_idx = block_first, last_idx = block_last })
            end

            if start_pos == initial_pos then break end
            start_pos = callbacks.get_next_char_pos(start_pos)
        end
    end

    -- Nothing to look up.
    if #all_candidates == 0 then return end

    -- Calling sdcv is fairly expensive, so reduce the cost by trying every
    -- candidate in one shot and then picking the longest one which gave us a
    -- result.
    --- @todo Given there is a limit to how many command-line arguments you can
    --       pass, we should split up the candidate list if it's too long.
    local all_words = {}
    for i = 1, #all_candidates do all_words[i] = all_candidates[i].text end
    local cancelled, all_results = self.dictionary:rawSdcv(all_words)
    if cancelled or not all_results then return end

    -- For each start block, pick the longest span that produced results, but only
    -- keep it if it contains the initially selected character.
    local final_candidates = {}
    for _, block in ipairs(blocks) do
        local best_idx = nil
        for i = block.first_idx, block.last_idx do
            local term_results = all_results[i]
            if term_results and #term_results ~= 0 then
                best_idx = i -- later i means longer span for this start
            end
        end
        if best_idx then
            local cand = all_candidates[best_idx]
            if containsXPointer(cand.pos0, cand.pos1, initial_pos) then
                table.insert(final_candidates, cand)
            end
        end
    end

    -- Choose the longest candidate across all starts.
    local best_word, best_len = nil, -1
    for _, cand in ipairs(final_candidates) do
        local l = cand.span_len or 0
        if l > best_len then
            best_len = l
            best_word = cand
        end
    end

    if best_word then
        return { best_word.pos0, best_word.pos1 }
    end
end

function Japanese:genMenuItem()
    local sub_item_table = {
        -- self.max_scan_length configuration
        {
            text_func = function()
                return T(N_("Text scan length: %1 character", "Text scan length: %1 characters", self.max_scan_length), self.max_scan_length)
            end,
            help_text = _("Number of characters to look ahead when trying to expand tap-and-hold word selection in documents."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                local Screen = require("device").screen
                local items = SpinWidget:new{
                    title_text = _("Text scan length"),
                    info_text = T(_([[
The maximum number of characters to look ahead when trying to expand tap-and-hold word selection in documents.
Larger values allow longer phrases to be selected automatically, but with the trade-off that selections may become slower.

Default value: %1]]), DEFAULT_TEXT_SCAN_LENGTH),
                    width = math.floor(Screen:getWidth() * 0.75),
                    value = self.max_scan_length,
                    value_min = 0,
                    value_max = 1000,
                    value_step = 1,
                    value_hold_step = 10,
                    ok_text = _("Set scan length"),
                    default_value = DEFAULT_TEXT_SCAN_LENGTH,
                    callback = function(spin)
                        self.max_scan_length = spin.value
                        G_reader_settings:saveSetting("language_japanese_text_scan_length", self.max_scan_length)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                }
                UIManager:show(items)
            end,
        },
        -- self.max_scan_lookback configuration
        {
            text_func = function()
                return T(N_("Text scan lookback: %1 character", "Text scan lookback: %1 characters", self.max_scan_lookback), self.max_scan_lookback)
            end,
            help_text = _("Number of characters to look back from the selection when trying to find the largest word containing the selected character."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                local Screen = require("device").screen
                local items = SpinWidget:new{
                    title_text = _("Text scan lookback"),
                    info_text = T(_([[
Start scanning up to this many characters before the initially selected character, expanding to the right to find the longest word that contains it.

Default value: %1]]), DEFAULT_TEXT_SCAN_LOOKBACK),
                    width = math.floor(Screen:getWidth() * 0.75),
                    value = self.max_scan_lookback,
                    value_min = 0,
                    value_max = 1000,
                    value_step = 1,
                    value_hold_step = 10,
                    ok_text = _("Set lookback"),
                    default_value = DEFAULT_TEXT_SCAN_LOOKBACK,
                    callback = function(spin)
                        self.max_scan_lookback = spin.value
                        G_reader_settings:saveSetting("language_japanese_text_scan_lookback", self.max_scan_lookback)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                }
                UIManager:show(items)
            end,
        },
    }
    -- self.deinflector configuration
    util.arrayAppend(sub_item_table, self.deinflector:genMenuItems())

    return {
        text = _("Japanese"),
        sub_item_table = sub_item_table,
    }
end

return Japanese
