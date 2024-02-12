local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local datetime = require("datetime")
local dump = require("dump")
local ffiutil = require("ffi/util")
local util = require("util")
local joinPath = ffiutil.joinPath
local lfs = require("libs/libkoreader-lfs")
local realpath = ffiutil.realpath
local C_ = require("gettext").pgettext

local history_file = joinPath(DataStorage:getDataDir(), "history.lua")

-- This is a singleton
local ReadHistory = {
    hist = {},
    last_read_time = 0,
}

local function getMandatory(date_time)
    return G_reader_settings:isTrue("history_datetime_short")
        and os.date(C_("Date string", "%y-%m-%d"), date_time) or datetime.secondsToDateTime(date_time)
end

local function buildEntry(input_time, input_file)
    local file_path = realpath(input_file) or input_file -- keep orig file path of deleted files
    local file_exists = lfs.attributes(file_path, "mode") == "file"
    return {
        time = input_time,
        file = file_path,
        text = input_file:gsub(".*/", ""),
        dim = not file_exists,
        mandatory = getMandatory(input_time),
        select_enabled = file_exists,
    }
end

function ReadHistory:getIndexByFile(item_file)
    for i, v in ipairs(self.hist) do
        if item_file == v.file then
            return i
        end
    end
end

--- Returns leftmost index of the entry with item_time using binary search
-- (items in history are sorted by time in reverse order).
-- If several entries have equal time, search within them by item_file in alphabetical order.
-- If there are no entries with item_time, returns insertion index.
function ReadHistory:getIndexByTime(item_time, item_file)
    local hist_nb = #self.hist
    if hist_nb == 0 then
        return 1
    end
    if item_time > self.hist[1].time then
        return 1
    elseif item_time < self.hist[hist_nb].time then
        return hist_nb + 1
    end
    local s, e, m, d = 1, hist_nb
    while s <= e do
        m = bit.rshift(s + e, 1)
        if item_time < self.hist[m].time then
            s, d = m + 1, 1
        else
            e, d = m - 1, 0
        end
    end
    local index = m + d
    if item_file then
        while index <= #self.hist
                and self.hist[index].time == item_time
                and self.hist[index].file:gsub(".*/", "") < item_file do
            index = index + 1
        end
    end
    return index
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
            file = v.file,
        })
    end
    util.writeToFile(dump(content), history_file, true, true)
    self:ensureLastFile()
end

--- Reads history table from file.
-- @treturn boolean true if the history_file has been updated and reloaded.
function ReadHistory:_read(force_read)
    local history_file_modification_time = lfs.attributes(history_file, "modification")
    if history_file_modification_time == nil then -- no history_file, proceed legacy only
        return true
    end
    if force_read or (history_file_modification_time > self.last_read_time) then
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
end

--- Reads history from legacy history folder and remove it iff empty.
-- Legacy history file is deleted when respective book is opened or deleted.
function ReadHistory:_readLegacyHistory()
    local history_dir = DataStorage:getHistoryDir()
    if not lfs.attributes(history_dir) then return end
    local history_updated
    for f in lfs.dir(history_dir) do
        local legacy_history_file = joinPath(history_dir, f)
        if lfs.attributes(legacy_history_file, "mode") == "file" then
            local item_path = DocSettings:getFileFromHistory(f)
            if item_path then
                local item_time = lfs.attributes(legacy_history_file, "modification")
                if self:addItem(item_path, item_time, true) then
                    history_updated = true
                end
            end
        end
    end
    if history_updated then
        self:_reduce()
        self:_flush()
    end
    os.remove(history_dir)
end

function ReadHistory:ensureLastFile()
    local last_existing_file
    for _, v in ipairs(self.hist) do
        if v.select_enabled then
            last_existing_file = v.file
            break
        end
    end
    G_reader_settings:saveSetting("lastfile", last_existing_file)
end

--- Get last or previous file in history that is not current_file
-- (self.ui.document.file, provided as current_file, might have
-- been removed from history).
function ReadHistory:getPreviousFile(current_file)
    if not current_file then
        current_file = G_reader_settings:readSetting("lastfile")
    end
    for _, v in ipairs(self.hist) do
        -- skip current document and deleted items kept in history
        if v.file ~= current_file and v.select_enabled then
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

--- Updates the history list after renaming/moving a file.
function ReadHistory:updateItem(file, new_filepath)
    local index = self:getIndexByFile(file)
    if index then
        local item = self.hist[index]
        item.file = new_filepath
        item.text = new_filepath:gsub(".*/", "")
        self:_flush()
    end
end

function ReadHistory:updateItems(files, new_path) -- files = { filepath = true, }
    local history_updated
    for file in pairs(files) do
        local index = self:getIndexByFile(file)
        if index then
            local item = self.hist[index]
            item.file = new_path .. "/" .. item.text
            history_updated = true
        end
    end
    if history_updated then
        self:_flush()
    end
