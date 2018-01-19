local Device = require("device")
local DocSettings = require("docsettings")
local Font = require("ui/font")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")
local _ = require("gettext")
local Screen = Device.screen
local getFileNameSuffix = require("util").getFileNameSuffix
local getFriendlySize = require("util").getFriendlySize

ffi.cdef[[
int strcoll (const char *str1, const char *str2);
]]

-- string sort function respecting LC_COLLATE
local function strcoll(str1, str2)
    return ffi.C.strcoll(str1, str2) < 0
end

local function kobostrcoll(str1, str2)
    return str1 < str2
end

local FileChooser = Menu:extend{
    cface = Font:getFace("smallinfofont"),
    no_title = true,
    path = lfs.currentdir(),
    parent = nil,
    show_hidden = nil,
    exclude_dirs = {"%.sdr$"},
    collate = "strcoll", -- or collate = "access",
    reverse_collate = false,
    path_items = {}, -- store last browsed location(item index) for each path
    perpage = G_reader_settings:readSetting("items_per_page"),
}

function FileChooser:init()
    self.width = Screen:getWidth()
    -- common dir filter
    self.dir_filter = function(dirname)
        for _, pattern in ipairs(self.exclude_dirs) do
            if dirname:match(pattern) then return false end
        end
        return true
    end
    self.list = function(path, dirs, files)
        -- lfs.dir directory without permission will give error
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if ok then
            for f in iter, dir_obj do
                if self.show_hidden or not string.match(f, "^%.[^.]") then
                    local filename = path.."/"..f
                    local attributes = lfs.attributes(filename)
                    if attributes ~= nil then
                        if attributes.mode == "directory" and f ~= "." and f~=".." then
                            if self.dir_filter(filename) then
                                table.insert(dirs, {name = f,
                                                    suffix = getFileNameSuffix(f),
                                                    fullpath = filename,
                                                    attr = attributes})
                            end
                        elseif attributes.mode == "file" then
                            if self.file_filter == nil or self.file_filter(filename) then
                                local percent_finished = 0
                                if self.collate == "percent_unopened_first" or self.collate == "percent_unopened_last" then
                                    if DocSettings:hasSidecarFile(filename) then
                                        local docinfo = DocSettings:open(filename)
                                        percent_finished = docinfo.data.percent_finished
                                        if percent_finished == nil then
                                            percent_finished = 0
                                        end
                                    end
                                end
                                table.insert(files, {name = f,
                                                     suffix = getFileNameSuffix(f),
                                                     fullpath = filename,
                                                     attr = attributes,
                                                     percent_finished = percent_finished })
                            end
                        end
                    end
                end
            end
        end
    end

    local strcoll_func = strcoll
    -- circumvent string collating in Kobo devices. See issue koreader/koreader#686
    if Device:isKobo() then
        strcoll_func = kobostrcoll
    end
    self.strcoll = function(a, b)
        if a == nil and b == nil then
            return false
        elseif a == nil then
            return true
        elseif b == nil then
            return false
        elseif DALPHA_SORT_CASE_INSENSITIVE then
            return strcoll_func(string.lower(a), string.lower(b))
        else
            return strcoll_func(a, b)
        end
    end
    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function FileChooser:genItemTableFromPath(path)
    local dirs = {}
    local files = {}

    self.list(path, dirs, files)

    local sorting
    if self.collate == "strcoll" then
        sorting = function(a, b)
            return self.strcoll(a.name, b.name)
        end
    elseif self.collate == "access" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                return true
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                return false
            end
            return a.attr.access > b.attr.access
        end
    elseif self.collate == "modification" then
        sorting = function(a, b)
            return a.attr.modification > b.attr.modification
        end
    elseif self.collate == "change" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                return false
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                return true
            end
            return a.attr.change > b.attr.change
        end
    elseif self.collate == "size" then
        sorting = function(a, b)
            return a.attr.size < b.attr.size
        end
    elseif self.collate == "type" then
        sorting = function(a, b)
            if a.suffix == nil and b.suffix == nil then
                return self.strcoll(a.name, b.name)
            else
                return self.strcoll(a.suffix, b.suffix)
            end
        end
    elseif self.collate == "percent_unopened_first" or self.collate == "percent_unopened_last" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                if self.collate == "percent_unopened_first" then
                    return false
                else
                    return true
                end
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                if self.collate == "percent_unopened_first" then
                    return true
                else
                    return false
                end
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                return a.name < b.name
            end

            if a.attr.mode == "directory" then return a.name < b.name end
            if b.attr.mode == "directory" then return a.name < b.name end

            return a.percent_finished < b.percent_finished
        end
    else
        sorting = function(a, b)
            return a.name < b.name
        end
    end

    if self.reverse_collate then
        local sorting_unreversed = sorting
        sorting = function(a, b) return sorting_unreversed(b, a) end
    end

    table.sort(dirs, sorting)
    if path ~= "/" then table.insert(dirs, 1, {name = ".."}) end
    table.sort(files, sorting)

    local item_table = {}
    for i, dir in ipairs(dirs) do
        -- count sume of directories and files inside dir
        local sub_dirs = {}
        local dir_files = {}
        local subdir_path = self.path.."/"..dir.name
        self.list(subdir_path, sub_dirs, dir_files)
        local num_items = #sub_dirs + #dir_files
        local istr
        if num_items == 1 then
            istr = _("1 item")
        else
            istr = util.template(_("%1 items"), num_items)
        end
        table.insert(item_table, {
            text = dir.name == ".." and  "⬆ ../" or dir.name.."/",
            mandatory = istr,
            path = subdir_path,
            is_go_up = dir.name == ".."
        })
    end

    -- set to false to show all files in regular font
    -- set to "opened" to show opened files in bold
    -- otherwise, show new files in bold
    local show_file_in_bold = G_reader_settings:readSetting("show_file_in_bold")

    for _, file in ipairs(files) do
        local full_path = self.path.."/"..file.name
        local file_size = lfs.attributes(full_path, "size") or 0
        local sstr = getFriendlySize(file_size)
        local file_item = {
            text = file.name,
            mandatory = sstr,
            path = full_path
        }
        if show_file_in_bold ~= false then
            file_item.bold = DocSettings:hasSidecarFile(full_path)
            if show_file_in_bold ~= "opened" then
                file_item.bold = not file_item.bold
            end
        end
        table.insert(item_table, file_item)
    end
    -- lfs.dir iterated node string may be encoded with some weird codepage on
    -- Windows we need to encode them to utf-8
    if ffi.os == "Windows" then
        for k, v in pairs(item_table) do
            if v.text then
                v.text = util.multiByteToUTF8(v.text) or ""
            end
        end
    end

    return item_table
