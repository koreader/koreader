local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local _ = require("gettext")
local Menu = require("ui/widget/menu")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local DropBox = require("frontend/apps/cloudstorage/dropbox")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Ftp = require("frontend/apps/cloudstorage/ftp")
local ConfirmBox = require("ui/widget/confirmbox")
local lfs = require("libs/libkoreader-lfs")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")

local CloudStorage = Menu:extend{
    cloud_servers = {
        {
            text = "Add new cloud storage",
            title = "Choose type of cloud",
            url = "add",
            editable = false,
        },
    },
    width = Screen:getWidth(),
    height = Screen:getHeight(),
    no_title = false,
    show_parent = nil,
    is_popout = false,
    is_borderless = true,
}

function CloudStorage:init()
    self:initial()
    self.callback_refresh = function()
        self.cs_settings = self:readSettings()
        self.menu_select = nil
        self.title = "Cloud Storage"
        self.show_parent = self
        self.item_table = self:genItemTableFromRoot()
        Menu.init(self)
    end
end

function CloudStorage:initial()
    self.cs_settings = self:readSettings()
    self.menu_select = nil
    self.title = "Cloud Storage"
    self.show_parent = self
    self.item_table = self:genItemTableFromRoot()
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
                self:openCloudServer(self.type, server.url)
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

function CloudStorage:configCloud(type)
    if type == "dropbox" then
        DropBox:configDropbox(nil, self.callback_refresh)
    end
    if type == "ftp" then
        Ftp:configFtp(nil, self.callback_refresh)
    end
end

function CloudStorage:openCloudServer(type, url)
    local tbl
    if type == "dropbox" then
        tbl = DropBox:runDropbox(url, self.password)
    end
    if type == "ftp" then
        tbl = Ftp:runFtp(self.address, self.username, self.password, url)
    end
    if tbl and #tbl > 0 then
        self:swithItemTable(url, tbl)
        return true
    elseif not tbl then
        UIManager:show(InfoMessage:new{
            text = _("Cannot fetch list folder!\nCheck configuration or network connection."),
            timeout = 3,
        })
        table.remove(self.paths)
        return false
    else
        UIManager:show(InfoMessage:new{text = _("Empty folder") })
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
        if not self:openCloudServer(self.type, item.url) then
            table.remove(self.paths)
        end
    end
    return true
end

function CloudStorage:downloadFile(item)
    local lastdir = G_reader_settings:readSetting("lastdir")
    local cs_settings = self:readSettings()
    local download_dir = cs_settings:readSetting("download_file") or lastdir
    local path = download_dir .. '/' .. item.text
    if lfs.attributes(path) then
        UIManager:show(ConfirmBox:new{
            text = _("File exist! Would you like to override it?"),
            ok_callback = function()
                self:cloudFile(item)
            end
        })
    else
        self:cloudFile(item)
    end
end

function CloudStorage:cloudFile(item)
    local buttons = {
        {
            {
                text = _("Download file"),
                callback = function()
                    --Dropbox
                    if self.type == "dropbox" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:scheduleIn(1, function()
                            DropBox:downloadDropboxFile(item, self.password, callback_close)
                        end)
                        UIManager:close(self.download_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes..."),
                            timeout = 1,
                        })
                    end
                    -- FTP
                    if self.type == "ftp" then
                        local callback_close = function()
                            self:onClose()
                        end
                        UIManager:scheduleIn(1, function()
                            Ftp:downloadFtpFile(item, self.address, self.username, self.password, callback_close)
                        end)
                        UIManager:close(self.download_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes..."),
                            timeout = 1,
                        })
                    end
                end,
            },
        },
        {
            {
                text = _("Set download directory"),
                callback = function()
                    require("ui/downloadmgr"):new{
                        title = _("Choose download directory"),
                        onConfirm = function(path)
                            self.cs_settings:saveSetting("download_file", path)
                            self.cs_settings:flush()
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

function CloudStorage:editCloudServer(item)
    item.callback_refresh = self.callback_refresh
    if item.type == "dropbox" then
        DropBox:configDropbox(item, self.callback_refresh)
    end
    if item.type == "ftp" then
        Ftp:configFtp(item, self.callback_refresh)
    end
end

function CloudStorage:deleteCloudServer(item)
    if item.type == "dropbox" then
        DropBox:deleteDropboxServer(item)
    end
    if item.type == "ftp" then
        Ftp:deleteFtpServer(item)
    end
    self:initial()
end

function CloudStorage:infoServer(item)
    if item.type == "dropbox" then
        DropBox:infoDropbox(item.password)
    end
    if item.type == "ftp" then
        Ftp:infoFtp(item)
    end
end

function CloudStorage:readSettings()
    self.cs_settings = LuaSettings:open(DataStorage:getSettingsDir().."/cssettings.lua")
    return self.cs_settings
end

function CloudStorage:onReturn()
    if #self.paths > 0 then
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            -- return to last path
            self:openCloudServer(self.type, path.url)
        else
            -- return to root path
            self:init()
        end
    end
    return true
end

return CloudStorage
