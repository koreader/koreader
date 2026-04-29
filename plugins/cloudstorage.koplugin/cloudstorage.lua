local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonSelector = require("ui/widget/buttonselector")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local ProgressbarDialog = require("ui/widget/progressbardialog")
local SortWidget = require("ui/widget/sortwidget")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = ffiUtil.template

local CloudStorage = BookList:extend{
    collates = {
        strcoll = {
            text = _("name"),
            sort_func = function(a, b)
                return ffiUtil.strcoll(a.text, b.text)
            end,
        },
        type = {
            text = _("type"),
            sort_func = function(a, b)
                if (a.suffix or b.suffix) and a.suffix ~= b.suffix then
                    return ffiUtil.strcoll(a.suffix, b.suffix)
                end
                return ffiUtil.strcoll(a.text, b.text)
            end,
        },
        size = {
            text = _("size"),
            sort_func = function(a, b)
                if a.filesize and b.filesize then
                    return a.filesize < b.filesize
                end
                return ffiUtil.strcoll(a.text, b.text)
            end,
        },
        date = {
            text = _("date modified"),
            sort_func = function(a, b)
                if a.modification and b.modification then
                    return a.modification > b.modification
                end
                return ffiUtil.strcoll(a.text, b.text)
            end,
        },
    },
}

function CloudStorage:init(re_init)
    self.choose_folder_callback = nil
    self.item_table = {}
    for i, server in ipairs(self.servers) do
        if self.providers[server.type] then
            table.insert(self.item_table, self:genItemFromServer(i))
        end
        if #self.item_table > 1 then
            table.sort(self.item_table, function(a, b) return a.order < b.order end)
        end
    end
    self.onLeftButtonTap = self.showPlusRootDialog
    if re_init then
        self.paths = {}
        self:switchItemTable(self.title, self.item_table, self.item_idx, nil, "")
        self.item_idx = nil -- set item_idx before opening a server to keep the page when reopening the root list
    else
        self.title_bar_left_icon = "plus"
        BookList.init(self)
    end
end

function CloudStorage:genItemFromServer(idx)
    local server = self.servers[idx]
    local mandatory = self.providers[server.type].name
    if idx == self.settings:readSetting("default_server") then
        mandatory = "★ " .. mandatory
    end
    return {
        text = server.name,
        mandatory = mandatory,
        server_idx = idx,
        type = server.type,
        url = server.url,
        order = server.order or idx,
    }
end

function CloudStorage:initServer(server_idx)
    local server = self.servers[server_idx]
    self.provider = self.providers[server.type]
    self.address = server.address
    self.username = server.username
    self.password = server.password
    self.collate = server.collate or "strcoll"
    return server
end

function CloudStorage:sortItemTable(tbl, url)
    tbl = tbl or self.item_table
    if #tbl == 0 then return end
    local folder_mode_item
    if self.choose_folder_callback and tbl[1].is_folder_long_press then
        folder_mode_item = table.remove(tbl, 1)
    end
    local sort_func = self.collates[self.collate].sort_func
    table.sort(tbl, function(a, b)
        if a.is_file and b.is_file then
            return sort_func(a, b)
        elseif a.is_folder and b.is_folder then
            return ffiUtil.strcoll(a.text, b.text)
        else -- folders first
            return a.is_folder
        end
    end)
    if self.choose_folder_callback then
        table.insert(tbl, 1, folder_mode_item or {
            is_folder_long_press = true,
            text = _("Long-press here to choose current folder"),
            bold = true,
            url = url,
        })
    end
end

function CloudStorage:show()
    local default_server_idx = self.settings:readSetting("default_server")
    if default_server_idx then -- open default server
        self.server_idx = default_server_idx
        local url = self.servers[default_server_idx].url
        table.insert(self.paths, { url = url })
        self:openCloudServer(url, true)
    else -- show root list of servers
        UIManager:show(self)
    end
end

