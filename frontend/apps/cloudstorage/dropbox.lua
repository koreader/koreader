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
local logger = require("logger")
local SyncCommon = require("apps/cloudstorage/synccommon")

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

-- Get remote files recursively for synchronization
function DropBox:getRemoteFilesRecursive(base_path, password, current_rel_path, on_progress)
    local files = {}
    local current_path = base_path
    if current_rel_path and current_rel_path ~= "" then
        current_path = base_path .. "/" .. current_rel_path
    end
    local file_list = DropBoxApi:showFiles(current_path, password, true)
    if not file_list then
        logger.err("DropBox:getRemoteFilesRecursive: Failed to list folder", current_path)
        return files
    end
    for _, item in ipairs(file_list) do
        local rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. item.text) or item.text
        if item.type == "file" then
            files[rel_path] = {
                url = item.url,
                size = item.size,
                text = item.text,
                type = "file"
            }
        elseif item.type == "folder" then
            local sub_files = self:getRemoteFilesRecursive(base_path, password, rel_path, on_progress)
            for k, v in pairs(sub_files) do
                files[k] = v
            end
        end
    end
    return files
end

-- Main synchronization function for Dropbox
function DropBox:synchronize(item, password, on_progress)
    logger.dbg("DropBox:synchronize called for item=", item.text, " local_path=", item.sync_dest_folder, " remote_path=", item.sync_source_folder)
    local local_path = item.sync_dest_folder
    local remote_path = item.sync_source_folder
    local results = SyncCommon.init_results()
    
    if not local_path or not remote_path then
        SyncCommon.add_error(results, _("Missing sync source or destination folder"))
        return results
    end
    
    -- Show progress for getting file lists
    SyncCommon.call_progress_callback(on_progress, "scan_remote", 0, 1, "")
    local remote_files = self:getRemoteFilesRecursive(remote_path, password, "", on_progress)
    
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
                logger.dbg("DropBox:synchronize downloading ", rel_path, " to ", local_file_path)
                local success = self:downloadFileNoUI(remote_file.url, password, local_file_path)
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
            logger.dbg("DropBox:synchronize deleting local file ", local_file.path)
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
    
    logger.dbg("DropBox:synchronize results:", results)
    return results
end

function DropBox:downloadFile(item, password, path, callback_close)
    local code_response = DropBoxApi:downloadFile(item.url, password, path)
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
