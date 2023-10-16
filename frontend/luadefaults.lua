--[[--
Subclass of LuaSettings dedicated to handling the legacy global constants.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local dump = require("dump")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local LuaDefaults = LuaSettings:extend{
    ro = nil, -- will contain the defaults.lua k/v pairs (const)
    rw = nil, -- will only contain non-defaults user-modified k/v pairs
}

--- Opens a settings file.
function LuaDefaults:open(path)
    local file_path = path or DataStorage:getDataDir() .. "/defaults.custom.lua"
    local new = LuaDefaults:extend{
        file = file_path,
    }
    local ok, stored

    -- File being absent and returning an empty table is a use case,
    -- so logger.warn() only if there was an existing file
    local existing = lfs.attributes(new.file, "mode") == "file"

    ok, stored = pcall(dofile, new.file)
    if ok and stored then
        new.rw = stored
    else
        if existing then logger.warn("LuaDefaults: Failed reading", new.file, "(probably corrupted).") end
        -- Fallback to .old if it exists
        ok, stored = pcall(dofile, new.file..".old")
        if ok and stored then
            if existing then logger.warn("LuaDefaults: read from backup file", new.file..".old") end
            new.rw = stored
        else
            if existing then logger.warn("LuaDefaults: no usable backup file for", new.file, "to read from") end
            new.rw = {}
        end
    end

    -- The actual defaults file, on the other hand, is set in stone.
    ok, stored = pcall(dofile, "defaults.lua")
    if ok and stored then
        new.ro = stored
    else
        error("Failed reading defaults.lua")
    end

    return new
end

--- Reads a setting, optionally initializing it to a default.
function LuaDefaults:readSetting(key, default)
    if not default then
        if self:hasBeenCustomized(key) then
            return self.rw[key]
        else
            return self.ro[key]
        end
    end

    if not self:hasBeenCustomized(key) then
        self.rw[key] = default
        return self.rw[key]
    end

    if self:hasBeenCustomized(key) then
        return self.rw[key]
    else
        return self.ro[key]
    end
end

--- Saves a setting.
function LuaDefaults:saveSetting(key, value)
    if util.tableEquals(self.ro[key], value, true) then
        -- Only keep actually custom settings in the rw table ;).
        return self:delSetting(key)
    else
        self.rw[key] = value
    end
    return self
end

--- Deletes a setting.
function LuaDefaults:delSetting(key)
    self.rw[key] = nil
    return self
end

--- Checks if setting exists.
function LuaDefaults:has(key)
    return self.ro[key] ~= nil
end

--- Checks if setting does not exist.
function LuaDefaults:hasNot(key)
    return self.ro[key] == nil
end

--- Checks if setting has been customized.
function LuaDefaults:hasBeenCustomized(key)
    return self.rw[key] ~= nil
end

--- Checks if setting has NOT been customized.
function LuaDefaults:hasNotBeenCustomized(key)
    return self.rw[key] == nil
end

--- Checks if setting is `true` (boolean).
function LuaDefaults:isTrue(key)
    if self:hasBeenCustomized(key) then
        return self.rw[key] == true
    else
        return self.ro[key] == true
    end
end

--- Checks if setting is `false` (boolean).
function LuaDefaults:isFalse(key)
    if self:hasBeenCustomized(key) then
        return self.rw[key] == false
    else
        return self.ro[key] == false
    end
end

--- Low-level API for filemanagersetdefaults
function LuaDefaults:getDataTables()
    return self.ro, self.rw
end

function LuaDefaults:readDefaultSetting(key)
    return self.ro[key]
end

-- NOP unsupported LuaSettings APIs
function LuaDefaults:wrap() end
function LuaDefaults:child() end
function LuaDefaults:initializeExtSettings() end
function LuaDefaults:getSettingForExt() end
function LuaDefaults:saveSettingForExt() end
function LuaDefaults:addTableItem() end
function LuaDefaults:removeTableItem() end
function LuaDefaults:reset() end

--- Writes settings to disk.
function LuaDefaults:flush()
    if not self.file then return end
    local directory_updated = self:backup() -- LuaSettings
    util.writeToFile(dump(self.rw, nil, true), self.file, true, true, directory_updated)
    return self
end

return LuaDefaults
