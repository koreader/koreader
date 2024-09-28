local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local FileSearcher = InputContainer:extend{
    case_sensitive = false,
    include_subfolders = true,
    include_metadata = false,
}

function FileSearcher:init()
    self:registerKeyEvents()
end

function FileSearcher:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowFileSearch = { { "Alt", "F" }, { "Ctrl", "F" } }
        self.key_events.ShowFileSearchBlank = { { "Alt", "Shift", "F" }, { "Ctrl", "Shift", "F" }, event = "ShowFileSearch", args = "" }
    end
end

function FileSearcher:onShowFileSearch(search_string)
    local search_dialog, check_button_case, check_button_subfolders, check_button_metadata
    local function _doSearch()
        local search_str = search_dialog:getInputText()
        if search_str == "" then return end
        FileSearcher.search_string = search_str
        UIManager:close(search_dialog)
        self.case_sensitive = check_button_case.checked
        self.include_subfolders = check_button_subfolders.checked
        self.include_metadata = check_button_metadata and check_button_metadata.checked
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            self:doSearch()
        end)
    end
    search_dialog = InputDialog:new{
        title = _("Enter text to search for in filename"),
        input = search_string or FileSearcher.search_string,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_dialog)
                    end,
                },
                {
                    text = _("Home folder"),
                    enabled = G_reader_settings:has("home_dir"),
                    callback = function()
                        self.path = G_reader_settings:readSetting("home_dir")
                        _doSearch()
                    end,
                },
                {
                    text = self.ui.file_chooser and _("Current folder") or _("Book folder"),
                    is_enter_default = true,
                    callback = function()
                        self.path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        _doSearch()
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_case)
    check_button_subfolders = CheckButton:new{
        text = _("Include subfolders"),
        checked = self.include_subfolders,
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_subfolders)
    if self.ui.coverbrowser then
        check_button_metadata = CheckButton:new{
            text = _("Also search in book metadata"),
            checked = self.include_metadata,
            parent = search_dialog,
        }
        search_dialog:addWidget(check_button_metadata)
    end
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

function FileSearcher:doSearch()
    local search_hash = self.path .. (FileSearcher.search_string or "") ..
        tostring(self.case_sensitive) .. tostring(self.include_subfolders) .. tostring(self.include_metadata)
    local not_cached = FileSearcher.search_hash ~= search_hash
    if not_cached then
        local Trapper = require("ui/trapper")
        local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
        UIManager:show(info)
        UIManager:forceRePaint()
        local completed, dirs, files, no_metadata_count = Trapper:dismissableRunInSubprocess(function()
            return self:getList()
        end, info)
        if not completed then return end
        UIManager:close(info)
        FileSearcher.search_hash = search_hash
        self.no_metadata_count = no_metadata_count
        -- Cannot do this in getList() within Trapper (cannot serialize function)
        local collate = FileChooser:getCollate()
        for i, v in ipairs(dirs) do
            local f, fullpath, attributes = unpack(v)
            dirs[i] = FileChooser:getListItem(nil, f, fullpath, attributes, collate)
        end
        for i, v in ipairs(files) do
            local f, fullpath, attributes = unpack(v)
            files[i] = FileChooser:getListItem(nil, f, fullpath, attributes, collate)
        end
        -- If we have a FileChooser instance, use it, to be able to make use of its natsort cache
        FileSearcher.search_results = (self.ui.file_chooser or FileChooser):genItemTable(dirs, files)
    end
    if #FileSearcher.search_results > 0 then
        self:onShowSearchResults(not_cached)
    else
        self:showSearchResultsMessage(true)
    end
end

