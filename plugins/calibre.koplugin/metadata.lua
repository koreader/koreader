--[[
    This module implements functions for loading, saving and editing calibre metadata files.

    Calibre uses JSON to store metadata on device after each wired transfer.
    In wireless transfers calibre sends the same metadata to the client, which is in charge
    of storing it.
--]]

local rapidjson = require("rapidjson")
local logger = require("logger")
local util = require("util")

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
function CalibreMetadata:loadDeviceInfo()
    local json, err = rapidjson.load(self.driveinfo)
    if not json then
        logger.warn("Unable to load device info from JSON file:", err)
        return {}
    end
    return json
end

-- saves driveinfo to JSON file
function CalibreMetadata:saveDeviceInfo(arg)
    -- keep previous device name, if any
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
    -- remove metadata we don't need
    metadata.thumbnail = nil
    metadata.cover = nil
    table.insert(self.books, #self.books + 1, metadata)
end

-- remove a book from our books table
function CalibreMetadata:removeBook(lpath)
    for i, v in ipairs(self.books) do
        if v.lpath == lpath then
            table.remove(self.books, i)
        end
    end
end

-- gets the uuid and index of a book from its path
function CalibreMetadata:getBookUuid(lpath)
    for i, v in ipairs(self.books) do
        if v.lpath == lpath then
            return v.uuid, i
        end
    end
    return "none"
end

-- gets the book id at the given index
function CalibreMetadata:getBookId(index)
    local book = {}
    book.priKey = index
    for _, v in pairs({ "uuid", "lpath", "last_modified"}) do
        book[v] = self.books[index][v]
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
    for i, v in ipairs(self.books) do
        local book = self.path .. "/" .. v.lpath
        if not util.fileExists(book) then
            logger.dbg("prunning book from DB at index", i, "path", book)
            self:removeBook(v.lpath)
            count = count + 1
        end
    end
    if count > 0 then
        self:saveBookList()
    end
    return count
end

-- cleans all temp data stored for current library.
function CalibreMetadata:clean()
    self.books = {}
    self.drive = {}
    self.path = nil
    self.driveinfo = nil
    self.metadata = nil
end

-- gets the last modification of the metadata for a given dir.
function CalibreMetadata:getTimestamp(dir)
    if not dir then return end
    local ok1, __, metadata = findCalibreFiles(dir)
    if not ok1 then return end
    return lfs.attributes(metadata, "modification")
end

-- initialize a directory as a calibre library.

-- This is the main function. Call it to initialize a calibre library
-- in a given path. It will find calibre files if they're on disk and
-- try to load info from them.

-- NOTE: you should care about the books table, because it could be huge.
-- If you're not working with the metadata directly (ie: in wireless connections)
-- you should copy relevant data to another table and free this one to keep things tidy.

function CalibreMetadata:init(dir, needs_metadata)
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
    elseif needs_metadata then
        -- no metadata to load
        return false
    end
    local deleted_count = self:prune()
    local elapsed = socket.gettime() - start
    logger.info(string.format(
        "calibre info loaded from disk in %f milliseconds: %d books. %d pruned",
        elapsed * 1000, #self.books, deleted_count))
    return true
end

return CalibreMetadata