function CloudStorage:openCloudServer(url, do_show)
    if self.caller_choose_folder_callback then
        self.choose_folder_callback = true
    end
    local server = self:initServer(self.server_idx)
    url = url or server.url
    self.provider.run(function()
        local tbl = self.provider.listFolder(url, true) -- including folders
        if tbl then
            self.onLeftButtonTap = function()
                self:showPlusCloudDialog(url)
            end
            self:sortItemTable(tbl, url)
            self:switchItemTable(server.name, tbl, nil, nil, url == "" and "/" or url)
            if do_show then
                UIManager:show(self)
            end
        else
            table.remove(self.paths)
            self.choose_folder_callback = nil
            if do_show then
                -- could not show the server content; show the root list of servers
                -- "flashui" is needed when called with wi-fi off (NetworkMgr:willRerunWhenConnected())
                UIManager:show(self, "flashui")
            end
            UIManager:show(InfoMessage:new{
                text = T(_("Server: %1"), server.name) .. "\n" ..
                    _("Could not fetch server's content.\nPlease check your configuration or network connection."),
            })
        end
    end)
end

function CloudStorage:onReturn()
    if #self.paths > 0 then
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            self:openCloudServer(path.url)
        else -- return to root list
            self:init(true)
        end
    end
    return true
end

function CloudStorage:onHoldReturn()
    if #self.paths > 1 then -- return to the server start folder
        local path = self.paths[1]
        if path then
            for i = #self.paths, 2, -1 do
                table.remove(self.paths)
            end
            self:openCloudServer(path.url)
        end
    end
    return true
end

function CloudStorage:onMenuSelect(item)
    if item.server_idx then -- root list
        table.insert(self.paths, { url = item.url })
        self.item_idx = item.idx
        self.server_idx = item.server_idx
        self:openCloudServer()
    elseif item.is_folder then
        table.insert(self.paths, { url = item.url })
        self:openCloudServer(item.url)
    elseif item.is_file and not self.choose_folder_callback then
        self:showFileDownloadDialog(item)
    end
    return true
end

function CloudStorage:onMenuHold(item)
    if self.choose_folder_callback then
        if item.is_folder or item.is_folder_long_press then
            self:showFolderChooseDialog(item)
        end
    else
        if item.server_idx then -- root list
            self:showServerDialog(item)
        elseif item.is_file then
            self:showFileDeleteDialog(item)
        end
    end
    return true
end

function CloudStorage:showFolderChooseDialog(item)
    local url = item.url == "" and "/" or item.url
    local folder_dialog
    folder_dialog = ButtonDialog:new{
        title = _("Choose this folder?") .. "\n\n" .. BD.dirpath(url) .. "\n",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(folder_dialog)
                    end,
                },
                {
                    text = _("Choose"),
                    callback = function()
                        UIManager:close(folder_dialog)
                        if self.caller_choose_folder_callback then
                            self:onClose()
                            local server = self.servers[self.server_idx]
                            self.caller_choose_folder_callback({
                                name     = server.name,
                                type     = server.type,
                                address  = server.address,
                                username = server.username,
                                password = server.password,
                                url      = item.url,
                            })
                        else
                            self.choose_folder_callback(item.url)
                            self:init(true)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(folder_dialog)
end

function CloudStorage:showFileDeleteDialog(item)
    if self.provider.deleteFile then
        UIManager:show(ConfirmBox:new{
            text = _("Delete this file?") .. "\n\n" .. item.text,
            ok_text = _("Delete"),
            ok_callback = function()
                local ok = self.provider.deleteFile(item.url)
                if ok then
                    table.remove(self.item_table, item.idx)
                    self:switchItemTable()
                else
                    UIManager:show(InfoMessage:new{ text = T(_("Could not delete file:\n%1"), item.text) })
                end
            end,
        })
    end
end

function CloudStorage:showServerDialog(item)
    local is_not_default_server = item.server_idx ~= self.settings:readSetting("default_server")
    local provider = self.providers[item.type]
    local server_dialog
    local buttons = {
        {
            {
                text = is_not_default_server and _("Set default") or _("Reset default"),
                callback = function()
                    UIManager:close(server_dialog)
                    local idx = is_not_default_server and item.server_idx or nil
                    self.settings:saveSetting("default_server", idx)
                    self._manager.updated = true
                    self:init(true)
                end,
            },
        },
        {
            {
                text = _("Remove server"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Remove this server?") .. "\n\n" .. item.text,
                        ok_text = _("Remove"),
                        ok_callback = function()
                            UIManager:close(server_dialog)
                            table.remove(self.servers, item.server_idx)
                            local default_server_idx = self.settings:readSetting("default_server")
                            if default_server_idx then
                                if default_server_idx == item.server_idx then
                                    self.settings:delSetting("default_server")
                                elseif default_server_idx > item.server_idx then
                                    self.settings:saveSetting("default_server", default_server_idx - 1)
                                end
                            end
                            self._manager.updated = true
                            self:init(true)
                        end,
                    })
                end,
            },
            {
                text = _("Server settings"),
                callback = function()
                    UIManager:close(server_dialog)
                    local update_callback = function()
                        self._manager.updated = true
                        self.item_table[item.idx] = self:genItemFromServer(item.server_idx)
                        self:updateItems(1, true)
                    end
                    provider.config(item.server_idx, update_callback)
                end,
            },
        },
    }
    if provider.downloadFile and not self.caller_choose_folder_callback then
        local server = self.servers[item.server_idx]
        table.insert(buttons, {}) -- separator
        table.insert(buttons, {
            {
                text = _("Sync now"),
                enabled = server.sync_source_folder ~= nil and server.sync_dest_folder ~= nil,
                callback = function()
                    UIManager:close(server_dialog)
                    self:syncCloud(item)
                end,
            },
            {
                text = _("Sync settings"),
                callback = function()
                    UIManager:close(server_dialog)
                    self:showSyncSettingsDialog(item)
                end,
            },
        })
    end
    server_dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(server_dialog)
