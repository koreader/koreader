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
local logger = require("logger")
local SyncCommon = require("apps/cloudstorage/synccommon")

local WebDav = {}

function WebDav:run(address, user, pass, path, folder_mode)
    logger.dbg("WebDav:run called with address=", address, " path=", path, " folder_mode=", folder_mode)
    -- Create options table with folder_mode properly set
    local options = {
        folder_mode = folder_mode
    }
    return WebDavApi:listFolder(address, user, pass, path, options)
end

function WebDav:showFiles(address, username, password, path)
    return WebDavApi:listFolder(address, username, password, path or "", {sync_mode = true})
end

function WebDav:downloadFile(item, address, username, password, local_path, callback_close)
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

function WebDav:downloadFileNoUI(address, username, password, relative_path, local_path)
    local download_url = WebDavApi:getJoinedPath(address, relative_path)
    local code_response = WebDavApi:downloadFile(download_url, username, password, local_path)
    return code_response == 200
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

-- Get remote files recursively for synchronization
function WebDav:getRemoteFilesRecursive(base_url, username, password, sync_folder_path, on_progress)
    local files = {}

    -- Internal recursive function that builds relative paths correctly
    local function getFilesRecursive(current_url, current_rel_path)
        logger.dbg("WebDav:getRemoteFilesRecursive listing:", current_url, " rel_path:", current_rel_path)

        local file_list = WebDavApi:listFolder(current_url, username, password, "", {sync_mode = true})
        if not file_list then
            logger.err("WebDav:getRemoteFilesRecursive: Failed to list folder", current_url)
            return
        end

        for _, item in ipairs(file_list) do
            if item.type == "file" then
                -- For files, build the relative path properly
                local rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. item.text) or item.text
                files[rel_path] = {
                    -- Store just the relative path for URL construction later
                    url = rel_path,
                    size = item.filesize,
                    text = item.text,
                    type = "file"
                }
            elseif item.type == "folder" then
                -- item.text contains the folder name with trailing slash, remove it
                local folder_name = item.text:gsub("/$", "") -- Remove trailing slash from folder name
                local sub_rel_path = current_rel_path and current_rel_path ~= "" and (current_rel_path .. "/" .. folder_name) or folder_name
                -- In sync mode, item.url is just the folder name, so append it to current_url
                local sub_url = WebDavApi:getJoinedPath(current_url, folder_name)
                logger.dbg("WebDav:getRemoteFilesRecursive processing folder:", folder_name, " sub_url:", sub_url, " sub_rel_path:", sub_rel_path)
                getFilesRecursive(sub_url, sub_rel_path)
            end
        end
    end

    -- Start recursion from the sync folder
    local start_url = sync_folder_path and sync_folder_path ~= "" and WebDavApi:getJoinedPath(base_url, sync_folder_path) or base_url
    getFilesRecursive(start_url, "")

    return files
end

-- Main synchronization function for WebDAV
function WebDav:synchronize(item, username, password, on_progress)
    logger.dbg("WebDav:synchronize called for item=", item.text, " sync_source_folder=", item.sync_source_folder, " sync_dest_folder=", item.sync_dest_folder)
    local local_path = item.sync_dest_folder
    -- Use the full WebDAV server address
    local remote_base_url = item.address
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
    -- Remove trailing slash too
    if sync_folder:sub(-1) == "/" then
        sync_folder = sync_folder:sub(1, -2)
    end

    local results = SyncCommon.init_results()

    logger.dbg("WebDav:synchronize remote_base_url=", remote_base_url, " sync_folder=", sync_folder, " local_path=", local_path)

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
                -- Construct download URL: base_url + sync_folder + file relative path
                local full_remote_path = sync_folder and sync_folder ~= "" and (sync_folder .. "/" .. remote_file.url) or remote_file.url
                logger.dbg("WebDav:synchronize downloading ", rel_path, " from ", full_remote_path, " to ", local_file_path)
                local success = self:downloadFileNoUI(remote_base_url, username, password, full_remote_path, local_file_path)

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
            logger.dbg("WebDav:synchronize deleting local file ", local_file.path)
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

    logger.dbg("WebDav:synchronize results:", results)
    return results
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
                            -- Ensure HTTPS by default for security
                            if not fields[2]:match("^https?://") then
                                UIManager:show(InfoMessage:new{
                                    text = _("Server address must start with http:// or https://\nHTTPS is strongly recommended for security."),
                                })
                                return
                            end
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
                                text = _("Please fill in all required fields."),
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
