--[[--
This module handles generic settings as well as KOReader's global settings system.
]]

local dump = require("dump")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local LuaSettings = {}

function LuaSettings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Opens a settings file.
function LuaSettings:open(file_path)
    local new = {file=file_path}
    local ok, stored

    -- File being absent and returning an empty table is a use case,
    -- so logger.warn() only if there was an existing file
    local existing = lfs.attributes(new.file, "mode") == "file"

    ok, stored = pcall(dofile, new.file)
    if ok and stored then
        new.data = stored
    else
        if existing then logger.warn("Failed reading", new.file, "(probably corrupted).") end
        -- Fallback to .old if it exists
        ok, stored = pcall(dofile, new.file..".old")
        if ok and stored then
            if existing then logger.warn("read from backup file", new.file..".old") end
            new.data = stored
        else
            if existing then logger.warn("no usable backup file for", new.file, "to read from") end
            new.data = {}
        end
    end

    return setmetatable(new, {__index = LuaSettings})
end

--- @todo DocSettings can return a LuaSettings to use following awesome features.
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
        self:saveSetting(key, false)
    end
    return self
end

--- Adds item to table.
function LuaSettings:addTableItem(key, value)
    local settings_table = self:has(key) and self:readSetting(key) or {}
    table.insert(settings_table, value)
    self:saveSetting(key, settings_table)
    return self
end

--- Removes index from table.
function LuaSettings:removeTableItem(key, index)
    local settings_table = self:has(key) and self:readSetting(key) or {}
    table.remove(settings_table, index)
    self:saveSetting(key, settings_table)
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
    local directory_updated = false
    if lfs.attributes(self.file, "mode") == "file" then
        -- As an additional safety measure (to the ffiutil.fsync* calls
        -- used below), we only backup the file to .old when it has
        -- not been modified in the last 60 seconds. This should ensure
        -- in the case the fsync calls are not supported that the OS
        -- may have itself sync'ed that file content in the meantime.
        local mtime = lfs.attributes(self.file, "modification")
        if mtime < os.time() - 60 then
            os.rename(self.file, self.file .. ".old")
            directory_updated = true -- fsync directory content too below
        end
    end
    local f_out = io.open(self.file, "w")
    if f_out ~= nil then
        os.setlocale('C', 'numeric')
        f_out:write("-- we can read Lua syntax here!\nreturn ")
        f_out:write(dump(self.data))
        f_out:write("\n")
        ffiutil.fsyncOpenedFile(f_out) -- force flush to the storage device
        f_out:close()
    end
    if directory_updated then
        -- Ensure the file renaming is flushed to storage device
        ffiutil.fsyncDirectory(self.file)
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
