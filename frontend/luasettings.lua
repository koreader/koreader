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

function LuaSettings:nilOrTrue(key)
    return self:hasNot(key) or self:isTrue(key)
end

function LuaSettings:flipNilOrTrue(key)
    if self:nilOrTrue(key) then
        self:saveSetting(key, false)
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

function LuaSettings:flush()
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
