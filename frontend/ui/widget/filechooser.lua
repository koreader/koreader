local BD = require("ui/bidi")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local OpenWithDialog = require("ui/widget/openwithdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local _ = require("gettext")
local Screen = Device.screen
local util = require("util")
local getFileNameSuffix = util.getFileNameSuffix
local getFriendlySize = util.getFriendlySize

local FileChooser = Menu:extend{
    no_title = true,
    path = lfs.currentdir(),
    show_path = true,
    parent = nil,
    show_hidden = false, -- set to true to show folders/files starting with "."
    file_filter = nil, -- function defined in the caller, returns true for files to be shown
    show_unsupported = false, -- set to true to ignore file_filter
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
    collate = "strcoll", -- or collate = "access",
    reverse_collate = false,
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

function FileChooser:show_file(filename)
    for _, pattern in ipairs(self.exclude_files) do
        if filename:match(pattern) then return false end
    end
    return self.show_unsupported or self.file_filter == nil or self.file_filter(filename)
end

function FileChooser:init()
    self.path_items = {}
    self.width = Screen:getWidth()
    self.list = function(path, dirs, files, count_only)
        -- lfs.dir directory without permission will give error
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if ok then
            unreadable_dir_content[path] = nil
            for f in iter, dir_obj do
                if self.show_hidden or not util.stringStartsWith(f, ".") then
                    local filename = path.."/"..f
                    local attributes = lfs.attributes(filename)
                    if attributes ~= nil then
                        local item = true
                        if attributes.mode == "directory" and f ~= "." and f ~= ".." then
                            if self:show_dir(f) then
                                if not count_only then
                                    item = {name = f,
                                            suffix = getFileNameSuffix(f),
                                            fullpath = filename,
                                            attr = attributes,}
                                end
                                table.insert(dirs, item)
                            end
                        -- Always ignore macOS resource forks.
                        elseif attributes.mode == "file" and not util.stringStartsWith(f, "._") then
                            if self:show_file(f) then
                                if not count_only then
                                    local percent_finished = 0
                                    if self.collate == "percent_unopened_first" or self.collate == "percent_unopened_last" then
                                        if DocSettings:hasSidecarFile(filename) then
                                            local docinfo = DocSettings:open(filename)
                                            percent_finished = docinfo.data.percent_finished or 0
                                        end
                                    end
                                    item = {name = f,
                                            suffix = getFileNameSuffix(f),
                                            fullpath = filename,
                                            attr = attributes,
                                            percent_finished = percent_finished,}
                                end
                                table.insert(files, item)
                            end
                        end
                    end
                end
            end
        else -- error, probably "permission denied"
            if unreadable_dir_content[path] then
                -- Add this dummy item that will be replaced with a message
                -- by genItemTableFromPath()
                table.insert(dirs, {
                    name = "./.",
                    fullpath = path,
                    attr = lfs.attributes(path),
                })
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
    end

    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function FileChooser:getSortingFunction(collate, reverse_collate)
    local sorting
    if collate == "strcoll" then
        sorting = function(a, b)
            return ffiUtil.strcoll(a.name, b.name)
        end
    elseif collate == "access" then
        sorting = function(a, b)
            return a.attr.access > b.attr.access
        end
    elseif collate == "modification" then
        sorting = function(a, b)
            return a.attr.modification > b.attr.modification
        end
    elseif collate == "change" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                return false
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                return true
            end
            return a.attr.change > b.attr.change
        end
    elseif collate == "size" then
        sorting = function(a, b)
            return a.attr.size < b.attr.size
        end
    elseif collate == "type" then
        sorting = function(a, b)
            if a.suffix == nil and b.suffix == nil then
                return ffiUtil.strcoll(a.name, b.name)
            else
                return ffiUtil.strcoll(a.suffix, b.suffix)
            end
        end
    elseif collate == "percent_unopened_first" or collate == "percent_unopened_last" then
        sorting = function(a, b)
            if DocSettings:hasSidecarFile(a.fullpath) and not DocSettings:hasSidecarFile(b.fullpath) then
                if collate == "percent_unopened_first" then
                    return false
                else
                    return true
                end
            end
            if not DocSettings:hasSidecarFile(a.fullpath) and DocSettings:hasSidecarFile(b.fullpath) then
                if collate == "percent_unopened_first" then
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
    elseif collate == "natural" then
        -- adapted from: http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
        local function addLeadingZeroes(d)
            local dec, n = string.match(d, "(%.?)0*(.+)")
            return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n)
        end
        sorting = function(a, b)
            return tostring(a.name):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#b.name)
                    < tostring(b.name):gsub("%.?%d+",addLeadingZeroes)..("%3d"):format(#a.name)
        end
    else
        sorting = function(a, b)
            return a.name < b.name
        end
    end

    if reverse_collate then
        local sorting_unreversed = sorting
        sorting = function(a, b) return sorting_unreversed(b, a) end
    end

    return sorting
end

function FileChooser:genItemTableFromPath(path)
    local dirs = {}
    local files = {}
    local up_folder_arrow = BD.mirroredUILayout() and BD.ltr("../ ⬆") or "⬆ ../"

    self.list(path, dirs, files)

    local sorting = self:getSortingFunction(self.collate, self.reverse_collate)

    if self.collate ~= "strcoll_mixed" then
        table.sort(dirs, sorting)
        table.sort(files, sorting)
    end
    if path ~= "/" and not (G_reader_settings:isTrue("lock_home_folder") and
                            path == G_reader_settings:readSetting("home_dir")) then
        table.insert(dirs, 1, {name = ".."})
    end
    if self.show_current_dir_for_hold then table.insert(dirs, 1, {name = "."}) end

    local item_table = {}
    for i, dir in ipairs(dirs) do
        local subdir_path = self.path.."/"..dir.name
        local text, bidi_wrap_func, istr
        if dir.name == ".." then
            text = up_folder_arrow
        elseif dir.name == "." then -- possible with show_current_dir_for_hold
            text = _("Long-press to choose current folder")
        elseif dir.name == "./." then -- added as content of an unreadable directory
            text = _("Current folder not readable. Some content may not be shown.")
        else
            text = dir.name.."/"
            bidi_wrap_func = BD.directory
            -- count number of folders and files inside dir
            local sub_dirs = {}
            local dir_files = {}
            self.list(subdir_path, sub_dirs, dir_files, true)
            istr = T("%1 \u{F016}", #dir_files)
            if #sub_dirs > 0 then
                istr = T("%1 \u{F114} ", #sub_dirs) .. istr
            end
        end
        table.insert(item_table, {
            text = text,
            bidi_wrap_func = bidi_wrap_func,
            mandatory = istr,
            path = subdir_path,
            is_go_up = dir.name == ".."
        })
    end

    -- set to false to show all files in regular font
    -- set to "opened" to show opened files in bold
    -- otherwise, show new files in bold
    local show_file_in_bold = G_reader_settings:readSetting("show_file_in_bold")

    for i = 1, #files do
        local file = files[i]
        local full_path = self.path.."/"..file.name
        local file_size = lfs.attributes(full_path, "size") or 0
        local sstr = getFriendlySize(file_size)
        local file_item = {
            text = file.name,
            bidi_wrap_func = BD.filename,
            mandatory = sstr,
            path = full_path,
            is_file = true,
        }
        if show_file_in_bold ~= false then
            file_item.bold = DocSettings:hasSidecarFile(full_path)
            if show_file_in_bold ~= "opened" then
                file_item.bold = not file_item.bold
            end
        end
        if self.filemanager and self.filemanager.selected_files and self.filemanager.selected_files[full_path] then
            file_item.dim = true
        end
        table.insert(item_table, file_item)
    end

    if self.collate == "strcoll_mixed" then
        sorting = function(a, b)
            if b.text == up_folder_arrow then return false end
            return ffiUtil.strcoll(a.text, b.text)
        end
        if self.reverse_collate then
            local sorting_unreversed = sorting
            sorting = function(a, b) return sorting_unreversed(b, a) end
        end
        table.sort(item_table, sorting)
    end
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

function FileChooser:updateItems(select_number)
    Menu.updateItems(self, select_number) -- call parent's updateItems()
    self:mergeTitleBarIntoLayout()
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
end

function FileChooser:refreshPath()
    local itemmatch = nil

    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)

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
                name = focused_path:sub(#path+2),
                fullpath = focused_path,
                attr = lfs.attributes(focused_path),
            }
        end
    end

    self:refreshPath()
    self:onPathChanged(path)
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

function FileChooser:toggleUnsupportedFiles()
    self.show_unsupported = not self.show_unsupported
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

function FileChooser:getNextFile(curr_file)
    local next_file
    for index, data in pairs(self.item_table) do
        if data.path == curr_file then
            if index+1 <= #self.item_table then
                next_file = self.item_table[index+1].path
                if lfs.attributes(next_file, "mode") == "file" and DocumentRegistry:hasProvider(next_file) then
                    break
                else
                    next_file = nil
                end
            end
        end
    end
    return next_file
end

-- Used in file manager select mode to select all files in a folder,
-- that are visible in all file browser pages, without subfolders.
function FileChooser:selectAllFilesInFolder()
    for _, item in pairs(self.item_table) do
        if item.is_file then
            self.filemanager.selected_files[item.path] = true
        end
    end
end

function FileChooser:showSetProviderButtons(file, one_time_providers)
    local ReaderUI = require("apps/reader/readerui")

    local __, filename_pure = util.splitFilePathName(file)
    local filename_suffix = util.getFileNameSuffix(file)

    local buttons = {}
    local radio_buttons = {}
    local filetype_provider = G_reader_settings:readSetting("provider") or {}
    local providers = DocumentRegistry:getProviders(file)
    if providers ~= nil then
        for ___, provider in ipairs(providers) do
            -- we have no need for extension, mimetype, weights, etc. here
            provider = provider.provider
            table.insert(radio_buttons, {
                {
                    text = provider.provider_name,
                    checked = DocumentRegistry:getProvider(file) == provider,
                    provider = provider,
                },
            })
        end
    else
        local provider = DocumentRegistry:getProvider(file)
        table.insert(radio_buttons, {
            {
                -- @translators %1 is the provider name, such as Cool Reader Engine or MuPDF.
                text = T(_("%1 ~Unsupported"), provider.provider_name),
                checked = true,
                provider = provider,
            },
        })
    end
    if one_time_providers and #one_time_providers > 0 then
        for ___, provider in ipairs(one_time_providers) do
            provider.one_time_provider = true
            table.insert(radio_buttons, {
                {
                    text = provider.provider_name,
                    provider = provider,
                },
            })
        end
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.set_provider_dialog)
            end,
        },
        {
            text = _("Open"),
            is_enter_default = true,
            callback = function()
                local provider = self.set_provider_dialog.radio_button_table.checked_button.provider
                if provider.one_time_provider then
                    UIManager:close(self.set_provider_dialog)
                    provider.callback()
                    return
                end

                -- always for this file
                if self.set_provider_dialog._check_file_button.checked then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open '%2' with %1?"),
                                   provider.provider_name, BD.filename(filename_pure)),
                        ok_text = _("Always"),
                        ok_callback = function()
                            DocumentRegistry:setProvider(file, provider, false)

                            ReaderUI:showReader(file, provider)
                            UIManager:close(self.set_provider_dialog)
                        end,
                    })
                -- always for all files of this file type
                elseif self.set_provider_dialog._check_global_button.checked then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open %2 files with %1?"),
                                 provider.provider_name, filename_suffix),
                        ok_text = _("Always"),
                        ok_callback = function()
                            DocumentRegistry:setProvider(file, provider, true)

                            ReaderUI:showReader(file, provider)
                            UIManager:close(self.set_provider_dialog)
                        end,
                    })
                else
                    -- just once
                    ReaderUI:showReader(file, provider)
                    UIManager:close(self.set_provider_dialog)
                end
            end,
        },
    })

    if filetype_provider[filename_suffix] ~= nil then
        table.insert(buttons, {
           {
               text = _("Reset default"),
                callback = function()
                    filetype_provider[filename_suffix] = nil
                    G_reader_settings:saveSetting("provider", filetype_provider)
                    UIManager:close(self.set_provider_dialog)
                end,
            },
        })
    end

    self.set_provider_dialog = OpenWithDialog:new{
        title = T(_("Open %1 with:"), BD.filename(filename_pure)),
        radio_buttons = radio_buttons,
        buttons = buttons,
    }
    UIManager:show(self.set_provider_dialog)
end

return FileChooser
