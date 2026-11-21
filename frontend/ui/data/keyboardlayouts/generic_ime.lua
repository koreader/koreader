---------------------------------
-- Generic input method engine --
---------------------------------
local logger = require("logger")
local util = require("util")
local Utf8Proc = require("ffi/utf8proc")

-- Numbered candidate window: when an IME sets candidate_pages, the composing
-- text shows the upcoming candidates with digit prefixes, the digit keys
-- (1-9) select a candidate directly, and the switch keys page through the
-- candidate list. The page size also adapts to the input box width so that
-- wide (multi-character) candidates never push the start of the line out
-- of view.
local PAGE = 9

-- Display width of a string in CJK-char units (CJK=1, ASCII=0.5)
local function textUnits(s)
    local w = 0
    for _, ch in ipairs(util.splitToChars(s)) do
        w = w + (ch:byte(1) >= 0xE0 and 1 or 0.5)
    end
    return w
end

-- How many candidates fit in one page (incl. the stage char) given the input
-- field width; falls back to candidate_pages when geometry is unknown.
local function visiblePageSize(imex, inputbox)
    local face_size = inputbox and inputbox.face and inputbox.face.size
    local box_w = inputbox and inputbox.width
    if not face_size or not box_w or box_w <= 0 then return PAGE end
    local pad = (inputbox.margin or 0) + (inputbox.bordersize or 0) + (inputbox.padding or 0)
    local avail = math.max(0, box_w - 2 * pad) / face_size - 2 -- cursor + rounding safety
    local units = textUnits(imex.char or "") + 1 -- stage chars + "[" "]"
    local last = math.min(imex.index + PAGE - 1, #imex.candi)
    local n = 0
    for i = imex.index + 1, last do
        local cand_units = 0.5 + textUnits(imex.candi[i])
        local truncated = i < last or last < #imex.candi
        local need = cand_units + (truncated and 0.5 or 0) -- room for the trailing "…"
        if units + need <= avail then
            units = units + cand_units
            n = n + 1
        else
            break
        end
    end
    return n + 1 -- the stage char counts as the first candidate of the page
end

-- Fuzzy pinyin: when the IME provides fuzzy_rules, candidates of codes that
-- differ by the rule pairs are merged after the exact hits, so e.g. typing
-- "zichi" still offers the candidates of "zhichi".
local FUZZY_MAX_VARIANTS = 16
local function fuzzy_variants(code, rules)
    local variants = {}
    local seen = { [code] = true }
    local queue = { code }
    while #queue > 0 and #variants < FUZZY_MAX_VARIANTS do
        local s = table.remove(queue)
        for _, rule in ipairs(rules) do
            for _, pair in ipairs({ { rule[1], rule[2] }, { rule[2], rule[1] } }) do
                local from, to = pair[1], pair[2]
                local pos = 1
                while true do
                    local start = s:find(from, pos, true)
                    if not start then break end
                    local v = s:sub(1, start-1) .. to .. s:sub(start + #from)
                    if not seen[v] then
                        seen[v] = true
                        variants[#variants+1] = v
                        if #variants >= FUZZY_MAX_VARIANTS then return variants end
                        queue[#queue+1] = v
                    end
                    pos = start + 1
                end
            end
        end
    end
    return variants
end

local function binarysearch( tbl, value, fcompval, reversed )
    if not fcompval then return end
    local iStart,iEnd = 1,#tbl
    local iMid
    while iStart <= iEnd do
        iMid = math.floor( (iStart+iEnd)/2 )
        local value2 = fcompval( tbl[iMid] )
        if value == value2 then
            if iMid == 1 or fcompval( tbl[iMid-1] ) ~= value then
                return iMid
            end
            iEnd = iMid - 1
            while iStart <= iEnd do
                iMid = math.floor( (iStart+iEnd)/2 )
                value2 = fcompval( tbl[iMid] )
                if value2 == value then
                    if fcompval( tbl[iMid-1] ) ~= value then
                        return iMid
                    else
                        iEnd = iMid - 1
                    end
                else
                    if fcompval( tbl[iMid+1] ) == value then
                        return iMid + 1
                    else
                        iStart = iMid + 2
                    end
                end
            end
            return iMid
        elseif ( reversed and value2 < value ) or ( not reversed and value2 > value ) then
            iEnd = iMid - 1
        else
            iStart = iMid + 1
        end
    end
end

local function stringReplaceAt(str, pos, r)
    return str:sub(1, pos-1) .. r .. str:sub(pos+1)
end

local _stack
local IME = {
    code_map = nil, -- hash, mandatory
    key_map = nil, -- input key to code map
    keys_string = "abcdefghijklmnopqrstuvwxyz",
    iter_map = nil, -- next code when using wildcard
    iter_map_last_key = nil,
    show_candi_callback = function() end,
    switch_char = "SWITCH",
    separator = "SEPARATOR",
    partial_separators = { " " }, -- when in state act as separator, otherwise input itself
    auto_separate_callback = function() return false end,
    local_del = "",  -- default
    has_case = false,
    exact_match = false,
    candidate_pages = nil, -- when set: numbered candidate window w/ digit selection & paging
    fuzzy_rules = nil, -- when set with fuzzy_enabled_callback: merge candidates of fuzzy variants
    fuzzy_enabled_callback = function() return false end,
    W = nil -- default no wildcard
}

function IME:new(new_o)
    local o = new_o or {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    return o
end

function IME:init()
    self:clear_stack()

    self.sorted_codes = {}
    for k,_ in pairs(self.code_map) do
        table.insert(self.sorted_codes, k)
    end
    table.sort(self.sorted_codes)

    if not self.key_map and self.keys_string then
        self.key_map = {}
        for i=0, #self.keys_string do
            self.key_map[self.keys_string:sub(i, i)] = self.keys_string:sub(i, i)
        end
    end

    if not self.iter_map and self.W then
        self.iter_map = {}
        local keys = util.splitToChars(self.keys_string)
        for i=1, #keys-1 do
            self.iter_map[keys[i]] = keys[i+1]
        end
        if #keys > 1 then
            self.iter_map[keys[#keys]] = keys[1]
        end
    end
end

function IME:clear_stack()
    _stack = { {code="", char="", index=1, candi={} } }
    self.last_key = ""
    self.last_index = 0
    self.hint_char_count = 0
    self.on_stage_char_count = 0
end

function IME:reset_status()
    self.last_key = ""
    self.last_index = 0
end

function IME:uniqueMap(code)
    -- Here we find out if given code has only one candidate and no other code
    -- starts with the given one, so that auto separation can take place.
    if not code then return true end
    if self.W and code:find(self.W) then
        return false -- with wildcard, we just return false even if its unique
    else
        if type(self.code_map[code]) == "table" then
            return false
        end
        local idx = binarysearch(self.sorted_codes, code, function(v) return v end)
        if idx == #self.sorted_codes then
            return true
        elseif not idx then
            idx = binarysearch(self.sorted_codes, code, function(v) return string.sub(v or "", 1, #code) end )
            if not idx or idx == #self.sorted_codes then
                return true
            end
        end
        local next_code = self.sorted_codes[idx+1]
        local unique = next_code:sub(1, #code) ~= code
        return unique
    end
end

function IME:searchStartWith(code)
    if self.exact_match then return end
    local result = binarysearch(self.sorted_codes, code, function(v) return string.sub(v or "", 1, #code) end)
    if result then
        local candi = self.code_map[self.sorted_codes[result]]
        if candi then
            logger.dbg("zh_kbd: got search result starting with", code, ":", candi)
        end
        if type(candi) == "string" then
            return { candi }
        end
        return candi
    end
end

function IME:getCandiFromMap(code)
    local candi = self.code_map[code]
    if candi then
        logger.dbg("zh_kbd: got candi from map with", code, ":", candi)
    end
    if type(candi) == "string" then
        return { candi }
    end
    return candi
end

function IME:getCandi(code)
    return self:getCandiFromMap(code) or self:searchStartWith(code) or {}
end

function IME:getCandiWithWildcard(code, from_reset)
    logger.dbg("zh_kdb: getCandiWithWildcard:", code, "lastKey:", self.last_key)
    for i=#code, 1, -1 do
        if code:sub(i, i) == self.W then
            if self.last_key:sub(i, i) == self.iter_map_last_key then
                local next = self.iter_map[self.iter_map_last_key]
                self.last_key = stringReplaceAt(self.last_key, i, next)
            else
                self.last_key = stringReplaceAt(self.last_key, i, self.iter_map[self.last_key:sub(i, i)])
                self.last_candi = self:getCandi(self.last_key)
                if #self.last_candi > 0 then
                    logger.dbg("zh_kbd: got candi with wildchard for key", self.last_key, ":", self.last_candi)
                    return self.last_candi
                end
                return self:getCandiWithWildcard(code, from_reset)
            end
        end
    end
    -- all wildcard reset
    self.last_candi = self:getCandi(self.last_key)
    if #self.last_candi > 0 then
        logger.dbg("zh_kbd: got candi with wildchard for key", self.last_key, ":", self.last_candi)
        return self.last_candi
    elseif not from_reset then
        return self:getCandiWithWildcard(code, true)
    end
end

function IME:getCandidates(code)
    logger.dbg("zh_kbd: getCandidates", code)
    if self.W then
        local wildcard_count = select(2, string.gsub(code, self.W, ""))
        if wildcard_count > 5 then
            -- we limit the wildcard count to 5 due to performance conserns
            return
        elseif wildcard_count ~= 0 then
            if #code == #self.last_key then -- only index change, no new stroke
                local last_candi = _stack[#_stack].candi
                return self:getCandiWithWildcard(code), last_candi
            else
                self:reset_status()
                self.last_key = code:gsub(self.W, self.iter_map_last_key)
                return self:getCandiWithWildcard(code)
            end
        end
    end
    -- no wildcard
    if self.candidate_pages and self.fuzzy_enabled_callback() then
        local merged = self:getMergedCandidates(code)
        if #merged > 0 then return merged end
        return
    end
    return self:getCandiFromMap(code) or self:searchStartWith(code)
end

-- Merge candidates of the typed code and its fuzzy variants: exact hits first,
-- then prefix matches; the originally typed code always ranks first.
function IME:getMergedCandidates(code)
    local merged, seen = {}, {}
    local function addCandi(candi)
        if type(candi) == "string" then candi = { candi } end
        if candi then
            for _, v in ipairs(candi) do
                if not seen[v] then
                    seen[v] = true
                    merged[#merged+1] = v
                end
            end
        end
    end
    addCandi(self:getCandiFromMap(code))
    local variants = fuzzy_variants(code, self.fuzzy_rules or {})
    for _, v in ipairs(variants) do
        addCandi(self:getCandiFromMap(v))
    end
    if #merged > 0 then return merged end
    addCandi(self:searchStartWith(code))
    for _, v in ipairs(variants) do
        addCandi(self:searchStartWith(v))
    end
    return merged
end


--- inputbox operation
function IME:delHintChars(inputbox)
    logger.dbg("zh_kbd: delete hint chars of count", self.hint_char_count)
    for i=1, self.hint_char_count do
        inputbox.delChar:raw_method_call()
    end
end

function IME:delOnStageAndHintChars(inputbox)
    self:delHintChars(inputbox)
    for i=1, self.on_stage_char_count do
        inputbox.delChar:raw_method_call()
    end
end

function IME:getHintChars(inputbox)
    self.hint_char_count = 0
    self.on_stage_char_count = 0
    local hint_chars = ""
    for i=1, #_stack do
        hint_chars = hint_chars .. _stack[i].char
        if _stack[i].char ~= "" then
            self.on_stage_char_count = self.on_stage_char_count + #util.splitToChars(_stack[i].char)
        end
    end
    local imex = _stack[#_stack]
    local has_wildcard = self.W and imex.code:find(self.W)
    if self.candidate_pages then
        local page_size = visiblePageSize(imex, inputbox)
        -- Numbered candidate window, page starts at imex.index. The stage char
        -- (candi[index], what space commits) stays outside the brackets; the
        -- brackets show the rest of the page with digit prefixes 2..S.
        if self:show_candi_callback() and #imex.candi > 1 and #imex.code > 0 and page_size >= 2 then
            hint_chars = hint_chars .. "["
            local last = math.min(imex.index + page_size - 1, #imex.candi)
            for i = imex.index + 1, last do
                hint_chars = hint_chars .. (i - imex.index + 1) .. imex.candi[i]
                self.hint_char_count = self.hint_char_count + 1 + #util.splitToChars(imex.candi[i])
            end
            if last < #imex.candi then
                hint_chars = hint_chars .. "…"
                self.hint_char_count = self.hint_char_count + 1
            end
            hint_chars = hint_chars .. "]"
            self.hint_char_count = self.hint_char_count + 2
        end
        logger.dbg("zh_kbd: got hint chars:", hint_chars, "with count", self.hint_char_count)
        return hint_chars
    end
    if self:show_candi_callback() and -- shows candidates
        #imex.candi ~= 0 and -- has candidates
        ( #imex.code > 1 or imex.index > 1 ) and -- more than one key
        ( #imex.candi > 1 or has_wildcard and imex.candi[1] ~= (imex.last_candi or {})[1] ) then -- one candidate but use wildcard, or more candidates
        hint_chars = hint_chars .. "["
        if #imex.candi > 1 then
            local remainder
            if not has_wildcard then
                remainder = (imex.index+1) % #imex.candi
            else
                remainder = (imex.index-self.last_index+1) % #imex.candi
            end
            local pos = remainder == 0 and #imex.candi or remainder
            if not (has_wildcard and pos == 1) then
                for i=1, math.min(#imex.candi-1, 5) do
                    hint_chars = hint_chars .. imex.candi[pos]
                    self.hint_char_count = self.hint_char_count + #util.splitToChars(imex.candi[pos])
                    pos = pos == #imex.candi and 1 or pos+1
                    if has_wildcard and pos == 1 then
                        break
                    end
                end
            end
        end
        if #imex.candi > 6 or has_wildcard then
            hint_chars = hint_chars .. "…"
            self.hint_char_count = self.hint_char_count + 1
        end
        hint_chars = hint_chars .. "]"
        self.hint_char_count = self.hint_char_count + 2
    end
    logger.dbg("zh_kbd: got hint chars:", hint_chars, "with count", self.hint_char_count)
    return hint_chars
end

function IME:refreshHintChars(inpuxbox)
    self:delOnStageAndHintChars(inpuxbox)
    inpuxbox.addChars:raw_method_call(self:getHintChars(inpuxbox))
end

function IME:separate(inputbox)
    if self.hint_char_count then
        self:delHintChars(inputbox)
    end
    self:clear_stack()
end

function IME:tweak_case(new_candi, old_imex, new_stroke_upper)
    if self.has_case then
        local old_chars = util.splitToChars(old_imex.char)
        logger.dbg("zh_ime: tweak_case old chars", old_chars, "new_candi", new_candi)
        for i=1, #new_candi do
            local new_chars = util.splitToChars(new_candi[i])
            for j=1, math.max(#new_chars, #old_chars) do
                local old_char = old_chars[j]
                local new_char = new_chars[j]
                if new_char ~= old_char then
                    if not old_char and new_stroke_upper then
                        -- tweak new_char
                        new_chars[j] = Utf8Proc.uppercase_dumb(new_char)
                    elseif old_char and new_char and old_char == Utf8Proc.uppercase_dumb(old_char) then
                        -- tweak new_char when corresponding old char is uppercase
                        new_chars[j] = Utf8Proc.uppercase_dumb(new_char)
                    end
                end
            end
            new_candi[i] = table.concat(new_chars)
        end
    end
end

function IME:hasCandidates()
    return #(_stack[#_stack].candi) > 0
end

function IME:wrappedDelChar(inputbox)
    local imex = _stack[#_stack]
    -- stepped deletion
    if #imex.code > 1 then
        -- last char has over one input strokes
        imex.code = string.sub(imex.code, 1, -2)
        imex.index = 1
        local new_candi, last_candi = self:getCandidates(imex.code)
        self:tweak_case(new_candi, imex)
        imex.candi, imex.last_candi = new_candi, last_candi
        imex.char = imex.candi[1]
        self:refreshHintChars(inputbox)
    elseif #_stack > 1 then
        -- over one chars, last char has only one stroke
        _stack[#_stack] = nil
        self:refreshHintChars(inputbox)
    elseif #imex.code == 1 then
        -- one char with one stroke
        self:delOnStageAndHintChars(inputbox)
        self:clear_stack()
    else
        inputbox.delChar:raw_method_call()
    end
end

function IME:wrappedAddChars(inputbox, char, orig_char)
    local imex = _stack[#_stack]
    if char == self.switch_char then
        if self.candidate_pages then
            -- page forward by the visible page size, wraps back to the first page
            local page_size = visiblePageSize(imex, inputbox)
            if #imex.candi > 1 and page_size >= 2 then
                imex.index = imex.index + page_size
                if imex.index > #imex.candi then imex.index = 1 end
                imex.char = imex.candi[imex.index]
                self:refreshHintChars(inputbox)
            end
            return
        end
        imex.index = imex.index + 1
        if self.W and imex.code:find(self.W) then
            if #imex.candi == 0 then
                return
            elseif imex.index - self.last_index > #imex.candi then
                self.last_index = self.last_index + #imex.candi
                imex.candi,imex.last_candi = self:getCandidates(imex.code)
                imex.char = imex.candi[1]
            else
                imex.char = imex.candi[imex.index - self.last_index]
            end
        elseif #imex.candi > 1 then
            local remainder = imex.index % #imex.candi
            imex.char = imex.candi[remainder==0 and #imex.candi or remainder]
        else
            return
        end
        self:refreshHintChars(inputbox)
    elseif char == self.switch_char_prev then
        if self.candidate_pages then
            -- page backward, first page wraps to the last page start
            local page_size = visiblePageSize(imex, inputbox)
            if #imex.candi > 1 and page_size >= 2 then
                if imex.index == 1 then
                    imex.index = #imex.candi - ((#imex.candi - 1) % page_size)
                else
                    imex.index = math.max(imex.index - page_size, 1)
                end
                imex.char = imex.candi[imex.index]
                self:refreshHintChars(inputbox)
            end
            return
        end
        if self.W and imex.code:find(self.W) then
            if #imex.candi == 0 then
                return
            elseif imex.index <= self.last_index + 1 then
                return
            else
                imex.index = imex.index - 1
                imex.char = imex.candi[imex.index - self.last_index]
            end
        elseif #imex.candi > 1 then
            imex.index = math.max(imex.index-1, 1)
            local remainder = imex.index % #imex.candi
            imex.char = imex.candi[remainder==0 and #imex.candi or remainder]
        else
            return
        end
        self:refreshHintChars(inputbox)
    elseif char == self.separator or
        _stack[1].code ~= "" and self.partial_separators and util.arrayContains(self.partial_separators, char) then
            self:separate(inputbox)
            return
    elseif char == self.local_del then
        if #imex.code > 0 then
            imex.candi = {}
            imex.char = ""
            local previous_imex = _stack[#_stack-1]
            if previous_imex then
                previous_imex.candi = {}
                previous_imex.char = ""
            end
            self:refreshHintChars(inputbox)
            self:clear_stack()
        else
            inputbox.delChar:raw_method_call()
        end
    elseif self.candidate_pages and #char == 1 and char >= "1" and char <= "9" and #imex.code > 0 then
        -- digit key selects the n-th candidate on the current page; digits beyond
        -- the visible page size commit literally (never a hidden candidate)
        local nd = tonumber(char)
        local page_size = visiblePageSize(imex, inputbox)
        local target = imex.index + nd - 1
        if nd <= page_size and imex.candi[target] then
            imex.char = imex.candi[target]
            self:refreshHintChars(inputbox)
            self:separate(inputbox)
        else
            -- literal digit, composition flushed (same path as stock for unmapped chars)
            self:separate(inputbox)
            inputbox.addChars:raw_method_call(char)
        end
    else
        local key = self.key_map[char]
        if key then
            imex.index = 1
            self:reset_status()
            local new_candi
            new_candi,imex.last_candi = self:getCandidates(imex.code..key)
            if new_candi and #new_candi > 0 then
                imex.code = imex.code .. key

                self:tweak_case(new_candi, imex, orig_char and orig_char ~= char)

                imex.char = new_candi[1]
                imex.candi = new_candi
                self:refreshHintChars(inputbox)
                if self.auto_separate_callback() and self:uniqueMap(imex.code) then
                    self:separate(inputbox)
                end
            else
                if self.auto_separate_callback() then -- flush current stack
                    self:separate(inputbox)
                end
                new_candi,imex.last_candi = self:getCandidates(key) or {orig_char or char},nil -- single stroke

                self:tweak_case(new_candi, {}, orig_char and orig_char ~= char)

                if self.auto_separate_callback() then
                    _stack[1] = { code=key, index=1, char=new_candi[1] or "", candi=new_candi }
                else
                    table.insert(_stack, {code=key, index=1, char=new_candi[1] or "", candi=new_candi} )
                end
                self:refreshHintChars(inputbox)
            end
        else
            self:separate(inputbox)
            inputbox.addChars:raw_method_call(orig_char or char)
        end
    end
end

return IME
