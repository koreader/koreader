local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local DropBox = require("apps/cloudstorage/dropbox")
local FFIUtil = require("ffi/util")
local Ftp = require("apps/cloudstorage/ftp")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WebDav = require("apps/cloudstorage/webdav")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local SyncCommon = require("apps/cloudstorage/synccommon")
local Trapper = require("ui/trapper")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local util = require("util")

local CloudStorage = Menu:extend{
    no_title = false,
    show_parent = nil,
    is_popout = false,
    is_borderless = true,
    title = _("Cloud storage"),
}

local server_types = {
    dropbox = _("Dropbox"),
    ftp = _("FTP"),
    webdav = _("WebDAV"),
}

function CloudStorage:init()
    --- @todo: Probably a good candidate for the new readSetting API
    self.cs_settings = self:readSettings()
    self.show_parent = self
    if self.item then
        self.item_table = self:genItemTable(self.item)
        self.choose_folder_mode = true
    else
        self.item_table = self:genItemTableFromRoot()
    end
    self.title_bar_left_icon = "plus"
    self.onLeftButtonTap = function() -- add new cloud storage
        self:selectCloudType()
    end
    Menu.init(self)
    if self.item then
        self.item_table[1].callback()
    end
end

function CloudStorage:genItemTableFromRoot()
    local item_table = {}
    local added_servers = self.cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(added_servers) do
        table.insert(item_table, {
            text = server.name,
            mandatory = server_types[server.type],
            address = server.address,
            username = server.username,
            password = server.password,
            type = server.type,
            editable = true,
            url = server.url,
            sync_source_folder = server.sync_source_folder,
            sync_dest_folder = server.sync_dest_folder,
            callback = function()
                self.type = server.type
                self.password = server.password
                self.address = server.address
                self.username = server.username
                self:openCloudServer(server.url)
            end,
        })
    end
    return item_table
end

function CloudStorage:genItemTable(item)
    local item_table = {}
    local added_servers = self.cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(added_servers) do
        if server.name == item.text and server.password == item.password and server.type == item.type then
            table.insert(item_table, {
                text = server.name,
                address = server.address,
                username = server.username,
                password = server.password,
                type = server.type,
                url = server.url,
                callback = function()
                    self.type = server.type
                    self.password = server.password
                    self.address = server.address
                    self.username = server.username
                    self:openCloudServer(server.url)
                end,
            })
        end
    end
    return item_table
end

