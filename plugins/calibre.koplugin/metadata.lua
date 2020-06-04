--[[ This module handles calibre metadata. ]]--

local JSON = require("json")
local logger = require("logger")
local util = require("util")

-- calibre uses JSON to store metadata on device after each wired transfer.
-- In wireless transfers it sends the same metadata to the client, which is
-- in charge of storing it.

--- loads a table from a JSON file
-- @string full path of the file to load
-- @treturn table
local function loadJSON(file)
    if not file then return end
    local f = io.open(file, "r")
    if not f then return end
    local data = f:read("*a")
    f:close()
    local ok, json = pcall(JSON.decode, data)
    if ok then return json end
    logger.warn("Unable to load book list from JSON file", file)
end

--- saves a table to a JSON file
-- @table data to save
-- @string file to store the data
-- @treturn boolean true if saved, nil otherwise
local function saveJSON(data, file)
    if not data or not file then return end
    local f = io.open(file, "w")
    if not f then return end
    local ok, json = pcall(JSON.encode, data)
    if not ok then
        logger.warn("Unable to save lua table", data, "to JSON file", file)
        return
    end
    f:write(json)
    f:close()
    return true
end

--- find calibre files for a given dir
local function findCalibreFiles(dir)
    local checkFile = function(t)
        local file
        for _, v in pairs(t) do
            file = dir .. "/" .. v
            if util.fileExists(file) then
                return true, file
            end
        end
        return false, file
    end
    local ok1, driveinfo = checkFile({"driveinfo.calibre", ".driveinfo.calibre"})
    local ok2, metadata = checkFile({"metadata.calibre", ".metadata.calibre"})
    if not ok1 or not ok2 then
        return false, driveinfo, metadata
    else
        return true, driveinfo, metadata
    end
end

local CalibreMetadata = {
    -- info about the library itself. It should
    -- hold a table with the contents of "driveinfo.calibre"
    drive = {},
    -- info about the books in this library. It should
    -- hold a table with the contents of "metadata.calibre"
    books = {},
}

-- sets device info from calibre
function CalibreMetadata:setDeviceInfo(arg)
    self.drive = arg
    logger.dbg("saved device info to file", self.driveinfo)
    saveJSON(self.drive, self.driveinfo)
end

-- loads the book list from disk
function CalibreMetadata:loadBookList()
    local t = loadJSON(self.metadata) or {}
    logger.dbg(string.format("loaded %d books from %s", #t, self.metadata))
    return t
end

-- saves the book list to disk
function CalibreMetadata:saveBookList()
    logger.dbg(string.format("saved %d books to %s", #self.books, self.metadata))
    return saveJSON(self.books, self.metadata)
end

-- add a book to our books table
function CalibreMetadata:addBook(metadata)
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

-- initialize a directory as a calibre library.

-- This is the main function. Call it to initialize a calibre library
-- in a given path. It will find calibre files if they're on disk and
-- try to load info from them. It will return true if it contains valid
-- calibre metadata and false otherwise.

-- NOTE: If the initialization returns true you should care about the books table,
-- because it could be huge. If you're not working with the metadata directly
-- (ie: in wireless connections) you should copy relevant data to another table
-- and free this one to keep things tidy.

function CalibreMetadata:init(dir)
    if not dir then
        self:clean()
        return false
    else
        self.path = dir
    end
    local ok
    ok, self.driveinfo, self.metadata = findCalibreFiles(dir)
    if not ok then
        self:clean()
        return false
    end
    self.drive = loadJSON(self.driveinfo) or {}
    self.books = loadJSON(self.metadata) or {}
    local deleted_count = self:prune()
    logger.info(string.format("calibre info loaded from disk: %d books. %d pruned",
        #self.books, deleted_count))
    return true
end

return CalibreMetadata
