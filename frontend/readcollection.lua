local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local collection_file = DataStorage:getSettingsDir() .. "/collection.lua"

local ReadCollection = {
    coll = {},
    last_read_time = 0,
    default_collection_name = "favorites",
}

local function buildEntry(file, order, mandatory)
    file = FFIUtil.realpath(file)
    if not file then return end
    if not mandatory then -- new item
        local attr = lfs.attributes(file)
        if not attr or attr.mode ~= "file" then return end
        mandatory = util.getFriendlySize(attr.size or 0)
    end
    return {
        file = file,
        text = file:gsub(".*/", ""),
        mandatory = mandatory,
        order = order,
    }
end

function ReadCollection:_read()
    local collection_file_modification_time = lfs.attributes(collection_file, "modification")
    if collection_file_modification_time then
        if collection_file_modification_time <= self.last_read_time then return end
        self.last_read_time = collection_file_modification_time
    end
    local collections = LuaSettings:open(collection_file)
    if collections:hasNot(self.default_collection_name) then
        collections:saveSetting(self.default_collection_name, {})
    end
    logger.dbg("ReadCollection: reading from collection file")
    self.coll = {}
    for coll_name, collection in pairs(collections.data) do
        local coll = {}
        for _, v in ipairs(collection) do
            local item = buildEntry(v.file, v.order)
            if item then -- exclude deleted files
                coll[item.file] = item
            end
        end
        self.coll[coll_name] = coll
    end
end

function ReadCollection:write(collection_name)
    local collections = LuaSettings:open(collection_file)
    for coll_name, coll in pairs(self.coll) do
        if not collection_name or coll_name == collection_name then
            local data = {}
            for _, item in pairs(coll) do
                table.insert(data, { file = item.file, order = item.order })
            end
            collections:saveSetting(coll_name, data)
        end
    end
    logger.dbg("ReadCollection: writing to collection file")
    collections:flush()
end

function ReadCollection:getFileCollectionName(file, collection_name)
    file = FFIUtil.realpath(file) or file
    for coll_name, coll in pairs(self.coll) do
        if not collection_name or coll_name == collection_name then
            if coll[file] then
                return coll_name, file
            end
        end
    end
end

function ReadCollection:hasFile(file, collection_name)
    local coll_name = self:getFileCollectionName(file, collection_name)
    return coll_name and true or false
end

function ReadCollection:getCollectionMaxOrder(collection_name)
    local max_order = 0
    for _, item in pairs(self.coll[collection_name]) do
        if max_order < item.order then
            max_order = item.order
        end
    end
    return max_order
end

function ReadCollection:getOrderedCollection(collection_name)
    local ordered_coll = {}
    for _, item in pairs(self.coll[collection_name]) do
        table.insert(ordered_coll, item)
    end
    table.sort(ordered_coll, function(v1, v2) return v1.order < v2.order end)
    return ordered_coll
end

function ReadCollection:updateCollectionOrder(collection_name, ordered_coll)
    local coll = self.coll[collection_name]
    for i, item in ipairs(ordered_coll) do
        coll[item.file].order = i
    end
    self:write(collection_name)
end

function ReadCollection:addItem(file, collection_name)
    collection_name = collection_name or self.default_collection_name
    local max_order = self:getCollectionMaxOrder(collection_name)
    local item = buildEntry(file, max_order + 1)
    self.coll[collection_name][item.file] = item
    self:write(collection_name)
end

function ReadCollection:addItems(files, collection_name) -- files = { filepath = true, }
    collection_name = collection_name or self.default_collection_name
    local coll = self.coll[collection_name]
    local max_order = self:getCollectionMaxOrder(collection_name)
    local do_write
    for file in pairs(files) do
        if not self:hasFile(file) then
            max_order = max_order + 1
            local item = buildEntry(file, max_order)
            coll[item.file] = item
            do_write = true
        end
    end
    if do_write then
        self:write(collection_name)
    end
end

function ReadCollection:removeItem(file, collection_name, no_write)
    local coll_name, file_name = self:getFileCollectionName(file, collection_name)
    if coll_name then
        self.coll[coll_name][file_name] = nil
        if not no_write then
            self:write(coll_name)
        end
        return true
    end
end

function ReadCollection:removeItems(files) -- files = { filepath = true, }
    local do_write
    for file in pairs(files) do
        if self:removeItem(file, nil, true) then
            do_write = true
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:removeItemsByPath(path)
    local do_write
    for coll_name, coll in pairs(self.coll) do
        for file_name in pairs(coll) do
            if util.stringStartsWith(file_name, path) then
                self.coll[coll_name][file_name] = nil
                do_write = true
            end
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:_updateItem(coll_name, file_name, new_filepath, new_path)
    local coll = self.coll[coll_name]
    local item_old = coll[file_name]
    local order, mandatory = item_old.order, item_old.mandatory
    new_filepath = new_filepath or new_path .. "/" .. item_old.text
    coll[file_name] = nil
    local item = buildEntry(new_filepath, order, mandatory) -- no lfs call
    coll[item.file] = item
end

function ReadCollection:updateItem(file, new_filepath)
    local coll_name, file_name = self:getFileCollectionName(file)
    if coll_name then
        self:_updateItem(coll_name, file_name, new_filepath)
        self:write(coll_name)
    end
end

function ReadCollection:updateItems(files, new_path) -- files = { filepath = true, }
    local do_write
    for file in pairs(files) do
        local coll_name, file_name = self:getFileCollectionName(file)
        if coll_name then
            self:_updateItem(coll_name, file_name, nil, new_path)
            do_write = true
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:updateItemsByPath(path, new_path)
    local len = #path
    local do_write
    for coll_name, coll in pairs(self.coll) do
        for file_name in pairs(coll) do
            if file_name:sub(1, len) == path then
                self:_updateItem(coll_name, file_name, new_path .. file_name:sub(len + 1))
                do_write = true
            end
        end
    end
    if do_write then
        self:write()
    end
end

ReadCollection:_read()

return ReadCollection