function CloudStorage:selectCloudType()
    local buttons = {}
    for server_type, name in FFIUtil.orderedPairs(server_types) do
        table.insert(buttons, {
            {
                text = name,
                callback = function()
                    UIManager:close(self.cloud_dialog)
                    self:configCloud(server_type)
                end,
            },
        })
    end
    self.cloud_dialog = ButtonDialog:new{
        title = _("Add new cloud storage"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.cloud_dialog)
    return true
end

function CloudStorage:generateDropBoxAccessToken()
    if self.username or self.address == nil or self.address == "" then
        -- short-lived token has been generated already in this session
        -- or we have long-lived token in self.password
        return true
    else
        local token = DropBox:getAccessToken(self.password, self.address)
        if token then
            self.password = token -- short-lived token
            self.username = true -- flag
            return true
        end
    end
end

function CloudStorage:openCloudServer(url)
    local tbl, e
    logger.dbg("CloudStorage:openCloudServer type=", self.type, " url=", url or "")
    if self.type == "dropbox" then
        if NetworkMgr:willRerunWhenOnline(function() self:openCloudServer(url) end) then
            return
        end
        if self:generateDropBoxAccessToken() then
            logger.dbg("CloudStorage:openCloudServer calling DropBox:run")
            tbl, e = DropBox:run(url, self.password, self.choose_folder_mode)
        end
    elseif self.type == "ftp" then
        if NetworkMgr:willRerunWhenConnected(function() self:openCloudServer(url) end) then
            return
        end
        tbl, e = Ftp:run(self.address, self.username, self.password, url)
    elseif self.type == "webdav" then
        if NetworkMgr:willRerunWhenConnected(function() self:openCloudServer(url) end) then
            return
        end
        logger.dbg("CloudStorage:openCloudServer calling WebDav:run")
        tbl, e = WebDav:run(self.address, self.username, self.password, url, self.choose_folder_mode)
    end
    if tbl then
        self:switchItemTable(url, tbl)
        if self.type == "dropbox" or self.type == "webdav" then
            self.onLeftButtonTap = function()
                self:showPlusMenu(url)
            end
        else
            self:setTitleBarLeftIcon("home")
            self.onLeftButtonTap = function()
                self:init()
            end
        end
        return true
    else
        logger.err("CloudStorage:openCloudServer failed:", e)
        UIManager:show(InfoMessage:new{
            text = _("Cannot fetch list of folder contents\nPlease check your configuration or network connection."),
            timeout = 3,
        })
        table.remove(self.paths)
        return false
    end
end

function CloudStorage:onMenuSelect(item)
    if item.callback then
        if item.url ~= nil then
            table.insert(self.paths, {
                url = item.url,
            })
        end
        item.callback()
    elseif item.type == "file" then
        self:downloadFile(item)
    elseif item.type == "other" then
        return true
    else
        table.insert(self.paths, {
            url = item.url,
        })
        if not self:openCloudServer(item.url) then
            table.remove(self.paths)
        end
    end
    return true
end

function CloudStorage:downloadFile(item)
    local function startDownloadFile(unit_item, address, username, password, path_dir, callback_close)
        UIManager:scheduleIn(1, function()
            if self.type == "dropbox" then
                DropBox:downloadFile(unit_item, password, path_dir, callback_close)
            elseif self.type == "ftp" then
                Ftp:downloadFile(unit_item, address, username, password, path_dir, callback_close)
            elseif self.type == "webdav" then
                WebDav:downloadFile(unit_item, address, username, password, path_dir, callback_close)
            end
        end)
        UIManager:show(InfoMessage:new{
            text = _("Downloading. This might take a moment."),
            timeout = 1,
        })
    end

    local function createTitle(filename_orig, filesize, filename, path) -- title for ButtonDialog
        local filesize_str = filesize and util.getFriendlySize(filesize) or _("N/A")

        return T(_("Filename:\n%1\n\nFile size:\n%2\n\nDownload filename:\n%3\n\nDownload folder:\n%4"),
            filename_orig, filesize_str, filename, BD.dirpath(path))
    end

    local cs_settings = self:readSettings()
    local download_dir = cs_settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
    local filename_orig = item.text
    local filename = filename_orig
    local filesize = item.filesize

    local buttons = {
        {
            {
                text = _("Choose folder"),
                callback = function()
                    require("ui/downloadmgr"):new{
                        onConfirm = function(path)
                            self.cs_settings:saveSetting("download_dir", path)
                            self.cs_settings:flush()
                            download_dir = path
                            self.download_dialog:setTitle(createTitle(filename_orig, filesize, filename, download_dir))
                        end,
                    }:chooseDir(download_dir)
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
                                        self.download_dialog:setTitle(createTitle(filename_orig, filesize, filename, download_dir))
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
                    UIManager:close(self.download_dialog)
                end,
            },
            {
                text = _("Download"),
                callback = function()
                    UIManager:close(self.download_dialog)
                    local path_dir = (download_dir ~= "/" and download_dir or "") .. '/' .. filename
                    local callback_close = function() self:onClose() end
                    if lfs.attributes(path_dir) then
                        UIManager:show(ConfirmBox:new{
                            text = _("File already exists. Would you like to overwrite it?"),
                            ok_callback = function()
                                startDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                            end
                        })
                    else
                        startDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                    end
                end,
            },
        },
    }

    self.download_dialog = ButtonDialog:new{
        title = createTitle(filename_orig, filesize, filename, download_dir),
        buttons = buttons,
    }
    UIManager:show(self.download_dialog)
end

function CloudStorage:updateSyncFolder(item, source, dest)
    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(cs_servers) do
        if server.name == item.text and server.password == item.password and server.type == item.type then
            if source then
                server.sync_source_folder = source
            end
            if dest then
                server.sync_dest_folder = dest
            end
            break
        end
    end
    cs_settings:saveSetting("cs_servers", cs_servers)
    cs_settings:flush()
end

function CloudStorage:onMenuHold(item)
    if item.type == "folder_long_press" then
        local title = T(_("Choose this folder?\n\n%1"), BD.dirpath(item.url))
        local onConfirm = self.onConfirm
        local button_dialog
        button_dialog = ButtonDialog:new{
            title = title,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(button_dialog)
                        end,
                    },
                    {
                        text = _("Choose"),
                        callback = function()
                            if onConfirm then
                                onConfirm(item.url)
                            end
                            UIManager:close(button_dialog)
                            UIManager:close(self)
                        end,
                    },
                },
            },
        }
        UIManager:show(button_dialog)
    end
    if item.editable then
        local cs_server_dialog
        local buttons = {
            {
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:infoServer(item)
                    end
                },
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:editCloudServer(item)
                    end
                },
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:deleteCloudServer(item)
                    end
                },
            },
        }
        if item.type == "dropbox" or item.type == "webdav" then
            table.insert(buttons, {
                {
                    text = _("Synchronize now"),
                    enabled = item.sync_source_folder ~= nil and item.sync_dest_folder ~= nil,
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:synchronizeCloud(item)
                    end
                },
                {
                    text = _("Synchronize settings"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:synchronizeSettings(item) 
                    end
                },
            })
        end
        cs_server_dialog = ButtonDialog:new{
            buttons = buttons
        }
        UIManager:show(cs_server_dialog)
        return true
    end
end

function CloudStorage:synchronizeCloud(item)
    self.type = item.type
    if self.type == "dropbox" then
        if NetworkMgr:willRerunWhenOnline(function() self:synchronizeCloud(item) end) then
            return
        end
    elseif self.type == "webdav" then
        if NetworkMgr:willRerunWhenConnected(function() self:synchronizeCloud(item) end) then
            return
        end
    else
        return
    end
    self.password = item.password
    self.address = item.address
    self.username = item.username
    logger.dbg("CloudStorage:synchronizeCloud type=", item.type, " item=", item.text)
    
    Trapper:wrap(function()
        Trapper:setPausedText(_("Download paused.\nDo you want to continue or abort downloading files?"))
        
        -- Progress callback for UI updates
        local function on_progress(kind, current, total, rel_path)
            local progress_text
            if kind == "scan_remote" then
                progress_text = _("Scanning remote files...")
            elseif kind == "scan_local" then
                progress_text = _("Scanning local files...")
            elseif kind == "create_dirs" then
                progress_text = _("Creating directories...")
            elseif kind == "download" then
                progress_text = T(_("Downloading %1/%2: %3"), current, total, rel_path or "")
            elseif kind == "cleanup" then
                progress_text = _("Cleaning up local files...")
            elseif kind == "cleanup_dirs" then
                progress_text = _("Removing empty folders...")
            else
                progress_text = _("Synchronizing...")
            end
            
            Trapper:info(progress_text)
        end
        
        local ok, results_or_err
        if item.type == "dropbox" then
            if self:generateDropBoxAccessToken() then
                if DropBox.synchronize then
                    logger.dbg("CloudStorage:synchronizeCloud calling DropBox.synchronize")
                    ok, results_or_err = pcall(DropBox.synchronize, DropBox, item, self.password, on_progress)
                else
                    ok, results_or_err = pcall(self.downloadListFiles, self, item)
                end
            end
        elseif item.type == "webdav" then
            if WebDav.synchronize then
                logger.dbg("CloudStorage:synchronizeCloud calling WebDav.synchronize")
                ok, results_or_err = pcall(WebDav.synchronize, WebDav, item, self.username, self.password, on_progress)
            else
                ok, results_or_err = pcall(self.downloadListFiles, self, item)
            end
        else
            ok, results_or_err = pcall(self.downloadListFiles, self, item)
        end
        
        if ok and results_or_err then
            local text
            if type(results_or_err) == "table" then
                -- New sync API result format
                local service_name = server_types[item.type] or _("Cloud service")
                text = T(N_("Successfully downloaded 1 file from %2.", "Successfully downloaded %1 files from %2.", results_or_err.downloaded), results_or_err.downloaded, service_name)
                
                if results_or_err.deleted_files and results_or_err.deleted_files > 0 then
                    text = text .. " " .. T(N_("Deleted 1 local file.", "Deleted %1 local files.", results_or_err.deleted_files), results_or_err.deleted_files)
                end
                if results_or_err.deleted_folders and results_or_err.deleted_folders > 0 then
                    text = text .. " " .. T(N_("Deleted 1 empty folder.", "Deleted %1 empty folders.", results_or_err.deleted_folders), results_or_err.deleted_folders)
                end
                if results_or_err.failed and results_or_err.failed > 0 then
                    text = text .. "\n" .. T(N_("Failed to download 1 file.", "Failed to download %1 files.", results_or_err.failed), results_or_err.failed)
                end
                if results_or_err.skipped and results_or_err.skipped > 0 then
                    text = text .. " " .. T(N_("Skipped 1 unchanged file.", "Skipped %1 unchanged files.", results_or_err.skipped), results_or_err.skipped)
                end
            else
                -- Legacy return format (just number)
                local downloaded_files = results_or_err
                if type(downloaded_files) == "boolean" then
                    downloaded_files = downloaded_files and 1 or 0
                end
                downloaded_files = downloaded_files or 0
                
                if downloaded_files == 0 then
                    text = _("No files to download.")
                else
                    local service_name = server_types[item.type] or _("Cloud service")
                    text = T(N_("Successfully downloaded 1 file from %2.", "Successfully downloaded %1 files from %2.", downloaded_files), downloaded_files, service_name)
                end
            end
            
            logger.dbg("CloudStorage:synchronizeCloud success:", text)
            UIManager:show(InfoMessage:new{
                text = text,
                timeout = 3,
            })
        else
            logger.err("CloudStorage:synchronizeCloud failed:", results_or_err)
            Trapper:reset()
            UIManager:show(InfoMessage:new{
                text = _("Synchronization failed.\nPlease check your configuration and connection."),
                timeout = 3,
            })
        end
    end)
end

function CloudStorage:downloadListFiles(item)
    local local_files = {}
    local path = item.sync_dest_folder
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if ok then
        for f in iter, dir_obj do
            local filename = path .."/" .. f
            local attributes = lfs.attributes(filename)
            if attributes and attributes.mode == "file" then
                local_files[f] = attributes.size
            end
        end
    end
    
    local remote_files
    if self.type == "dropbox" then
        remote_files = DropBox:showFiles(item.sync_source_folder, self.password)
    elseif self.type == "webdav" then
        remote_files = WebDav:showFiles(self.address, self.username, self.password, item.url)
    end
    
    if not remote_files or #remote_files == 0 then
        UI:clear()
        return false, 0  -- Return both boolean and numeric value
    end
    
    local files_to_download = 0
    for i, file in ipairs(remote_files) do
        if not local_files[file.text] or local_files[file.text] ~= file.size then
            files_to_download = files_to_download + 1
            remote_files[i].download = true
        end
    end

    if files_to_download == 0 then
        UI:clear()
        return false, 0  -- Return both boolean and numeric value
    end

    local response, go_on
    local proccessed_files = 0
    local success_files = 0
    local unsuccess_files = 0
    for _, file in ipairs(remote_files) do
        if file.download then
            proccessed_files = proccessed_files + 1
            local text = string.format("Downloading file (%d/%d):\n%s", proccessed_files, files_to_download, file.text)
            go_on = UI:info(text)
            if not go_on then
                break
            end
            if self.type == "dropbox" then
                response = DropBox:downloadFileNoUI(file.url, self.password, item.sync_dest_folder .. "/" .. file.text)
            elseif self.type == "webdav" then
                response = WebDav:downloadFileNoUI(self.address, self.username, self.password, file.url, item.sync_dest_folder .. "/" .. file.text)
            end
            if response then
                success_files = success_files + 1
            else
                unsuccess_files = unsuccess_files + 1
            end
        end
    end
    UI:clear()
    return success_files, unsuccess_files  -- Return both values
end

function CloudStorage:synchronizeSettings(item)
    local syn_dialog
    local remote_sync_folder = item.sync_source_folder or _("not set")
    local local_sync_folder = item.sync_dest_folder or _("not set")
    local service_name = server_types[item.type] or _("Cloud service")

    syn_dialog = ButtonDialog:new {
        title = T(_("%1 folder:\n%2\nLocal folder:\n%3"), service_name, BD.dirpath(remote_sync_folder), BD.dirpath(local_sync_folder)),
        title_align = "center",
        buttons = {
            {
                {
                    text = T(_("Choose %1 folder"), service_name),
                    callback = function()
                        UIManager:close(syn_dialog)
                        require("ui/downloadmgr"):new{
                            item = item,
                            onConfirm = function(path)
                                self:updateSyncFolder(item, path)
                                item.sync_source_folder = path
                                self:synchronizeSettings(item)
                            end,
                        }:chooseCloudDir()
                    end,
                },
            },
            {
                {
                    text = _("Choose local folder"),
                    callback = function()
                        UIManager:close(syn_dialog)
                        require("ui/downloadmgr"):new{
                            onConfirm = function(path)
                                self:updateSyncFolder(item, nil, path)
                                item.sync_dest_folder = path
                                self:synchronizeSettings(item)
                            end,
                        }:chooseDir()
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(syn_dialog)
                    end,
                },
            },
        }
    }
    UIManager:show(syn_dialog)
end

function CloudStorage:showPlusMenu(url)
    local button_dialog
    button_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = _("Upload file"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:uploadFile(url)
                    end,
                },
            },
            {
                {
                    text = _("New folder"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:createFolder(url)
                    end,
                },
            },
            {},
            {
                {
                    text = _("Return to cloud storage list"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:init()
                    end,
                },
            },
        },
    }
    UIManager:show(button_dialog)
