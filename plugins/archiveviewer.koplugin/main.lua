local Archiver = require("ffi/archiver")
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
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local ArchiveViewer = WidgetContainer:extend{
    name = "archiveviewer",
    fullname = _("Archive viewer"),
    arc = nil, -- archive
    -- list_table is a flat table containing archive files and folders
    -- key - a full path of the folder ("/" for root), for all folders and subfolders of any level
    -- value - a subtable of subfolders and files in the folder
    -- subtable key - a name of a subfolder ending with /, or a name of a file (without path)
    -- subtable value - false for subfolders, or file size (string)
    list_table = nil,
}

local SUPPORTED_EXTENSIONS = {
    cbr  = true,
    cbz  = true,
    epub = true,
    rar  = true,
    zip  = true,
}

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
    return SUPPORTED_EXTENSIONS[util.getFileNameSuffix(file):lower()] ~= nil
end

function ArchiveViewer:openFile(file)
    local _, filename = util.splitFilePathName(file)

    self.arc = Archiver.Reader:new()
    self.fm_updated = nil
    self.list_table = {}

    if self.arc:open(file) then
        self:getListTable()
    end

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

    for entry in self.arc:iterate() do
        if entry.mode == "file" then
            parse_path(entry.path, entry.size)
        end
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
                    logger.dbg("plugin.archiveviewer:: rendering image", filepath)
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
    local directory = util.splitFilePathName(self.arc.filepath)
    self.fm_updated = self.arc:extractToPath(filepath, directory .. filepath)
end

function ArchiveViewer:extractContent(filepath)
    return self.arc:extractToMemory(filepath)
end

return ArchiveViewer