function FileSearcher:getList()
    self.no_metadata_count = 0 -- will be updated in doSearch() with result from subprocess
    local sys_folders = { -- do not search in sys_folders
        ["/dev"] = true,
        ["/proc"] = true,
        ["/sys"] = true,
        ["/mnt/base-us"] = true, -- Kindle
    }
    local search_string = FileSearcher.search_string
    if search_string ~= "*" then -- one * to show all files
        if not self.case_sensitive then
            search_string = Utf8Proc.lowercase(util.fixUtf8(search_string, "?"))
        end
        -- replace '.' with '%.'
        search_string = search_string:gsub("%.","%%%.")
        -- replace '*' with '.*'
        search_string = search_string:gsub("%*","%.%*")
        -- replace '?' with '.'
        search_string = search_string:gsub("%?","%.")
    end

    local dirs, files = {}, {}
    local scan_dirs = {self.path}
    while #scan_dirs ~= 0 do
        local new_dirs = {}
        -- handle each dir
        for _, d in ipairs(scan_dirs) do
            -- handle files in d
            local ok, iter, dir_obj = pcall(lfs.dir, d)
            if ok then
                for f in iter, dir_obj do
                    local fullpath = "/" .. f
                    if d ~= "/" then
                        fullpath = d .. fullpath
                    end
                    local attributes = lfs.attributes(fullpath) or {}
                    -- Don't traverse hidden folders if we're not showing them
                    if attributes.mode == "directory" and f ~= "." and f ~= ".."
                            and (FileChooser.show_hidden or not util.stringStartsWith(f, "."))
                            and FileChooser:show_dir(f) then
                        if self.include_subfolders and not sys_folders[fullpath] then
                            table.insert(new_dirs, fullpath)
                        end
                        if self:isFileMatch(f, fullpath, search_string) then
                            table.insert(dirs, { f, fullpath, attributes })
                        end
                    -- Always ignore macOS resource forks, too.
                    elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                            and (FileChooser.show_unsupported or DocumentRegistry:hasProvider(fullpath))
                            and FileChooser:show_file(f) then
                        if self:isFileMatch(f, fullpath, search_string, true) then
                            table.insert(files, { f, fullpath, attributes })
                        end
                    end
                end
            end
        end
        scan_dirs = new_dirs
    end
    return dirs, files, self.no_metadata_count
end

function FileSearcher:isFileMatch(filename, fullpath, search_string, is_file)
    if search_string == "*" then
        return true
    end
    if not self.case_sensitive then
        filename = Utf8Proc.lowercase(util.fixUtf8(filename, "?"))
    end
    if string.find(filename, search_string) then
        return true
    end
    if self.include_metadata and is_file and DocumentRegistry:hasProvider(fullpath) then
        local book_props = self.ui.coverbrowser:getBookInfo(fullpath) or
                           self.ui.bookinfo.getDocProps(fullpath, nil, true) -- do not open the document
        if next(book_props) ~= nil then
            if self.ui.bookinfo:findInProps(book_props, search_string, self.case_sensitive) then
                return true
            end
        else
            self.no_metadata_count = self.no_metadata_count + 1
        end
    end
end

function FileSearcher:showSearchResultsMessage(no_results)
    local text = no_results and T(_("No results for '%1'."), FileSearcher.search_string)
    if self.no_metadata_count == 0 then
        UIManager:show(ConfirmBox:new{
            text = text,
            icon = "notice-info",
            ok_text = _("File search"),
            ok_callback = function()
                self:onShowFileSearch()
            end,
        })
    else
        local txt = T(N_("1 book has been skipped.", "%1 books have been skipped.",
            self.no_metadata_count), self.no_metadata_count) .. "\n" ..
            _("Not all books metadata extracted yet.\nExtract metadata now?")
        text = no_results and text .. "\n\n" .. txt or txt
        UIManager:show(ConfirmBox:new{
            text = text,
            ok_text = _("Extract"),
            ok_callback = function()
                if not no_results then
                    self.search_menu.close_callback()
                end
                self.ui.coverbrowser:extractBooksInDirectory(self.path)
            end,
        })
    end
end

function FileSearcher:onShowSearchResults(not_cached)
    if not not_cached and FileSearcher.search_results == nil then
        self:onShowFileSearch()
        return
    end

    self.search_menu = Menu:new{
        subtitle = T(_("Query: %1"), FileSearcher.search_string),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:setSelectMode() end,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        handle_hold_on_hold_release = true,
        ui = self.ui,
        _manager = self,
    }
    self.search_menu.close_callback = function()
        self.selected_files = nil
        UIManager:close(self.search_menu)
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
    end
    self:updateMenu(FileSearcher.search_results)
    UIManager:show(self.search_menu)
    if not_cached and self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
end

