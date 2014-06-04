local Menu = require("ui/widget/menu")
local Screen = require("ui/screen")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
local util = require("ffi/util")
-- lfs
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
    show_filesize = DSHOWFILESIZE,
    filter = function(filename) return true end,
}

function FileChooser:init()
    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function FileChooser:genItemTableFromPath(path)
    local dirs = {}
    local files = {}

    -- lfs.dir directory without permission will give error
    if pcall(lfs.dir, self.path) then
        for f in lfs.dir(self.path) do
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
    table.sort(dirs, strcoll)
    if path ~= "/" then table.insert(dirs, 1, "..") end
    table.sort(files, strcoll)

    local item_table = {}
    for _, dir in ipairs(dirs) do
        table.insert(item_table, { text = dir.."/", path = self.path.."/"..dir })
    end
    for _, file in ipairs(files) do
        local full_path = self.path.."/"..file
        if self.show_filesize then
            local sstr = string.format("%4.1fM",lfs.attributes(full_path, "size")/1024/1024)
            table.insert(item_table, { text = file, mandatory = sstr, path = full_path })
        else
            table.insert(item_table, { text = file, path = full_path })
        end
    end

    return item_table
end

function FileChooser:changeToPath(path)
    path = util.realpath(path)
    self.path = path
    self:refreshPath()
end

function FileChooser:refreshPath()
    self:swithItemTable(nil, self:genItemTableFromPath(self.path))
end

function FileChooser:toggleHiddenFiles()
    self.show_hidden = not self.show_hidden
    self:swithItemTable(nil, self:genItemTableFromPath(self.path))
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
