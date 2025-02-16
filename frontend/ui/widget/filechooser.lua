local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

-- NOTE: It's our caller's responsibility to setup a title bar and pass it to us via custom_title_bar (c.f., FileManager)
local FileChooser = BookList:extend{
    path = lfs.currentdir(),
    show_path = true,
    parent = nil,
    show_finished    = G_reader_settings:readSetting("show_finished", true), -- books marked as finished
    show_hidden      = G_reader_settings:readSetting("show_hidden", false), -- folders/files starting with "."
    show_unsupported = G_reader_settings:readSetting("show_unsupported", false), -- set to true to ignore file_filter
    file_filter = nil, -- function defined in the caller, returns true for files to be shown
    -- NOTE: Input is *always* a relative entry name
    exclude_dirs = { -- const
        -- KOReader / Kindle
        "%.sdr$",
        -- Kobo
        "^%.adobe%-digital%-editions$",
        "^certificates$",
        "^custom%-dict$",
        "^dict$",
        "^iink$",
        "^kepub$",
        "^markups$",
        "^webstorage$",
        "^%.kobo%-images$",
        -- macOS
        "^%.fseventsd$",
        "^%.Trashes$",
        "^%.Spotlight%-V100$",
        -- *nix
        "^%.Trash$",
        "^%.Trash%-%d+$",
        -- Windows
        "^RECYCLED$",
        "^RECYCLER$",
        "^%$Recycle%.Bin$",
        "^System Volume Information$",
        -- Plato
        "^%.thumbnail%-previews$",
        "^%.reading%-states$",
    },
    exclude_files = { -- const
        -- Kobo
        "^BookReader%.sqlite",
        "^KoboReader%.sqlite",
        "^device%.salt%.conf$",
        -- macOS
        "^%.DS_Store$",
        -- *nix
        "^%.directory$",
        -- Windows
        "^Thumbs%.db$",
        -- Calibre
        "^driveinfo%.calibre$",
        "^metadata%.calibre$",
        -- Plato
        "^%.fat32%-epoch$",
        "^%.metadata%.json$",
    },
    path_items = nil, -- hash, store last browsed location (item index) for each path
    goto_letter = true,
}

-- Cache of content we knew of for directories that are not readable
-- (i.e. /storage/emulated/ on Android that we can meet when coming
-- from readable /storage/emulated/0/ - so we know it contains "0/")
local unreadable_dir_content = {}

function FileChooser:show_dir(dirname)
    for _, pattern in ipairs(self.exclude_dirs) do
        if dirname:match(pattern) then return false end
    end
    return true
end

function FileChooser:show_file(filename, fullpath)
    for _, pattern in ipairs(self.exclude_files) do
        if filename:match(pattern) then return false end
    end
    if not self.show_unsupported and self.file_filter ~= nil and not self.file_filter(filename) then return false end
    if not FileChooser.show_finished and fullpath ~= nil and BookList.getBookStatus(fullpath) == "complete" then return false end
    return true
end

function FileChooser:init()
    self.path_items = {}
    if lfs.attributes(self.path, "mode") ~= "directory" then
        self.path = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
    end
    BookList.init(self)
    self:refreshPath()
end

function FileChooser:getList(path, collate)
    local dirs, files = {}, {}
    -- lfs.dir directory without permission will give error
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if ok then
        unreadable_dir_content[path] = nil
        for f in iter, dir_obj do
            if FileChooser.show_hidden or not util.stringStartsWith(f, ".") then
                local fullpath = path.."/"..f
                local attributes = lfs.attributes(fullpath) or {}
                local item = true
                if attributes.mode == "directory" and f ~= "." and f ~= ".."
                        and self:show_dir(f) then
                    if collate then -- when collate == nil count only to display in folder mandatory
                        item = self:getListItem(path, f, fullpath, attributes, collate)
                    end
                    table.insert(dirs, item)
                -- Always ignore macOS resource forks.
                elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                        and self:show_file(f, fullpath) then
                    if collate then -- when collate == nil count only to display in folder mandatory
                        item = self:getListItem(path, f, fullpath, attributes, collate)
                    end
                    table.insert(files, item)
                end
            end
        end
    else -- error, probably "permission denied"
        if unreadable_dir_content[path] then
            -- Add this dummy item that will be replaced with a message by genItemTable()
            table.insert(dirs, self:getListItem(path, "./.", path, {}))
            -- If we knew about some content (if we had come up from them
            -- to this directory), have them shown
            for k, v in pairs(unreadable_dir_content[path]) do
                if v.attr and v.attr.mode == "directory" then
                    table.insert(dirs, v)
                else
                    table.insert(files, v)
                end
            end
        end
    end
    return dirs, files
end