function FileSearcher:updateMenu(item_table)
    item_table = item_table or self.search_menu.item_table
    self.search_menu:switchItemTable(T(_("Search results (%1)"), #item_table), item_table, -1)
end

function FileSearcher:onMenuSelect(item)
    if lfs.attributes(item.path) == nil then return end
    if self._manager.selected_files then
        if item.is_file then
            item.dim = not item.dim and true or nil
            self._manager.selected_files[item.path] = item.dim
            self._manager:updateMenu()
        end
    else
        self._manager:showFileDialog(item)
    end
end

function FileSearcher:showFileDialog(item)
    local file = item.path
    local bookinfo, dialog
    local function close_dialog_callback()
        UIManager:close(dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(dialog)
        self.search_menu.close_callback()
    end
    local function update_item_callback()
        item.mandatory = FileChooser:getMenuItemMandatory(item, FileChooser:getCollate())
        self:updateMenu()
    end
    local buttons = {}
    if item.is_file then
        local is_currently_opened = self.ui.document and self.ui.document.file == file
        local has_provider = DocumentRegistry:hasProvider(file)
        local has_sidecar = DocSettings:hasSidecarFile(file)
        local doc_settings_or_file = is_currently_opened and self.ui.doc_settings
            or (has_sidecar and DocSettings:open(file) or file)
        if has_provider or has_sidecar then
            bookinfo = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)
            table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_callback))
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_callback, is_currently_opened),
                self.ui.collections:genAddToCollectionButton(file, close_dialog_callback, update_item_callback),
            })
        end
        table.insert(buttons, {
            {
                text = _("Delete"),
                enabled = not is_currently_opened,
                callback = function()
                    local function post_delete_callback()
                        UIManager:close(dialog)
                        table.remove(FileSearcher.search_results, item.idx)
                        table.remove(self.search_menu.item_table, item.idx)
                        self:updateMenu()
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager:showDeleteFileDialog(file, post_delete_callback)
                end,
            },
            filemanagerutil.genBookInformationButton(doc_settings_or_file, bookinfo, close_dialog_callback),
        })
    end
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        {
            text = _("Open"),
            enabled = DocumentRegistry:hasProvider(file, nil, true), -- allow auxiliary providers
            callback = function()
                close_dialog_menu_callback()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager.openFile(self.ui, file)
            end,
        },
    })
    local title = file
    if bookinfo then
        if bookinfo.title then
            title = title .. "\n\n" .. T(_("Title: %1"), bookinfo.title)
        end
        if bookinfo.authors then
            title = title .. "\n" .. T(_("Authors: %1"), bookinfo.authors:gsub("[\n\t]", "|"))
        end
    end
    dialog = ButtonDialog:new{
        title = title .. "\n",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function FileSearcher:onMenuHold(item)
    if self._manager.selected_files or lfs.attributes(item.path) == nil then return true end
    if item.is_file then
        if DocumentRegistry:hasProvider(item.path, nil, true) then
            self.close_callback()
            local FileManager = require("apps/filemanager/filemanager")
            FileManager.openFile(self.ui, item.path)
        end
    else
        self.close_callback()
        if self.ui.file_chooser then
            local pathname = util.splitFilePathName(item.path)
            self.ui.file_chooser:changeToPath(pathname, item.path)
        else -- called from Reader
            self.ui:onClose()
            self.ui:showFileManager(item.path)
        end
    end
    return true
end

function FileSearcher:setSelectMode()
    if self.selected_files then
        self:showSelectModeDialog()
    else
        self.selected_files = {}
        self.search_menu:setTitleBarLeftIcon("check")
    end
end

function FileSearcher:showSelectModeDialog()
    local item_table = self.search_menu.item_table
    local select_count = util.tableSize(self.selected_files)
    local actions_enabled = select_count > 0
    local title = actions_enabled and T(N_("1 file selected", "%1 files selected", select_count), select_count)
        or _("No files selected")
    local select_dialog
    local buttons = {
        {
            {
                text = _("Deselect all"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    for file in pairs (self.selected_files) do
                        self.selected_files[file] = nil
                    end
                    for _, item in ipairs(item_table) do
                        item.dim = nil
                    end
                    self:updateMenu()
                end,
            },
            {
                text = _("Select all"),
                callback = function()
                    UIManager:close(select_dialog)
                    for _, item in ipairs(item_table) do
                        if item.is_file then
                            item.dim = true
                            self.selected_files[item.path] = true
                        end
                    end
                    self:updateMenu()
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self.selected_files = nil
                    self.search_menu:setTitleBarLeftIcon("appbar.menu")
                    if actions_enabled then
                        for _, item in ipairs(item_table) do
                            item.dim = nil
                        end
                    end
                    self:updateMenu()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    self.search_menu.close_callback()
                    if self.ui.file_chooser then
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        self.ui.file_chooser:refreshPath()
                    else -- called from Reader
                        self.ui:onClose()
                        self.ui:showFileManager(self.path .. "/", selected_files)
                    end
                end,
            },
        },
    }
    select_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(select_dialog)
end

return FileSearcher
