local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local getFriendlySize = require("util").getFriendlySize
local lfs = require("libs/libkoreader-lfs")
local realpath = require("ffi/util").realpath
local util = require("frontend/util")

local collection_file = DataStorage:getSettingsDir() .. "/collection.lua"

local ReadCollection = {}

function ReadCollection:read(collections)
    local collection_handle = LuaSettings:open(collection_file)
    local coll = collection_handle:readSetting(collections) or {}
    local coll_max_item = 0

    for _, v in pairs(coll) do
        if v.order > coll_max_item then
            coll_max_item = v.order
        end
    end
    return coll, coll_max_item
end

function ReadCollection:readAllCollection()
    local collection = LuaSettings:open(collection_file)
    if collection and collection.data then
        return collection.data
    else
        return {}
    end
end

function ReadCollection:prepareList(collection)
    local data = self:read(collection)
    local list = {}
    for _, v in pairs(data) do
        local file_exists = lfs.attributes(v.file, "mode") == "file"
        table.insert(list, {
            order = v.order,
            text = v.file:gsub(".*/", ""),
            file = realpath(v.file) or v.file, -- keep orig file path of deleted files
            dim = not file_exists, -- "dim", as expected by Menu
            mandatory = file_exists and getFriendlySize(lfs.attributes(v.file, "size") or 0),
            callback = function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(v.file)
            end
        })
    end
    table.sort(list, function(v1,v2)
        return v1.order < v2.order
    end)
    return list
end

function ReadCollection:removeItemByPath(path, is_dir)
    local dir
    local should_write = false
    if is_dir then
        path = path .. "/"
    end
    local coll = self:readAllCollection()
    for i, _ in pairs(coll) do
        local single_collection = coll[i]
        for item = #single_collection, 1, -1 do
            if not is_dir and single_collection[item].file == path then
                should_write = true
                table.remove(single_collection, item)
            elseif is_dir then
                dir = util.splitFilePathName(single_collection[item].file)
                if dir == path then
                    should_write = true
                    table.remove(single_collection, item)
                end
            end
        end
    end
    if should_write then
        local collection = LuaSettings:open(collection_file)
        collection.data = coll
        collection:flush()
    end
end

function ReadCollection:updateItemByPath(old_path, new_path)
    local is_dir = false
    local dir, file
    if lfs.attributes(new_path, "mode") == "directory" then
        is_dir = true
        old_path = old_path .. "/"
    end
    local should_write = false
    local coll = self:readAllCollection()
    for i, j in pairs(coll) do
        for k, v in pairs(j) do
            if not is_dir and v.file == old_path then
                should_write = true
                coll[i][k].file = new_path
            elseif is_dir then
                dir, file = util.splitFilePathName(v.file)
                if dir == old_path then
                    should_write = true
                    coll[i][k].file = string.format("%s/%s", new_path, file)
                end
            end
        end
    end
    if should_write then
        local collection = LuaSettings:open(collection_file)
        collection.data = coll
        collection:flush()
    end
end

function ReadCollection:removeItem(item, collection)
    local coll = self:read(collection)
    for k, v in pairs(coll) do
        if v.file == item then
            table.remove(coll, k)
            break
        end
    end
    self:writeCollection(coll, collection)
end

function ReadCollection:writeCollection(coll_items, coll)
    local collection = LuaSettings:open(collection_file)
    collection:saveSetting(coll, coll_items)
    collection:flush()
end

function ReadCollection:addItem(file, collection)
    local coll, coll_max_item = self:read(collection)
    coll_max_item = coll_max_item + 1
    local collection_item =
    {
        file = file,
        order = coll_max_item
    }
    table.insert(coll, collection_item)
    self:writeCollection(coll, collection)
end

function ReadCollection:checkItemExist(item, collection)
    local coll = self:read(collection)
    for _, v in pairs(coll) do
        if v.file == item then
            return true
        end
    end
    return false
end

return ReadCollection

