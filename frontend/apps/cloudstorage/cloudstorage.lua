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
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Screen = require("device").screen

local CloudStorage = Menu:extend{
    cloud_servers = {
        {
            text = "Add new cloud storage",
            title = "Choose type of cloud",
            url = "add",
            editable = false,
        },
    },
    no_title = false,
    show_parent = nil,
    is_popout = false,
    is_borderless = true,
}

function CloudStorage:init()
    self.cs_settings = self:readSettings()
    self.menu_select = nil
    self.title = "Cloud Storage"
    self.show_parent = self
    self.item_table = self:genItemTableFromRoot()
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    Menu.init(self)
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
    local tbl
    local NetworkMgr = require("ui/network/manager")
    if self.type == "dropbox" then
        if not NetworkMgr:isOnline() then
            NetworkMgr:promptWifiOn()
            return
        end
        tbl = DropBox:run(url, self.password)
    elseif self.type == "ftp" then
        if not NetworkMgr:isConnected() then
            NetworkMgr:promptWifiOn()
            return
        end
        tbl = Ftp:run(self.address, self.username, self.password, url)
    end
    if tbl and #tbl > 0 then
        self:switchItemTable(url, tbl)
        return true
    elseif not tbl then
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
    if lfs.attributes(path) then
        UIManager:show(ConfirmBox:new{
            text = _("File already exists. Would you like to overwrite it?"),
            ok_callback = function()
                self:cloudFile(item, path)
            end
        })
    else
        self:cloudFile(item, path)
    end
end

function CloudStorage:cloudFile(item, path)
    local path_dir = path
    local buttons = {
        {
            {
                text = _("Download file"),
                callback = function()
                    if self.type == "dropbox" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:scheduleIn(1, function()
                            DropBox:downloadFile(item, self.password, path_dir, callback_close)
                        end)
                        UIManager:close(self.download_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes…"),
                            timeout = 1,
                        })
                    elseif self.type == "ftp" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:scheduleIn(1, function()
                            Ftp:downloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                        end)
                        UIManager:close(self.download_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes…"),
                            timeout = 1,
                        })
                    end
                end,
            },
        },
        {
            {
                text = _("Choose download directory by long-pressing"),
                callback = function()
                    require("ui/downloadmgr"):new{
                        title = _("Choose download directory"),
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

function CloudStorage:onMenuHold(item)
    if item.editable then
        local cs_server_dialog
        cs_server_dialog = ButtonDialog:new{
            buttons = {
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
        }
        UIManager:show(cs_server_dialog)
        return true
    end
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
                type = "ftp",
                url = "/"
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

return CloudStorage
