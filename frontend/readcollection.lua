local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local collection_file = DataStorage:getSettingsDir() .. "/collection.lua"

local ReadCollection = {
    coll = nil, -- hash table
    coll_order = nil, -- hash table
    last_read_time = 0,
    default_collection_name = "favorites",
}

-- read, write

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
    self.coll_order = {}
    for coll_name, collection in pairs(collections.data) do
        local coll = {}
        for _, v in ipairs(collection) do
            local item = buildEntry(v.file, v.order)
            if item then -- exclude deleted files
                coll[item.file] = item
            end
        end
        self.coll[coll_name] = coll
        if not collection.settings then -- favorites, first run
            collection.settings = { order = 1 }
        end
        self.coll_order[coll_name] = collection.settings.order
    end
end

function ReadCollection:write(collection_name)
    local collections = LuaSettings:open(collection_file)
    for coll_name in pairs(collections.data) do
        if not self.coll[coll_name] then
            collections:delSetting(coll_name)
        end
    end
    for coll_name, coll in pairs(self.coll) do
        if not collection_name or coll_name == collection_name then
            local data = { settings = { order = self.coll_order[coll_name] } }
            for _, item in pairs(coll) do
                table.insert(data, { file = item.file, order = item.order })
            end
            collections:saveSetting(coll_name, data)
        end
    end
    logger.dbg("ReadCollection: writing to collection file")
    collections:flush()
end

-- info

function ReadCollection:isFileInCollection(file, collection_name)
    file = FFIUtil.realpath(file) or file
    return self.coll[collection_name][file] and true or false
end

function ReadCollection:isFileInCollections(file)
    file = FFIUtil.realpath(file) or file
    for _, coll in pairs(self.coll) do
        if coll[file] then
            return true
        end
    end
    return false
end

function ReadCollection:getCollectionsWithFile(file)
    file = FFIUtil.realpath(file) or file
    local collections = {}
    for coll_name, coll in pairs(self.coll) do
        if coll[file] then
            collections[coll_name] = true
        end
    end
    return collections
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

-- manage items

function ReadCollection:addItem(file, collection_name)
    local max_order = self:getCollectionMaxOrder(collection_name)
    local item = buildEntry(file, max_order + 1)
    self.coll[collection_name][item.file] = item
    self:write(collection_name)
end

function ReadCollection:addRemoveItemMultiple(file, collections_to_add)
    file = FFIUtil.realpath(file) or file
    for coll_name, coll in pairs(self.coll) do
        if collections_to_add[coll_name] then
            if not coll[file] then
                local max_order = self:getCollectionMaxOrder(coll_name)
                coll[file] = buildEntry(file, max_order + 1)
            end
        else
            if coll[file] then
                coll[file] = nil
            end
        end
    end
    self:write()
end

function ReadCollection:addItemsMultiple(files, collections_to_add)
    for file in pairs(files) do
        file = FFIUtil.realpath(file) or file
        for coll_name in pairs(collections_to_add) do
            local coll = self.coll[coll_name]
            if not coll[file] then
                local max_order = self:getCollectionMaxOrder(coll_name)
                coll[file] = buildEntry(file, max_order + 1)
            end
        end
    end
    self:write()
end

function ReadCollection:removeItem(file, collection_name, no_write) -- FM: delete file; FMColl: remove file
    file = FFIUtil.realpath(file) or file
    if collection_name then
        if self.coll[collection_name][file] then
            self.coll[collection_name][file] = nil
            if not no_write then
                self:write(collection_name)
            end
            return true
        end
    else
        local do_write
        for _, coll in pairs(self.coll) do
            if coll[file] then
                coll[file] = nil
                do_write = true
            end
        end
        if do_write then
            if not no_write then
                self:write()
            end
            return true
        end
    end
end

function ReadCollection:removeItems(files) -- FM: delete files
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

function ReadCollection:removeItemsByPath(path) -- FM: delete folder
    local do_write
    for coll_name, coll in pairs(self.coll) do
        for file_name in pairs(coll) do
            if util.stringStartsWith(file_name, path) then
                coll[file_name] = nil
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

function ReadCollection:updateItem(file, new_filepath) -- FM: rename file, move file
    file = FFIUtil.realpath(file) or file
    local do_write
    for coll_name, coll in pairs(self.coll) do
        if coll[file] then
            self:_updateItem(coll_name, file, new_filepath)
            do_write = true
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:updateItems(files, new_path) -- FM: move files
    local do_write
    for file in pairs(files) do
        file = FFIUtil.realpath(file) or file
        for coll_name, coll in pairs(self.coll) do
            if coll[file] then
                self:_updateItem(coll_name, file, nil, new_path)
                do_write = true
            end
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:updateItemsByPath(path, new_path) -- FM: rename folder, move folder
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

-- manage collections

function ReadCollection:addCollection(coll_name)
    local max_order = 0
    for _, order in pairs(self.coll_order) do
        if max_order < order then
            max_order = order
        end
    end
    self.coll_order[coll_name] = max_order + 1
    self.coll[coll_name] = {}
    self:write(coll_name)
end

function ReadCollection:renameCollection(coll_name, new_name)
    self.coll_order[new_name] = self.coll_order[coll_name]
    self.coll[new_name] = self.coll[coll_name]
    self.coll_order[coll_name] = nil
    self.coll[coll_name] = nil
    self:write(new_name)
end

function ReadCollection:removeCollection(coll_name)
    self.coll_order[coll_name] = nil
    self.coll[coll_name] = nil
    self:write()
end

function ReadCollection:updateCollectionListOrder(ordered_coll)
    for i, item in ipairs(ordered_coll) do
        self.coll_order[item.name] = i
    end
    self:write()
end

ReadCollection:_read()

return ReadCollection