end

function FileChooser:updateItems(select_number)
    Menu.updateItems(self, select_number) -- call parent's updateItems()
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
end

function FileChooser:refreshPath()
    local itemmatch = nil
    if self.focused_path then
        itemmatch = {path = self.focused_path}
        -- We use focused_path only once, but remember it
        -- for CoverBrower to re-apply it on startup if needed
        self.prev_focused_path = self.focused_path
        self.focused_path = nil
    end
    self:switchItemTable(nil, self:genItemTableFromPath(self.path), self.path_items[self.path], itemmatch)
end

function FileChooser:changeToPath(path, focused_path)
    path = util.realpath(path)
    self.path = path
    if focused_path then
        self.focused_path = focused_path
    end
    self:refreshPath()
    self:onPathChanged(path)
end

function FileChooser:changePageToPath(path)
    if not path then return end
    for num, item in ipairs(self.item_table) do
        if item.path == path then
            local page = math.floor((num-1) / self.perpage) + 1
            if page ~= self.page then
                self:onGotoPage(page)
            end
            break
        end
    end
end

function FileChooser:toggleHiddenFiles()
    self.show_hidden = not self.show_hidden
    self:refreshPath()
end

function FileChooser:setCollate(collate)
    self.collate = collate
    self:refreshPath()
end

function FileChooser:toggleReverseCollate()
    self.reverse_collate = not self.reverse_collate
    self:refreshPath()
end

function FileChooser:onMenuSelect(item)
    -- parent directory of dir without permission get nil mode
    -- we need to change to parent path in this case
    if lfs.attributes(item.path, "mode") == "file" then
        self:onFileSelect(item.path)
    else
        self:changeToPath(item.path, item.is_go_up and self.path)
    end
    return true
end

function FileChooser:onMenuHold(item)
    self:onFileHold(item.path)
    return true
end

function FileChooser:onFileSelect(file)
    UIManager:close(self)
    return true
end

function FileChooser:onFileHold(file)
    return true
end

function FileChooser:onPathChanged(path)
    return true
end

return FileChooser
