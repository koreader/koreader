--[[--
Handles append-mostly data such as KOReader's bookmarks and dictionary search history.
]]

local LuaSettings = require("luasettings")
local dbg = require("dbg")
local dump = require("dump")
local logger = require("logger")
local util = require("util")

local LuaData = LuaSettings:new{
    name = "",
    max_backups = 9,
}

--- Creates a new LuaData instance.
function LuaData:open(file_path, o) -- luacheck: ignore 312
    if o and type(o) ~= "table" then
        if dbg.is_on then
            error("LuaData: got "..type(o)..", table expected")
        else
            o = {}
        end
    end
    -- always initiate a new instance
    -- careful, `o` is already a table so we use parentheses
    self = LuaData:new(o)

    local new = {file=file_path, data={}}

    -- some magic to allow for self-describing function names
    local _local = {}
    _local.__index = _local
    setmetatable(_G, _local)
    _local[self.name.."Entry"] = function(table)
        if table.index then
            -- we've got a deleted setting, overwrite with nil
            if not table.data then new.data[table.index] = nil end
            new.data[table.index] = new.data[table.index] or {}
            local size = util.tableSize(table.data)
            if size == 1 then
                for key, value in pairs(table.data) do
                    new.data[table.index][key] = value
                end
            else
                new.data[table.index] = table.data
            end
        -- we've got it all at once
        else
            new.data = table
        end
    end

    local ok = false
    if lfs.attributes(new.file, "mode") == "file" then
        ok = pcall(dofile, new.file)
        if ok then
            logger.dbg("data is read from ", new.file)
        else
            logger.dbg(new.file, " is invalid, remove.")
            os.remove(new.file)
        end
    end
    if not ok then
        for i=1, self.max_backups, 1 do
            local backup_file = new.file..".old."..i
            if lfs.attributes(backup_file, "mode") == "file" then
                if pcall(dofile, backup_file) then
                    logger.dbg("data is read from ", backup_file)
                    break
                else
                    logger.dbg(backup_file, " is invalid, remove.")
                    os.remove(backup_file)
                end
            end
        end
    end

    return setmetatable(new, {__index = self})
end

--- Saves a setting.
function LuaData:saveSetting(key, value)
    self.data[key] = value
    self:append{
        index = key,
        data = value,
    }
    return self
end

--- Deletes a setting.
function LuaData:delSetting(key)
    self.data[key] = nil
    self:append{
        index = key,
    }
    return self
end

--- Adds item to table.
function LuaData:addTableItem(table_name, value)
    local settings_table = self:has(table_name) and self:readSetting(table_name) or {}
    table.insert(settings_table, value)
    self.data[table_name] = settings_table
    self:append{
        index = table_name,
        data = {[#settings_table] = value},
    }
end

local _orig_removeTableItem = LuaSettings.removeTableItem
--- Removes index from table.
function LuaData:removeTableItem(key, index)
    _orig_removeTableItem(self, key, index)
    self:flush()
    return self
end

--- Appends settings to disk.
function LuaData:append(data)
    if not self.file then return end
    local f_out = io.open(self.file, "a")
    if f_out ~= nil then
        os.setlocale('C', 'numeric')
        f_out:write(self.name.."Entry")
        f_out:write(dump(data))
        f_out:write("\n")
        f_out:close()
    end
    return self
end

--- Replaces existing settings with table.
function LuaData:reset(table)
    self.data = table
    self:flush()
    return self
end

--- Writes all settings to disk (does not append).
function LuaData:flush()
    if not self.file then return end

    if lfs.attributes(self.file, "mode") == "file" then
        for i=1, self.max_backups, 1 do
            if lfs.attributes(self.file..".old."..i, "mode") == "file" then
                logger.dbg("LuaData: Rename ", self.file .. ".old." .. i, " to ", self.file .. ".old." .. i+1)
                os.rename(self.file, self.file .. ".old." .. i+1)
            else
                break
            end
        end
        logger.dbg("LuaData: Rename ", self.file, " to ", self.file .. ".old.1")
        os.rename(self.file, self.file .. ".old.1")
    end

    logger.dbg("LuaData: Write to ", self.file)
    local f_out = io.open(self.file, "w")
    if f_out ~= nil then
        os.setlocale('C', 'numeric')
        f_out:write("-- we can read Lua syntax here!\n")
        f_out:write(self.name.."Entry")
        f_out:write(dump(self.data))
        f_out:write("\n")
        f_out:close()
    end
    return self
end

return LuaData