end

function CloudStorage:showPlusRootDialog()
    local plus_root_dialog
    local buttons = {}
    for _, provider in pairs(self.providers) do
        table.insert(buttons, {
            {
                text = provider.name, -- add new storage
                callback = function()
                    UIManager:close(plus_root_dialog)
                    local update_callback = function(new_server)
                        self._manager.updated = true
                        local max_order = #self.servers
                        for _, item in ipairs(self.servers) do
                            if max_order < item.order then
                                max_order = item.order
                            end
                        end
                        new_server.order = max_order + 1
                        local next_idx = #self.servers + 1
                        self.servers[next_idx] = new_server
                        self.item_table[next_idx] = self:genItemFromServer(next_idx)
                        self:switchItemTable(nil, self.item_table, next_idx)
                    end
                    provider.config(nil, update_callback)
                end,
            },
        })
    end
    if #buttons > 1 then
        table.sort(buttons, function(a, b) return ffiUtil.strcoll(a[1].text, b[1].text) end)
    end
    table.insert(buttons, {}) -- separator
    table.insert(buttons, {
        {
            text = _("Arrange servers"),
            enabled = #self.item_table > 1,
            callback = function()
                UIManager:close(plus_root_dialog)
                local sort_widget
                sort_widget = SortWidget:new{
                    title = _("Arrange servers"),
                    item_table = self.item_table,
                    callback = function()
                        self._manager.updated = true
                        for i, item in ipairs(sort_widget.item_table) do
                            self.servers[item.server_idx].order = i
                        end
                        self:init(true)
                    end,
                }
                UIManager:show(sort_widget)
            end,
        },
    })
    plus_root_dialog = ButtonDialog:new{
        title = _("Add new server"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(plus_root_dialog)
end

function CloudStorage:showPlusCloudDialog(url)
    local plus_cloud_dialog
    plus_cloud_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = _("New folder"),
                    enabled = self.provider.createFolder and true or false,
                    callback = function()
                        UIManager:close(plus_cloud_dialog)
                        self:showFolderCreateDialog(url)
                    end,
                },
            },
            {
                {
                    text = _("Upload selected files"),
                    enabled = self.provider.uploadFile and not self.choose_folder_callback
                        and self._manager.ui.selected_files ~= nil,
                    callback = function()
                        UIManager:close(plus_cloud_dialog)
                        self:showSelectedFilesUploadDialog(url)
                    end,
                },
                {
                    text = _("Upload file"),
                    enabled = self.provider.uploadFile and not self.choose_folder_callback,
                    callback = function()
                        UIManager:close(plus_cloud_dialog)
                        self:showFileUploadDialog(url)
                    end,
                },
            },
            {}, -- separator
            {
                {
                    text = _("Info"),
                    enabled = self.provider.info and true or false,
                    callback = function()
                        UIManager:close(plus_cloud_dialog)
                        self.provider.info()
                    end,
                },
                {
                    text = T(_("Sort by: %1"), self.collates[self.collate].text),
                    callback = function()
                        UIManager:show(ButtonSelector:new{
                            current_value = self.collate,
                            values = {
                                { self.collates["strcoll"].text, "strcoll" },
                                { self.collates["type"].text, "type" },
                                { self.collates["size"].text, "size" },
                                { self.collates["date"].text, "date" },
                            },
                            callback = function(value)
                                UIManager:close(plus_cloud_dialog)
                                if self.collate ~= value then
                                    self.collate = value
                                    self.servers[self.server_idx].collate = value ~= "strcoll" and value or nil
                                    self._manager.updated = true
                                    self:sortItemTable()
                                    self:updateItems(1, true)
                                end
                            end,
                        })
                    end,
                },
            },
            {
                {
                    text = _("Return to server list"),
                    callback = function()
                        UIManager:close(plus_cloud_dialog)
                        self:init(true)
                    end,
                },
            },
        },
    }
    UIManager:show(plus_cloud_dialog)
