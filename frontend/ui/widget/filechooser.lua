local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local Device = require("device")
local util = require("ffi/util")
local DEBUG = require("dbg")
local _ = require("gettext")
local ffi = require("ffi")
ffi.cdef[[
int strcoll (const char *str1, const char *str2);
]]

-- string sort function respecting LC_COLLATE
local function strcoll(str1, str2)
    return ffi.C.strcoll(str1, str2) < 0
end

local FileChooser = Menu:extend{
    no_title = true,
    path = lfs.currentdir(),
    parent = nil,
    show_hidden = nil,
    filter = function(filename) return true end,
    exclude_dirs = {"%.sdr$"},
    strcoll = strcoll,
    collate = "strcoll", -- or collate = "access",
    reverse_collate = false,
    path_pages = {}, -- store last browsed location(page) for each path
}

function FileChooser:init()
    self.width = Screen:getWidth()
    -- common dir filter
    self.dir_filter = function(dirname)
        for _, pattern in ipairs(self.exclude_dirs) do
            if dirname:match(pattern) then return end
        end
        return true
    end
    -- circumvent string collating in Kobo devices. See issue koreader/koreader#686
    if Device:isKobo() then
        self.strcoll = function(a, b) return a < b end
    end
    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function FileChooser:genItemTableFromPath(path)
    local dirs = {}
    local files = {}

    -- lfs.dir directory without permission will give error
    local ok, iter, dir_obj = pcall(lfs.dir, self.path)
    if ok then
        for f in iter, dir_obj do
            if self.show_hidden or not string.match(f, "^%.[^.]") then
                local filename = self.path.."/"..f
                local attributes = lfs.attributes(filename)
                if attributes.mode == "directory" and f ~= "." and f~=".." then
                    if self.dir_filter(filename) then
                        table.insert(dirs, {name = f, attr = attributes})
                    end
                elseif attributes.mode == "file" then
                    if self.file_filter(filename) then
                        table.insert(files, {name = f, attr = attributes})
                    end
                end
            end
        end
    end

    local sorting = nil
    local reverse = self.reverse_collate
    if self.collate == "strcoll" then
        if DALPHA_SORT_CASE_INSENSITIVE then
            sorting = function(a, b)
                return self.strcoll(string.lower(a.name), string.lower(b.name)) == not reverse
            end
        else
            sorting = function(a, b)
                return self.strcoll(a.name, b.name) == not reverse
            end
        end
    elseif self.collate == "access" then
        sorting = function(a, b)
            if reverse then
                return a.attr.access < b.attr.access
            else
                return a.attr.access > b.attr.access
            end
        end
    end

    table.sort(dirs, sorting)
    if path ~= "/" then table.insert(dirs, 1, {name = ".."}) end
    table.sort(files, sorting)

    local item_table = {}
    for i, dir in ipairs(dirs) do
        local path = self.path.."/"..dir.name
        local items = 0
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if ok then
            for f in iter, dir_obj do
                items = items + 1
            end
            -- exclude "." and ".."
            items = items - 2
        end
        local istr = util.template(
            items == 0 and _("0 items")
            or items == 1 and _("1 item")
            or _("%1 items"), items)
        table.insert(item_table, {
            text = dir.name.."/",
            mandatory = istr,
            path = path
        })
    end
    for _, file in ipairs(files) do
        local full_path = self.path.."/"..file.name
        local file_size = lfs.attributes(full_path, "size") or 0
        local sstr = ""
        if file_size > 1024*1024 then
            sstr = string.format("%4.1f MB", file_size/1024/1024)
        elseif file_size > 1024 then
            sstr = string.format("%4.1f KB", file_size/1024)
        else
            sstr = string.format("%d B", file_size)
        end
        table.insert(item_table, {
            text = file.name,
            mandatory = sstr,
            path = full_path
        })
    end
    -- lfs.dir iterated node string may be encoded with some weird codepage on Windows
    -- we need to encode them to utf-8
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
    self.path_pages[self.path] = self.page
end

function FileChooser:refreshPath()
    self.page = self.path_pages[self.path] or 1
    self:swithItemTable(nil, self:genItemTableFromPath(self.path), -1)
end

function FileChooser:changeToPath(path)
    path = util.realpath(path)
    self.path = path
    self:refreshPath()
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
        self:changeToPath(item.path)
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

return FileChooser
