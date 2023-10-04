local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local datetime = require("datetime")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Menu = require("ui/widget/menu")
local OpenWithDialog = require("ui/widget/openwithdialog")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local sort = require("sort")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = ffiUtil.template

local FileChooser = Menu:extend{
    no_title = true,
    path = lfs.currentdir(),
    show_path = true,
    parent = nil,
    show_hidden = false, -- set to true to show folders/files starting with "."
    file_filter = nil, -- function defined in the caller, returns true for files to be shown
    show_unsupported = false, -- set to true to ignore file_filter
    show_finished = true, -- show all books
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
    if not self.show_finished and fullpath ~= nil and filemanagerutil.getStatus(fullpath) == "complete" then return false end
    return true
end

function FileChooser:init()
    self.path_items = {}
    self.width = Screen:getWidth()
    self.item_table = self:genItemTableFromPath(self.path)
    Menu.init(self) -- call parent's init()
end

function FileChooser:getList(path, collate)
    local dirs, files = {}, {}
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
                            if collate then -- when collate == nil count only to display in folder mandatory
                                item = self:getListItem(f, filename, attributes)
                            end
                            table.insert(dirs, item)
                        end
                    -- Always ignore macOS resource forks.
                    elseif attributes.mode == "file" and not util.stringStartsWith(f, "._") then
                        if self:show_file(f, filename) then
                            if collate then -- when collate == nil count only to display in folder mandatory
                                item = self:getListItem(f, filename, attributes, collate)
                            end
                            table.insert(files, item)
                        end
                    end
                end
            end
        end
    else -- error, probably "permission denied"
        if unreadable_dir_content[path] then
            -- Add this dummy item that will be replaced with a message by genItemTable()
            table.insert(dirs, self:getListItem("./.", path, lfs.attributes(path)))
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

function FileChooser:getListItem(f, filename, attributes, collate)
    local item = {
        text = f,
        fullpath = filename,
        attr = attributes,
    }
    if collate then -- file
        if G_reader_settings:readSetting("show_file_in_bold") ~= false then
            item.opened = DocSettings:hasSidecarFile(filename)
        end
        if collate == "type" then
            item.suffix = util.getFileNameSuffix(f)
        elseif collate == "percent_unopened_first" or collate == "percent_unopened_last" then
            local percent_finished
            item.opened = DocSettings:hasSidecarFile(filename)
            if item.opened then
                local doc_settings = DocSettings:open(filename)
                percent_finished = doc_settings:readSetting("percent_finished")
            end
            item.percent_finished = percent_finished or 0
        end
    end
    return item
end

function FileChooser:getSortingFunction(collate, reverse_collate)
    local sorting
    if collate == "strcoll" then
        sorting = function(a, b)
            return ffiUtil.strcoll(a.text, b.text)
        end
    elseif collate == "natural" then
        local natsort
        -- Only keep the cache if we're an *instance* of FileChooser
        if self ~= FileChooser then
            natsort, self.natsort_cache = sort.natsort_cmp(self.natsort_cache)
        else
            natsort = sort.natsort_cmp()
        end
        sorting = function(a, b)
            return natsort(a.text, b.text)
        end
    elseif collate == "access" then
        sorting = function(a, b)
            return a.attr.access > b.attr.access
        end
    elseif collate == "date" then
        sorting = function(a, b)
            return a.attr.modification > b.attr.modification
        end
    elseif collate == "size" then
        sorting = function(a, b)
            return a.attr.size < b.attr.size
        end
    elseif collate == "type" then
        sorting = function(a, b)
            if (a.suffix or b.suffix) and a.suffix ~= b.suffix then
                return ffiUtil.strcoll(a.suffix, b.suffix)
            end
            return ffiUtil.strcoll(a.text, b.text)
        end
    else -- collate == "percent_unopened_first" or collate == "percent_unopened_last"
        sorting = function(a, b)
            if a.opened == b.opened then
                if a.opened then
                    return a.percent_finished < b.percent_finished
                end
                return ffiUtil.strcoll(a.text, b.text)
            end
            if collate == "percent_unopened_first" then
                return b.opened
            end
            return a.opened
        end
    end

    if reverse_collate then
        local sorting_unreversed = sorting
        sorting = function(a, b) return sorting_unreversed(b, a) end
    end

    return sorting
end

function FileChooser:genItemTableFromPath(path)
    local collate = G_reader_settings:readSetting("collate", "strcoll")
    local dirs, files = self:getList(path, collate)
    return self:genItemTable(dirs, files, path)
end

function FileChooser:genItemTable(dirs, files, path)
    local collate = G_reader_settings:readSetting("collate")
    local collate_not_for_mixed = collate == "size" or
                                  collate == "type" or
                                  collate == "percent_unopened_first" or
                                  collate == "percent_unopened_last"
    local collate_mixed = G_reader_settings:isTrue("collate_mixed")
    local reverse_collate = G_reader_settings:isTrue("reverse_collate")
    local sorting = self:getSortingFunction(collate, reverse_collate)
    if collate_not_for_mixed or not collate_mixed then
        table.sort(files, sorting)
        if collate_not_for_mixed then
            sorting = self:getSortingFunction("strcoll", reverse_collate)
        end
        table.sort(dirs, sorting)
    end

    local item_table = {}

    for i, dir in ipairs(dirs) do
        local text, bidi_wrap_func, mandatory
        if dir.text == "./." then -- added as content of an unreadable directory
            text = _("Current folder not readable. Some content may not be shown.")
        else
            text = dir.text.."/"
            bidi_wrap_func = BD.directory
            if path then -- file browser or PathChooser
                mandatory = self:getMenuItemMandatory(dir)
            end
        end
        table.insert(item_table, {
            text = text,
            attr = dir.attr,
            bidi_wrap_func = bidi_wrap_func,
            mandatory = mandatory,
            path = dir.fullpath,
        })
    end

    -- set to false to show all files in regular font
    -- set to "opened" to show opened files in bold
    -- otherwise, show new files in bold
    local show_file_in_bold = G_reader_settings:readSetting("show_file_in_bold")

    for i, file in ipairs(files) do
        local file_item = {
            text = file.text,
            attr = file.attr,
            bidi_wrap_func = BD.filename,
            mandatory = self:getMenuItemMandatory(file, collate),
            path = file.fullpath,
            is_file = true,
        }
        if show_file_in_bold ~= false then
            file_item.bold = file.opened
            if show_file_in_bold ~= "opened" then
                file_item.bold = not file_item.bold
            end
        end
        if self.filemanager and self.filemanager.selected_files and self.filemanager.selected_files[file.fullpath] then
            file_item.dim = true
        end
        table.insert(item_table, file_item)
    end

    if not collate_not_for_mixed and collate_mixed then
        table.sort(item_table, sorting)
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
                text = _("Long-press to choose current folder"),
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
        -- display the sorting parameter in mandatory
        if collate == "access" then
            text = datetime.secondsToDateTime(item.attr.access)
        elseif collate == "date" then
            text = datetime.secondsToDateTime(item.attr.modification)
        elseif collate == "percent_unopened_first" or collate == "percent_unopened_last" then
            text = item.opened and string.format("%d %%", 100 * item.percent_finished) or "–"
        else
            text = util.getFriendlySize(item.attr.size or 0)
        end
    else -- folder, count number of folders and files inside it
        local sub_dirs, dir_files = self:getList(item.fullpath)
        text = T("%1 \u{F016}", #dir_files)
        if #sub_dirs > 0 then
            text = T("%1 \u{F114} ", #sub_dirs) .. text
        end
    end
    return text
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
                text = focused_path:sub(#path > 1 and #path+2 or 2),
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
        if not item.is_file and item.path == path then
            local page = math.floor((num-1) / self.perpage) + 1
            if page ~= self.page then
                self:onGotoPage(page)
            end
            break
        end
    end
end

function FileChooser:toggleFinishedBooks()
    self.show_finished = not self.show_finished
    self:refreshPath()
end

function FileChooser:toggleHiddenFiles()
    self.show_hidden = not self.show_hidden
    self:refreshPath()
end

function FileChooser:toggleUnsupportedFiles()
    self.show_unsupported = not self.show_unsupported
    self:refreshPath()
end

function FileChooser:onMenuSelect(item)
    -- parent directory of dir without permission get nil mode
    -- we need to change to parent path in this case
    if item.is_file then
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

-- Used in ReaderStatus:onOpenNextDocumentInFolder().
function FileChooser:getNextFile(curr_file)
    local is_curr_file_found
    for i, item in ipairs(self.item_table) do
        if not is_curr_file_found and item.path == curr_file then
            is_curr_file_found = true
        end
        if is_curr_file_found then
            local next_file = self.item_table[i+1]
            if next_file and next_file.is_file and DocumentRegistry:hasProvider(next_file.path) then
                return next_file.path
            end
        end
    end
end

-- Used in file manager select mode to select all files in a folder,
-- that are visible in all file browser pages, without subfolders.
function FileChooser:selectAllFilesInFolder()
    for _, item in ipairs(self.item_table) do
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
    for _, provider in ipairs(one_time_providers) do
        provider.one_time_provider = true
        table.insert(radio_buttons, {
            {
                text = provider.provider_name,
                provider = provider,
            },
        })
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