end

function CloudStorage:showFileDownloadDialog(item)
    if self.provider.downloadFile == nil then return end
    local function startDownloadFile(unit_item, local_path)
        local progressbar_dialog = ProgressbarDialog:new{
            title = _("Downloading…"),
            subtitle = unit_item.text,
            progress_max = unit_item.filesize,
        }
        UIManager:scheduleIn(1, function()
            local progress_callback = function(progress)
                progressbar_dialog:reportProgress(progress)
            end
            local code = self.provider.downloadFile(unit_item.url, local_path, progress_callback)
            progressbar_dialog:close()
            if code == 200 then
                local text = T(_("File saved to:\n%1"), BD.filepath(local_path))
                if DocumentRegistry:hasProvider(local_path) then
                    UIManager:show(ConfirmBox:new{
                        text = text .. "\n\n" .. _("Would you like to read the downloaded book now?"),
                        ok_callback = function()
                            self:onClose()
                            filemanagerutil.openFile(self._manager.ui, local_path, nil, true)
                        end,
                    })
                else
                    UIManager:show(InfoMessage:new{ text = text })
                end
            else
                UIManager:show(InfoMessage:new{ text = T(_("Could not save file to:\n%1"), BD.filepath(local_path)) })
            end
        end)
        progressbar_dialog:show()
    end

    local function createTitle(filename_orig, filesize, filename, path) -- title for ButtonDialog
        local filesize_str = filesize and util.getFriendlySize(filesize) or _("N/A")
        return T(_("Filename:\n%1\n\nFile size:\n%2\n\nDownload filename:\n%3\n\nDownload folder:\n%4"),
            filename_orig, filesize_str, filename, BD.dirpath(path))
    end

    local download_dir = self.settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
    local filename_orig = item.text
    local filename = filename_orig
    local filesize = item.filesize

    local download_dialog
    local buttons = {
        {
            {
                text = _("Choose folder"),
                callback = function()
                    UIManager:show(PathChooser:new{
                        select_file = false,
                        path = download_dir,
                        onConfirm = function(path)
                            self.settings:saveSetting("download_dir", path)
                            self._manager.updated = true
                            download_dir = path
                            download_dialog:setTitle(createTitle(filename_orig, filesize, filename, download_dir))
                        end,
                    })
                end,
            },
            {
                text = _("Change filename"),
                callback = function()
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter filename"),
                        input = filename,
                        input_hint = filename_orig,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(input_dialog)
                                    end,
                                },
                                {
                                    text = _("Set filename"),
                                    is_enter_default = true,
                                    callback = function()
                                        filename = input_dialog:getInputValue()
                                        if filename == "" then
                                            filename = filename_orig
                                        end
                                        UIManager:close(input_dialog)
                                        download_dialog:setTitle(createTitle(filename_orig, filesize, filename, download_dir))
                                    end,
                                },
                            }
                        },
                    }
                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(download_dialog)
                end,
            },
            {
                text = _("Download"),
                callback = function()
                    UIManager:close(download_dialog)
                    local local_path = (download_dir ~= "/" and download_dir or "") .. "/" .. filename
                    local_path = util.fixUtf8(local_path, "_")
                    if lfs.attributes(local_path) then
                        UIManager:show(ConfirmBox:new{
                            text = _("File already exists. Would you like to overwrite it?"),
                            ok_callback = function()
                                startDownloadFile(item, local_path)
                            end,
                        })
                    else
                        startDownloadFile(item, local_path)
                    end
                end,
            },
        },
    }

    download_dialog = ButtonDialog:new{
        title = createTitle(filename_orig, filesize, filename, download_dir),
        buttons = buttons,
    }
    UIManager:show(download_dialog)
