local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("ui/screen")
local Device = require("ui/device")
local util = require("ffi/util")
local DEBUG = require("dbg")
local _ = require("gettext")
local ffi = require("ffi")
ffi.cdef[[
int strcoll (char *str1, char *str2);
]]

-- string sort function respecting LC_COLLATE
local function strcoll(str1, str2)
    return ffi.C.strcoll(ffi.cast("char*", str1), ffi.cast("char*", str2)) <= 0
end

local FileChooser = Menu:extend{
    height = Screen:getHeight(),
    width = Screen:getWidth(),
    no_title = true,
    path = lfs.currentdir(),
    parent = nil,
    show_hidden = nil,
    filter = function(filename) return true end,
    exclude_dirs = {"%.sdr$"},
    collate = strcoll,
}

function FileChooser:init()
    -- common dir filter
    self.dir_filter = function(dirname)
        for _, pattern in ipairs(self.exclude_dirs) do
            if dirname:match(pattern) then return end
        end
        return true
    end
    -- disable string collating in Kobo devices. See issue koreader/koreader#686
    if Device:isKobo() then self.collate = nil end
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
                local filemode = lfs.attributes(filename, "mode")
                if filemode == "directory" and f ~= "." and f~=".." then
                    if self.dir_filter(filename) then
                        table.insert(dirs, f)
                    end
                elseif filemode == "file" then
                    if self.file_filter(filename) then
                        table.insert(files, f)
                    end
                end
            end
        end
    end
    table.sort(dirs, self.collate)
    if path ~= "/" then table.insert(dirs, 1, "..") end
    table.sort(files, self.collate)

    local item_table = {}
    for i, dir in ipairs(dirs) do
        local path = self.path.."/"..dir
        local items = 0
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if ok then
            for f in iter, dir_obj do
                items = items + 1
            end
            -- exclude "." and ".."
            items = items - 2
        end
        local istr = items .. (items > 1 and _(" items") or _(" item"))
        table.insert(item_table, {
            text = dir.."/",
            mandatory = istr,
            path = path
        })
    end
    for _, file in ipairs(files) do
        local full_path = self.path.."/"..file
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
            text = file,
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

function FileChooser:refreshPath()
    self:swithItemTable(nil, self:genItemTableFromPath(self.path))
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