end

function CloudStorage:uploadFile(url)
    local path_chooser
    path_chooser = PathChooser:new{
        select_directory = false,
        path = self.last_path,
        onConfirm = function(file_path)
            self.last_path = file_path:match("(.*)/")
            if self.last_path == "" then self.last_path = "/" end
            if lfs.attributes(file_path, "size") > 157286400 then
                UIManager:show(InfoMessage:new{
                    text = _("File size must be less than 150 MB."),
                })
            else
                local callback_close = function()
                    self:openCloudServer(url)
                end
                UIManager:nextTick(function()
                    UIManager:show(InfoMessage:new{
                        text = _("Uploading…"),
                        timeout = 1,
                    })
                end)
                local url_base = url ~= "/" and url or ""
                UIManager:tickAfterNext(function()
                    if self.type == "dropbox" then
                        DropBox:uploadFile(url_base, self.password, file_path, callback_close)
                    elseif self.type == "webdav" then
                        WebDav:uploadFile(url_base, self.address, self.username, self.password, file_path, callback_close)
                    end
                end)
            end
        end
    }
    UIManager:show(path_chooser)
end

function CloudStorage:createFolder(url)
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
                        local callback_close = function()
                            if check_button_enter_folder.checked then
                                table.insert(self.paths, {
                                    url = url,
                                })
                                url = url_base .. "/" .. folder_name
                            end
                            self:openCloudServer(url)
                        end
                        if self.type == "dropbox" then
                            DropBox:createFolder(url_base, self.password, folder_name, callback_close)
                        elseif self.type == "webdav" then
                            WebDav:createFolder(url_base, self.address, self.username, self.password, folder_name, callback_close)
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

