--[[
simple serialization function, won't do uservalues, functions, loops
]]

local insert = table.insert

local function _serialize(what, outt, indent, max_lv, history)
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
                insert(outt, string.rep("\t", indent - up))
                insert(outt, "^------- ]]")
                return
            end
        end
        local new_history = { what, unpack(history) }
        local didrun = false
        insert(outt, "{")
        for k, v in pairs(what) do
            if didrun then
                insert(outt, ",")
            end
            insert(outt, "\n")
            insert(outt, string.rep("\t", indent+1))
            insert(outt, "[")
            _serialize(k, outt, indent+1, max_lv, new_history)
            insert(outt, "] = ")
            _serialize(v, outt, indent+1, max_lv, new_history)
            didrun = true
        end
        if didrun then
            insert(outt, "\n")
            insert(outt, string.rep("\t", indent))
        end
        insert(outt, "}")
    elseif type(what) == "string" then
        insert(outt, string.format("%q", what))
    elseif type(what) == "number" or type(what) == "boolean" then
        insert(outt, tostring(what))
    elseif type(what) == "function" then
        insert(outt, "nil --[[ FUNCTION ]]")
    elseif type(what) == "nil" then
        insert(outt, "nil")
    end
end

--[[
Serializes whatever is in "data" to a string that is parseable by Lua

You can optionally specify a maximum recursion depth in "max_lv"
--]]
local function dump(data, max_lv)
    local out = {}
    _serialize(data, out, 0, max_lv)
    return table.concat(out)
end

return dump
