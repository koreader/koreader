--[[--
Handles append-mostly data such as KOReader's bookmarks and dictionary search history.
]]

local LuaSettings = require("luasettings")
local dbg = require("dbg")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
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

    -- Some magic to allow for self-describing function names:
    -- We'll use data_env both as the environment when loading the data, *and* its metatable,
    -- *and* as the target of its index lookup metamethod.
    -- Its NameEntry field is a function responsible for actually storing the data in the right place in the LuaData object.
    -- It gets called via __index lookup in the global scope (i.e., the env) when Lua tries to resolve
    -- the global NameEntry function calls in our stored data.
    -- NOTE: We could also make the metatable's __index field point to a function, and handle the lookup ourselves inside it,
    --       but using an empty env with loadfile is not a bad idea to begin with anyway ;).
    local data_env = {}
    data_env.__index = data_env
    setmetatable(data_env, data_env)
    data_env[self.name.."Entry"] = function(table)
        if table.index then
            -- We've got a deleted setting, overwrite with nil and be done with it.
            if not table.data then
                new.data[table.index] = nil
                return
            end

            if type(table.data) == "table" then
                new.data[table.index] = new.data[table.index] or {}
                local size = util.tableSize(table.data)
                if size == 1 then
                    -- It's an incremental array element, insert it in the array at its proper index
                    for key, value in pairs(table.data) do
                        new.data[table.index][key] = value
                    end
                else
                    -- It's a complex table, just replace the whole thing
                    new.data[table.index] = table.data
                end
            else
                new.data[table.index] = table.data
            end
        else
            -- It's an untagged blob, use it as-is
            new.data = table
        end
    end

    local ok, err
    if lfs.attributes(new.file, "mode") == "file" then
        ok, err = loadfile(new.file, "t", data_env)
        if ok then
            logger.dbg("data is read from", new.file)
            ok()
        else
            logger.dbg(new.file, "is invalid, removed.", err)
            os.remove(new.file)
        end
    end
    if not ok then
        for i=1, self.max_backups, 1 do
            local backup_file = new.file..".old."..i
            if lfs.attributes(backup_file, "mode") == "file" then
                ok, err = loadfile(backup_file, "t", data_env)
                if ok then
                    logger.dbg("data is read from", backup_file)
                    ok()
                    break
                else
                    logger.dbg(backup_file, "is invalid, removed.", err)
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

--- Removes index from table.
function LuaData:removeTableItem(key, index)
    LuaSettings.removeTableItem(self, key, index)
    self:flush()
    return self
end

--- Appends settings to disk.
function LuaData:append(data)
    if not self.file then return end
    local f_out = io.open(self.file, "a")
    if f_out ~= nil then
        os.setlocale('C', 'numeric')
        -- NOTE: This is a function call, with a table as its single argument. Parentheses are elided.
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
                logger.dbg("LuaData: Rename", self.file .. ".old." .. i, "to", self.file .. ".old." .. i+1)
                os.rename(self.file, self.file .. ".old." .. i+1)
            else
                break
            end
        end
        logger.dbg("LuaData: Rename", self.file, "to", self.file .. ".old.1")
        os.rename(self.file, self.file .. ".old.1")
    end

    logger.dbg("LuaData: Write to", self.file)
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
