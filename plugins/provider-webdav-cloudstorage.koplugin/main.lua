local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local WebDavApi = require("webdavapi")
local InfoMessage = require("ui/widget/infomessage")
local Provider = require("provider")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local SyncCommon = require("plugins/cloudstorage.koplugin/synccommon")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

-- WebDAV Provider inheriting from base class
local BaseCloudStorage = require("plugins/cloudstorage.koplugin/base")
local WebDavProvider = BaseCloudStorage:new {
    name = "webdav",
    version = "1.0.0",
}

function WebDavProvider:list(address, username, password, path, folder_mode)
    logger.dbg("WebDAV:list called with address=", address, " path=", path, " folder_mode=", folder_mode)
    local options = {
        folder_mode = folder_mode
    }
    return WebDavApi:listFolder(address, username, password, path, options)
end

function WebDavProvider:download(item, address, username, password, local_path, callback_close)
    local code_response = WebDavApi:downloadFile(WebDavApi:getJoinedPath(address, item.url), username, password, local_path)
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

function WebDavProvider:info(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "WebDAV", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

function WebDavProvider:sync(item, address, username, password, on_progress)
    logger.dbg("WebDAV:synchronize called for item=", item.text, " sync_source_folder=", item.sync_source_folder, " sync_dest_folder=", item.sync_dest_folder)
    local local_path = item.sync_dest_folder
    local remote_base_url = address
    local sync_folder = item.sync_source_folder or ""

    if not local_path or not remote_base_url then
        local results = SyncCommon.init_results()
        SyncCommon.add_error(results, _("Missing sync source or destination configuration"))
        return results
    end

    -- Remove leading slash from sync_folder to avoid double slashes
    if sync_folder:sub(1, 1) == "/" then
        sync_folder = sync_folder:sub(2)
    end
    if sync_folder:sub(-1) == "/" then
        sync_folder = sync_folder:sub(1, -2)
    end

    local results = SyncCommon.init_results()

    logger.dbg("WebDAV:synchronize remote_base_url=", remote_base_url, " sync_folder=", sync_folder, " local_path=", local_path)

    -- Show progress for getting file lists
    SyncCommon.call_progress_callback(on_progress, "scan_remote", 0, 1, "")
    local remote_files = self:getRemoteFilesRecursive(remote_base_url, username, password, sync_folder, on_progress)

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
                logger.dbg("WebDAV:synchronize downloading ", rel_path, " to ", local_file_path)
                local success = self:downloadFileNoUI(remote_base_url, username, password, remote_file.relative_path, local_file_path)
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
            logger.dbg("WebDAV:synchronize deleting local file ", local_file.path)
            local success, err = SyncCommon.delete_local_file(local_file.path)
            if success then
                results.deleted_files = results.deleted_files + 1
            else
                SyncCommon.add_error(results, _("Failed to delete file: ") .. rel_path .. " (" .. (err or "unknown error") .. ")")
            end
        end
    end

    logger.dbg("WebDAV:synchronize results:", results)
    return results
end

-- Helper function for downloading files without UI
function WebDavProvider:downloadFileNoUI(address, username, password, relative_path, local_path)
    local download_url = WebDavApi:getJoinedPath(address, relative_path)
    local code_response = WebDavApi:downloadFile(download_url, username, password, local_path)
    return code_response == 200
end

-- Helper function to get remote files recursively
function WebDavProvider:getRemoteFilesRecursive(base_url, username, password, sync_folder_path, on_progress)
    local files = {}

    local function getFilesRecursive(current_url, current_rel_path)
        logger.dbg("WebDAV:getRemoteFilesRecursive listing:", current_url, " rel_path:", current_rel_path)

        local file_list = WebDavApi:listFolder(current_url, username, password, "", {sync_mode = true})
        if not file_list then
            logger.err("WebDAV:getRemoteFilesRecursive: Failed to list folder", current_url)
            return
        end

        for _, item in ipairs(file_list) do
            if item.type == "file" then
                local rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. item.text) or item.text
                -- Store the full relative path including sync_folder_path for downloading
                local full_relative_path
                if sync_folder_path and sync_folder_path ~= "" then
                    full_relative_path = sync_folder_path .. "/" .. rel_path
                else
                    full_relative_path = rel_path
                end
                files[rel_path] = {
                    relative_path = full_relative_path,
                    size = item.filesize,
                    text = item.text,
                    type = "file"
                }
            elseif item.type == "folder" then
                local folder_name = item.text:gsub("/$", "")
                local sub_rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. folder_name) or folder_name
                local sub_url = WebDavApi:getJoinedPath(current_url, folder_name)
                getFilesRecursive(sub_url, sub_rel_path)
            end
        end
    end

    local start_url = sync_folder_path and sync_folder_path ~= "" and WebDavApi:getJoinedPath(base_url, sync_folder_path) or base_url
    getFilesRecursive(start_url, "")

    return files
end

-- Register the WebDAV provider with the Provider system
Provider:register("cloudstorage", "webdav", {
    name = _("WebDAV"),
    list = function(...) return WebDavProvider:list(...) end,
    download = function(...) return WebDavProvider:download(...) end,
    info = function(...) return WebDavProvider:info(...) end,
    sync = function(...) return WebDavProvider:sync(...) end,
    config_title = _("WebDAV account"),
    config_fields = {
        {name = "name", hint = _("Server display name")},
        {name = "address", hint = _("WebDAV address, for example https://example.com/dav")},
        {name = "username", hint = _("Username")},
        {name = "password", hint = _("Password"), text_type = "password"},
        {name = "url", hint = _("Start folder, for example /books")},
    },
    config_info = _([[Server address must be of the form http(s)://domain.name/path
This can point to a sub-directory of the WebDAV server.
The start folder is appended to the server path.]])
})

return {}
