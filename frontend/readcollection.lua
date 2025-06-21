local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local LuaSettings = require("luasettings")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local collection_file = DataStorage:getSettingsDir() .. "/collection.lua"

local ReadCollection = {
    coll = nil, -- hash table
    coll_settings = nil, -- hash table
    last_read_time = 0,
    default_collection_name = "favorites",
}

-- read, write

local function buildEntry(file, order, attr)
    file = ffiUtil.realpath(file)
    if file then
        attr = attr or lfs.attributes(file)
        if attr and attr.mode == "file" then
            return {
                file  = file,
                text  = file:gsub(".*/", ""),
                order = order,
                attr  = attr,
            }
        end
    end
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
    self.coll_settings = {}
    local updated_collections = {}
    for coll_name, collection in pairs(collections.data) do
        local coll = {}
        for _, v in ipairs(collection) do
            local item = buildEntry(v.file, v.order)
            if item then -- exclude deleted files
                coll[item.file] = item
            end
        end
        self.coll[coll_name] = coll
        self.coll_settings[coll_name] = collection.settings or { order = 1 } -- favorites, first run
        if self:updateCollectionFromFolder(coll_name) > 0 then
            updated_collections[coll_name] = true
        end
    end
    if next(updated_collections) ~= nil then
        self:write(updated_collections)
    end
end

function ReadCollection:write(updated_collections)
    local collections = LuaSettings:open(collection_file)
    for coll_name in pairs(collections.data) do
        if not self.coll[coll_name] then
            collections:delSetting(coll_name)
        end
    end
    for coll_name, coll in pairs(self.coll) do
        if updated_collections == nil or updated_collections[1] or updated_collections[coll_name] then
            local is_manual_collate = not self.coll_settings[coll_name].collate or nil
            local data = { settings = self.coll_settings[coll_name] }
            for _, item in pairs(coll) do
                table.insert(data, { file = item.file, order = is_manual_collate and item.order })
            end
            collections:saveSetting(coll_name, data)
        end
    end
    logger.dbg("ReadCollection: writing to collection file")
    collections:flush()
end

function ReadCollection:updateLastBookTime(file)
    file = ffiUtil.realpath(file)
    if file then
        local now = os.time()
        for _, coll in pairs(self.coll) do
            if coll[file] then
                coll[file].attr.access = now
            end
        end
    end
end

-- info

function ReadCollection:isFileInCollection(file, collection_name)
    file = ffiUtil.realpath(file) or file
    return self.coll[collection_name] and self.coll[collection_name][file] and true or false
end

function ReadCollection:isFileInCollections(file, ignore_show_mark_setting)
    if ignore_show_mark_setting or G_reader_settings:nilOrTrue("collection_show_mark") then
        file = ffiUtil.realpath(file) or file
        for _, coll in pairs(self.coll) do
            if coll[file] then
                return true
            end
        end
    end
    return false
end

function ReadCollection:getCollectionsWithFile(file)
    file = ffiUtil.realpath(file) or file
    local collections = {}
    for coll_name, coll in pairs(self.coll) do
        if coll[file] then
            collections[coll_name] = true
        end
    end
    return collections
end

function ReadCollection:getCollectionNextOrder(collection_name)
    if self.coll_settings[collection_name].collate then return end
    local max_order = 0
    for _, item in pairs(self.coll[collection_name]) do
        if max_order < item.order then
            max_order = item.order
        end
    end
    return max_order + 1
end

-- manage items

function ReadCollection:addItem(file, collection_name, attr)
    local item = buildEntry(file, self:getCollectionNextOrder(collection_name), attr)
    self.coll[collection_name][item.file] = item
end

function ReadCollection:addRemoveItemMultiple(file, collections_to_add)
    file = ffiUtil.realpath(file) or file
    local attr
    for coll_name, coll in pairs(self.coll) do
        if collections_to_add[coll_name] then
            if not coll[file] then
                attr = attr or lfs.attributes(file)
                coll[file] = buildEntry(file, self:getCollectionNextOrder(coll_name), attr)
            end
        else
            if coll[file] then
                coll[file] = nil
            end
        end
    end
end

function ReadCollection:addItemsMultiple(files, collections_to_add)
    local count = 0
    for file in pairs(files) do
        file = ffiUtil.realpath(file) or file
        local attr
        for coll_name in pairs(collections_to_add) do
            local coll = self.coll[coll_name]
            if not coll[file] then
                attr = attr or lfs.attributes(file)
                coll[file] = buildEntry(file, self:getCollectionNextOrder(coll_name), attr)
                count = count + 1
            end
        end
    end
    return count
end

function ReadCollection:removeItem(file, collection_name, no_write) -- FM: delete file; FMColl: remove file
    file = ffiUtil.realpath(file) or file
    if collection_name then
        if self.coll[collection_name][file] then
            self.coll[collection_name][file] = nil
            if not no_write then
                self:write({ collection_name = true })
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
    new_filepath = new_filepath or new_path .. "/" .. item_old.text
    local item = buildEntry(new_filepath, item_old.order, item_old.attr) -- no lfs call
    coll[item.file] = item
    coll[file_name] = nil
end

function ReadCollection:updateItem(file, new_filepath) -- FM: rename file, move file
    file = ffiUtil.realpath(file) or file
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
        file = ffiUtil.realpath(file) or file
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

function ReadCollection:updateCollectionFromFolder(collection_name, folders)
    folders = folders or self.coll_settings[collection_name].folders
    local count = 0
    if folders then
        local coll = self.coll[collection_name]
        local filetypes
        local str = util.tableGetValue(self.coll_settings[collection_name], "filter", "add", "filetype")
        if str then -- string of comma separated file types
            filetypes = {}
            for filetype in util.gsplit(str, ",") do
                filetypes[util.trim(filetype)] = true
            end
        end
        local function add_item_callback(file, f, attr)
            file = ffiUtil.realpath(file)
            local does_match = coll[file] == nil and not util.stringStartsWith(f, "._")
                and (filetypes or DocumentRegistry:hasProvider(file))
            if does_match then
                if filetypes then
                    local _, fileext = require("apps/filemanager/filemanagerutil").splitFileNameType(file)
                    does_match = filetypes[fileext]
                end
                if does_match then
                    self:addItem(file, collection_name, attr)
                    count = count + 1
                end
            end
        end
        for folder, folder_settings in pairs(folders) do
            util.findFiles(folder, add_item_callback, folder_settings.subfolders)
        end
    end
    return count
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
end

-- manage collections

function ReadCollection:addCollection(coll_name)
    local max_order = 0
    for _, settings in pairs(self.coll_settings) do
        if max_order < settings.order then
            max_order = settings.order
        end
    end
    self.coll_settings[coll_name] = { order = max_order + 1 }
    self.coll[coll_name] = {}
end

function ReadCollection:renameCollection(coll_name, new_name)
    self.coll_settings[new_name] = self.coll_settings[coll_name]
    self.coll[new_name] = self.coll[coll_name]
    self.coll_settings[coll_name] = nil
    self.coll[coll_name] = nil
end

function ReadCollection:removeCollection(coll_name)
    self.coll_settings[coll_name] = nil
    self.coll[coll_name] = nil
end

function ReadCollection:updateCollectionListOrder(ordered_coll)
    for i, item in ipairs(ordered_coll) do
        self.coll_settings[item.name].order = i
    end
end

ReadCollection:_read()

return ReadCollection