function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local item = {
        text = f,
        path = fullpath,
        attr = attributes,
    }
    if attributes.mode == "file" then
        -- set to false to show all files in regular font
        -- set to "opened" to show opened files in bold
        -- otherwise, show new files in bold
        local show_file_in_bold = G_reader_settings:readSetting("show_file_in_bold")
        item.bidi_wrap_func = BD.filename
        item.is_file = true
        if collate.item_func ~= nil then
            local book_info = collate.bookinfo_required and BookList.getBookInfo(item.path)
            collate.item_func(item, book_info)
        end
        if show_file_in_bold ~= false then
            if item.opened == nil then -- could be set in item_func
                item.opened = BookList.hasBookBeenOpened(item.path)
            end
            item.bold = item.opened
            if show_file_in_bold ~= "opened" then
                item.bold = not item.bold
            end
        end
        item.dim = self.filemanager and self.filemanager.selected_files
                   and self.filemanager.selected_files[item.path]
        item.mandatory = self:getMenuItemMandatory(item, collate)
    else -- folder
        if item.text == "./." then -- added as content of an unreadable directory
            item.text = _("Current folder not readable. Some content may not be shown.")
        else
            item.text = item.text.."/"
            item.bidi_wrap_func = BD.directory
            if collate.can_collate_mixed and collate.item_func ~= nil then
                collate.item_func(item)
            end
            if dirpath then -- file browser or PathChooser
                item.mandatory = self:getMenuItemMandatory(item)
            end
        end
    end
    return item
end

function FileChooser:getCollate()
    local collate_id = G_reader_settings:readSetting("collate", "strcoll")
    local collate = self.collates[collate_id]
    if collate ~= nil then
        return collate, collate_id
    else
        G_reader_settings:saveSetting("collate", "strcoll")
        return self.collates.strcoll, "strcoll"
    end
end

function FileChooser:getSortingFunction(collate, reverse_collate)
    local sorting
    -- Only keep the cache if we're an *instance* of FileChooser
    if self ~= FileChooser then
        sorting, self.sort_cache = collate.init_sort_func(self.sort_cache)
    else
        sorting = collate.init_sort_func()
    end

    if reverse_collate then
        local sorting_unreversed = sorting
        sorting = function(a, b) return sorting_unreversed(b, a) end
    end

    return sorting
end

function FileChooser:clearSortingCache()
    self.sort_cache = nil
end

function FileChooser:genItemTableFromPath(path)
    local collate = self:getCollate()
    local dirs, files = self:getList(path, collate)
    return self:genItemTable(dirs, files, path)
end

