---------------------------------
-- RIME-style Cangjie IME with phrase-level continuous input (連打組詞)
---------------------------------
-- Features:
-- 1. Shows typed cangjie radicals after cursor + predicted phrase
-- 2. No auto-commit; Space runs max-matching and commits the full phrase
-- 3. Candidates for the first segment shown in hint: [明天 口卜·1明2冐]
-- 4. Number keys 1-9 confirm the first segment, retain remaining buffer
-- 5. Segmentation is lazy-cached: computed once per unique buffer content
---------------------------------
local util   = require("util")

-- Maps each Cangjie key letter to its display radical
local RADICAL_MAP = {
    A="日", B="月", C="金", D="木", E="水", F="火", G="土",
    H="竹", I="戈", J="十", K="大", L="中", M="一", N="弓",
    O="人", P="心", Q="手", R="口", S="尸", T="廿", U="山",
    V="女", W="田", X="難", Y="卜", Z="重",
}

local MAX_CODE_LEN = 5   -- maximum number of radicals in one cangjie code

local CangjieIME = {
    -- config (set by caller)
    code_map        = nil,  -- cangjie dictionary {CODE -> string|table}
    key_map         = nil,  -- maps keyboard char to cangjie letter
    show_candidates = true,
    max_candidates  = 9,
    -- mutable input state
    buf             = "",   -- raw keystroke buffer  (e.g. "RIYUYIDA")
    segments        = nil,  -- cached segmentation result; nil = stale
    --   segments is a list of {code=str, cands=table, chosen=int}
    hint_char_count = 0,    -- Unicode char-count of hint currently in inputbox
}

-- ── Construction ────────────────────────────────────────────────────────────

function CangjieIME:new(config)
    local o = config or {}
    setmetatable(o, self)
    self.__index = self
    o:clear()
    return o
end

-- ── State management ────────────────────────────────────────────────────────

function CangjieIME:clear()
    self.buf             = ""
    self.segments        = nil
    self.hint_char_count = 0
end

function CangjieIME:clear_stack()   -- backward-compat alias
    self:clear()
end

-- ── Dictionary helpers ──────────────────────────────────────────────────────

-- Return the candidate list for a raw code string (uppercase ASCII).
function CangjieIME:get_candidates(code)
    if not self.code_map or code == "" then return {} end
    local v = self.code_map[code]
    if type(v) == "string" then return {v} end
    return v or {}
end

-- Convert an uppercase ASCII code to radical glyphs ("AB" -> "日月").
function CangjieIME:code_to_radicals(code)
    local t = {}
    for i = 1, #code do
        t[i] = RADICAL_MAP[code:sub(i,i)] or code:sub(i,i)
    end
    return table.concat(t)
end

-- ── Maximum-matching segmentation ───────────────────────────────────────────

-- Split buf into segments using forward maximum matching.
-- Each segment: {code=str, cands=table, chosen=int (1-based)}
-- Segments with no dictionary match have cands={} and chosen=1.
-- Only called via ensure_segments(); never called on every keystroke.
function CangjieIME:do_segment(buf)
    local result = {}
    local pos    = 1
    local len    = #buf
    while pos <= len do
        local matched_code  = nil
        local matched_cands = nil
        -- Try longest match first (MAX_CODE_LEN down to 1)
        for seg_len = math.min(MAX_CODE_LEN, len - pos + 1), 1, -1 do
            local code  = buf:sub(pos, pos + seg_len - 1)
            local cands = self:get_candidates(code)
            if #cands > 0 then
                matched_code  = code
                matched_cands = cands
                break
            end
        end
        if matched_code then
            table.insert(result, {
                code   = matched_code,
                cands  = matched_cands,
                chosen = 1,
            })
            pos = pos + #matched_code
        else
            -- Unmatched single key: include with empty cands so display is intact
            table.insert(result, {
                code   = buf:sub(pos, pos),
                cands  = {},
                chosen = 1,
            })
            pos = pos + 1
        end
    end
    return result
end

-- Ensure self.segments is valid for the current self.buf.
-- Segmentation only runs when segments==nil (i.e. buf just changed).
function CangjieIME:ensure_segments()
    if self.buf == "" then
        self.segments = {}
        return
    end
    if self.segments == nil then
        self.segments = self:do_segment(self.buf)
    end
end

-- ── Hint display ────────────────────────────────────────────────────────────