end

function CloudStorage:showFileUploadDialog(url)
    UIManager:show(PathChooser:new{
        select_directory = false,
        path = self.last_path,
        onConfirm = function(file_path)
            self.last_path = file_path:match("(.*)/")
            if self.last_path == "" then self.last_path = "/" end
            if lfs.attributes(file_path, "size") > 157286400 then
                UIManager:show(InfoMessage:new{ text = _("File size must be less than 150 MB.") })
            else
                UIManager:nextTick(function()
                    UIManager:show(InfoMessage:new{
                        text = _("Uploading…"),
                        timeout = 1,
                    })
                end)
                UIManager:tickAfterNext(function()
                    local url_base = url ~= "/" and url or ""
                    local code = self.provider.uploadFile(url_base, file_path)
                    if code == 200 then
                        self:openCloudServer(url)
                        UIManager:show(InfoMessage:new{ text = T(_("File uploaded:\n%1"), BD.filepath(file_path)) })
                    else
                        UIManager:show(InfoMessage:new{ text = T(_("Could not upload file:\n%1"), BD.filepath(file_path)) })
                    end
                end)
            end
        end,
    })
end

function CloudStorage:showSelectedFilesUploadDialog(url)
    local files = self._manager.ui.selected_files
    local files_nb = util.tableSize(files)
    UIManager:show(ConfirmBox:new{
        text = T(N_("Upload 1 file?", "Upload %1 files?", files_nb), files_nb),
        ok_text = _("Upload"),
        ok_callback = function()
            local url_base = url ~= "/" and url or ""
            local Trapper = require("ui/trapper")
            Trapper:wrap(function()
                Trapper:setPausedText("Upload paused.\nDo you want to continue or abort uploading files?")
                local proccessed_files, success_files, unsuccess_files = 0, 0, 0
                for file in pairs(files) do
                    proccessed_files = proccessed_files + 1
                    local text = string.format("Uploading file (%d/%d):\n%s", proccessed_files, files_nb, file:gsub(".*/", ""))
                    if not Trapper:info(text) then
                        break
                    end
                    local code = self.provider.uploadFile(url_base, file)
                    if code == 200 then
                        files[file] = nil
                        success_files = success_files + 1
                    else
                        unsuccess_files = unsuccess_files + 1
                    end
                end
                Trapper:clear()
                if success_files > 0 then
                    self:openCloudServer(url)
                end
                local text = T(N_("Uploaded 1 file.", "Uploaded %1 files.", success_files), success_files)
                if unsuccess_files > 0 then
                    text = text .. "\n" ..
                        T(N_("Could not upload 1 file.", "Could not upload %1 files.", unsuccess_files), unsuccess_files)
                end
                UIManager:show(InfoMessage:new{ text = text })
                if not next(files) then
                    self._manager.ui:onToggleSelectMode()
                end
            end)
        end,
    })
end

