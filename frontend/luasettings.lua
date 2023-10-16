--[[--
This module handles generic settings as well as KOReader's global settings system.
]]

local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local LuaSettings = {}

function LuaSettings:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
-- NOTE: Instances are created via open, so we do *NOT* implement a new method, to avoid confusion.

--- Opens a settings file.
function LuaSettings:open(file_path)
    local new = LuaSettings:extend{
        file = file_path,
    }
    local ok, stored

    -- File being absent and returning an empty table is a use case,
    -- so logger.warn() only if there was an existing file
    local existing = lfs.attributes(new.file, "mode") == "file"

    ok, stored = pcall(dofile, new.file)
    if ok and stored then
        new.data = stored
    else
        if existing then logger.warn("LuaSettings: Failed reading", new.file, "(probably corrupted).") end
        -- Fallback to .old if it exists
        ok, stored = pcall(dofile, new.file..".old")
        if ok and stored then
            if existing then logger.warn("LuaSettings: read from backup file", new.file..".old") end
            new.data = stored
        else
            if existing then logger.warn("LuaSettings: no usable backup file for", new.file, "to read from") end
            new.data = {}
        end
    end

    return new
end

function LuaSettings:wrap(data)
    return self:extend{
        data = type(data) == "table" and data or {},
    }
end

--[[--Reads child settings.

@usage

    Settings:saveSetting("key", {
        a = "b",
        c = true,
        d = false,
    })

    local child = Settings:child("key")

    child:readSetting("a")
    -- result "b"
]]
function LuaSettings:child(key)
    return self:wrap(self:readSetting(key))
end

--[[-- Reads a setting, optionally initializing it to a default.

If default is provided, and the key doesn't exist yet, it is initialized to default first.
This ensures both that the defaults are actually set if necessary,
and that the returned reference actually belongs to the LuaSettings object straight away,
without requiring further interaction (e.g., saveSetting) from the caller.

This is mainly useful if the data type you want to retrieve/store is assigned/returned/passed by reference (e.g., a table),
and you never actually break that reference by assigning another one to the same variable, (by e.g., assigning it a new object).
c.f., <https://www.lua.org/manual/5.1/manual.html#2.2>.

@param key The setting's key
@param default Initialization data (Optional)
]]
function LuaSettings:readSetting(key, default)
    -- No initialization data: legacy behavior
    if not default then
        return self.data[key]
    end

    if not self:has(key) then
        self.data[key] = default
    end
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
    return self.data[key] ~= nil
end

--- Checks if setting does not exist.
function LuaSettings:hasNot(key)
    return self.data[key] == nil
end

--- Checks if setting is `true` (boolean).
function LuaSettings:isTrue(key)
    return self.data[key] == true
end

--- Checks if setting is `false` (boolean).
function LuaSettings:isFalse(key)
    return self.data[key] == false
end

--- Checks if setting is `nil` or `true`.
function LuaSettings:nilOrTrue(key)
    return self:hasNot(key) or self:isTrue(key)
end

--- Checks if setting is `nil` or `false`.
function LuaSettings:nilOrFalse(key)
    return self:hasNot(key) or self:isFalse(key)
end

--- Flips `nil` or `true` to `false`, and `false` to `nil`.
--- e.g., a setting that defaults to true.
function LuaSettings:flipNilOrTrue(key)
    if self:nilOrTrue(key) then
        self:saveSetting(key, false)
    else
        self:delSetting(key)
    end
    return self
end

--- Flips `nil` or `false` to `true`, and `true` to `nil`.
--- e.g., a setting that defaults to false.
function LuaSettings:flipNilOrFalse(key)
    if self:nilOrFalse(key) then
        self:saveSetting(key, true)
    else
        self:delSetting(key)
    end
    return self
end

--- Flips a setting between `true` and `nil`.
function LuaSettings:flipTrue(key)
    if self:isTrue(key) then
        self:delSetting(key)
    else
        self:saveSetting(key, true)
    end
    return self
end

--- Flips a setting between `false` and `nil`.
function LuaSettings:flipFalse(key)
    if self:isFalse(key) then
        self:delSetting(key)
    else
        self:saveSetting(key, false)
    end
    return self
end

-- Unconditionally makes a boolean setting `true`.
function LuaSettings:makeTrue(key)
    self:saveSetting(key, true)
    return self
end

-- Unconditionally makes a boolean setting `false`.
function LuaSettings:makeFalse(key)
    self:saveSetting(key, false)
    return self
end

--- Toggles a boolean setting
function LuaSettings:toggle(key)
    if self:nilOrFalse(key) then
        self:saveSetting(key, true)
    else
        self:saveSetting(key, false)
    end
    return self
end

-- Initializes settings per extension with default values
function LuaSettings:initializeExtSettings(key, defaults, force_init)
    local curr = self:readSetting(key)
    if not curr or force_init then
        self:saveSetting(key, defaults)
        return true
    end
    return false
end

-- Returns saved setting for given extension
function LuaSettings:getSettingForExt(key, ext)
    local saved_settings = self:readSetting(key) or {}
    return saved_settings[ext]
end

-- Sets setting for given extension
function LuaSettings:saveSettingForExt(key, value, ext)
    local saved_settings = self:readSetting(key) or {}
    saved_settings[ext] = value
    self:saveSetting(key, saved_settings)
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

function LuaSettings:backup(file)
    file = file or self.file
    local directory_updated
    if lfs.attributes(file, "mode") == "file" then
        -- As an additional safety measure (to the ffiutil.fsync* calls used in util.writeToFile),
        -- we only backup the file to .old when it has not been modified in the last 60 seconds.
        -- This should ensure in the case the fsync calls are not supported
        -- that the OS may have itself sync'ed that file content in the meantime.
        local mtime = lfs.attributes(file, "modification")
        if mtime < os.time() - 60 then
            os.rename(file, file .. ".old")
            directory_updated = true -- fsync directory content
        end
    end
    return directory_updated
end

--- Writes settings to disk.
function LuaSettings:flush()
    if not self.file then return end
    local directory_updated = self:backup()
    util.writeToFile(dump(self.data, nil, true), self.file, true, true, directory_updated)
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
