--[[--
This module implements functions for loading, saving and editing calibre metadata files.

Calibre uses JSON to store metadata on device after each wired transfer.
In wireless transfers calibre sends the same metadata to the client, which is in charge
of storing it.

@module koplugin.calibre.metadata
--]]--

local TimeVal = require("ui/timeval")
local lfs = require("libs/libkoreader-lfs")
local rapidjson = require("rapidjson")
local logger = require("logger")
local parser = require("parser")
local util = require("util")

local used_metadata = {
    "uuid",
    "lpath",
    "last_modified",
    "size",
    "title",
    "authors",
    "tags",
    "series",
    "series_index"
}

-- The search metadata cache requires an even smaller subset
local search_used_metadata = {
    "lpath",
    "size",
    "title",
    "authors",
    "tags",
    "series",
    "series_index"
}

local function slim(book, is_search)
    local slim_book = {}
    for _, k in ipairs(is_search and search_used_metadata or used_metadata) do
        if k == "series" or k == "series_index" then
            slim_book[k] = book[k] or rapidjson.null
        elseif k == "tags" then
            slim_book[k] = book[k] or {}
        else
            slim_book[k] = book[k]
        end
    end
    return slim_book
end

-- this is the max file size we attempt to decode using json. For larger
-- files we want to attempt to manually parse the file to avoid OOM errors
local MAX_JSON_FILESIZE = 30 * 1000 * 1000

--- find calibre files for a given dir
local function findCalibreFiles(dir)
    local function existOrLast(file)
        local fullname
        local options = { file, "." .. file }
        for _, option in ipairs(options) do
            fullname = dir .. "/" .. option
            if util.fileExists(fullname) then
                return true, fullname
            end
        end
        return false, fullname
    end
    local ok_meta, file_meta = existOrLast("metadata.calibre")
    local ok_drive, file_drive = existOrLast("driveinfo.calibre")
    return ok_meta, ok_drive, file_meta, file_drive
end

local CalibreMetadata = {
    -- info about the library itself. It should
    -- hold a table with the contents of "driveinfo.calibre"
    drive = {},
    -- info about the books in this library. It should
    -- hold a table with the contents of "metadata.calibre"
    books = {},
}

--- loads driveinfo from JSON file
function CalibreMetadata:loadDeviceInfo(file)
    if not file then file = self.driveinfo end
    local json, err = rapidjson.load(file)
    if not json then
        logger.warn("Unable to load device info from JSON file:", err)
        return {}
    end
    return json
end

-- saves driveinfo to JSON file
function CalibreMetadata:saveDeviceInfo(arg)
    -- keep previous device name. This allow us to identify the calibre driver used.
    -- "Folder" is used by connect to folder
    -- "KOReader" is used by smart device app
    -- "Amazon", "Kobo", "Bq" ... are used by platform device drivers
    local previous_name = self.drive.device_name
    self.drive = arg
    if previous_name then
        self.drive.device_name = previous_name
    end
    rapidjson.dump(self.drive, self.driveinfo)
end

-- loads books' metadata from JSON file
function CalibreMetadata:loadBookList()
    local attr = lfs.attributes(self.metadata)
    if not attr then
        logger.warn("Unable to get file attributes from JSON file:", self.metadata)
        return {}
    end
    local valid = attr.mode == "file" and attr.size > 0
    if not valid then
        logger.warn("File is invalid", self.metadata)
        return {}
    end
    local books, err
    if attr.size > MAX_JSON_FILESIZE then
        books, err = parser.parseFile(self.metadata)
    else
        books, err = rapidjson.load(self.metadata)
    end
    if not books then
        logger.warn(string.format("Unable to load library from json file %s: \n%s",
            self.metadata, err))
        return {}
    end
    return books
end

-- saves books' metadata to JSON file
function CalibreMetadata:saveBookList()
    local file = self.metadata
    local books = self.books
    rapidjson.dump(rapidjson.array(books), file, { pretty = true })
end

-- add a book to our books table
function CalibreMetadata:addBook(book)
    table.insert(self.books, #self.books + 1, slim(book))
end

-- remove a book from our books table
function CalibreMetadata:removeBook(lpath)
    local function drop_lpath(t, i, j)
        return t[i].lpath ~= lpath
    end
    util.arrayRemove(self.books, drop_lpath)
end

-- gets the uuid and index of a book from its path
function CalibreMetadata:getBookUuid(lpath)
    for index, book in ipairs(self.books) do
        if book.lpath == lpath then
            return book.uuid, index
        end
    end
    return "none"
end

-- gets the book id at the given index
function CalibreMetadata:getBookId(index)
    local book = {}
    book.priKey = index
    for _, key in ipairs({"uuid", "lpath", "last_modified"}) do
        book[key] = self.books[index][key]
    end
    return book
end

-- gets the book metadata at the given index
function CalibreMetadata:getBookMetadata(index)
    return self.books[index]
end

-- removes deleted books from table
function CalibreMetadata:prune()
    local count = 0
    for index, book in ipairs(self.books) do
        local path = self.path .. "/" .. book.lpath
        if not util.fileExists(path) then
            logger.dbg("prunning book from DB at index", index, "path", path)
            self:removeBook(book.lpath)
            count = count + 1
        end
    end
    if count > 0 then
        self:saveBookList()
    end
    return count
end

-- removes unused metadata from books
function CalibreMetadata:cleanUnused(is_search)
    for index, book in ipairs(self.books) do
        self.books[index] = slim(book, is_search)
    end

    -- We don't want to stomp on the library's actual JSON db for metadata searches.
    if is_search then
        return
    end

    self:saveBookList()
end

-- cleans all temp data stored for current library.
function CalibreMetadata:clean()
    self.books = {}
    self.drive = {}
    self.path = nil
    self.driveinfo = nil
    self.metadata = nil
end

-- get keys from driveinfo.calibre
function CalibreMetadata:getDeviceInfo(dir, kind)
    if not dir or not kind then return end
    local _, ok_drive, __, driveinfo = findCalibreFiles(dir)
    if not ok_drive then return end
    local drive = self:loadDeviceInfo(driveinfo)
    if drive then
        return drive[kind]
    end
end

-- initialize a directory as a calibre library.

-- This is the main function. Call it to initialize a calibre library
-- in a given path. It will find calibre files if they're on disk and
-- try to load info from them.

-- NOTE: Take special notice of the books table, because it could be huge.
-- If you're not working with the metadata directly (ie: in wireless connections)
-- you should copy relevant data to another table and free this one to keep things tidy.

function CalibreMetadata:init(dir, is_search)
    if not dir then return end
    local start = TimeVal:now()
    self.path = dir
    local ok_meta, ok_drive, file_meta, file_drive = findCalibreFiles(dir)
    self.driveinfo = file_drive
    if ok_drive then
        self.drive = self:loadDeviceInfo()
    end
    self.metadata = file_meta
    if ok_meta then
        self.books = self:loadBookList()
    elseif is_search then
        -- no metadata to search
        return false
    end

    local msg
    if is_search then
        self:cleanUnused(is_search)
        msg = string.format("(search) in %.3f milliseconds: %d books",
            TimeVal:getDurationMs(start), #self.books)
    else
        local deleted_count = self:prune()
        self:cleanUnused()
        msg = string.format("in %.3f milliseconds: %d books. %d pruned",
            TimeVal:getDurationMs(start), #self.books, deleted_count)
    end
    logger.info(string.format("calibre info loaded from disk %s", msg))
    return true
end

return CalibreMetadata