function CloudStorage:showFolderCreateDialog(url)
    local input_dialog, check_button_enter_folder
    input_dialog = InputDialog:new{
        title = _("New folder"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local folder_name = input_dialog:getInputText()
                        if folder_name == "" then return end
                        UIManager:close(input_dialog)
                        local url_base = url ~= "/" and url or ""
                        local ok = self.provider.createFolder(url_base, folder_name)
                        if ok then
                            if check_button_enter_folder.checked then
                                url = url_base .. "/" .. folder_name
                                table.insert(self.paths, { url = url })
                            end
                            self:openCloudServer(url)
                        else
                            UIManager:show(InfoMessage:new{ text = T(_("Could not create folder:\n%1"), folder_name) })
                        end
                    end,
                },
            }
        },
    }
    check_button_enter_folder = CheckButton:new{
        text = _("Enter folder after creation"),
        checked = false,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_enter_folder)
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function CloudStorage:showSyncSettingsDialog(item)
    local server = self.servers[item.server_idx]
    local sync_source_folder = server.sync_source_folder == "" and "/" or server.sync_source_folder
    local sync_dialog
    sync_dialog = ButtonDialog:new{
        title = server.name .. "\n\n" .. T(_("Remote (source) folder:\n%1\nLocal (destination) folder:\n%2"),
            sync_source_folder and BD.dirpath(sync_source_folder) or _("not set"),
            server.sync_dest_folder and BD.dirpath(server.sync_dest_folder) or _("not set")),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Choose remote folder"),
                    callback = function()
                        UIManager:close(sync_dialog)
                        self.choose_folder_callback = function(path)
                            server.sync_source_folder = path
                            self._manager.updated = true
                            self:showSyncSettingsDialog(item)
                        end
                        table.insert(self.paths, { url = item.url })
                        self.item_idx = item.idx
                        self.server_idx = item.server_idx
                        self:openCloudServer()
                    end,
                },
            },
            {
                {
                    text = _("Choose local folder"),
                    callback = function()
                        UIManager:close(sync_dialog)
                        UIManager:show(PathChooser:new{
                            select_file = false,
                            path = server.sync_dest_folder,
                            onConfirm = function(path)
                                server.sync_dest_folder = path
                                self._manager.updated = true
                                self:showSyncSettingsDialog(item)
                            end,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(sync_dialog)
end

function CloudStorage:syncCloud(item)
    local server = self:initServer(item.server_idx)
    self.provider.run(function()
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            Trapper:setPausedText("Download paused.\nDo you want to continue or abort downloading files?")
            Trapper:info(_("Retrieving files…"))
            local url = server.sync_source_folder == "/" and "" or server.sync_source_folder
            local remote_files = self.provider.listFolder(url) -- excluding folders
            if not remote_files then
                Trapper:clear()
                UIManager:show(InfoMessage:new{
                    text = T(_("Server: %1"), server.name) .. "\n" ..
                        _("Could not fetch server's content.\nPlease check your configuration or network connection."),
                })
                return
            end

            local local_files = {}
            local path = server.sync_dest_folder
            local ok, iter, dir_obj = pcall(lfs.dir, path)
            if ok then
                for f in iter, dir_obj do
                    local filename = path .."/" .. f
                    local attributes = lfs.attributes(filename)
                    if attributes.mode == "file" then
                        local_files[f] = attributes.size
                    end
                end
            end

            local files_to_download = 0
            for i, file in ipairs(remote_files) do
                if not local_files[file.text] or local_files[file.text] ~= file.filesize then
                    files_to_download = files_to_download + 1
                    remote_files[i].download = true
                end
            end
            if files_to_download == 0 then
                Trapper:clear()
                UIManager:show(InfoMessage:new{ text = _("No files to download.") })
                return
            end

            local proccessed_files, success_files, unsuccess_files = 0, 0, 0
            for _, file in ipairs(remote_files) do
                if file.download then
                    proccessed_files = proccessed_files + 1
                    local text = string.format("Downloading file (%d/%d):\n%s", proccessed_files, files_to_download, file.text)
                    if not Trapper:info(text) then
                        break
                    end
                    local code = self.provider.downloadFile(file.url, server.sync_dest_folder .. "/" .. file.text)
                    if code == 200 then
                        success_files = success_files + 1
                    else
                        unsuccess_files = unsuccess_files + 1
                    end
                end
            end
            Trapper:clear()
            local text = T(N_("Downloaded 1 file.", "Downloaded %1 files.", success_files), success_files)
            if unsuccess_files > 0 then
                text = text .. "\n" ..
                    T(N_("Could not download 1 file.", "Could not download %1 files.", unsuccess_files), unsuccess_files)
            end
            UIManager:show(InfoMessage:new{ text = text })
        end)
    end)
end

return CloudStorage
