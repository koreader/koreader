local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local DropBoxApi = require("dropboxapi")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Provider = require("provider")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local SyncCommon = require("plugins/cloudstorage.koplugin/synccommon")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

-- Dropbox Provider using the base class
local BaseCloudStorage = require("plugins/cloudstorage.koplugin/base")
local DropboxProvider = BaseCloudStorage:new {
    name = "dropbox",
    version = "1.0.0",
}

function DropboxProvider:list(address, username, password, path, folder_mode)
    logger.dbg("Dropbox:list called with path=", path, " folder_mode=", folder_mode)
    logger.dbg("Dropbox:list params: address=", address and "***provided***" or "nil", 
               " username=", username and "***provided***" or "nil", 
               " password=", password and "***provided***" or "nil")
    
    if NetworkMgr:willRerunWhenOnline(function() return self:list(address, username, password, path, folder_mode) end) then
        return nil
    end
    
    -- Generate access token if needed
    local access_token = password
    
    -- If we have app credentials (address), treat password as refresh token
    if address and address ~= "" then
        logger.dbg("Dropbox:list using refresh token flow")
        access_token = DropBoxApi:getAccessToken(password, address)
        if not access_token then
            logger.warn("Dropbox:list failed to get access token")
            return nil, _("Failed to get Dropbox access token")
        end
        logger.dbg("Dropbox:list got access token, length=", #access_token)
    else
        logger.dbg("Dropbox:list using direct access token (legacy mode)")
    end
    
    -- Fix: Correct parameter order for listFolder
    logger.dbg("Dropbox:list calling DropBoxApi:listFolder with path=", path, " access_token length=", access_token and #access_token or "nil")
    return DropBoxApi:listFolder(path, access_token, folder_mode)
end

function DropboxProvider:download(item, address, username, password, local_path, callback_close)
    if NetworkMgr:willRerunWhenOnline(function() self:download(item, address, username, password, local_path, callback_close) end) then
        return
    end
    
    -- Generate access token if needed
    local access_token = password
    if not username and address and address ~= "" then
        access_token = DropBoxApi:getAccessToken(password, address)
        if not access_token then
            UIManager:show(InfoMessage:new{
                text = _("Failed to get Dropbox access token"),
                timeout = 3,
            })
            return
        end
    end
    
    local code_response = DropBoxApi:downloadFile(item, access_token, local_path)
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

function DropboxProvider:info(item)
    local info_text = T(_"Type: %1\nName: %2", "Dropbox", item.text)
    UIManager:show(InfoMessage:new{text = info_text})
end

function DropboxProvider:sync(item, address, username, password, on_progress)
    logger.dbg("Dropbox:synchronize called for item=", item.text, " sync_source_folder=", item.sync_source_folder, " sync_dest_folder=", item.sync_dest_folder)
    
    if NetworkMgr:willRerunWhenOnline(function() self:sync(item, address, username, password, on_progress) end) then
        return
    end
    
    local local_path = item.sync_dest_folder
    local sync_folder = item.sync_source_folder or ""

    if not local_path then
        local results = SyncCommon.init_results()
        SyncCommon.add_error(results, _("Missing sync destination folder"))
        return results
    end

    -- Generate access token if needed
    local access_token = password
    if not username and address and address ~= "" then
        access_token = DropBoxApi:getAccessToken(password, address)
        if not access_token then
            local results = SyncCommon.init_results()
            SyncCommon.add_error(results, _("Failed to get Dropbox access token"))
            return results
        end
    end

    local results = SyncCommon.init_results()

    logger.dbg("Dropbox:synchronize sync_folder=", sync_folder, " local_path=", local_path)

    -- Show progress for getting file lists
    SyncCommon.call_progress_callback(on_progress, "scan_remote", 0, 1, "")
    local remote_files = self:getRemoteFilesRecursive(access_token, sync_folder, on_progress)

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
                logger.dbg("Dropbox:synchronize downloading ", rel_path, " to ", local_file_path)
                local success = self:downloadFileNoUI(access_token, remote_file, local_file_path)
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
            logger.dbg("Dropbox:synchronize deleting local file ", local_file.path)
            local success, err = SyncCommon.delete_local_file(local_file.path)
            if success then
                results.deleted_files = results.deleted_files + 1
            else
                SyncCommon.add_error(results, _("Failed to delete file: ") .. rel_path .. " (" .. (err or "unknown error") .. ")")
            end
        end
    end

    logger.dbg("Dropbox:synchronize results:", results)
    return results
end

-- Helper function for downloading files without UI (for sync)
function DropboxProvider:downloadFileNoUI(access_token, remote_file, local_path)
    -- Fix: Pass the URL from the remote_file object, not the whole object
    local code_response = DropBoxApi:downloadFile(remote_file.url, access_token, local_path)
    return code_response == 200
end

-- Helper function to get remote files recursively
function DropboxProvider:getRemoteFilesRecursive(access_token, sync_folder_path, on_progress)
    logger.dbg("Dropbox:getRemoteFilesRecursive called with sync_folder_path=", sync_folder_path)
    local files = {}

    local function getFilesRecursive(current_path, current_rel_path)
        logger.dbg("Dropbox:getRemoteFilesRecursive listing:", current_path, " rel_path:", current_rel_path)

        -- Fix: Don't pass folder_mode for sync - we want raw file/folder data
        local file_list = DropBoxApi:listFolder(current_path, access_token, false)
        if not file_list then
            logger.err("Dropbox:getRemoteFilesRecursive: Failed to list folder", current_path)
            return
        end

        logger.dbg("Dropbox:getRemoteFilesRecursive got", #file_list, "items from listFolder")

        for i, item in ipairs(file_list) do
            logger.dbg("Dropbox:getRemoteFilesRecursive processing item", i, ":", item.text, "type:", item.type)
            
            if item.type == "file" then
                local rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. item.text) or item.text
                logger.dbg("Dropbox:getRemoteFilesRecursive adding file:", rel_path, "size:", item.mandatory)
                
                files[rel_path] = {
                    url = item.url,
                    size = item.filesize or item.size, -- Try both fields
                    text = item.text,
                    type = "file"
                }
            elseif item.type == "folder" then
                local folder_name = item.text:gsub("/$", "") -- Remove trailing slash if present
                local sub_rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. folder_name) or folder_name
                local sub_path = current_path .. "/" .. folder_name
                logger.dbg("Dropbox:getRemoteFilesRecursive recursing into folder:", folder_name, "sub_path:", sub_path)
                getFilesRecursive(sub_path, sub_rel_path)
            else
                logger.dbg("Dropbox:getRemoteFilesRecursive ignoring item with unknown type:", item.type)
            end
        end
    end

    local start_path = sync_folder_path and sync_folder_path ~= "" and sync_folder_path or ""
    logger.dbg("Dropbox:getRemoteFilesRecursive starting with path:", start_path)
    getFilesRecursive(start_path, "")

    logger.dbg("Dropbox:getRemoteFilesRecursive found total files:", table.getn and table.getn(files) or "unknown count")
    for rel_path, file_info in pairs(files) do
        logger.dbg("Dropbox:getRemoteFilesRecursive final file:", rel_path, "size:", file_info.size, "type:", file_info.type)
    end

    return files
end

-- Register the Dropbox provider with the Provider system
Provider:register("cloudstorage", "dropbox", {
    name = _("Dropbox"),
    list = function(...) return DropboxProvider:list(...) end,
    download = function(...) return DropboxProvider:download(...) end,
    info = function(...) return DropboxProvider:info(...) end,
    sync = function(...) return DropboxProvider:sync(...) end,
    config_title = _("Dropbox account"),
    config_fields = {
        {name = "name", hint = _("Dropbox account name")},
        {name = "password", hint = _("App key"), text_type = "password"},
        {name = "address", hint = _("Authorization code")},
        {name = "url", hint = _("Dropbox folder"), default = "/"},
    },
    config_info = _([[
To use Dropbox, you need to:
1. Create a Dropbox app at https://www.dropbox.com/developers/apps
2. Get the app key and enter it as the password
3. Get an authorization code and enter it as the address
4. The folder path should start with / (e.g., /books)

Note: This uses OAuth2 authentication. The authorization code will be exchanged for access tokens automatically.]])
})

return {}
