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

-- Найти файлы синхронизации для других форматов этой же книги
-- @param doc_path - путь к текущей книге
-- @param history_items - список книг из истории KOReader (можно получить через G_reader_settings или историю)
-- @return массив найденных наборов закладок из других форматов
function SyncDB.findMatchingSyncFiles(doc_path)
    local base_name = SyncDB.getBaseName(doc_path)
    logger.dbg("bookmarks_sync: Searching for matches for base_name: '", base_name, "'")
    local matching_bookmarks = {}
    local search_scope = G_reader_settings:readSetting("bookmarks_sync_search_scope") or "all"
    logger.dbg("bookmarks_sync: Using search scope:", search_scope)

    local candidate_files = {}

    if search_scope == "all" or search_scope == "known" then
        -- 1. Книги из глобального кэша настроек (источник для "Все закладки")
        local all_doc_settings = G_reader_settings:readSetting("doc_settings") or {}
        logger.dbg("bookmarks_sync: Found", util.tableSize(all_doc_settings), "books in the global settings cache.")
        for filepath, _ in pairs(all_doc_settings) do
            candidate_files[filepath] = true
        end

        -- 2. Книги из истории чтения
        local history = ReadHistory.hist or {}
        logger.dbg("bookmarks_sync: Found", #history, "books in the reading history.")
        for _, item in ipairs(history) do
            candidate_files[item.file] = true
        end
    end

    if search_scope == "all" or search_scope == "folder" then
        -- 3. Книги из папки текущей книги и ее подпапок (по вашему предложению)
        -- Это найдет книги, которые еще не были открыты, но могут иметь файлы синхронизации.
        local book_dir, _ = util.splitFilePathName(doc_path)
        logger.dbg("bookmarks_sync: Also scanning the current book's directory:", book_dir)

        local function scan_directory_for_books(dir)
            logger.dbg("bookmarks_sync: [SCAN] Attempting to scan directory:", dir)
            if not dir then
                logger.warn("bookmarks_sync: [SCAN] Directory path is nil. Aborting scan for this path.")
                return
            end
            local dir_attr = lfs.attributes(dir)
            if not dir_attr or dir_attr.mode ~= "directory" then
                logger.warn("bookmarks_sync: [SCAN] Path is not a directory or is inaccessible:", dir)
                return
            end

            logger.dbg("bookmarks_sync: [SCAN] Directory exists. Iterating contents...")
            local iter, err = lfs.dir(dir)
            if not iter then
                logger.err("bookmarks_sync: [SCAN] lfs.dir failed for path:", dir, "Error:", err)
                return
            end

            for item in iter, err do
                logger.dbg("bookmarks_sync: [SCAN] Found item in directory:", item)
                if item ~= "." and item ~= ".." then
                    local full_path = dir:gsub("/$", "") .. "/" .. item
                    local attr = lfs.attributes(full_path)
                    if attr and attr.mode == "directory" then
                        pcall(scan_directory_for_books, full_path) -- recursive call, wrapped in pcall for safety
                    elseif attr and attr.mode == "file" and item:lower():match("%.(epub|pdf|fb2|mobi|djvu|xps|cbz|cbt|cbr|txt|html|rtf)$") then
                        logger.dbg("bookmarks_sync: [SCAN] Found candidate book file:", full_path)
                        candidate_files[full_path] = true
                    end
                end
            end
            logger.dbg("bookmarks_sync: [SCAN] Finished iterating directory:", dir)
        end

        -- We wrap the initial call in pcall to catch any top-level errors that lfs.dir might not
        local ok, err = pcall(scan_directory_for_books, book_dir)
        if not ok then
            logger.err("bookmarks_sync: [SCAN] A critical error occurred during directory scan:", err)
        end
    end

    logger.dbg("bookmarks_sync: Total unique candidate books for sync check:", util.tableSize(candidate_files))

    for filepath, _ in pairs(candidate_files) do
        -- Пропускаем текущий открытый документ
        if filepath == doc_path then
            goto continue
        end

        -- У книги есть закладки. Теперь проверим, является ли она той же самой книгой,
        -- что и открытая сейчас, но в другом формате. Для этого мы используем наш файл синхронизации,
        -- так как он хранит каноническое имя и историю переименований.
        local sync_file_path = SyncDB.getSyncFilePath(filepath)
        if sync_file_path and lfs.attributes(sync_file_path, "mode") == "file" then
            local sync_settings = LuaSettings:open(sync_file_path)
            local other_basename = sync_settings:readSetting("current_basename")

            -- Дополнительная проверка: если у файла синхронизации нет basename, он бесполезен
            if not other_basename then
                goto continue
            end

            local other_history = sync_settings:readSetting("basenames_history") or {}

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
                local other_bookmarks = sync_settings:readSetting("bookmarks") or {}
                if #other_bookmarks > 0 then
                    logger.dbg("bookmarks_sync: Found a match with book:", filepath)
                    table.insert(matching_bookmarks, {
                        filepath = filepath,
                        bookmarks = other_bookmarks
                    })
                end
            end
        end

        ::continue::
    end

    return matching_bookmarks
end

return SyncDB
