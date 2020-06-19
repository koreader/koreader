--[[
    This module implements functions for loading, saving and editing calibre metadata files.

    Calibre uses JSON to store metadata on device after each wired transfer.
    In wireless transfers calibre sends the same metadata to the client, which is in charge
    of storing it.
--]]

local rapidjson = require("rapidjson")
local logger = require("logger")
local util = require("util")

local unused_metadata = {
    "application_id",
    "author_link_map",
    "author_sort",
    "author_sort_map",
    "book_producer",
    "comments",
    "cover",
    "db_id",
    "identifiers",
    "languages",
    "pubdate",
    "publication_type",
    "publisher",
    "rating",
    "rights",
    "thumbnail",
    "timestamp",
    "title_sort",
    "user_categories",
    "user_metadata",
    "_series_sort_",
}

--- find calibre files for a given dir
local function findCalibreFiles(dir)
    local function existOrLast(file)
        local fullname
        local options = { file, "." .. file }
        for _, option in pairs(options) do
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
    local json, err = rapidjson.load(self.metadata)
    if not json then
        logger.warn("Unable to load book list from JSON file:", self.metadata, err)
        return {}
    end
    return json
end

-- saves books' metadata to JSON file
function CalibreMetadata:saveBookList()
    -- replace bad table values with null
    local file = self.metadata
    local books = self.books
    for index, book in ipairs(books) do
        for key, item in pairs(book) do
            if type(item) == "function" then
                books[index][key] = rapidjson.null
            end
        end
    end
    rapidjson.dump(rapidjson.array(books), file, { pretty = true })
end

-- add a book to our books table
function CalibreMetadata:addBook(metadata)
    for _, key in pairs(unused_metadata) do
        metadata[key] = nil
    end
    table.insert(self.books, #self.books + 1, metadata)
end

-- remove a book from our books table
function CalibreMetadata:removeBook(lpath)
    for index, book in ipairs(self.books) do
        if book.lpath == lpath then
            table.remove(self.books, index)
        end
    end
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
    for _, key in pairs({ "uuid", "lpath", "last_modified"}) do
        book[key] = self.books[index][key]
    end
    return book
end

-- gets the book metadata at the given index
function CalibreMetadata:getBookMetadata(index)
    local book = self.books[index]
    for key, value in pairs(book) do
        if type(value) == "function" then
            book[key] = rapidjson.null
        end
    end
    return book
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
function CalibreMetadata:cleanUnused()
    local slim_books = self.books
    for index, _ in ipairs(slim_books) do
        for _, key in pairs(unused_metadata) do
            slim_books[index][key] = nil
        end
    end
    self.books = slim_books
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

-- NOTE: you should care about the books table, because it could be huge.
-- If you're not working with the metadata directly (ie: in wireless connections)
-- you should copy relevant data to another table and free this one to keep things tidy.

function CalibreMetadata:init(dir, is_search)
    if not dir then return end
    local socket = require("socket")
    local start = socket.gettime()
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

    local deleted_count = self:prune()
    local elapsed = socket.gettime() - start
    logger.info(string.format(
        "calibre info loaded from disk in %f milliseconds: %d books. %d pruned",
        elapsed * 1000, #self.books, deleted_count))
    if not is_search then
        self:cleanUnused()
    end
    return true
end

return CalibreMetadata