function CloudStorage:configCloud(type)
    local callbackAdd = function(fields)
        local cs_settings = self:readSettings()
        local cs_servers = cs_settings:readSetting("cs_servers") or {}
        if type == "dropbox" then
            table.insert(cs_servers,{
                name = fields[1],
                password = fields[2],
                address = fields[3],
                url = fields[4],
                type = "dropbox",
            })
        elseif type == "ftp" then
            table.insert(cs_servers,{
                name = fields[1],
                address = fields[2],
                username = fields[3],
                password = fields[4],
                url = fields[5],
                type = "ftp",
            })
        elseif type == "webdav" then
            table.insert(cs_servers,{
                name = fields[1],
                address = fields[2],
                username = fields[3],
                password = fields[4],
                url = fields[5],
                type = "webdav",
            })
        end
        cs_settings:saveSetting("cs_servers", cs_servers)
        cs_settings:flush()
        self:init()
    end
    if type == "dropbox" then
        DropBox:config(nil, callbackAdd)
    end
    if type == "ftp" then
        Ftp:config(nil, callbackAdd)
    end
    if type == "webdav" then
        WebDav:config(nil, callbackAdd)
    end
end

function CloudStorage:editCloudServer(item)
    local callbackEdit = function(updated_config, fields)
        local cs_settings = self:readSettings()
        local cs_servers = cs_settings:readSetting("cs_servers") or {}
        if item.type == "dropbox" then
            for i, server in ipairs(cs_servers) do
                if server.name == updated_config.text and server.password == updated_config.password then
                    server.name = fields[1]
                    server.password = fields[2]
                    server.address = fields[3]
                    server.url = fields[4]
                    cs_servers[i] = server
                    break
                end
            end
        elseif item.type == "ftp" then
            for i, server in ipairs(cs_servers) do
                if server.name == updated_config.text and server.address == updated_config.address then
                    server.name = fields[1]
                    server.address = fields[2]
                    server.username = fields[3]
                    server.password = fields[4]
                    server.url = fields[5]
                    cs_servers[i] = server
                    break
                end
            end
        elseif item.type == "webdav" then
            for i, server in ipairs(cs_servers) do
                if server.name == updated_config.text and server.address == updated_config.address then
                    server.name = fields[1]
                    server.address = fields[2]
                    server.username = fields[3]
                    server.password = fields[4]
                    server.url = fields[5]
                    cs_servers[i] = server
                    break
                end
            end
        end
        cs_settings:saveSetting("cs_servers", cs_servers)
        cs_settings:flush()
        self:init()
    end
    if item.type == "dropbox" then
        DropBox:config(item, callbackEdit)
    elseif item.type == "ftp" then
        Ftp:config(item, callbackEdit)
    elseif item.type == "webdav" then
        WebDav:config(item, callbackEdit)
    end
