local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local T = ffiUtil.template

local ArchiveViewer = WidgetContainer:extend{
    -- list_table is a flat table containing archive files and folders
    -- key - a full path of the folder ("/" for root), for all folders and subfolders of any level
    -- value - a subtable of subfolders and files in the folder
    -- subtable key - a name of a subfolder ending with /, or a name of a file (without path)
    -- subtable value - false for subfolders, or file size (string)
    list_table = nil,
    arc_type = nil,
    arc_ext = {
        cbz  = true,
        epub = true,
        zip  = true,
    },
}

function ArchiveViewer:isSupported(file)
    return self.arc_ext[util.getFileNameSuffix(file):lower()] and true or false
end

function ArchiveViewer:openArchiveViewer(file)
    local _, filename = util.splitFilePathName(file)
    local fileext = util.getFileNameSuffix(file):lower()
    if fileext == "cbz" or fileext == "epub" or fileext == "zip" then
        self.arc_type = "zip"
    end

    self.fm_updated = nil
    self.list_table = {}
    if self.arc_type == "zip" then
        self:getZipListTable(file)
    else -- add other archivers here
        return
    end

    local item_table = self:getItemTable() -- root
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    local menu = Menu:new{
        is_borderless = true,
        is_popout = false,
        title_multilines = true,
        show_parent = menu_container,
        onMenuSelect = function(self_menu, item)
            if item.text:sub(-1) == "/" then -- folder
                local title = item.path == "" and filename or filename.."/"..item.path
                self_menu:switchItemTable(title, self:getItemTable(item.path))
            else
                self:showFileDialog(file, item.path)
            end
        end,
        close_callback = function()
            UIManager:close(menu_container)
            if self.fm_updated then
                self.ui:onRefresh()
            end
        end,
    }
    table.insert(menu_container, menu)
    menu:switchItemTable(filename, item_table)
    UIManager:show(menu_container)
end

function ArchiveViewer:getZipListTable(file)
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

    local std_out = io.popen("unzip ".."-qql \""..file.."\"")
    if std_out then
        for line in std_out:lines() do
            -- entry datetime not used so far
            local fsize, fname = string.match(line, "%s+(%d+)%s+[-0-9]+%s+[0-9:]+%s+(.+)")
            parse_path(fname, fsize or 0)
        end
        std_out:close()
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
    for _, v in ipairs(dirs) do
        table.insert(item_table, v)
    end
    for _, v in ipairs(files) do
        table.insert(item_table, v)
    end
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

function ArchiveViewer:showFileDialog(arcfile, filepath)
    local dialog
    local buttons = {
        {
            {
                text = _("Extract"),
                callback = function()
                    UIManager:close(dialog)
                    self:extractFile(arcfile, filepath)
                end,
            },
            {
                text = _("View"),
                callback = function()
                    UIManager:close(dialog)
                    self:viewFile(arcfile, filepath)
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

function ArchiveViewer:viewFile(arcfile, filepath)
    local content
    if self.arc_type == "zip" then
        local std_out = io.popen("unzip ".."-qp \""..arcfile.."\"".." ".."\""..filepath.."\"")
        if std_out then
            content = std_out:read("*all")
            std_out:close()
        else
            UIManager:show(InfoMessage:new{
                text = _("Cannot extract file content."),
                icon = "notice-warning",
            })
            return
        end
    else
        return
    end

    if DocumentRegistry:isImageFile(filepath) then
        local RenderImage = require("ui/renderimage")
        local ImageViewer = require("ui/widget/imageviewer")
        UIManager:show(ImageViewer:new{
            image = RenderImage:renderImageData(content, #content),
            fullscreen = true,
            with_title_bar = false,
        })
    else
        local TextViewer = require("ui/widget/textviewer")
        UIManager:show(TextViewer:new{
            title = filepath,
            title_multilines = true,
            text = content,
            justified = false,
        })
    end
end

function ArchiveViewer:extractFile(arcfile, filepath)
    if self.arc_type == "zip" then
        local std_out = io.popen("unzip ".."-qo \""..arcfile.."\"".." ".."\""..filepath.."\""..
                                 " -d ".."\""..util.splitFilePathName(arcfile).."\"")
        if std_out then
            std_out:close()
        end
    else
        return
    end
    self.fm_updated = true
end

return ArchiveViewer