function FileChooser:genItemTable(dirs, files, path)
    local collate = self:getCollate()
    local collate_mixed = G_reader_settings:isTrue("collate_mixed")
    local reverse_collate = G_reader_settings:isTrue("reverse_collate")
    local sorting = self:getSortingFunction(collate, reverse_collate)

    local item_table = {}
    if collate.can_collate_mixed and collate_mixed then
        table.move(dirs, 1, #dirs, 1, item_table)
        table.move(files, 1, #files, #item_table + 1, item_table)
        table.sort(item_table, sorting)
    else
        table.sort(files, sorting)
        if not collate.can_collate_mixed then -- keep folders sorted by name not reversed
            sorting = self:getSortingFunction(self.collates.strcoll)
        end
        table.sort(dirs, sorting)
        table.move(dirs, 1, #dirs, 1, item_table)
        table.move(files, 1, #files, #item_table + 1, item_table)
    end

    if path then -- file browser or PathChooser
        if path ~= "/" and not (G_reader_settings:isTrue("lock_home_folder") and
                                path == G_reader_settings:readSetting("home_dir")) then
            table.insert(item_table, 1, {
                text = BD.mirroredUILayout() and BD.ltr("../ ⬆") or "⬆ ../",
                path = path.."/..",
                is_go_up = true,
            })
        end
        if self.show_current_dir_for_hold then
            table.insert(item_table, 1, {
                text = _("Long-press here to choose current folder"),
                bold = true,
                path = path.."/.",
            })
        end
    end

    -- lfs.dir iterated node string may be encoded with some weird codepage on
    -- Windows we need to encode them to utf-8
    if ffi.os == "Windows" then
        for _, v in ipairs(item_table) do
            if v.text then
                v.text = ffiUtil.multiByteToUTF8(v.text) or ""
            end
        end
    end

    return item_table
end

function FileChooser:getMenuItemMandatory(item, collate)
    local text
    if collate then -- file
        if collate.mandatory_func ~= nil then
            text = collate.mandatory_func(item)
        else
            text = util.getFriendlySize(item.attr.size or 0)
        end
        if ReadCollection:isFileInCollections(item.path) then
            text = "☆ " .. text
        end
    else -- folder, count number of folders and files inside it
        local sub_dirs, dir_files = self:getList(item.path)
        text = T("%1 \u{F016}", #dir_files)
        if #sub_dirs > 0 then
            text = T("%1 \u{F114} ", #sub_dirs) .. text
        end
        if FileManagerShortcuts:hasFolderShortcut(item.path) then
            text = "☆ " .. text
        end
    end
    return text
end

function FileChooser:updateItems(select_number, no_recalculate_dimen)
    BookList.updateItems(self, select_number, no_recalculate_dimen) -- call parent's updateItems()
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
end

function FileChooser:refreshPath()
    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)

    local itemmatch
    if self.focused_path then
        itemmatch = {path = self.focused_path}
        -- We use focused_path only once, but remember it
        -- for CoverBrowser to re-apply it on startup if needed
        self.prev_focused_path = self.focused_path
        self.focused_path = nil
    end
    local subtitle = self.filemanager == nil and BD.directory(filemanagerutil.abbreviate(self.path))
    self:switchItemTable(nil, self:genItemTableFromPath(self.path), self.path_items[self.path], itemmatch, subtitle)
end

function FileChooser:changeToPath(path, focused_path)
    path = ffiUtil.realpath(path)
    self.path = path

    if focused_path then
        self.focused_path = focused_path
        -- We know focused_path is a child of path. In case path is
        -- not a readable directory, we can have focused_path shown,
        -- to allow the user to go back in it
        if not unreadable_dir_content[path] then
            unreadable_dir_content[path] = {}
        end
        if not unreadable_dir_content[path][focused_path] then
            unreadable_dir_content[path][focused_path] = {
                text = focused_path:sub(#path > 1 and #path+2 or 2),
                path = focused_path,
                attr = lfs.attributes(focused_path),
            }
        end
    end

    self:refreshPath()
    if self.filemanager then
        self.filemanager:handleEvent(Event:new("PathChanged", path))
    end
end

function FileChooser:goHome()
    local home_dir = G_reader_settings:readSetting("home_dir")
    if not home_dir or lfs.attributes(home_dir, "mode") ~= "directory" then
        -- Try some sane defaults, depending on platform
        home_dir = Device.home_dir
    end
    if home_dir then
        -- Jump to the first page if we're already home
        if self.path and home_dir == self.path then
            self:onGotoPage(1)
            -- Also pick up new content, if any.
            self:refreshPath()
        else
            self:changeToPath(home_dir)
        end
        return true
    end
end

function FileChooser:onFolderUp()
    if not (G_reader_settings:isTrue("lock_home_folder") and
            self.path == G_reader_settings:readSetting("home_dir")) then
        self:changeToPath(string.format("%s/..", self.path), self.path)
    end
end

function FileChooser:changePageToPath(path)
    if not path then return end
    for num, item in ipairs(self.item_table) do
        if not item.is_file and item.path == path then
            local page = math.floor((num-1) / self.perpage) + 1
            if page ~= self.page then
                self:onGotoPage(page)
            end
            break
        end
    end
end

function FileChooser:toggleShowFilesMode(mode)
    -- modes: "show_finished", "show_hidden", "show_unsupported"
    FileChooser[mode] = not FileChooser[mode]
    G_reader_settings:saveSetting(mode, FileChooser[mode])
    self:refreshPath()
end

function FileChooser:onMenuSelect(item)
    -- parent directory of dir without permission get nil mode
    -- we need to change to parent path in this case
    if item.is_file then
        self:onFileSelect(item)
    else
        self:changeToPath(item.path, item.is_go_up and self.path)
    end
    return true
end

function FileChooser:onMenuHold(item)
    self:onFileHold(item)
    return true
end

function FileChooser:onFileSelect(item)
    UIManager:close(self)
    return true
end

function FileChooser:onFileHold(item)
    return true
end

-- Used in ReaderStatus:onOpenNextDocumentInFolder().
function FileChooser:getNextFile(curr_file)
    local show_finished = FileChooser.show_finished
    FileChooser.show_finished = true
    local curr_path = curr_file:match(".*/"):gsub("/$", "")
    local item_table = self:genItemTableFromPath(curr_path)
    FileChooser.show_finished = show_finished
    local is_curr_file_found
    for i, item in ipairs(item_table) do
        if not is_curr_file_found and item.path == curr_file then
            is_curr_file_found = true
        end
        if is_curr_file_found then
            local next_file = item_table[i+1]
            if next_file and next_file.is_file and DocumentRegistry:hasProvider(next_file.path)
                    and BookList.getBookStatus(next_file.path) ~= "complete" then
                return next_file.path
            end
        end
    end
end

-- Used in file manager select mode to select all files in a folder,
-- that are visible in all file browser pages, without subfolders.
function FileChooser:selectAllFilesInFolder(do_select)
    for _, item in ipairs(self.item_table) do
        if item.is_file then
            if do_select then
                self.filemanager.selected_files[item.path] = true
                item.dim = true
            else
                item.dim = nil
            end
        end
    end
    self:updateItems(1, true)
end

return FileChooser
