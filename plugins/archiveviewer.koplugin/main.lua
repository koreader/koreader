local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local DocumentRegistry = require("document/documentregistry")
local ImageViewer = require("ui/widget/imageviewer")
local Menu = require("ui/widget/menu")
local RenderImage = require("ui/renderimage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template
local ffi = require "ffi"
local libarchive = ffi.loadlib("archive", "13")
local logger = require("logger")
require "ffi/libarchive_h"

local ArchiveViewer = WidgetContainer:extend{
    name = "archiveviewer",
    fullname = _("Archive viewer"),
    arc_file = nil, -- archive
    -- list_table is a flat table containing archive files and folders
    -- key - a full path of the folder ("/" for root), for all folders and subfolders of any level
    -- value - a subtable of subfolders and files in the folder
    -- subtable key - a name of a subfolder ending with /, or a name of a file (without path)
    -- subtable value - false for subfolders, or file size (string)
    list_table = nil,
    arc_ext = {
        cbr  = true,
        cbz  = true,
        epub = true,
        rar  = true,
        zip  = true,
    },
}

local function archiveReadIter(filename)
    logger.dbg('archiveviewer: opening file', filename)
    local archive = ffi.gc(libarchive.archive_read_new(), libarchive.archive_free)
    libarchive.archive_read_support_format_all(archive)
    libarchive.archive_read_support_filter_all(archive)
    if libarchive.archive_read_open_filename(archive, filename, 10240) ~= libarchive.ARCHIVE_OK then
        logger.err('archiveviewer: opening file', filename, ffi.string(libarchive.archive_error_string(archive)))
        return function() end
    end
    local entry = ffi.new('struct archive_entry *[1]')
    return function ()
        local err = libarchive.archive_read_next_header(archive, entry)
        if err ~= libarchive.ARCHIVE_OK then
            if err ~= libarchive.ARCHIVE_EOF then
                logger.err('archiveviewer: reading next header', ffi.string(libarchive.archive_error_string(archive)))
            end
            libarchive.archive_read_close(archive)
            return nil
        end
        return archive, entry[0]
    end
end

local function getSuffix(file)
    return util.getFileNameSuffix(file):lower()
end

function ArchiveViewer:init()
    self:registerDocumentRegistryAuxProvider()
end

function ArchiveViewer:registerDocumentRegistryAuxProvider()
    DocumentRegistry:addAuxProvider({
        provider_name = self.fullname,
        provider = self.name,
        order = 40, -- order in OpenWith dialog
        disable_file = true,
        disable_type = false,
    })
end

function ArchiveViewer:isFileTypeSupported(file)
    return self.arc_ext[getSuffix(file)] and true or false
end

function ArchiveViewer:openFile(file)
    local _, filename = util.splitFilePathName(file)
    self.arc_file = file

    self.fm_updated = nil
    self.list_table = {}
    self:getListTable()

    self.menu = Menu:new{
        title = filename,
        item_table = self:getItemTable(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_multilines = true,
        onMenuSelect = function(self_menu, item)
            if item.is_file then
                self:showFileDialog(item.path)
            else
                local title = item.path == "" and filename or filename.."/"..item.path
                self_menu:switchItemTable(title, self:getItemTable(item.path))
            end
        end,
        close_callback = function()
            UIManager:close(self.menu)
            if self.fm_updated then
                self.ui:onRefresh()
            end
        end,
    }
    UIManager:show(self.menu)
end

function ArchiveViewer:getListTable()
    local function parse_path(filepath, filesize)
        if not filepath then return end
        local path, name = util.splitFilePathName(filepath)
        if path == "" then
            path = "/"
        end
        if not self.list_table[path] then
            self.list_table[path] = {}
        end
        if name == "" then -- some archivers include subfolder name as a separate entry ending with "/"
            if path ~= "/" then
                parse_path(path:sub(1,-2), false) -- filesize == false for subfolders
            end
        else
            if self.list_table[path][name] == nil then
                self.list_table[path][name] = filesize
                parse_path(path:sub(1,-2), false) -- go up to include subfolders of the branch into the table
            end
        end
    end

    for archive, entry in archiveReadIter(self.arc_file) do
        local path = ffi.string(libarchive.archive_entry_pathname(entry))
        local size = libarchive.archive_entry_size(entry)
        parse_path(path, size)
    end
end

function ArchiveViewer:getItemTable(path)
    local prefix, item_table
    if path == nil or path == "" then -- root
        path = "/"
        prefix = ""
        item_table = {}
    else
        prefix = path
        item_table = {
            {
                text = BD.mirroredUILayout() and BD.ltr("../ ⬆") or "⬆ ../",
                path = util.splitFilePathName(path:sub(1,-2)),
            },
        }
    end

    local files, dirs = {}, {}
    for name, v in pairs(self.list_table[path] or {}) do
        if v then -- file
            table.insert(files, {
                text = name,
                is_file = true,
                bidi_wrap_func = BD.filename,
                path = prefix..name,
                mandatory = util.getFriendlySize(tonumber(v)),
            })
        else -- folder
            local dirname = name.."/"
            table.insert(dirs, {
                text = dirname,
                bidi_wrap_func = BD.directory,
                path = prefix..dirname,
                mandatory = self:getItemDirMandatory(prefix..dirname),
            })
        end
    end
    local sorting = function(a, b) -- by name, folders first
        return ffiUtil.strcoll(a.text, b.text)
    end
    table.sort(dirs, sorting)
    table.sort(files, sorting)
    table.move(dirs, 1, #dirs, #item_table + 1, item_table)
    table.move(files, 1, #files, #item_table + 1, item_table)
    return item_table
end

function ArchiveViewer:getItemDirMandatory(name)
    local sub_dirs, dir_files = 0, 0
    for _, v in pairs(self.list_table[name]) do
        if v then
            dir_files = dir_files + 1
        else
            sub_dirs = sub_dirs + 1
        end
    end
    local text = T("%1 \u{F016}", dir_files)
    if sub_dirs > 0 then
        text = T("%1 \u{F114} ", sub_dirs) .. text
    end
    return text
end

function ArchiveViewer:showFileDialog(filepath)
    local dialog
    local buttons = {
        {
            {
                text = _("Extract"),
                callback = function()
                    UIManager:close(dialog)
                    self:extractFile(filepath)
                end,
            },
            {
                text = _("View"),
                callback = function()
                    UIManager:close(dialog)
                    self:viewFile(filepath)
                end,
            },
        },
    }
    dialog = ButtonDialog:new{
        title = filepath .. "\n\n" .. _("On extraction, if the file already exists, it will be overwritten."),
        width_factor = 0.8,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function ArchiveViewer:viewFile(filepath)
    if DocumentRegistry:isImageFile(filepath) then
        local index = 0
        local curr_index
        local images_list = {}
        for i, item in ipairs(self.menu.item_table) do
            local item_path = item.path
            if item.is_file and DocumentRegistry:isImageFile(item_path) then
                table.insert(images_list, item_path)
                if not curr_index then
                    index = index + 1
                    if item_path == filepath then
                        curr_index = index
                    end
                end
            end
        end
        local image_table = { image_disposable = true }
        setmetatable(image_table, {__index = function (_, key)
                local content = self:extractContent(images_list[key])
                if content then
                    return RenderImage:renderImageData(content, #content)
                end
            end
        })
        local viewer = ImageViewer:new{
            image = image_table,
            images_list_nb = #images_list,
            fullscreen = true,
            with_title_bar = false,
            image_disposable = false,
        }
        UIManager:show(viewer)
        viewer:switchToImageNum(curr_index)
    else
        local viewer = TextViewer:new{
            title = filepath,
            title_multilines = true,
            text = self:extractContent(filepath),
            text_type = "file_content",
        }
        UIManager:show(viewer)
    end
end

function ArchiveViewer:extractFile(filepath)
    for archive, entry in archiveReadIter(self.arc_file) do
        local path = ffi.string(libarchive.archive_entry_pathname(entry))
        if path == filepath then
            local directory = util.splitFilePathName(self.arc_file)
            path = directory .. "/" .. path
            local dest = libarchive.archive_write_disk_new()
            libarchive.archive_write_disk_set_options(dest,
                libarchive.ARCHIVE_EXTRACT_SECURE_NODOTDOT +
                libarchive.ARCHIVE_EXTRACT_SECURE_SYMLINKS
            )
            libarchive.archive_entry_set_pathname(entry, path)
            if libarchive.archive_read_extract2(archive, entry, dest) ~= libarchive.ARCHIVE_OK then
                logger.err('archiveviewer: extracting to', path, ffi.string(libarchive.archive_error_string(dest)))
            end
            libarchive.archive_write_close(dest)
            libarchive.archive_free(dest)
            self.fm_updated = true
        end
    end
end

function ArchiveViewer:extractContent(filepath)
    for archive, entry in archiveReadIter(self.arc_file) do
        local path = ffi.string(libarchive.archive_entry_pathname(entry))
        local size = libarchive.archive_entry_size(entry)
        if path == filepath then
            local content = ffi.gc(ffi.C.malloc(size), ffi.C.free)
            if libarchive.archive_read_data(archive, content, size) ~= size then
                print(ffi.string(libarchive.archive_error_string(self.archive)))
                return
            end
            return ffi.string(content, size)
        end
    end
end

return ArchiveViewer
