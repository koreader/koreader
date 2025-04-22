local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local WebDavApi = require("apps/cloudstorage/webdavapi")
local util = require("util")
local ffiutil = require("ffi/util")
local _ = require("gettext")
local T = require("ffi/util").template

local WebDav = {}

function WebDav:run(address, user, pass, path, folder_mode)
    return WebDavApi:listFolder(address, user, pass, path, folder_mode)
end

function WebDav:downloadFile(item, address, username, password, local_path, callback_close, progress_callback)
    local code_response = WebDavApi:downloadFile(
        WebDavApi:getJoinedPath(address, item.url),
        username,
        password,
        local_path,
        progress_callback
    )

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

function WebDav:uploadFile(url, address, username, password, local_path, callback_close)
    local path = WebDavApi:getJoinedPath(address, url)
    path = WebDavApi:getJoinedPath(path, ffiutil.basename(local_path))
    local code_response = WebDavApi:uploadFile(path, username, password, local_path)
    if type(code_response) == "number" and code_response >= 200 and code_response < 300 then
        UIManager:show(InfoMessage:new{
            text = T(_("File uploaded:\n%1"), BD.filepath(address)),
        })
        if callback_close then callback_close() end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not upload file:\n%1"), BD.filepath(address)),
            timeout = 3,
        })
    end
end

function WebDav:createFolder(url, address, username, password, folder_name, callback_close)
    local code_response = WebDavApi:createFolder(address .. WebDavApi.urlEncode(url .. "/" .. folder_name), username, password, folder_name)
    if code_response == 201 then
        if callback_close then
            callback_close()
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not create folder:\n%1"), folder_name),
        })
    end
end

function WebDav:config(item, callback)
    local text_info = _([[Server address must be of the form http(s)://domain.name/path
This can point to a sub-directory of the WebDAV server.
The start folder is appended to the server path.]])

    local title, text_name, text_address, text_username, text_password, text_folder
    if item then
        title = _("Edit WebDAV account")
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
                hint = _("Server display name"),
            },
            {
                text = text_address,
                hint = _("WebDAV address, for example https://example.com/dav"),
            },
            {
                text = text_username,
                hint = _("Username"),
            },
            {
                text = text_password,
                text_type = "password",
                hint = _("Password"),
            },
            {
                text = text_folder,
                hint = _("Start folder, for example /books"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
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
                    text = _("Save"),
                    callback = function()
                        local fields = self.settings_dialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" then
                            -- make sure the URL is a valid path
                            if fields[5] ~= "" then
                                if not fields[5]:match('^/') then
                                    fields[5] = '/' .. fields[5]
                                end
                                fields[5] = fields[5]:gsub("/$", "")
                            end
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
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function WebDav:info(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "WebDAV", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

return WebDav
