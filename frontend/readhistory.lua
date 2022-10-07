local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local dump = require("dump")
local ffiutil = require("ffi/util")
local util = require("util")
local joinPath = ffiutil.joinPath
local lfs = require("libs/libkoreader-lfs")
local realpath = ffiutil.realpath

local history_file = joinPath(DataStorage:getDataDir(), "history.lua")

-- This is a singleton
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
    return {
        time = input_time,
        file = file_path,
        text = input_file:gsub(".*/", ""),
        dim = lfs.attributes(file_path, "mode") ~= "file", -- "dim", as expected by Menu
        mandatory_func = function() -- Show the last read time
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
        end,
    }
end

function ReadHistory:getIndexByFile(item_file)
    for i, v in ipairs(self.hist) do
        if item_file == v.file then
            return i
        end
    end
end

function ReadHistory:getIndexByTime(item_time)
    local hist_nb = #self.hist
    if hist_nb == 0 then
        return 1
    end
    if item_time >= self.hist[1].time then
        return 1
    elseif item_time < self.hist[hist_nb].time then
        return hist_nb + 1
    end
    -- binary search (returns min index when several elements equal item_time)
    local s, e, m, d = 1, hist_nb
    while s <= e do
        m = math.floor((s + e) / 2)
        if item_time < self.hist[m].time then
            s, d = m + 1, 1
        elseif item_time >= self.hist[m].time then
            e, d = m - 1, 0
        end
    end
    return m + d
end

--- Reduces number of history items to the required limit by removing old items.
function ReadHistory:_reduce()
    local history_size = G_reader_settings:readSetting("history_size") or 500
    while #self.hist > history_size do
        table.remove(self.hist)
    end
end

--- Saves history table to a file.
function ReadHistory:_flush()
    local content = {}
    for _, v in ipairs(self.hist) do
        table.insert(content, {
            time = v.time,
            file = v.file
        })
    end
    local f = io.open(history_file, "w")
    if f then
        f:write("return " .. dump(content) .. "\n")
        ffiutil.fsyncOpenedFile(f) -- force flush to the storage device
        f:close()
    end
end

--- Reads history table from file.
-- @treturn boolean true if the history_file has been updated and reloaded.
function ReadHistory:_read(force_read)
    local history_file_modification_time = lfs.attributes(history_file, "modification")
    if history_file_modification_time == nil
            or (not force_read and (history_file_modification_time <= self.last_read_time)) then
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

--- Reads history from legacy history folder.
function ReadHistory:_readLegacyHistory()
    local history_dir = DataStorage:getHistoryDir()
    for f in lfs.dir(history_dir) do
        local path = joinPath(history_dir, f)
        if lfs.attributes(path, "mode") == "file" then
            path = DocSettings:getPathFromHistory(f)
            if path ~= nil and path ~= "" then
                local file = DocSettings:getNameFromHistory(f)
                if file ~= nil and file ~= "" then
                    local item_path = joinPath(path, file)
                    local real_path = realpath(item_path)
                    local item_time = lfs.attributes(joinPath(history_dir, f), "modification")
                    local index = self:getIndexByTime(item_time)
                    if self.hist[index].file ~= real_path then
                        while index <= #self.hist -- sort alhabetically
                                and self.hist[index].time == item_time
                                and self.hist[index].file < real_path do
                            index = index + 1
                        end
                        table.insert(self.hist, index, buildEntry(item_time, item_path))
                    end
                end
            end
        end
    end
end

function ReadHistory:_init()
    self:reload()
end

function ReadHistory:ensureLastFile()
    local last_existing_file
    for _, v in ipairs(self.hist) do
        if lfs.attributes(v.file, "mode") == "file" then
            last_existing_file = v.file
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
    for _, v in ipairs(self.hist) do
        -- skip current document and deleted items kept in history
        if v.file ~= current_file and lfs.attributes(v.file, "mode") == "file" then
            return v.file
        end
    end
end

--- Used in the BookShortcuts plugin.
function ReadHistory:getFileByDirectory(directory, recursive)
    local real_path = realpath(directory)
    for _, v in ipairs(self.hist) do
        local ipath = realpath(ffiutil.dirname(v.file))
        if ipath == real_path or (recursive and util.stringStartsWith(ipath, real_path)) then
             return v.file
        end
    end
end

--- Updates the history list after deleting a file.
function ReadHistory:fileDeleted(path)
    local index = self:getIndexByFile(path)
    if index then
        if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
            self:removeItem(self.hist[index], index)
        else
            self.hist[index].dim = true
            self:ensureLastFile()
        end
    end
end

--- Removes the history item if the document settings has been reset.
function ReadHistory:fileSettingsPurged(path)
    if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
        -- Also remove it from history on purge when that setting is enabled
        self:removeItemByPath(path)
    end
end

--- Checks the history list for deleted files and removes history items respectively.
function ReadHistory:clearMissing()
    local history_updated
    for i, v in ipairs(self.hist) do
        if v.file == nil or lfs.attributes(v.file, "mode") ~= "file" then
            self:removeItem(v, i, true) -- no flush
            history_updated = true
        end
    end
    if history_updated then
        self:_flush()
        self:ensureLastFile()
    end
end

function ReadHistory:removeItemByPath(path)
    local index = self:getIndexByFile(path)
    if index then
        self:removeItem(self.hist[index], index)
    end
end

function ReadHistory:updateItemByPath(old_path, new_path)
    local index = self:getIndexByFile(old_path)
    if index then
        self.hist[index].file = new_path
        self.hist[index].text = new_path:gsub(".*/", "")
        self.hist[index].callback = function()
            selectCallback(new_path)
        end
        self:_flush()
        self:reload(true)
    end
    if G_reader_settings:readSetting("lastfile") == old_path then
        G_reader_settings:saveSetting("lastfile", new_path)
    end
    self:ensureLastFile()
end

function ReadHistory:removeItem(item, idx, no_flush)
    local index = idx or self:getIndexByTime(item.time)
    table.remove(self.hist, index)
    os.remove(DocSettings:getHistoryPath(item.file))
    if not no_flush then
        self:_flush()
        self:ensureLastFile()
    end
end

--- Adds new item (last opened document) to the top of the history list.
function ReadHistory:addItem(file, ts)
    if file ~= nil and lfs.attributes(file, "mode") == "file" then
        local now = ts or os.time()
        local mtime = lfs.attributes(file, "modification")
        lfs.touch(file, now, mtime)
        local index = self:getIndexByFile(realpath(file))
        if index == 1 then -- last book
            self.hist[1].time = now
        else -- old or new book
            if index then -- old book
                table.remove(self.hist, index)
            end
            table.insert(self.hist, 1, buildEntry(now, file))
            self:_reduce()
            G_reader_settings:saveSetting("lastfile", file)
        end
        self:_flush()
    end
end

--- Reloads history from history_file.
-- @treturn boolean true if history_file has been updated and reload happened.
function ReadHistory:reload(force_read)
    if self:_read(force_read) then
        self:_readLegacyHistory()
        self:_reduce()
        return true
    end

    return false
end

ReadHistory:_init()

return ReadHistory
