local DropBoxApi = require("apps/cloudstorage/dropboxapi")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")

local DropBox = {}

function DropBox:run(url, password)
    return DropBoxApi:listFolder(url, password)
end

function DropBox:downloadFile(item, password, path, close)
    local code_response = DropBoxApi:downloadFile(item.url, password, path)
    if code_response == 200 then
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

function DropBox:config(item, callback)
    local text_info = "How to generate Access Token:\n"..
        "1. Open the following URL in your Browser, and log in using your account: https://www.dropbox.com/developers/apps.\n"..
        "2. Click on >>Create App<<, then select >>Dropbox API app<<.\n"..
        "3. Now go on with the configuration, choosing the app permissions and access restrictions to your DropBox folder.\n"..
        "4. Enter the >>App Name<< that you prefer (e.g. KOReader).\n"..
        "5. Now, click on the >>Create App<< button.\n" ..
        "6. When your new App is successfully created, please click on the Generate button.\n"..
        "7. Under the 'Generated access token' section, then enter code in Dropbox token field."
    local hint_top = _("Your Dropbox name")
    local text_top = ""
    local hint_bottom = _("Dropbox token\n\n\n\n ")
    local text_bottom = ""
    local title
    local text_button_right = _("Add")
    if item then
        title = _("Edit Dropbox account")
        text_button_right = _("Apply")
        text_top = item.text
        text_bottom = item.password
    else
        title = _("Add Dropbox account")
    end
    self.settings_dialog = MultiInputDialog:new {
        title = title,
        fields = {
            {
                text = text_top,
                hint = hint_top ,
            },
            {
                text = text_bottom,
                hint = hint_bottom,
                scroll = false,
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
                                --edit
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
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function DropBox:info(token)
    local info = DropBoxApi:fetchInfo(token)
    local info_text
    if info and info.name then
        info_text = T(_"Type: %1\nName: %2\nEmail: %3\nCounty: %4",
            "Dropbox",info.name.display_name, info.email, info.country)
    else
        info_text = _("No information available")
    end
    UIManager:show(InfoMessage:new{text = info_text})
end

return DropBox
