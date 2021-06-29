local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local DropBox = require("apps/cloudstorage/dropbox")
local Ftp = require("apps/cloudstorage/ftp")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WebDav = require("apps/cloudstorage/webdav")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = require("device").screen

local CloudStorage = Menu:extend{
    cloud_servers = {
        {
            text = _("Add new cloud storage"),
            title = _("Choose cloud type"),
            url = "add",
            editable = false,
        },
    },
    no_title = false,
    show_parent = nil,
    is_popout = false,
    is_borderless = true,
    title = _("Cloud storage")
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
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    Menu.init(self)
    if self.item then
        self.item_table[1].callback()
    end
end

function CloudStorage:genItemTableFromRoot()
    local item_table = {}
    table.insert(item_table, {
        text = _("Add new cloud storage"),
        callback = function()
            self:selectCloudType()
        end,
    })
    local added_servers = self.cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(added_servers) do
        table.insert(item_table, {
            text = server.name,
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
    local buttons = {
        {
            {
                text = _("Dropbox"),
                callback = function()
                    UIManager:close(self.cloud_dialog)
                    self:configCloud("dropbox")
                end,
            },
        },
        {
            {
                text = _("FTP"),
                callback = function()
                    UIManager:close(self.cloud_dialog)
                    self:configCloud("ftp")
                end,
            },
        },
        {
            {
                text = _("WebDAV"),
                callback = function()
                    UIManager:close(self.cloud_dialog)
                    self:configCloud("webdav")
                end,
            },
        },
    }
        self.cloud_dialog = ButtonDialogTitle:new{
            title = _("Choose cloud storage type"),
            title_align = "center",
            buttons = buttons,
    }

    UIManager:show(self.cloud_dialog)
    return true
end

function CloudStorage:openCloudServer(url)
    local tbl, e
    local NetworkMgr = require("ui/network/manager")
    if self.type == "dropbox" then
        if NetworkMgr:willRerunWhenOnline(function() self:openCloudServer(url) end) then
            return
        end
        tbl, e = DropBox:run(url, self.password, self.choose_folder_mode)
    elseif self.type == "ftp" then
        if NetworkMgr:willRerunWhenConnected(function() self:openCloudServer(url) end) then
            return
        end
        tbl, e = Ftp:run(self.address, self.username, self.password, url)
    elseif self.type == "webdav" then
        if NetworkMgr:willRerunWhenConnected(function() self:openCloudServer(url) end) then
            return
        end
        tbl, e = WebDav:run(self.address, self.username, self.password, url)
    end
    if tbl and #tbl > 0 then
        self:switchItemTable(url, tbl)
        return true
    elseif not tbl then
        logger.err("CloudStorage:", e)
        UIManager:show(InfoMessage:new{
            text = _("Cannot fetch list of folder contents\nPlease check your configuration or network connection."),
            timeout = 3,
        })
        table.remove(self.paths)
        return false
    else
        UIManager:show(InfoMessage:new{ text = _("Empty folder") })
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
    local lastdir = G_reader_settings:readSetting("lastdir")
    local cs_settings = self:readSettings()
    local download_dir = cs_settings:readSetting("download_dir") or lastdir
    local path = download_dir .. '/' .. item.text
    self:cloudFile(item, path)
end

function CloudStorage:cloudFile(item, path)
    local download_text = _("Downloading. This might take a moment.")
    local function dropboxDownloadFile(unit_item, password, path_dir, callback_close)
        UIManager:scheduleIn(1, function()
            DropBox:downloadFile(unit_item, password, path_dir, callback_close)
        end)
        UIManager:show(InfoMessage:new{
            text = download_text,
            timeout = 1,
        })
    end

    local function ftpDownloadFile(unit_item, address, username, password, path_dir, callback_close)
        UIManager:scheduleIn(1, function()
            Ftp:downloadFile(unit_item, address, username, password, path_dir, callback_close)
        end)
        UIManager:show(InfoMessage:new{
            text = download_text,
            timeout = 1,
        })
    end

    local function webdavDownloadFile(unit_item, address, username, password, path_dir, callback_close)
        UIManager:scheduleIn(1, function()
            WebDav:downloadFile(unit_item, address, username, password, path_dir, callback_close)
        end)
        UIManager:show(InfoMessage:new{
            text = download_text,
            timeout = 1,
        })
    end

    local path_dir = path
    local overwrite_text = _("File already exists. Would you like to overwrite it?")
    local buttons = {
        {
            {
                text = _("Download file"),
                callback = function()
                    if self.type == "dropbox" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:close(self.download_dialog)
                        if lfs.attributes(path) then
                            UIManager:show(ConfirmBox:new{
                                text = overwrite_text,
                                ok_callback = function()
                                    dropboxDownloadFile(item, self.password, path_dir, callback_close)
                                end
                            })
                        else
                            dropboxDownloadFile(item, self.password, path_dir, callback_close)
                        end
                    elseif self.type == "ftp" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:close(self.download_dialog)
                        if lfs.attributes(path) then
                            UIManager:show(ConfirmBox:new{
                                text = overwrite_text,
                                ok_callback = function()
                                    ftpDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                                end
                            })
                        else
                            ftpDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                        end
                    elseif self.type == "webdav" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:close(self.download_dialog)
                        if lfs.attributes(path) then
                            UIManager:show(ConfirmBox:new{
                                text = overwrite_text,
                                ok_callback = function()
                                    webdavDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                                end
                            })
                        else
                            webdavDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                        end
                    end
                end,
            },
        },
        {
            {
                text = _("Choose download folder"),
                callback = function()
                    require("ui/downloadmgr"):new{
                        show_hidden = G_reader_settings:readSetting("show_hidden"),
                        onConfirm = function(path_download)
                            self.cs_settings:saveSetting("download_dir", path_download)
                            self.cs_settings:flush()
                            path_dir = path_download .. '/' .. item.text
                        end,
                    }:chooseDir()
                end,
            },
        },
    }
    self.download_dialog = ButtonDialog:new{
        buttons = buttons
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
        local title = T(_("Select this folder?\n\n%1"), BD.dirpath(item.url))
        local onConfirm = self.onConfirm
        local button_dialog
        button_dialog = ButtonDialogTitle:new{
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
                        text = _("Select"),
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
                    enabled = true,
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:infoServer(item)
                    end
                },
                {
                    text = _("Edit"),
                    enabled = true,
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:editCloudServer(item)

                    end
                },
                {
                    text = _("Delete"),
                    enabled = true,
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:deleteCloudServer(item)
                    end
                },
            },
        }
        if item.type == "dropbox" then
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
                    enabled = true,
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
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        Trapper:setPausedText("Download paused.\nDo you want to continue or abort downloading files?")
        local ok, downloaded_files, failed_files = pcall(self.downloadListFiles, self, item)
        if ok and downloaded_files then
            if not failed_files then failed_files = 0 end
            local text
            if downloaded_files == 0 and failed_files == 0 then
                text = _("No files to download from Dropbox.")
            elseif downloaded_files > 0 and failed_files == 0 then
                text = T(_("Successfully downloaded %1 files from Dropbox to local storage."), downloaded_files)
            else
                text = T(_("Successfully downloaded %1 files from Dropbox to local storage.\nFailed to download %2 files."),
                    downloaded_files, failed_files)
            end
            UIManager:show(InfoMessage:new{
                text = text,
                timeout = 3,
            })
        else
            Trapper:reset() -- close any last widget not cleaned if error
            UIManager:show(InfoMessage:new{
                text = _("No files to download from Dropbox.\nPlease check your configuration and connection."),
                timeout = 3,
            })
        end
    end)
end

function CloudStorage:downloadListFiles(item)
    local local_files = {}
    local path = item.sync_dest_folder
    local UI = require("ui/trapper")
    UI:info(_("Retrieving files…"))

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
    local remote_files = DropBox:showFiles(item.sync_source_folder, item.password)
    if #remote_files == 0 then
        UI:clear()
        return false
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
        return 0
    end

    local response, go_on
    local proccessed_files = 0
    local success_files = 0
    local unsuccess_files = 0
    for _, file in ipairs(remote_files) do
        if file.download then
            proccessed_files = proccessed_files + 1
            print(file.url)
            local text = string.format("Downloading file (%d/%d):\n%s", proccessed_files, files_to_download, file.text)
            go_on = UI:info(text)
            if not go_on then
                break
            end
            response = DropBox:downloadFileNoUI(file.url, item.password, item.sync_dest_folder .. "/" .. file.text)
            if response then
                success_files = success_files + 1
            else
                unsuccess_files = unsuccess_files + 1
            end
        end
    end
    UI:clear()
    return success_files, unsuccess_files
end

function CloudStorage:synchronizeSettings(item)
    local syn_dialog
    local dropbox_sync_folder = item.sync_source_folder or "not set"
    local local_sync_folder = item.sync_dest_folder or "not set"
    syn_dialog = ButtonDialogTitle:new {
        title = T(_("Dropbox folder:\n%1\nLocal folder:\n%2"), BD.dirpath(dropbox_sync_folder), BD.dirpath(local_sync_folder)),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Choose Dropbox folder"),
                    callback = function()
                        UIManager:close(syn_dialog)
                        require("ui/cloudmgr"):new{
                            item = item,
                            onConfirm = function(path)
                                self:updateSyncFolder(item, path)
                                item.sync_source_folder = path
                                self:synchronizeSettings(item)
                            end,
                        }:chooseDir()
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

function CloudStorage:configCloud(type)
    local callbackAdd = function(fields)
        local cs_settings = self:readSettings()
        local cs_servers = cs_settings:readSetting("cs_servers") or {}
        if type == "dropbox" then
            table.insert(cs_servers,{
                name = fields[1],
                password = fields[2],
                type = "dropbox",
                url = "/"
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
        DropBox:info(item.password)
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
