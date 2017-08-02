--[[--
This module handles generic settings as well as KOReader's global settings system.
]]

local dump = require("dump")

local LuaSettings = {}

--- Opens a settings file.
function LuaSettings:open(file_path)
    local new = {file=file_path}
    local ok, stored

    ok, stored = pcall(dofile, new.file)
    if ok and stored then
        new.data = stored
    else
        new.data = {}
    end

    return setmetatable(new, {__index = LuaSettings})
end

-- TODO: DocSettings can return a LuaSettings to use following awesome features.
function LuaSettings:wrap(data)
    local new = {data = type(data) == "table" and data or {}}
    return setmetatable(new, {__index = LuaSettings})
end

--[[--Reads child settings.

@usage

    Settings:saveSetting("key", {
        a = "b",
        c = "true",
        d = false,
    })

    local child = Settings:child("key")

    child:readSetting("a")
    -- result "b"
]]
function LuaSettings:child(key)
    return LuaSettings:wrap(self:readSetting(key))
end

--- Reads a setting.
function LuaSettings:readSetting(key)
    return self.data[key]
end

--- Saves a setting.
function LuaSettings:saveSetting(key, value)
    self.data[key] = value
    return self
end

--- Deletes a setting.
function LuaSettings:delSetting(key)
    self.data[key] = nil
    return self
end

--- Checks if setting exists.
function LuaSettings:has(key)
    return self:readSetting(key) ~= nil
end

--- Checks if setting does not exist.
function LuaSettings:hasNot(key)
    return self:readSetting(key) == nil
end

--- Checks if setting is `true`.
function LuaSettings:isTrue(key)
    return string.lower(tostring(self:readSetting(key))) == "true"
end

--- Checks if setting is `false`.
function LuaSettings:isFalse(key)
    return string.lower(tostring(self:readSetting(key))) == "false"
end

--- Checks if setting is `nil` or `true`.
function LuaSettings:nilOrTrue(key)
    return self:hasNot(key) or self:isTrue(key)
end

--- Checks if setting is `nil` or `false`.
function LuaSettings:nilOrFalse(key)
    return self:hasNot(key) or self:isFalse(key)
end

--- Flips `nil` or `true` to `false`.
function LuaSettings:flipNilOrTrue(key)
    if self:nilOrTrue(key) then
        self:saveSetting(key, false)
    else
        self:delSetting(key)
    end
    return self
end

--- Flips `nil` or `false` to `true`.
function LuaSettings:flipNilOrFalse(key)
    if self:nilOrFalse(key) then
        self:saveSetting(key, true)
    else
        self:delSetting(key)
    end
    return self
end

--- Flips setting to `true`.
function LuaSettings:flipTrue(key)
    if self:isTrue(key) then
        self:delSetting(key)
    else
        self:saveSetting(key, true)
    end
    return self
end

--- Flips setting to `false`.
function LuaSettings:flipFalse(key)
    if self:isFalse(key) then
        self:delSetting(key)
    else
        self:saveSetting(key, true)
    end
    return self
end

--- Replaces existing settings with table.
function LuaSettings:reset(table)
    self.data = table
    return self
end

--- Writes settings to disk.
function LuaSettings:flush()
    if not self.file then return end
    local f_out = io.open(self.file, "w")
    if f_out ~= nil then
        os.setlocale('C', 'numeric')
        f_out:write("-- we can read Lua syntax here!\nreturn ")
        f_out:write(dump(self.data))
        f_out:write("\n")
        f_out:close()
    end
    return self
end

--- Closes settings file.
function LuaSettings:close()
    self:flush()
end

--- Purges settings file.
function LuaSettings:purge()
    if self.file then
        os.remove(self.file)
    end
    return self
end

return LuaSettings
