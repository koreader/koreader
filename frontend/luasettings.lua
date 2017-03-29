local dump = require("dump")

local LuaSettings = {}

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

function LuaSettings:child(key)
    return LuaSettings:wrap(self:readSetting(key))
end

function LuaSettings:readSetting(key)
    return self.data[key]
end

function LuaSettings:saveSetting(key, value)
    self.data[key] = value
end

function LuaSettings:delSetting(key)
    self.data[key] = nil
end

function LuaSettings:has(key)
    return self:readSetting(key) ~= nil
end

function LuaSettings:hasNot(key)
    return self:readSetting(key) == nil
end

function LuaSettings:isTrue(key)
    return string.lower(tostring(self:readSetting(key))) == "true"
end

function LuaSettings:isFalse(key)
    return string.lower(tostring(self:readSetting(key))) == "false"
end

function LuaSettings:nilOrTrue(key)
    return self:hasNot(key) or self:isTrue(key)
end

function LuaSettings:nilOrFalse(key)
    return self:hasNot(key) or self:isFalse(key)
end

function LuaSettings:flipNilOrTrue(key)
    if self:nilOrTrue(key) then
        self:saveSetting(key, false)
    else
        self:delSetting(key)
    end
end

function LuaSettings:flipNilOrFalse(key)
    if self:nilOrFalse(key) then
        self:saveSetting(key, true)
    else
        self:delSetting(key)
    end
end

function LuaSettings:flipTrue(key)
    if self:isTrue(key) then
        self:delSetting(key)
    else
        self:saveSetting(key, true)
    end
end

function LuaSettings:flipFalse(key)
    if self:isFalse(key) then
        self:delSetting(key)
    else
        self:saveSetting(key, true)
    end
end

function LuaSettings:reset(table)
    self.data = table
end

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
end

function LuaSettings:close()
    self:flush()
end

function LuaSettings:purge()
    if self.file then
        os.remove(self.file)
    end
end

return LuaSettings
