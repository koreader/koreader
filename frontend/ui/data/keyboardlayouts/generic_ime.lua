---------------------------------
-- Generic input method engine --
---------------------------------
local logger = require("logger")
local util = require("util")
local Utf8Proc = require("ffi/utf8proc")

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
    return self:getCandiFromMap(code) or self:searchStartWith(code)
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

function IME:getHintChars()
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
    inpuxbox.addChars:raw_method_call(self:getHintChars())
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