end

function CloudStorage:deleteCloudServer(item)
    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    for i, server in ipairs(cs_servers) do
        if server.name == item.text and server.password == item.password and server.type == item.type then
            table.remove(cs_servers, i)
            break
        end
    end
    cs_settings:saveSetting("cs_servers", cs_servers)
    cs_settings:flush()
    self:init()
end

function CloudStorage:infoServer(item)
    if item.type == "dropbox" then
        if NetworkMgr:willRerunWhenOnline(function() self:infoServer(item) end) then
            return
        end
        self.password = item.password
        self.address = item.address
        if self:generateDropBoxAccessToken() then
            DropBox:info(self.password)
            self.username = nil
        end
    elseif item.type == "ftp" then
        Ftp:info(item)
    elseif item.type == "webdav" then
        WebDav:info(item)
    end
end

function CloudStorage:readSettings()
    self.cs_settings = LuaSettings:open(DataStorage:getSettingsDir().."/cloudstorage.lua")
    return self.cs_settings
end

function CloudStorage:onReturn()
    if #self.paths > 0 then
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            -- return to last path
            self:openCloudServer(path.url)
        else
            -- return to root path
            self:init()
        end
    end
    return true
end

function CloudStorage:onHoldReturn()
    if #self.paths > 1 then
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

return CloudStorage
