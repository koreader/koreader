local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local md5 = require("ffi/sha2").md5
local util = require("util")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local SyncDB = {}

-- Получить базовое имя файла без расширения
function SyncDB.getBaseName(filepath)
    if not filepath then return "" end
    local _, filename = util.splitFilePathName(filepath)
    if not filename then return "" end
    return filename:gsub("%.%w+$", "")
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
        bookmarks = settings:readSetting("bookmarks") or {}
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
                logger.info("bookmarks_sync: Обнаружено переименование книги. Старое имя добавлено в историю:", existing.current_basename)
            end
        end
    end
    
    local settings = LuaSettings:open(filepath)
    settings:saveSetting("book_id", current_id)
    settings:saveSetting("current_basename", base_name)
    settings:saveSetting("basenames_history", history)
    settings:saveSetting("bookmarks", bookmarks)
    settings:flush()
    
    return true
end

-- Найти файлы синхронизации для других форматов этой же книги
-- @param doc_path - путь к текущей книге
-- @param history_items - список книг из истории KOReader (можно получить через G_reader_settings или историю)
-- @return массив найденных наборов закладок из других форматов
function SyncDB.findMatchingSyncFiles(doc_path)
    local base_name = SyncDB.getBaseName(doc_path)
    local matching_bookmarks = {}
    
    -- Для поиска совпадений нам нужно пройти по истории открывавшихся книг.
    -- В KOReader история хранится в G_reader_settings под ключом "history".
    local history = G_reader_settings:readSetting("history") or {}
    
    for filepath, _ in pairs(history) do
        -- Игнорируем саму текущую книгу
        if filepath ~= doc_path then
            local other_sdr = DocSettings:getSidecarDir(filepath)
            local other_sync_file = other_sdr and (other_sdr .. "/bookmarks_sync.lua")
            
            if other_sync_file and lfs.attributes(other_sync_file, "mode") == "file" then
                local other_settings = LuaSettings:open(other_sync_file)
                local other_basename = other_settings:readSetting("current_basename")
                local other_history = other_settings:readSetting("basenames_history") or {}
                
                -- Проверяем совпадение текущего имени с именем или историей имен другой книги
                local is_match = (other_basename == base_name)
                if not is_match then
                    for _, hist_name in ipairs(other_history) do
                        if hist_name == base_name then
                            is_match = true
                            break
                        end
                    end
                end
                
                if is_match then
                    local other_bookmarks = other_settings:readSetting("bookmarks") or {}
                    logger.info("bookmarks_sync: Найдено совпадение с книгой:", filepath)
                    table.insert(matching_bookmarks, {
                        filepath = filepath,
                        bookmarks = other_bookmarks
                    })
                end
            end
        end
    end
    
    return matching_bookmarks
end

return SyncDB
