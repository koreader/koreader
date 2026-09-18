local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local md5 = require("ffi/sha2").md5
local util = require("util")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local ReadHistory = require("readhistory")

local SyncDB = {}

-- Получить базовое имя файла без расширения
function SyncDB.getBaseName(filepath)
    if not filepath then return "" end
    local _, filename = util.splitFilePathName(filepath)
    if not filename then return "" end
    return util.trim(filename:gsub("%.%w+$", ""))
end

-- Получить путь к файлу bookmarks_sync.lua для конкретной книги
function SyncDB.getSyncFilePath(doc_path)
    -- getSidecarDir возвращает путь к SDR-папке
    local sdr_dir = DocSettings:getSidecarDir(doc_path)
    if not sdr_dir then return nil end
    return sdr_dir .. "/bookmarks_sync.lua"
end

-- Загрузить данные синхронизации из файла настроек книги
function SyncDB.loadBookSync(doc_path)
    local filepath = SyncDB.getSyncFilePath(doc_path)
    if not filepath or lfs.attributes(filepath, "mode") ~= "file" then
        return nil
    end
    
    local settings = LuaSettings:open(filepath)
    local data = {
        book_id = settings:readSetting("book_id"),
        current_basename = settings:readSetting("current_basename"),
        basenames_history = settings:readSetting("basenames_history") or {},
        bookmarks = settings:readSetting("bookmarks") or {},
    }
    return data
end

-- Сохранить данные синхронизации в файл настроек книги
-- @param doc_path - путь к книге
-- @param bookmarks - массив нормализованных закладок
function SyncDB.saveBookSync(doc_path, bookmarks)
    local filepath = SyncDB.getSyncFilePath(doc_path)
    if not filepath then return false end
    
    local base_name = SyncDB.getBaseName(doc_path)
    local current_id = md5(base_name)
    
    -- Загружаем существующие данные, чтобы сохранить историю имен
    local existing = SyncDB.loadBookSync(doc_path)
    local history = {}
    
    if existing then
        history = existing.basenames_history or {}
        -- Если имя изменилось, добавляем старое имя в историю
        if existing.current_basename and existing.current_basename ~= base_name then
            local found = false
            for _, name in ipairs(history) do
                if name == existing.current_basename then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(history, existing.current_basename)
                logger.dbg("bookmarks_sync: Book renamed. Adding old name to history:", existing.current_basename)
            end
        end
    end
    
    local settings = LuaSettings:open(filepath)
    settings:saveSetting("book_id", current_id)
    settings:saveSetting("current_basename", base_name)
    settings:saveSetting("basenames_history", history)
    settings:saveSetting("bookmarks", bookmarks)
    settings:flush()
    logger.dbg("bookmarks_sync: Saved", #bookmarks, "bookmarks to sync file for", doc_path)
    
    return true
end

return SyncDB
