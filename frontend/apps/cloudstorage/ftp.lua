local ConfirmBox = require("ui/widget/confirmbox")
local FtpApi = require("apps/cloudstorage/ftpapi")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ReaderUI = require("apps/reader/readerui")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Ftp = {
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

function Ftp:run(address, user, pass, path)
    local url = generateUrl(address, user, pass) .. path
    return FtpApi:listFolder(url, path)
end

function Ftp:downloadFile(item, address, user, pass, path, close)
    local url = generateUrl(address, user, pass) .. item.url
    local response = FtpApi:downloadFile(url)
    if response ~= nil then
        path = util.fixUtf8(path, "_")
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
            text = T(_("Could not save file to:\n%1"), path),
            timeout = 3,
        })
    end
end

function Ftp:config(item, callback)
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
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                },
                {
                    text = text_button_right,
                    callback = function()
                        local fields = MultiInputDialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" then
                            if item then
                                -- edit
                                callback(item, fields)
                            else
                                -- add new
                                callback(fields)
                            end
                            self.settings_dialog:onClose()
                            UIManager:close(self.settings_dialog)
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please fill in all fields.")
                            })
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

function Ftp:info(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "FTP", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

return Ftp
