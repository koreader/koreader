local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local FtpApi = require("ftpapi")
local InfoMessage = require("ui/widget/infomessage")
local Provider = require("provider")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local SyncCommon = require("plugins/cloudstorage.koplugin/synccommon")
local util = require("util")
local ltn12 = require("ltn12")
local _ = require("gettext")
local T = require("ffi/util").template

-- FTP Provider inheriting from base class
local BaseCloudStorage = require("plugins/cloudstorage.koplugin/base")
local FtpProvider = BaseCloudStorage:new {
    name = "ftp",
    version = "1.0.0",
}

function FtpProvider:list(address, username, password, path, folder_mode)
    local url = FtpApi:generateUrl(address, util.urlEncode(username), util.urlEncode(password)) .. path
    logger.dbg("FTP:list generated URL:", url)
    logger.dbg("FTP:list address:", address, "username:", username, "path:", path)
    local result, err = FtpApi:listFolder(url, path, folder_mode)
    logger.dbg("FTP:list result:", result)
    logger.dbg("FTP:list error:", err)
    if result then
        logger.dbg("FTP:list result type:", type(result))
        logger.dbg("FTP:list result length:", #result)
        for i, item in ipairs(result) do
            logger.dbg("FTP:list item", i, ":", item)
        end
    end
    return result, err
end

function FtpProvider:download(item, address, username, password, path, callback_close)
    local url = FtpApi:generateUrl(address, util.urlEncode(username), util.urlEncode(password)) .. item.url
    logger.dbg("FTP:downloadFile url", url)
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

function FtpProvider:info(item)
    local info_text = T(_"Type: %1\nName: %2\nAddress: %3", "FTP", item.text, item.address)
    UIManager:show(InfoMessage:new{text = info_text})
end

-- Helper function to recursively get all files from FTP directories
function FtpProvider:getRemoteFilesRecursive(address, username, password, base_path, current_path)
    current_path = current_path or ""
    local all_files = {}

    local full_path = base_path .. current_path
    logger.dbg("FTP:getRemoteFilesRecursive scanning:", full_path)

    local items, err = self:list(address, username, password, full_path)
    if not items then
        logger.err("FTP:getRemoteFilesRecursive failed to list:", full_path, "error:", err)
        return all_files
    end

    for _, item in ipairs(items) do
        local rel_path = current_path .. "/" .. item.text:gsub("/$", "")  -- Remove trailing slash from folder names

        if item.type == "file" then
            -- Add file to results
            all_files[rel_path] = {
                text = item.text,
                url = item.url,
                type = "file",
                size = item.size
            }
            logger.dbg("FTP:getRemoteFilesRecursive found file:", rel_path)
        elseif item.type == "folder" then
            -- Recursively scan subdirectory
            logger.dbg("FTP:getRemoteFilesRecursive entering folder:", rel_path)
            local subfolder_files = self:getRemoteFilesRecursive(address, username, password, base_path, rel_path)
            -- Merge results
            for sub_rel_path, sub_file in pairs(subfolder_files) do
                all_files[sub_rel_path] = sub_file
            end
        end
    end

    return all_files
end

function FtpProvider:sync(item, address, username, password, on_progress)
    logger.dbg("FTP:synchronize called for item=", item.text, " local_path=", item.sync_dest_folder, " remote_path=", item.sync_source_folder)
    local local_path = item.sync_dest_folder
    local remote_path = item.sync_source_folder
    local results = SyncCommon.init_results()

    if not local_path or not remote_path then
        SyncCommon.add_error(results, _("Missing sync source or destination folder"))
        return results
    end

    -- Show progress for getting file lists
    SyncCommon.call_progress_callback(on_progress, "scan_remote", 0, 1, "")

    -- Use recursive scanning to get all files from subdirectories
    local remote_files = self:getRemoteFilesRecursive(address, username, password, remote_path)

    if not remote_files or next(remote_files) == nil then
        logger.dbg("FTP:sync no remote files found")
        -- Still continue to allow cleanup of local files
    else
        logger.dbg("FTP:sync found", #remote_files, "remote files")
    end

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

    logger.dbg("FTP:sync total files to download:", total_to_download)

    -- Download new/changed files with progress
    local current_download = 0
    for rel_path, remote_file in pairs(remote_files) do
        if remote_file.type == "file" then
            local local_file = local_files[rel_path]
            local should_download = not local_file or (remote_file.size and local_file.size ~= remote_file.size)
            if should_download then
                current_download = current_download + 1
                SyncCommon.call_progress_callback(on_progress, "download", current_download, total_to_download, remote_file.text)
                -- Fix double slash issue by using proper path joining
                local local_file_path
                if local_path:sub(-1) == "/" then
                    local_file_path = local_path .. rel_path
                else
                    local_file_path = local_path .. "/" .. rel_path
                end
                logger.dbg("FTP:synchronize downloading ", rel_path, " to ", local_file_path)
                local success = self:downloadFileNoUI(address, username, password, remote_file, local_file_path)
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
            logger.dbg("FTP:synchronize deleting local file ", local_file.path)
            local success, err = SyncCommon.delete_local_file(local_file.path)
            if success then
                results.deleted_files = results.deleted_files + 1
            else
                SyncCommon.add_error(results, _("Failed to delete file: ") .. rel_path .. " (" .. (err or "unknown error") .. ")")
            end
        end
    end

    logger.dbg("FTP:synchronize results:", results)
    return results
end

-- Helper function for downloading files without UI (for sync)
function FtpProvider:downloadFileNoUI(address, username, password, remote_file, local_path)
    local url = FtpApi:generateUrl(address, util.urlEncode(username), util.urlEncode(password)) .. remote_file.url
    logger.dbg("FTP:downloadFileNoUI downloading from:", url, "to:", local_path)

    -- Normalize path for UTF-8 issues
    local normalized_path = util.fixUtf8(local_path, "_")

    -- Create file handle for ltn12 sink - don't manually close it as ltn12 handles this
    local file, err = io.open(normalized_path, "wb")  -- Use binary mode for epub files
    if not file then
        logger.err("FTP: Could not open local file for writing:", normalized_path, "error:", err)
        return false
    end

    logger.dbg("FTP:downloadFileNoUI file opened successfully, starting download")
    local response = FtpApi:ftpGet(url, "retr", ltn12.sink.file(file))

    -- ltn12.sink.file automatically closes the file handle, so we don't need to close it manually

    if response ~= nil then
        logger.dbg("FTP:downloadFileNoUI download successful")
        return true
    else
        logger.err("FTP:downloadFileNoUI download failed")
        return false
    end
end

-- Register the FTP provider with the Provider system
Provider:register("cloudstorage", "ftp", {
    name = _("FTP"),
    list = function(...) return FtpProvider:list(...) end,
    download = function(...) return FtpProvider:download(...) end,
    info = function(...) return FtpProvider:info(...) end,
    sync = function(...) return FtpProvider:sync(...) end,
    config_title = _("FTP account"),
    config_fields = {
        {name = "name", hint = _("Your FTP name")},
        {name = "address", hint = _("FTP address eg ftp://example.com")},
        {name = "username", hint = _("FTP username")},
        {name = "password", hint = _("FTP password"), text_type = "password"},
        {name = "url", hint = _("FTP folder")},
    },
    config_info = _([[
The FTP address must be in the following format:
ftp://example.domain.com
An IP address is also supported, for example:
ftp://10.10.10.1
Username and password are optional.

⚠️ SECURITY WARNING: FTP transmits passwords in plain text. Use only on trusted networks or consider secure alternatives like SFTP/WebDAV over HTTPS.]])
})

return {}
