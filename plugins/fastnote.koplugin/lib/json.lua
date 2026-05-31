--[[--
lib/json.lua — minimal JSON encoder/decoder for fastnote stroke data.

Pure Lua; no KOReader or FFI dependencies — fully busted-testable.

Only the subset needed by lib/svg.lua is implemented:
  Encode: strings, numbers, booleans, arrays, objects, null (nil).
  Decode: same types; all standard JSON accepted.

Keys in encoded objects are sorted for deterministic output (useful in tests).
--]]--

local M = {}

-- ---------------------------------------------------------------------------
-- Encoder
-- ---------------------------------------------------------------------------

local function _escape_string(s)
    return s
        :gsub('\\', '\\\\')
        :gsub('"',  '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
        :gsub('\t', '\\t')
end

local function _encode(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "number" then
        if val ~= val then return "null" end          -- NaN → null
        if val == math.huge or val == -math.huge then return "null" end
        -- Use integer form when there's no fractional part, full precision otherwise
        if math.floor(val) == val and math.abs(val) < 1e15 then
            return string.format("%d", val)
        end
        return string.format("%.14g", val)
    elseif t == "string" then
        return '"' .. _escape_string(val) .. '"'
    elseif t == "table" then
        -- Array: consecutive integer keys starting at 1 with no gaps
        local n = #val
        local is_array = (n > 0)
        if is_array then
            for k in pairs(val) do
                if type(k) ~= "number" or k < 1 or k > n or math.floor(k) ~= k then
                    is_array = false
                    break
                end
            end
        else
            -- Empty table: check for any non-integer key to decide
            for k in pairs(val) do
                if type(k) ~= "number" then
                    is_array = false
                    break
                end
            end
        end
        if is_array then
            local parts = {}
            for i = 1, n do parts[i] = _encode(val[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            local parts = {}
            for k, v in pairs(val) do
                if type(k) == "string" then
                    parts[#parts + 1] = '"' .. _escape_string(k) .. '":' .. _encode(v)
                end
            end
            table.sort(parts)
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    error("json.encode: unsupported type " .. t)
end

function M.encode(val)
    return _encode(val)
end

-- ---------------------------------------------------------------------------
-- Decoder
-- ---------------------------------------------------------------------------

function M.decode(text)
    local pos = 1
    local len = #text

    local function skip_ws()
        while pos <= len do
            local b = text:byte(pos)
            if b == 32 or b == 9 or b == 10 or b == 13 then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse  -- forward-declared

    local function parse_string()
        pos = pos + 1  -- skip opening '"'
        local buf = {}
        while pos <= len do
            local c = text:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(buf)
            elseif c == '\\' then
                pos = pos + 1
                local e = text:sub(pos, pos)
                local map = {['"']='"', ['\\']='\\',['/']='/',
                             n='\n', r='\r', t='\t', b='\b', f='\f'}
                buf[#buf + 1] = map[e] or e
            else
                buf[#buf + 1] = c
            end
            pos = pos + 1
        end
        error("json.decode: unterminated string")
    end

    local function parse_number()
        local s, e = text:find("^-?%d+%.?%d*[eE]?[+%-]?%d*", pos)
        if not s then error("json.decode: expected number at pos " .. pos) end
        local n = tonumber(text:sub(s, e))
        pos = e + 1
        return n
    end

    local function parse_array()
        pos = pos + 1  -- skip '['
        local arr = {}
        skip_ws()
        if text:sub(pos, pos) == ']' then pos = pos + 1; return arr end
        while true do
            skip_ws()
            arr[#arr + 1] = parse()
            skip_ws()
            local c = text:sub(pos, pos)
            if     c == ']' then pos = pos + 1; break
            elseif c == ',' then pos = pos + 1
            else error("json.decode: expected ',' or ']' at pos " .. pos)
            end
        end
        return arr
    end

    local function parse_object()
        pos = pos + 1  -- skip '{'
        local obj = {}
        skip_ws()
        if text:sub(pos, pos) == '}' then pos = pos + 1; return obj end
        while true do
            skip_ws()
            if text:sub(pos, pos) ~= '"' then
                error("json.decode: expected '\"' at pos " .. pos)
            end
            local key = parse_string()
            skip_ws()
            if text:sub(pos, pos) ~= ':' then
                error("json.decode: expected ':' at pos " .. pos)
            end
            pos = pos + 1
            skip_ws()
            obj[key] = parse()
            skip_ws()
            local c = text:sub(pos, pos)
            if     c == '}' then pos = pos + 1; break
            elseif c == ',' then pos = pos + 1
            else error("json.decode: expected ',' or '}' at pos " .. pos)
            end
        end
        return obj
    end

    parse = function()
        skip_ws()
        local c = text:sub(pos, pos)
        if c == '"' then
            return parse_string()
        elseif c == '[' then
            return parse_array()
        elseif c == '{' then
            return parse_object()
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4; return nil
        else
            return parse_number()
        end
    end

    local result = parse()
    return result
end

return M