-- Build the preedit hint string.
--
-- Single segment  :  [口卜·1明2冐3暌…]
-- Multiple segments: [明天 口卜·1明2冐]
--                     ^predicted phrase  ^first-segment detail
--
-- Also sets self.hint_char_count to the exact Unicode char count
-- so that refresh_hint can delete exactly the right number of chars.
function CangjieIME:build_hint()
    if self.buf == "" then
        self.hint_char_count = 0
        return ""
    end

    self:ensure_segments()

    local segs  = self.segments
    local parts = {}
    local n     = 0  -- Unicode char count

    local function push(s)
        parts[#parts+1] = s
        n = n + #util.splitToChars(s)
    end

    push("[")

    -- ── Predicted-phrase prefix (only when ≥2 segments) ──
    if #segs > 1 then
        for _, seg in ipairs(segs) do
            local ch = (seg.cands[seg.chosen] or "?")
            push(ch)
        end
        push(" ")   -- space separating phrase from first-segment detail
    end

    -- ── First-segment radicals ──
    local first = segs[1] or {code="", cands={}, chosen=1}
    push(self:code_to_radicals(first.code))

    -- ── First-segment candidates ──
    if self.show_candidates and #first.cands > 0 then
        push("\xc2\xb7")   -- U+00B7 · (middle dot)
        local limit = math.min(#first.cands, self.max_candidates)
        for i = 1, limit do
            push(tostring(i))
            push(first.cands[i])
        end
        if #first.cands > self.max_candidates then
            push("\xe2\x80\xa6")  -- U+2026 …
        end
    end

    push("]")

    self.hint_char_count = n
    return table.concat(parts)
end

-- Delete the old hint from the inputbox, build and insert the new one.
function CangjieIME:refresh_hint(inputbox)
    for _ = 1, self.hint_char_count do
        inputbox.delChar:raw_method_call()
    end
    local hint = self:build_hint()
    if hint ~= "" then
        inputbox.addChars:raw_method_call(hint)
    end
end

-- ── Commit helpers ──────────────────────────────────────────────────────────

-- Remove hint from inputbox and clear all IME state.
function CangjieIME:separate(inputbox)
    for _ = 1, self.hint_char_count do
        inputbox.delChar:raw_method_call()
    end
    self:clear()
end

-- Assemble and commit the complete phrase produced by segmentation.
-- Called by the space handler.
function CangjieIME:commit_all(inputbox)
    self:ensure_segments()
    local assembled = {}
    for _, seg in ipairs(self.segments) do
        if #seg.cands > 0 then
            table.insert(assembled, seg.cands[seg.chosen])
        end
        -- Unmatched segments are silently dropped
    end
    local phrase = table.concat(assembled)
    -- Remove hint
    for _ = 1, self.hint_char_count do
        inputbox.delChar:raw_method_call()
    end
    self:clear()
    if phrase ~= "" then
        inputbox.addChars:raw_method_call(phrase)
    end
end

-- Confirm candidate idx for the FIRST segment only, then retain the rest
-- of the buffer so the user can continue correcting or commit later.
function CangjieIME:commit_first_segment(inputbox, idx)
    self:ensure_segments()
    local first = self.segments and self.segments[1]
    if not first or #first.cands == 0 then return false end
    idx = idx or first.chosen
    local ch = first.cands[idx]
    if not ch then return false end

    local remaining = self.buf:sub(#first.code + 1)

    -- Remove hint
    for _ = 1, self.hint_char_count do
        inputbox.delChar:raw_method_call()
    end
    self:clear()

    -- Commit the chosen character
    inputbox.addChars:raw_method_call(ch)

    -- Restart with the remaining buffer (if any)
    if remaining ~= "" then
        self.buf      = remaining
        self.segments = nil     -- will be recomputed by next build_hint
        self:refresh_hint(inputbox)
    end
    return true
end

-- ── Main input handlers (called from cj_keyboard.lua) ───────────────────────

function CangjieIME:handle_input(inputbox, char)

    -- ── Number key 1-9: confirm first segment with that candidate ────────
    if self.buf ~= "" and char >= "1" and char <= "9" then
        local idx = tonumber(char)
        if not self:commit_first_segment(inputbox, idx) then
            -- No matching candidate: discard preedit, insert digit literally
            self:separate(inputbox)
            inputbox.addChars:raw_method_call(char)
        end
        return true
    end

    -- ── Space: run max-matching and commit the whole phrase ──────────────
    if char == " " then
        if self.buf ~= "" then
            self:commit_all(inputbox)
        else
            inputbox.addChars:raw_method_call(" ")
        end
        return true
    end

    -- ── Cangjie radical key: append to buffer ────────────────────────────
    local key = self.key_map and self.key_map[char]
    if key then
        self.buf      = self.buf .. key
        self.segments = nil   -- invalidate cache (recomputed in build_hint)
        self:refresh_hint(inputbox)
        return true
    end

    -- ── Any other key: flush preedit then pass char through ──────────────
    if self.buf ~= "" then
        self:commit_all(inputbox)
    end
    inputbox.addChars:raw_method_call(char)
    return true
end

function CangjieIME:handle_del(inputbox)
    if self.buf == "" then
        inputbox.delChar:raw_method_call()
        return
    end
    self.buf      = self.buf:sub(1, -2)
    self.segments = nil
    self:refresh_hint(inputbox)
end

-- Arrow keys cycle candidates of the FIRST segment
function CangjieIME:handle_next_cand(inputbox)
    self:ensure_segments()
    local first = self.segments and self.segments[1]
    if first and #first.cands > 1 then
        first.chosen = (first.chosen % #first.cands) + 1
        -- Rebuild hint (segments already valid; just re-render)
        for _ = 1, self.hint_char_count do
            inputbox.delChar:raw_method_call()
        end
        local hint = self:build_hint()
        if hint ~= "" then
            inputbox.addChars:raw_method_call(hint)
        end
    end
end

function CangjieIME:handle_prev_cand(inputbox)
    self:ensure_segments()
    local first = self.segments and self.segments[1]
    if first and #first.cands > 1 then
        first.chosen = first.chosen - 1
        if first.chosen < 1 then first.chosen = #first.cands end
        for _ = 1, self.hint_char_count do
            inputbox.delChar:raw_method_call()
        end
        local hint = self:build_hint()
        if hint ~= "" then
            inputbox.addChars:raw_method_call(hint)
        end
    end
end

function CangjieIME:has_candidates()
    self:ensure_segments()
    local first = self.segments and self.segments[1]
    return first ~= nil and #first.cands > 0
end

return CangjieIME
