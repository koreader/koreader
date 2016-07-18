local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local joinPath = require("ffi/util").joinPath
local dump = require("dump")

local history_file = joinPath(DataStorage:getDataDir(), "history.lua")

local ReadHistory = {
    hist = {},
}

local function buildEntry(input_time, input_file)
    return {
        time = input_time,
        text = input_file:gsub(".*/", ""),
        file = input_file,
        callback = function()
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(input_file)
        end
    }
end

function ReadHistory:_sort()
    for i = #self.hist, 1, -1 do
        if lfs.attributes(self.hist[i].file, "mode") ~= "file" then
            table.remove(self.hist, i)
        end
    end
    table.sort(self.hist, function(l, r) return l.file < r.file end)
    -- TODO(zijiehe): Use binary insert instead of a loop to deduplicate.
    for i = #self.hist, 2, -1 do
        if self.hist[i].file == self.hist[i - 1].file then
            if self.hist[i].time < self.hist[i - 1].time then
                table.remove(self.hist, i)
            else
                table.remove(self.hist,i - 1)
            end
        end
    end
    table.sort(self.hist, function(v1, v2) return v1.time > v2.time end)
    -- TODO(zijiehe): Use binary search to find an item when deleting it.
    for i = 1, #self.hist, 1 do
        self.hist[i].index = i
    end
end

-- Reduces total count in hist list to a reasonable number by removing last
-- several items.
function ReadHistory:_reduce()
    while #self.hist > 500 do
        table.remove(self.hist, #self.hist)
    end
end

-- Flushes current history table into file.
function ReadHistory:_flush()
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

-- Reads history table from file
function ReadHistory:_read()
    local ok, data = pcall(dofile, history_file)
    if ok then
        for k, v in pairs(data) do
            table.insert(self.hist, buildEntry(v.time, v.file))
        end
    end
end

-- Reads history from legacy history folder
function ReadHistory:_readLegacyHistory()
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
                        buildEntry(lfs.attributes(path, "modification"),
                                   joinPath(path, file)))
                end
            end
        end
    end
end

function ReadHistory:_init()
    self:_read()
    self:_readLegacyHistory()
    self:_sort()
    self:_reduce()
end

function ReadHistory:removeItem(item)
    table.remove(self.hist, item.index)
    os.remove(DocSettings:getHistoryPath(item.file))
    self:_flush()
end

function ReadHistory:addItem(file)
    if file ~= nil and lfs.attributes(file, "mode") == "file" then
        table.insert(self.hist, 1, buildEntry(os.time(), file))
        -- TODO(zijiehe): We do not need to sort if we can use binary insert and
        -- binary search.
        self:_sort()
        self:_reduce()
        self:_flush()
    end
end

ReadHistory:_init()

return ReadHistory
