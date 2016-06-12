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
