local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local DropBoxApi = require("apps/cloudstorage/dropboxapi")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")

local DropBox = {}

function DropBox:getAccessToken(refresh_token, app_key_colon_secret)
    return DropBoxApi:getAccessToken(refresh_token, app_key_colon_secret)
end

function DropBox:run(url, password, choose_folder_mode)
    return DropBoxApi:listFolder(url, password, choose_folder_mode)
end

function DropBox:showFiles(url, password)
    return DropBoxApi:showFiles(url, password)
end

function DropBox:downloadFile(item, password, path, callback_close, progress_callback)
    local code_response = DropBoxApi:downloadFile(item.url, password, path, progress_callback)
    if code_response == 200 then
        local __, filename = util.splitFilePathName(path)
        if G_reader_settings:isTrue("show_unsupported") and not DocumentRegistry:hasProvider(filename) then
            UIManager:show(InfoMessage:new{
                text = T(_("File saved to:\n%1"), BD.filename(path)),
            })
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"),
                    BD.filepath(path)),
                ok_callback = function()
                    local Event = require("ui/event")
                    UIManager:broadcastEvent(Event:new("SetupShowReader"))

                    if callback_close then
                        callback_close()
                    end

                    ReaderUI:showReader(path)
                end
            })
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not save file to:\n%1"), BD.filepath(path)),
            timeout = 3,
        })
    end
end

function DropBox:downloadFileNoUI(url, password, path)
    local code_response = DropBoxApi:downloadFile(url, password, path)
    return code_response == 200
end

function DropBox:uploadFile(url, password, file_path, callback_close)
    local code_response = DropBoxApi:uploadFile(url, password, file_path)
    local __, filename = util.splitFilePathName(file_path)
    if code_response == 200 then
        UIManager:show(InfoMessage:new{
            text = T(_("File uploaded:\n%1"), filename),
        })
        if callback_close then
            callback_close()
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not upload file:\n%1"), filename),
        })
    end
end

function DropBox:createFolder(url, password, folder_name, callback_close)
    local code_response = DropBoxApi:createFolder(url, password, folder_name)
    if code_response == 200 then
        if callback_close then
            callback_close()
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Could not create folder:\n%1"), folder_name),
        })
    end
end

function DropBox:config(item, callback)
    local text_info = _([[
Dropbox access tokens are short-lived (4 hours).
To generate new access token please use Dropbox refresh token and <APP_KEY>:<APP_SECRET> string.

Some of the previously generated long-lived tokens are still valid.]])
    local text_name, text_token, text_appkey, text_url
    if item then
        text_name = item.text
        text_token = item.password
        text_appkey = item.address
        text_url = item.url
    end
    self.settings_dialog = MultiInputDialog:new {
        title = _("Dropbox cloud storage"),
        fields = {
            {
                text = text_name,
                hint = _("Cloud storage displayed name"),
            },
            {
                text = text_token,
                hint = _("Dropbox refresh token\nor long-lived token (deprecated)"),
            },
            {
                text = text_appkey,
                hint = _("Dropbox <APP_KEY>:<APP_SECRET>\n(leave blank for long-lived token)"),
            },
            {
                text = text_url,
                hint = _("Dropbox folder (/ for root)"),
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
                        if item then
                            callback(item, fields)
                        else
                            callback(fields)
                        end
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function DropBox:info(token)
    local info = DropBoxApi:fetchInfo(token)
    local space_usage = DropBoxApi:fetchInfo(token, true)
    if info and space_usage then
        local account_type = info.account_type and info.account_type[".tag"]
        local name = info.name and info.name.display_name
        local space_total = space_usage.allocation and space_usage.allocation.allocated
        UIManager:show(InfoMessage:new{
            text = T(_"Type: %1\nName: %2\nEmail: %3\nCountry: %4\nSpace total: %5\nSpace used: %6",
                account_type, name, info.email, info.country,
                util.getFriendlySize(space_total), util.getFriendlySize(space_usage.used)),
        })
    end
end

return DropBox
