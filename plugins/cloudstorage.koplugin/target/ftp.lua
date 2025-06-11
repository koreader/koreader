local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local FtpApi = require("plugins/cloudstorage.koplugin/target/ftpapi")
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
    logger.dbg("FTP:list called with address=", address, " path=", path, " folder_mode=", folder_mode)

    local url = FtpApi:generateUrl(address, util.urlEncode(username), util.urlEncode(password)) .. path
    return FtpApi:listFolder(url, path, folder_mode)
end

function FtpProvider:download(item, address, username, password, path, callback_close)
    local url = FtpApi:generateUrl(address, util.urlEncode(username), util.urlEncode(password)) .. item.url
    logger.dbg("FTP:downloadFile url generated")
    path = util.fixUtf8(path, "_")
    local file, err = io.open(path, "w")
    if not file then
        UIManager:show(InfoMessage:new{
            text = T(_("Could not save file to:\n%1\nError: %2"), BD.filepath(path), err or "unknown error"),
            timeout = 3,
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
    local info_text = T(_"Type: %1\nName: %2", "FTP", item.text)
    UIManager:show(InfoMessage:new{text = info_text})
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
    local remote_files = self:getRemoteFilesRecursive(address, username, password, remote_path)

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
            if SyncCommon.should_download_file(local_file, remote_file) then
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
            if SyncCommon.should_download_file(local_file, remote_file) then
                current_download = current_download + 1
                SyncCommon.call_progress_callback(on_progress, "download", current_download, total_to_download, remote_file.text)

                local local_file_path = local_path:sub(-1) == "/" and (local_path .. rel_path) or (local_path .. "/" .. rel_path)
                logger.dbg("FTP:synchronize downloading ", rel_path, " to ", local_file_path)

                local success = self:downloadFileNoUI(address, username, password, remote_file, local_file_path)
                if success then
                    results.downloaded = results.downloaded + 1
                else
                    results.failed = results.failed + 1
                    SyncCommon.add_error(results, _("Failed to download file: ") .. remote_file.text)
                end

                -- Yield to keep UI responsive
                SyncCommon.yield_if_needed(current_download, 5)
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

-- Helper function to recursively get all files from FTP directories
function FtpProvider:getRemoteFilesRecursive(address, username, password, base_path)
    logger.dbg("FTP:getRemoteFilesRecursive called with base_path=", base_path)

    -- Use the common recursive scanner from SyncCommon
    local list_function = function(addr, user, pass, path, folder_mode)
        local url = FtpApi:generateUrl(addr, util.urlEncode(user), util.urlEncode(pass)) .. path
        return FtpApi:listFolder(url, path, folder_mode)
    end

    return SyncCommon.get_remote_files_recursive(
        self,
        list_function,
        {address, username, password}, -- base_params for FTP
        base_path,
        nil -- on_progress
    )
end

-- Helper function for downloading files without UI (for sync)
function FtpProvider:downloadFileNoUI(address, username, password, remote_file, local_path)
    local url = FtpApi:generateUrl(address, util.urlEncode(username), util.urlEncode(password)) .. remote_file.url
    local normalized_path = util.fixUtf8(local_path, "_")

    return SyncCommon.safe_file_operation(function(file)
        local result = FtpApi:ftpGet(url, "retr", ltn12.sink.file(file))
        return result ~= nil
    end, normalized_path, "wb")
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
