local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local dump = require("dump")
local joinPath = require("ffi/util").joinPath
local lfs = require("libs/libkoreader-lfs")
local realpath = require("ffi/util").realpath

local history_file = joinPath(DataStorage:getDataDir(), "history.lua")

local ReadHistory = {
    hist = {},
    last_read_time = 0,
}

local function buildEntry(input_time, input_file)
    return {
        time = input_time,
        text = input_file:gsub(".*/", ""),
        file = realpath(input_file) or input_file, -- keep orig file path of deleted files
        dim = lfs.attributes(input_file, "mode") ~= "file", -- "dim", as expected by Menu
        callback = function()
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(input_file)
        end
    }
end

local function fileFirstOrdering(l, r)
    if l.file == r.file then
        return l.time > r.time
    else
        return l.file < r.file
    end
end

local function timeFirstOrdering(l, r)
    if l.time == r.time then
        return l.file < r.file
    else
        return l.time > r.time
    end
end

function ReadHistory:_indexing(start)
    assert(self ~= nil)
    -- TODO(Hzj_jie): Use binary search to find an item when deleting it.
    for i = start, #self.hist, 1 do
        self.hist[i].index = i
    end
end

function ReadHistory:_sort()
    assert(self ~= nil)
    local autoremove_deleted_items_from_history =
        not G_reader_settings:nilOrFalse("autoremove_deleted_items_from_history")
    if autoremove_deleted_items_from_history then
        self:clearMissing()
    end
    table.sort(self.hist, fileFirstOrdering)
    -- TODO(zijiehe): Use binary insert instead of a loop to deduplicate.
    for i = #self.hist, 2, -1 do
        if self.hist[i].file == self.hist[i - 1].file then
            table.remove(self.hist, i)
        end
    end
    table.sort(self.hist, timeFirstOrdering)
    self:_indexing(1)
end

-- Reduces total count in hist list to a reasonable number by removing last
-- several items.
function ReadHistory:_reduce()
    assert(self ~= nil)
    while #self.hist > 500 do
        table.remove(self.hist, #self.hist)
    end
end

-- Flushes current history table into file.
function ReadHistory:_flush()
    assert(self ~= nil)
    local content = {}
    for k, v in pairs(self.hist) do
        content[k] = {
            time = v.time,
            file = v.file
        }
    end
    local f = io.open(history_file, "w")
    f:write("return " .. dump(content) .. "\n")
    f:close()
end

--- Reads history table from file.
-- @treturn boolean true if the history_file has been updated and reloaded.
function ReadHistory:_read()
    assert(self ~= nil)
    local history_file_modification_time = lfs.attributes(history_file, "modification")
    if history_file_modification_time == nil
    or history_file_modification_time <= self.last_read_time then
        return false
    end
    self.last_read_time = history_file_modification_time
    local ok, data = pcall(dofile, history_file)
    if ok and data then
        for k, v in pairs(data) do
            table.insert(self.hist, buildEntry(v.time, v.file))
        end
    end
    return true
end

-- Reads history from legacy history folder
function ReadHistory:_readLegacyHistory()
    assert(self ~= nil)
    local history_dir = DataStorage:getHistoryDir()
    for f in lfs.dir(history_dir) do
        local path = joinPath(history_dir, f)
        if lfs.attributes(path, "mode") == "file" then
            path = DocSettings:getPathFromHistory(f)
            if path ~= nil and path ~= "" then
                local file = DocSettings:getNameFromHistory(f)
                if file ~= nil and file ~= "" then
                    table.insert(
                        self.hist,
                        buildEntry(lfs.attributes(joinPath(history_dir, f), "modification"),
                                   joinPath(path, file)))
                end
            end
        end
    end
end

function ReadHistory:_init()
    assert(self ~= nil)
    self:reload()
end

function ReadHistory:clearMissing()
    assert(self ~= nil)
    for i = #self.hist, 1, -1 do
        if self.hist[i].file == nil or lfs.attributes(self.hist[i].file, "mode") ~= "file" then
            table.remove(self.hist, i)
        end
    end
end

function ReadHistory:removeItemByPath(path)
    assert(self ~= nil)
    for i = #self.hist, 1, -1 do
        if self.hist[i].file == path then
            self:removeItem(self.hist[i])
            break
        end
    end
end

function ReadHistory:updateItemByPath(old_path, new_path)
    assert(self ~= nil)
    for i = #self.hist, 1, -1 do
        if self.hist[i].file == old_path then
            self.hist[i].file = new_path
            self:_flush()
            self.hist[i].callback = function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(new_path)
            end
            break
        end
    end
end

function ReadHistory:removeItem(item)
    assert(self ~= nil)
    table.remove(self.hist, item.index)
    os.remove(DocSettings:getHistoryPath(item.file))
    self:_indexing(item.index)
    self:_flush()
end

function ReadHistory:addItem(file)
    assert(self ~= nil)
    if file ~= nil and lfs.attributes(file, "mode") == "file" then
        table.insert(self.hist, 1, buildEntry(os.time(), file))
        -- TODO(zijiehe): We do not need to sort if we can use binary insert and
        -- binary search.
        self:_sort()
        self:_reduce()
        self:_flush()
    end
end

function ReadHistory:setDeleted(item)
    assert(self ~= nil)
    if self.hist[item.index] then
        self.hist[item.index].dim = true
    end
end

--- Reloads history from history_file.
-- @treturn boolean true if history_file has been updated and reload happened.
function ReadHistory:reload()
    assert(self ~= nil)
    if self:_read() then
        self:_readLegacyHistory()
        self:_sort()
        self:_reduce()
        return true
    end

    return false
end

ReadHistory:_init()

return ReadHistory