end

--- Updates the history list after renaming/moving a folder.
function ReadHistory:updateItemsByPath(old_path, new_path)
    local len = #old_path
    local history_updated
    for i, v in ipairs(self.hist) do
        if v.file:sub(1, len) == old_path then
            self.hist[i].file = new_path .. v.file:sub(len + 1)
            history_updated = true
        end
    end
    if history_updated then
        self:_flush()
    end
end

--- Updates the history list after deleting a file.
function ReadHistory:fileDeleted(path_or_index)
    local index
    local is_single = type(path_or_index) == "string"
    if is_single then -- deleting single file, path passed
        index = self:getIndexByFile(path_or_index)
    else -- deleting folder, index passed
        index = path_or_index
    end
    if index then
        if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
            self:removeItem(self.hist[index], index, not is_single) -- flush immediately when deleting single file only
        else
            self.hist[index].dim = true
            self.hist[index].select_enabled = false
            if is_single then
                self:ensureLastFile()
            end
        end
    end
end

--- Updates the history list after deleting a folder.
function ReadHistory:folderDeleted(path)
    local history_updated
    for i = #self.hist, 1, -1 do
        local file = self.hist[i].file
        if util.stringStartsWith(file, path) then
            self:fileDeleted(i)
            history_updated = true
            DocSettings.updateLocation(file) -- remove sdr if not in book location
        end
    end
    if history_updated then
        if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
            self:_flush()
        else
            self:ensureLastFile()
        end
    end
end

function ReadHistory:removeItems(files) -- files = { filepath = true, }
    local history_updated
    for file in pairs(files) do
        local index = self:getIndexByFile(file)
        if index then
            self:fileDeleted(index)
            history_updated = true
        end
    end
    if history_updated then
        if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
            self:_flush()
        else
            self:ensureLastFile()
        end
    end
end

--- Removes the history item if the document settings has been reset.
function ReadHistory:fileSettingsPurged(path)
    if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
        self:removeItemByPath(path)
    end
end

--- Checks the history list for deleted files and removes history items respectively.
function ReadHistory:clearMissing()
    local history_updated
    for i = #self.hist, 1, -1 do
        local file = self.hist[i].file
        if file == nil or lfs.attributes(file, "mode") ~= "file" then
            self:removeItem(self.hist[i], i, true) -- no flush
            history_updated = true
        end
    end
    if history_updated then
        self:_flush()
    end
end

function ReadHistory:removeItemByPath(path)
    local index = self:getIndexByFile(path)
    if index then
        self:removeItem(self.hist[index], index)
    end
end

function ReadHistory:removeItem(item, idx, no_flush)
    local index = idx or self:getIndexByTime(item.time, item.file:gsub(".*/", ""))
    table.remove(self.hist, index)
    os.remove(DocSettings:getHistoryPath(item.file))
    if not no_flush then
        self:_flush()
    end
end

--- Adds new item (last opened document) to the top of the history list.
-- If item time (ts) is passed, add item to the history list at this time position.
function ReadHistory:addItem(file, ts, no_flush)
    file = realpath(file)
    if not file or (ts and lfs.attributes(file, "mode") ~= "file") then
        return -- bad legacy item
    end
    local index = self:getIndexByFile(file)
    if ts and index and self.hist[index].time == ts then
        return -- legacy item already added
    end
    local now = ts or os.time()
    local mtime = lfs.attributes(file, "modification")
    lfs.touch(file, now, mtime) -- update book access time for sorting by last read date
    if index == 1 and not ts then -- last book, update access time only
        self.hist[1].time = now
        self.hist[1].mandatory = getMandatory(now)
    else -- old or new book
        if index then -- old book
            table.remove(self.hist, index)
        end
        index = ts and self:getIndexByTime(ts, file:gsub(".*/", "")) or 1
        table.insert(self.hist, index, buildEntry(now, file))
    end
    if not no_flush then
        self:_reduce()
        self:_flush()
    end
    return true -- used while adding legacy items
end

--- Updates last book access time on closing the document.
function ReadHistory:updateLastBookTime(no_flush)
    local now = os.time()
    self.hist[1].time = now
    self.hist[1].mandatory = getMandatory(now)
    if not no_flush then
        self:_flush()
    end
end

function ReadHistory:updateDateTimeString()
    for _, v in ipairs(self.hist) do
        v.mandatory = getMandatory(v.time)
    end
end

--- Reloads history from history_file and legacy history folder.
function ReadHistory:reload(force_read)
    if self:_read(force_read) then
        self:_readLegacyHistory()
        if G_reader_settings:isTrue("autoremove_deleted_items_from_history") then
            self:clearMissing()
        end
        self:_reduce()
    end
end

function ReadHistory:_init()
    self:reload()
end

ReadHistory:_init()

return ReadHistory
