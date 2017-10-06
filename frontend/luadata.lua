--[[--
Handles append-mostly data such as KOReader's bookmarks and dictionary search history.
]]

local LuaSettings = require("luasettings")
local dump = require("dump")
--local logger = require("logger")
local util = require("util")

local LuaData = LuaSettings:new{
    name = nil,
}
--- Opens a LuaData file.
function LuaData:open(file_path, name)
    if name then self.name = name end
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
        end
    end

    pcall(dofile, new.file)

    return setmetatable(new, {__index = LuaData})
end

--- Saves a setting.
function LuaData:saveSetting(key, value)
    self.data[key] = value
    self:append({
        index = key,
        data = value,
    })
    return self
end

--- Deletes a setting.
function LuaData:delSetting(key)
    self.data[key] = nil
    self:append({
        index = key,
    })
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
