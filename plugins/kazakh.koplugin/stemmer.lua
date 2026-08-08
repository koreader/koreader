--[[--
Kazakh ladder stemmer — generates dictionary-form candidates for lookup.

Kazakh is agglutinative: `мектептерімізде` is `мектеп` plus plural, first
person plural possessive, and locative. A reader looking that word up in a
StarDict dictionary finds nothing, because dictionaries are keyed on lemmas.

This module walks the suffix layers backwards and returns **every** analysis
that is morphologically legal — the "ladder" — rather than trying to pick one:

    ladder("мектептерімізде") ->
        мектептерімізде, мектептеріміз, мектептері, мектептер, мектеп

Picking one is what a normal stemmer does, and it is exactly where a stemmer
fails: for `маманда` a scorer strips down to `мама`, past the real root
`маман`. Here the dictionary itself is the filter — every rung is handed to
sdcv and whichever ones exist come back. That also means no lexicon has to be
shipped or loaded.

Provenance and licence
----------------------

This is a port of `kazsearch.ladder` (Python, https://github.com/iDynbek/kazsearch-py),
which is itself derived from the Rust core of pg-kazsearch by darkhanakh
(https://github.com/darkhanakh/pg-kazsearch), licensed LGPL-3.0-or-later.

As a derivative of LGPL-3.0 code it is distributed here under the terms of
KOReader's AGPL-3.0-or-later licence, as permitted by LGPL-3.0 section 2 and
AGPL-3.0 section 13.
--]]

local rules = require("rules")

local Stemmer = {}

local MIN_RUNG_CHARS = 2
local MAX_STEM_CHARS = 64
local MAX_STEPS = 8

--- Vowel classification -----------------------------------------------------
-- Kazakh vowel harmony: a suffix must agree with the class of the stem's last
-- harmony-bearing vowel. Glides (у/и/ю) are transparent and carry no class,
-- which is why loanwords like `туризм` accept suffixes of either class.

local BACK, FRONT, GLIDE, LOAN = {}, {}, {}, {}
local function fill(set, s)
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do set[c] = true end
end
fill(BACK,  "аоұыу")
fill(FRONT, "әеөүіиё")
fill(GLIDE, "уию")
fill(LOAN,  "яэ")

local function is_vowel(c) return BACK[c] or FRONT[c] end
local function is_vocalic(c) return BACK[c] or FRONT[c] or LOAN[c] end

--- UTF-8 handling -----------------------------------------------------------
-- Everything below indexes by CHARACTER, never by byte: Cyrillic is two bytes
-- per character in UTF-8, so byte offsets would put every length check and
-- every suffix boundary in the wrong place.

local function decode(word)
    local chars, offs, i = {}, {}, 1
    for pos, c in word:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
        chars[i] = c
        offs[i] = pos
        i = i + 1
    end
    offs[i] = #word + 1
    return chars, offs, i - 1
end

-- U+0400–U+04FF (Cyrillic) is exactly the two-byte UTF-8 sequences with a lead
-- byte of 0xD0–0xD3.
local function all_cyrillic(chars, n)
    for i = 1, n do
        local c = chars[i]
        if #c ~= 2 then return false end
        local b = c:byte(1)
        if b < 0xD0 or b > 0xD3 then return false end
    end
    return true
end

--- Prefix tables ------------------------------------------------------------
-- Precomputed so each harmony check inside the walk is a lookup rather than a
-- rescan of the prefix.

local function prefix_tables(chars, n)
    local syll, harm_back, tail_back, has_strong = {}, {}, {}, {}
    syll[0], harm_back[0], tail_back[0], has_strong[0] = 0, true, true, false

    local nsyll, wb_back, strong = 0, true, false
    local last1, last2 = nil, nil

    for i = 1, n do
        local c = chars[i]
        if is_vocalic(c) then nsyll = nsyll + 1 end

        if not GLIDE[c] then
            if BACK[c] or c == "я" then
                wb_back, strong = true, true
            elseif FRONT[c] or c == "э" then
                wb_back, strong = false, true
            end
            if is_vocalic(c) then
                last1 = last2
                last2 = c
            end
        end

        local tb
        if last2 == nil then
            tb = true
        elseif LOAN[last2] then
            tb = (last1 ~= nil) and (BACK[last1] or false) or true
        else
            tb = BACK[last2] or false
        end

        syll[i], harm_back[i], tail_back[i], has_strong[i] = nsyll, wb_back, tb, strong
    end
    return syll, harm_back, tail_back, has_strong
end

local function harmony_ok(t, i, harmony)
    if harmony == rules.HARM_ANY then return true end
    if i == 0 then return false end
    -- A harmony-neutral prefix accepts either class; without this no classed
    -- ending could ever attach to a glide-only loanword.
    if not t.has_strong[i] then return true end
    local full_back = t.harm_back[i]
    if harmony == rules.HARM_BACK and full_back then return true end
    if harmony == rules.HARM_FRONT and not full_back then return true end
    if t.syll[i] >= 4 then
        local tb = t.tail_back[i]
        if harmony == rules.HARM_BACK then return tb else return not tb end
    end
    return false
end

--- Per-layer legality guards ------------------------------------------------

local POSS_TAILS = {
    "ымыз", "іміз", "ыңыз", "іңіз", "мыз", "міз", "ңыз", "ңіз",
    "ым", "ім", "ың", "ің", "сы", "сі", "ы", "і",
}

local function ends_with(s, suffix)
    return s:sub(-#suffix) == suffix
end

local function count_syllables(chars, upto)
    local n = 0
    for i = 1, upto do
        if is_vocalic(chars[i]) then n = n + 1 end
    end
    return n
end

local function count_strong_syllables(chars, upto)
    local n = 0
    for i = 1, upto do
        local c = chars[i]
        if is_vocalic(c) and not GLIDE[c] then n = n + 1 end
    end
    return n
end

local function layer_guard(layer_id, sfx, base_str, base_chars, base_len, steps)
    if layer_id == rules.LAYER_CASE then
        if sfx == "н" then
            return ends_with(base_str, "сы") or ends_with(base_str, "сі")
                or ends_with(base_str, "ы") or ends_with(base_str, "і")
        end
        if sfx == "а" or sfx == "е" then
            for _, t in ipairs(POSS_TAILS) do
                if ends_with(base_str, t) then return true end
            end
            local last = base_chars[base_len]
            if last == "м" or last == "ң" then
                if base_len >= 2 then return is_vowel(base_chars[base_len - 1]) end
            end
            return false
        end
        if base_len == 0 then return false end
        local last = base_chars[base_len]
        if sfx == "ны" or sfx == "ні" then
            return is_vocalic(last)
        end
        if sfx == "ын" or sfx == "ін" or sfx == "ды" or sfx == "ді"
            or sfx == "ты" or sfx == "ті" then
            return not is_vocalic(last)
        end

    elseif layer_id == rules.LAYER_POSS then
        if sfx == "м" or sfx == "ң" then
            return base_len > 0 and is_vowel(base_chars[base_len]) or false
        end

    elseif layer_id == rules.LAYER_VTENSE then
        if sfx == "у" then
            return base_len >= 2 and count_syllables(base_chars, base_len) >= 1
        end
        if sfx == "й" then return steps > 0 end
        if sfx == "а" or sfx == "е" then
            return steps > 0 and count_syllables(base_chars, base_len) >= 2
        end

    elseif layer_id == rules.LAYER_VNEG then
        return base_len >= 3

    elseif layer_id == rules.LAYER_VPERSON then
        if sfx == "м" or sfx == "ң" or sfx == "қ" or sfx == "к" then
            return count_syllables(base_chars, base_len) >= 2
        end

    elseif layer_id == rules.LAYER_DERIV then
        if sfx == "лық" or sfx == "лік" or sfx == "дық" or sfx == "дік"
            or sfx == "тық" or sfx == "тік" then
            return count_syllables(base_chars, base_len) >= 2
        end
        -- No lexicon is shipped, so the dictionary-base branch of this guard
        -- (see kazsearch.explore.layer_guard) cannot apply; the syllable test
        -- is the conservative half and is what the Python reference reduces to
        -- when built without a lexicon.
        if sfx == "лы" or sfx == "лі" then
            return count_syllables(base_chars, base_len) >= 2
        end
        if sfx == "ушы" or sfx == "уші" then
            return count_strong_syllables(base_chars, base_len) >= 2
        end
    end
    return true
end

local DERIV_REENTER = {
    ["ндағы"] = true, ["ндегі"] = true, ["дағы"] = true,
    ["дегі"] = true, ["тағы"] = true, ["тегі"] = true,
}

local function next_state_idx(noun_track, cur, layer_id, sfx)
    if not noun_track then
        if layer_id == rules.LAYER_VVOICE then return 4 end
        return cur + 1
    end
    if layer_id == rules.LAYER_DERIV and DERIV_REENTER[sfx] then return 3 end
    if layer_id == rules.LAYER_DERIV then return 5 end
    return cur + 1
end

--- Sound-change repair ------------------------------------------------------
-- Stripping a vowel-initial possessive exposes changes that must be undone
-- before the root looks like its dictionary form: кітабы -> кітаб -> кітап.

local function apply_mutation(s)
    if s == "" then return s end
    if ends_with(s, "б") then return s:sub(1, #s - #"б") .. "п" end
    if ends_with(s, "ғ") then return s:sub(1, #s - #"ғ") .. "қ" end
    if ends_with(s, "г") then
        local base = s:sub(1, #s - #"г")
        local last = base:match("[%z\1-\127\194-\244][\128-\191]*$")
        if last == "о" or last == "ө" or last == "ұ" or last == "ү" or last == "у" then
            return s
        end
        return base .. "к"
    end
    return s
end

local function elision_restore(chars, n, s)
    -- Only н/з-final stems elide, and only after a consonant: орны -> орн -> орын.
    if n < 2 then return nil end
    local last, prev = chars[n], chars[n - 1]
    if last ~= "н" and last ~= "з" then return nil end
    if is_vocalic(prev) and not (ends_with(s, "уз") or ends_with(s, "із")) then
        return nil
    end
    local lv
    for i = n, 1, -1 do
        if is_vowel(chars[i]) then lv = chars[i] break end
    end
    if lv == nil then return nil end
    local ins = BACK[lv] and "ы" or "і"
    return s:sub(1, #s - #last) .. ins .. last
end

--- The walk -----------------------------------------------------------------

--- Every morphologically legal analysis of `word`, longest first.
-- @string word a single lowercase Kazakh word
-- @treturn {string,...} candidate dictionary forms, including `word` itself
function Stemmer.ladder(word)
    if word == nil or word == "" then return {} end

    local chars, offs, n = decode(word)
    -- Nothing to add: KOReader already looks the original word up, so a word
    -- too short to have any rung contributes no candidates. Returning the word
    -- here instead would just duplicate the lookup it already performs.
    if n < MIN_RUNG_CHARS then return {} end
    -- A token with a digit, hyphen or apostrophe in it is not a Kazakh word,
    -- and stripping what looks like a suffix off one invents forms: `аб'ба`
    -- would yield `аб'`. The reference implementation refuses these outright,
    -- so this does too.
    if not all_cyrillic(chars, n) then return { word } end
    if n >= MAX_STEM_CHARS then return { word } end

    local syll, harm_back, tail_back, has_strong = prefix_tables(chars, n)
    local t = { syll = syll, harm_back = harm_back,
                tail_back = tail_back, has_strong = has_strong }

    local function prefix(i) return word:sub(1, offs[i + 1] - 1) end

    local found, nchars_of, order = {}, {}, {}
    local function record(form, steps)
        if form == nil or #form == 0 then return end
        local _, nchars = form:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
        if nchars < MIN_RUNG_CHARS then return end
        if found[form] == nil then
            found[form] = steps
            nchars_of[form] = nchars
            order[#order + 1] = form
        elseif steps < found[form] then
            found[form] = steps
        end
    end

    local tracks = { { rules.NOUN_LAYERS, true }, { rules.VERB_LAYERS, false } }
    for _, track in ipairs(tracks) do
        local layers, noun_track = track[1], track[2]
        local nlayer = #layers

        local queue = { { n, 1, 0, nil, 0 } }  -- len, layer, steps, last_sfx, nominal
        local head = 1
        local seen = { [n .. ":1:0"] = true }

        while head <= #queue do
            local st = queue[head]; head = head + 1
            local len, li, steps, last_sfx, nominal = st[1], st[2], st[3], st[4], st[5]

            local form = prefix(len)
            record(form, steps)
            -- A rung reached by stripping a possessive may need its sound
            -- change undone before it matches a dictionary headword.
            if steps > 0 and nominal > 0 and last_sfx and rules.POSS_VOWEL[last_sfx] then
                local m = apply_mutation(form)
                local mc, _, mn = decode(m)
                record(elision_restore(mc, mn, m) or m, steps)
            end

            if li <= nlayer and steps < MAX_STEPS then
                -- Option 1: skip this layer.
                local k = len .. ":" .. (li + 1) .. ":" .. steps
                if not seen[k] then
                    seen[k] = true
                    queue[#queue + 1] = { len, li + 1, steps, last_sfx, nominal }
                end

                -- Option 2: strip a suffix that matches here.
                local layer = layers[li]
                local cur = prefix(len)
                for _, r in ipairs(layer.rules) do
                    if r.n < len and ends_with(cur, r.s) then
                        local base_len = len - r.n
                        if base_len >= 2 and syll[base_len] >= 1
                            and harmony_ok(t, base_len, r.h)
                            and layer_guard(layer.id, r.s, prefix(base_len),
                                            chars, base_len, steps) then
                            local ni = next_state_idx(noun_track, li, layer.id, r.s)
                            local nnom = nominal
                            if layer.kind == rules.KIND_NOMINAL then nnom = nnom + 1 end
                            local k2 = base_len .. ":" .. ni .. ":" .. (steps + 1)
                            if not seen[k2] then
                                seen[k2] = true
                                queue[#queue + 1] = { base_len, ni, steps + 1, r.s, nnom }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Longest first, then shallowest. Sorting on #a would compare BYTES, which
    -- diverges from the reference as soon as a token mixes scripts.
    table.sort(order, function(a, b)
        if nchars_of[a] ~= nchars_of[b] then return nchars_of[a] > nchars_of[b] end
        if found[a] ~= found[b] then return found[a] < found[b] end
        return a < b
    end)
    return order
end

return Stemmer
