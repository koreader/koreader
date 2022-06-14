local BD = require("ui/bidi")
local BookInfoManager = require("apps/filemanager/filemanagerbookinfo")
local Device = require("device")
local Menu = require("ui/widget/menu")
local FileChooser = require("ui/widget/filechooser")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local _ = require("gettext")
local Screen = Device.screen
local logger = require("logger")
local util = require("util")

local TagChooser = Menu:extend{
    no_title = false,
    path = lfs.currentdir(),
    show_path = true,
    has_close_button = true,
    show_hidden = false, -- set to true to show folders/files starting with "."
    file_filter = nil, -- function defined in the caller, returns true for files to be shown
    -- NOTE: Input is *always* a relative entry name
    goto_letter = true,
}

function TagChooser:show_file(filename)
    return self.file_filter == nil or self.file_filter(filename)
end

function TagChooser:init()
    self.width = Screen:getWidth()
    self.list = function(path, tags)
        -- lfs.dir directory without permission will give error
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if ok then
            for f in iter, dir_obj do
                if self.show_hidden or not util.stringStartsWith(f, ".") then
                    local filename = path.."/"..f
                    local attributes = lfs.attributes(filename)
                    if attributes ~= nil then
                        -- Always ignore macOS resource forks.
                        if attributes.mode == "file" and not util.stringStartsWith(f, "._") then
                            if self:show_file(f) then
                                local extract_data = true
                                local bookinfo = BookInfoManager:show(filename, nil, extract_data)
                                if bookinfo then
                                    if bookinfo.keywords then
                                        local kws = util.splitToArray(bookinfo.keywords, "\n")
                                        for i=1, #kws do
                                            local kw = BD.auto(kws[i])
                                            if tags[kw] == nil then
                                                tags[kw] = {}
                                            end
                                            table.insert(tags[kw], f)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else -- error, probably "permission denied"
            logger.warn("Read error:", path)
        end
    end

    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function TagChooser:genItemTableFromPath(path)
    local tags = {}

    self.list(path, tags)

    local item_table = {}
    for tag, books in pairs(tags) do
        table.insert(item_table, {
            text = tag,
            bidi_wrap_func = BD.auto,
            mandatory = T("%1 \u{F016}", #books),
            books = books
        })
    end

    local sorting = function(a, b)
        return ffiUtil.strcoll(a.text, b.text)
    end
    table.sort(item_table, sorting)
    -- lfs.dir iterated node string may be encoded with some weird codepage on
    -- Windows we need to encode them to utf-8
    if ffi.os == "Windows" then
        for k, v in pairs(item_table) do
            if v.text then
                v.text = ffiUtil.multiByteToUTF8(v.text) or ""
            end
        end
    end

    return item_table
end

function TagChooser:onMenuSelect(tag)
    local file_chooser = FileChooser:new{
        parent = self,
        path = self.path,
        select_directory = false,
        select_file = true,
        detailed_file_info = true,
        no_title = false,
        title = tag.text,
        file_filter = function(filename)
            for i, book in ipairs(tag.books) do
                if filename == book then
                    return true
                end
            end
            return false
        end,
    }
    function file_chooser:show_dir(dirname)
        return false
    end
    function file_chooser:onMenuHold(item)
        self:onMenuSelect(item)
    end
    function file_chooser:onPathChanged(path) -- handle ..
        UIManager:close(self)
    end
    function file_chooser:onFileSelect(file)
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file)
        UIManager:close(self)
        UIManager:close(self.parent)
    end
    UIManager:show(file_chooser)
    return true
end

function TagChooser:onMenuHold(item)
    return self:onMenuSelect(item)
end

return TagChooser
