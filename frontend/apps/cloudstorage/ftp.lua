local InputContainer = require("ui/widget/container/inputcontainer")
local FtpApi = require("frontend/apps/cloudstorage/ftpapi")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderUI = require("apps/reader/readerui")
local Screen = require("device").screen
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local Ftp = InputContainer:new {
}
local function generateUrl(address, user, pass)
    local colon_sign = ""
    local at_sign = ""
    if user ~= "" then
        at_sign = "@"
    end
    if pass ~= "" then
        colon_sign = ":"
    end
    local replace = "://" .. user .. colon_sign .. pass .. at_sign
    local url = string.gsub(address, "://", replace)
    return url
end

function Ftp:runFtp(address, user, pass, path)
    local url = generateUrl(address, user, pass) .. path
    return FtpApi:listFolder(url)
end

function Ftp:downloadFtpFile(item, address, user, pass, close)
    local url = generateUrl(address, user, pass) .. item.url
    local lastdir = G_reader_settings:readSetting("lastdir")
    local cs_settings = self:readSettings()
    local download_dir = cs_settings:readSetting("download_file") or lastdir
    local path = download_dir .. '/' .. item.text
    local response = FtpApi:downloadFile(url)
    if response ~= nil then
        local file = io.open(path, "w")
        file:write(response)
        file:close()
        UIManager:show(ConfirmBox:new{
            text = T(_("File saved to:\n %1\nWould you like to read the downloaded book now?"),
                path),
            ok_callback = function()
                close()
                ReaderUI:showReader(path)
            end
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Could not save file to:\n") .. path,
            timeout = 3,
        })
    end
end

function Ftp:configFtp(item, callback_refresh)
    local text_info = "FTP address must be in the format ftp://example.domian.com\n"..
        "Also supported is format with IP e.g: ftp://10.10.10.1\n"..
        "Username and password are optional."
    local hint_name = _("Your FTP name")
    local text_name = ""
    local hint_address = _("FTP address eg ftp://example.com")
    local text_address = ""
    local hint_username = _("FTP username")
    local text_username = ""
    local hint_password = _("FTP password")
    local text_password = ""
    local title
    local text_button_right = _("Add")
    if item then
        title = _("Edit FTP account")
        text_button_right = _("Apply")
        text_name = item.text
        text_address = item.address
        text_username = item.username
        text_password = item.password
    else
        title = _("Add FTP account")
    end
    self.settings_dialog = MultiInputDialog:new {
        title = title,
        fields = {
            {
                text = text_name,
                input_type = "string",
                hint = hint_name ,
            },
            {
                text = text_address,
                input_type = "string",
                hint = hint_address ,
            },
            {
                text = text_username,
                input_type = "string",
                hint = hint_username,
            },
            {
                text = text_password,
                input_type = "string",
                hint = hint_password,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{text = text_info })
                    end
                },
                {
                    text = text_button_right,
                    callback = function()
                        local fields = MultiInputDialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" then
                            if item then
                                self:saveEditedSettingsFtp(fields, item, callback_refresh)
                            else
                                self:saveSettingsFtp(fields, callback_refresh)
                            end
                            self.settings_dialog:onClose()
                            UIManager:close(self.settings_dialog)
                        else
                            UIManager:show(InfoMessage:new{text = "Please fill in all fields." })
                        end
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.95,
        height = Screen:getHeight() * 0.2,
        input_type = "text",
    }
    self.settings_dialog:onShowKeyboard()
    UIManager:show(self.settings_dialog)
end

function Ftp:saveSettingsFtp(fields, callback_refresh)
    local ftp_name = fields[1]
    local ftp_address = fields[2]
    local ftp_username = fields[3]
    local ftp_password = fields[4]

    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    table.insert(cs_servers,{
        name = ftp_name,
        address = ftp_address,
        username = ftp_username,
        password = ftp_password,
        type = "ftp",
        url = "/"
    })
    cs_settings:saveSetting("cs_servers", cs_servers)
    cs_settings:flush()
    if callback_refresh then
        callback_refresh()
    end
end

function Ftp:saveEditedSettingsFtp(fields, item, callback_refresh)
    local servers = {}
    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(cs_servers) do
        if server.name == item.text and server.address == item.address then
            server.name = fields[1]
            server.address = fields[2]
            server.username = fields[3]
            server.password = fields[4]
        end
        table.insert(servers, server)
    end
    cs_settings:saveSetting("cs_servers", servers)
    cs_settings:flush()
    if callback_refresh then
        callback_refresh()
    end
end

function Ftp:deleteFtpServer(item)
    local servers = {}
    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(cs_servers) do
        if server.name ~= item.text and server.password ~= item.password then
            table.insert(servers, server)
        end
    end
    cs_settings:saveSetting("cs_servers", servers)
    cs_settings:flush()
end

function Ftp:infoFtp(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "FTP", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

function Ftp:readSettings()
    return LuaSettings:open(DataStorage:getSettingsDir().."/cssettings.lua")
end

return Ftp
