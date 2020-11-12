--[[--
A simple serialization function which won't do uservalues, functions, or loops.
]]

local isUbuntuTouch = os.getenv("UBUNTU_APPLICATION_ISOLATION") ~= nil
local insert = table.insert
local indent_prefix = "    "

local function _serialize(what, outt, indent, max_lv, history, _pairs)
    if not max_lv then
        max_lv = math.huge
    end

    if indent > max_lv then
        return
    end

    if type(what) == "table" then
        history = history or {}
        for up, item in ipairs(history) do
            if item == what then
                insert(outt, "nil --[[ LOOP:\n")
                insert(outt, string.rep(indent_prefix, indent - up))
                insert(outt, "^------- ]]")
                return
            end
        end
        local new_history = { what, unpack(history) }
        local didrun = false
        insert(outt, "{")
        for k, v in _pairs(what) do
            insert(outt, "\n")
            insert(outt, string.rep(indent_prefix, indent+1))
            insert(outt, "[")
            _serialize(k, outt, indent+1, max_lv, new_history, _pairs)
            insert(outt, "] = ")
            _serialize(v, outt, indent+1, max_lv, new_history, _pairs)
            insert(outt, ",")
            didrun = true
        end
        if didrun then
            insert(outt, "\n")
            insert(outt, string.rep(indent_prefix, indent))
        end
        insert(outt, "}")
    elseif type(what) == "string" then
        insert(outt, string.format("%q", what))
    elseif type(what) == "number" then
        if isUbuntuTouch then
            --- @fixme The `SDL_CreateRenderer` function in Ubuntu touch somehow
            -- use a strange locale that formats number like this: 1.10000000000000g+02
            -- which cannot be recognized by loadfile after the number is dumped.
            -- Here the workaround is to preserve enough precision in "%.13e" format.
            insert(outt, string.format("%.13e", what))
        else
            insert(outt, tostring(what))
        end
    elseif type(what) == "boolean" then
        insert(outt, tostring(what))
    elseif type(what) == "function" then
        insert(outt, tostring(what))
    elseif type(what) == "nil" then
        insert(outt, "nil")
    end
end

--[[--Serializes whatever is in `data` to a string that is parseable by Lua.

You can optionally specify a maximum recursion depth in `max_lv`.
@function dump
@param data the object you want serialized (table, string, number, boolean, nil)
@param max_lv optional maximum recursion depth
--]]
local function dump(data, max_lv, ordered)
    local out = {}
    local _pairs = ordered and require("ffi/util").orderedPairs or pairs
    _serialize(data, out, 0, max_lv, nil, _pairs)
    return table.concat(out)
end

return dump
