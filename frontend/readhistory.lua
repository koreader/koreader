local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local dump = require("dump")
local ffiutil = require("ffi/util")
local util = require("util")
local joinPath = ffiutil.joinPath
local lfs = require("libs/libkoreader-lfs")
local realpath = ffiutil.realpath

local history_file = joinPath(DataStorage:getDataDir(), "history.lua")

local ReadHistory = {
    hist = {},
    last_read_time = 0,
}

local function selectCallback(path)
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(path)
end

local function buildEntry(input_time, input_file)
    local file_path = realpath(input_file) or input_file -- keep orig file path of deleted files
    local file_exists = lfs.attributes(file_path, "mode") == "file"
    return {
        time = input_time,
        text = input_file:gsub(".*/", ""),
        file = file_path,
        dim = not file_exists, -- "dim", as expected by Menu
        -- mandatory = file_exists and util.getFriendlySize(lfs.attributes(input_file, "size") or 0),
        mandatory_func = function() -- Show the last read time (rather than file size)
            local readerui_instance = require("apps/reader/readerui"):_getRunningInstance()
            local currently_opened_file = readerui_instance and readerui_instance.document and readerui_instance.document.file
            local last_read_ts
            if file_path == currently_opened_file then
                -- Don't use the sidecar file date which is updated regularly while
                -- reading: keep showing the opening time for the current document.
                last_read_ts = input_time
            else
                -- For past documents, the last save time of the settings is better
                -- as last read time than input_time (its last opening time, that
                -- we fallback to it no sidecar file)
                last_read_ts = DocSettings:getLastSaveTime(file_path) or input_time
            end
            return util.secondsToDate(last_read_ts, G_reader_settings:isTrue("twelve_hour_clock"))
        end,
        select_enabled_func = function()
            return lfs.attributes(file_path, "mode") == "file"
        end,
        callback = function()
            selectCallback(input_file)
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
    --- @todo (Hzj_jie): Use binary search to find an item when deleting it.
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
    --- @todo (zijiehe): Use binary insert instead of a loop to deduplicate.
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
    for _, v in ipairs(self.hist) do
        table.insert(content, {
            time = v.time,
            file = v.file
        })
    end
    local f = io.open(history_file, "w")
    f:write("return " .. dump(content) .. "\n")
    ffiutil.fsyncOpenedFile(f) -- force flush to the storage device
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
        self.hist = {}
        for _, v in ipairs(data) do
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

function ReadHistory:ensureLastFile()
    local last_existing_file = nil
    for i=1, #self.hist do
        if lfs.attributes(self.hist[i].file, "mode") == "file" then
            last_existing_file = self.hist[i].file
            break
        end
    end
    G_reader_settings:saveSetting("lastfile", last_existing_file)
end

function ReadHistory:getLastFile()
    self:ensureLastFile()
    return G_reader_settings:readSetting("lastfile")
end

function ReadHistory:getPreviousFile(current_file)
    -- Get last or previous file in history that is not current_file
    -- (self.ui.document.file, probided as current_file, might have
    -- been removed from history)
    if not current_file then
        current_file = G_reader_settings:readSetting("lastfile")
    end
    for i=1, #self.hist do
        -- skip current document and deleted items kept in history
        local file = self.hist[i].file
        if file ~= current_file and lfs.attributes(file, "mode") == "file" then
            return file
        end
    end
end

function ReadHistory:fileDeleted(path)
    if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
        self:removeItemByPath(path)
    else
        -- Make it dimed
        for i=1, #self.hist do
            if self.hist[i].file == path then
                self.hist[i].dim = true
                break
            end
        end
        self:ensureLastFile()
    end
end

function ReadHistory:fileSettingsPurged(path)
    if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
        -- Also remove it from history on purge when that setting is enabled
        self:removeItemByPath(path)
    end
end

function ReadHistory:clearMissing()
    assert(self ~= nil)
    for i = #self.hist, 1, -1 do
        if self.hist[i].file == nil or lfs.attributes(self.hist[i].file, "mode") ~= "file" then
            self:removeItem(self.hist[i], i)
        end
    end
    self:ensureLastFile()
end

function ReadHistory:removeItemByPath(path)
    assert(self ~= nil)
    for i = #self.hist, 1, -1 do
        if self.hist[i].file == path then
            self:removeItem(self.hist[i])
            break
        end
    end
    self:ensureLastFile()
end

function ReadHistory:updateItemByPath(old_path, new_path)
    assert(self ~= nil)
    for i = #self.hist, 1, -1 do
        if self.hist[i].file == old_path then
            self.hist[i].file = new_path
            self.hist[i].text = new_path:gsub(".*/", "")
            self:_flush()
            self.hist[i].callback = function()
                selectCallback(new_path)
            end
            break
        end
    end
    if G_reader_settings:readSetting("lastfile") == old_path then
        G_reader_settings:saveSetting("lastfile", new_path)
    end
    self:ensureLastFile()
end

function ReadHistory:removeItem(item, idx)
    assert(self ~= nil)
    table.remove(self.hist, item.index or idx)
    os.remove(DocSettings:getHistoryPath(item.file))
    self:_indexing(item.index or idx)
    self:_flush()
    self:ensureLastFile()
end

function ReadHistory:addItem(file, ts)
    assert(self ~= nil)
    if file ~= nil and lfs.attributes(file, "mode") == "file" then
        local now = ts or os.time()
        table.insert(self.hist, 1, buildEntry(now, file))
        --- @todo (zijiehe): We do not need to sort if we can use binary insert and
        -- binary search.
        -- util.execute("/bin/touch", "-a", file)
        -- This emulates `touch -a` in LuaFileSystem's API, since it may be absent (Android)
        -- or provided by busybox, which doesn't support the `-a` flag.
        local mtime = lfs.attributes(file, "modification")
        lfs.touch(file, now, mtime)
        self:_sort()
        self:_reduce()
        self:_flush()
        G_reader_settings:saveSetting("lastfile", file)
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
