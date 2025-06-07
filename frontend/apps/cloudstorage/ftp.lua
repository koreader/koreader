local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local FtpApi = require("apps/cloudstorage/ftpapi")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local SyncCommon = require("apps/cloudstorage/synccommon")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Ftp = {}

function Ftp:run(address, user, pass, path)
    local url = FtpApi:generateUrl(address, util.urlEncode(user), util.urlEncode(pass)) .. path
    return FtpApi:listFolder(url, path)
end

function Ftp:downloadFile(item, address, user, pass, path, callback_close)
    local url = FtpApi:generateUrl(address, util.urlEncode(user), util.urlEncode(pass)) .. item.url
    logger.dbg("downloadFile url", url)
    path = util.fixUtf8(path, "_")
    local file, err = io.open(path, "w")
    if not file then
        UIManager:show(InfoMessage:new{
            text = T(_("Could not save file to %1:\n%2"), BD.filepath(path), err),
        })
        return
    end
    local response = FtpApi:ftpGet(url, "retr", ltn12.sink.file(file))
    if response ~= nil then
        local __, filename = util.splitFilePathName(path)
        if G_reader_settings:isTrue("show_unsupported") and not DocumentRegistry:hasProvider(filename) then
            UIManager:show(InfoMessage:new{
                text = T(_("File saved to:\n%1"), BD.filepath(path)),
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

function Ftp:synchronize(item, user, pass, on_progress)
    logger.dbg("Ftp:synchronize called for item=", item.text, " local_path=", item.sync_dest_folder, " remote_path=", item.sync_source_folder)
    local local_path = item.sync_dest_folder
    local remote_path = item.sync_source_folder
    local results = SyncCommon.init_results()

    if not local_path or not remote_path then
        SyncCommon.add_error(results, _("Missing sync source or destination folder"))
        return results
    end

    -- Show progress for getting file lists
    SyncCommon.call_progress_callback(on_progress, "scan_remote", 0, 1, "")
    local remote_files = FtpApi:listFolder(remote_path, user, pass)

    SyncCommon.call_progress_callback(on_progress, "scan_local", 0, 1, "")
    local local_files = SyncCommon.get_local_files_recursive(local_path, "")

    -- Create necessary local directories
    SyncCommon.call_progress_callback(on_progress, "create_dirs", 0, 1, "")
    local dir_errors = SyncCommon.create_local_directories(local_path, remote_files)
    for _, err in ipairs(dir_errors) do
        SyncCommon.add_error(results, err)
    end

    -- Count total files to download for progress
    local total_to_download = 0
    for rel_path, remote_file in pairs(remote_files) do
        if remote_file.type == "file" then
            local local_file = local_files[rel_path]
            local should_download = not local_file or (remote_file.size and local_file.size ~= remote_file.size)
            if should_download then
                total_to_download = total_to_download + 1
            end
        end
    end

    -- Download new/changed files with progress
    local current_download = 0
    for rel_path, remote_file in pairs(remote_files) do
        if remote_file.type == "file" then
            local local_file = local_files[rel_path]
            local should_download = not local_file or (remote_file.size and local_file.size ~= remote_file.size)

            if should_download then
                current_download = current_download + 1
                SyncCommon.call_progress_callback(on_progress, "download", current_download, total_to_download, remote_file.text)
                local local_file_path = local_path .. "/" .. rel_path
                logger.dbg("Ftp:synchronize downloading ", rel_path, " to ", local_file_path)
                local success = FtpApi:ftpGet(remote_file.url, "retr", ltn12.sink.file(io.open(local_file_path, "w")))

                if success then
                    results.downloaded = results.downloaded + 1
                else
                    results.failed = results.failed + 1
                    SyncCommon.add_error(results, _("Failed to download file: ") .. remote_file.text)
                end
            else
                results.skipped = results.skipped + 1
            end
        end
    end

    -- Delete local files that don't exist remotely
    SyncCommon.call_progress_callback(on_progress, "cleanup", 0, 1, "")
    for rel_path, local_file in pairs(local_files) do
        if not remote_files[rel_path] then
            logger.dbg("Ftp:synchronize deleting local file ", local_file.path)
            local success, err = SyncCommon.delete_local_file(local_file.path)
            if success then
                results.deleted_files = results.deleted_files + 1
            else
                SyncCommon.add_error(results, _("Failed to delete file: ") .. rel_path .. " (" .. (err or "unknown error") .. ")")
            end
        end
    end

    -- Clean up empty folders
    SyncCommon.call_progress_callback(on_progress, "cleanup_dirs", 0, 1, "")
    local deleted_folders, folder_errors = SyncCommon.delete_empty_folders(local_path)
    results.deleted_folders = deleted_folders
    for _, err in ipairs(folder_errors) do
        SyncCommon.add_error(results, err)
    end

    logger.dbg("Ftp:synchronize results:", results)
    return results
end

function Ftp:config(item, callback)
    local text_info = _([[
The FTP address must be in the following format:
ftp://example.domain.com
An IP address is also supported, for example:
ftp://10.10.10.1
Username and password are optional.]])
    local hint_name = _("Your FTP name")
    local text_name = ""
    local hint_address = _("FTP address eg ftp://example.com")
    local text_address = ""
    local hint_username = _("FTP username")
    local text_username = ""
    local hint_password = _("FTP password")
    local text_password = ""
    local hint_folder = _("FTP folder")
    local text_folder = "/"
    local title
    local text_button_right = _("Add")
    if item then
        title = _("Edit FTP account")
        text_button_right = _("Apply")
        text_name = item.text
        text_address = item.address
        text_username = item.username
        text_password = item.password
        text_folder = item.url
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
                    text = text_button_right,
                    callback = function()
                        local fields = self.settings_dialog:getFields()
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
        input_type = "text",
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function Ftp:info(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "FTP", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

return Ftp
