local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local WebDavApi = require("apps/cloudstorage/webdavapi")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local WebDav = {}

function WebDav:run(address, user, pass, path)
    return WebDavApi:listFolder(address, user, pass, path)
end

function WebDav:downloadFile(item, address, username, password, local_path, callback_close)
    local code_response = WebDavApi:downloadFile(address .. WebDavApi:urlEncode( item.url ), username, password, local_path)
    if code_response == 200 then
        local __, filename = util.splitFilePathName(local_path)
        if G_reader_settings:isTrue("show_unsupported") and not DocumentRegistry:hasProvider(filename) then
            UIManager:show(InfoMessage:new{
                text = T(_("File saved to:\n%1"), BD.filepath(local_path)),
            })
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"),
                    BD.filepath(local_path)),
                ok_callback = function()
                    local Event = require("ui/event")
                    UIManager:broadcastEvent(Event:new("SetupShowReader"))

                    if callback_close then
                        callback_close()
                    end

                    ReaderUI:showReader(local_path)
                end
            })
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not save file to:\n%1"), BD.filepath(local_path)),
            timeout = 3,
        })
    end
end

function WebDav:config(item, callback)
    local text_info = _([[Server address must be of the form http(s)://domain.name/path
This can point to a sub-directory of the WebDAV server.
The start folder is appended to the server path.]])

    local hint_name = _("Server display name")
    local text_name = ""
    local hint_address = _("WebDAV address, for example https://example.com/dav")
    local text_address = ""
    local hint_username = _("Username")
    local text_username = ""
    local hint_password = _("Password")
    local text_password = ""
    local hint_folder = _("Start folder")
    local text_folder = ""
    local title
    local text_button_ok = _("Add")
    if item then
        title = _("Edit WebDAV account")
        text_button_ok = _("Apply")
        text_name = item.text
        text_address = item.address
        text_username = item.username
        text_password = item.password
        text_folder = item.url
    else
        title = _("Add WebDAV account")
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
                text_type = "password",
                hint = hint_password,
            },
            {
                text = text_folder,
                input_type = "string",
                hint = hint_folder,
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
                    text = text_button_ok,
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
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
        input_type = "text",
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()

end

function WebDav:info(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "WebDAV", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

return WebDav
