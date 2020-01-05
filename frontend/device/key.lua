--[[
an interface for key presses
]]

local Key = {}

function Key:new(key, modifiers)
    local o = { key = key, modifiers = modifiers }

    -- we're a hash map, too
    o[key] = true
    for mod, pressed in pairs(modifiers) do
        if pressed then
            o[mod] = true
        end
    end

    setmetatable(o, self)
    self.__index = self
    return o
end

function Key:__tostring()
    return table.concat(self:getSequence(), "-")
end

--[[
get a sequence that can be matched against later

use this to let the user press a sequence and then
store this as configuration data (configurable
shortcuts)
]]
function Key:getSequence()
    local seq = {}
    for mod, pressed in pairs(self.modifiers) do
        if pressed then
            table.insert(seq, mod)
        end
    end
    table.insert(seq, self.key)
end

--[[
this will match a key against a sequence

the sequence should be a table of key names that
must be pressed together to match.
if an entry in this table is itself a table, at
least one key in this table must match.

E.g.:

Key:match({ "Alt", "K" }) -- match Alt-K
Key:match({ "Alt", { "K", "L" }}) -- match Alt-K _or_ Alt-L
]]
function Key:match(sequence)
    local mod_keys = {} -- a hash table for checked modifiers
    for _, key in ipairs(sequence) do
        if type(key) == "table" then
            local found = false
            for _, variant in ipairs(key) do
                if self[variant] then
                    found = true
                    break
                end
            end
            if not found then
                -- one of the needed keys is not pressed
                return false
            end
        elseif not self[key] then
            -- needed key not pressed
            return false
        elseif self.modifiers[key] ~= nil then
            -- checked key is a modifier key
            mod_keys[key] = true
        end
    end

    for mod, pressed in pairs(self.modifiers) do
        if pressed and not mod_keys[mod] then
            -- additional modifier keys are pressed, don't match
            return false
        end
    end

    return true
end

return Key
