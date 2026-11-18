local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local datetime = require("datetime")
local ffiUtil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local DropBox = {
    name = _("Dropbox"),
    type = "dropbox",
    base = nil, -- CloudStorage self, will be filled in Cloud:onShowCloudStorageList()
}

local DropBoxApi = {}

local API_TOKEN           = "https://api.dropbox.com/oauth2/token"
local API_URL_INFO        = "https://api.dropboxapi.com/2/users/get_current_account"
local API_GET_SPACE_USAGE = "https://api.dropboxapi.com/2/users/get_space_usage"
local API_LIST_FOLDER     = "https://api.dropboxapi.com/2/files/list_folder"
local API_LIST_ADD_FOLDER = "https://api.dropboxapi.com/2/files/list_folder/continue"
local API_CREATE_FOLDER   = "https://api.dropboxapi.com/2/files/create_folder_v2"
local API_DELETE_FILE     = "https://api.dropboxapi.com/2/files/delete_v2"
local API_DOWNLOAD_FILE   = "https://content.dropboxapi.com/2/files/download"
local API_UPLOAD_FILE     = "https://content.dropboxapi.com/2/files/upload"
local API_UPLOAD_START    = "https://content.dropboxapi.com/2/files/upload_session/start"
local API_UPLOAD_APPEND   = "https://content.dropboxapi.com/2/files/upload_session/append_v2"
local API_UPLOAD_FINISH   = "https://content.dropboxapi.com/2/files/upload_session/finish"

local UPLOAD_CHUNK_SIZE   = 4 * 1024 * 1024

local function genRequestHeaders(content_type, token, arg)
    return {
        ["Content-Type"]    = content_type,
        ["Authorization"]   = "Bearer ".. token,
        ["Dropbox-API-Arg"] = arg and JSON.encode(arg),
    }
end

function DropBoxApi.getAccessToken(refresh_token, app_key_colon_secret)
    local sink = {}
    local data = "grant_type=refresh_token&refresh_token=" .. refresh_token
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = API_TOKEN,
        method  = "POST",
        headers = {
            ["Authorization"] = "Basic " .. require("ffi/sha2").bin_to_base64(app_key_colon_secret),
            ["Content-Type"]  = "application/x-www-form-urlencoded",
        },
        source  = ltn12.source.string(data),
        sink    = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    local result_response = table.concat(sink)
    if code == 200 and result_response ~= "" then
        local _, result = pcall(JSON.decode, result_response)
        return result["access_token"]
    end
    logger.warn("DropBoxApi: cannot get access token:", status or code)
    logger.warn("DropBoxApi: error:", result_response)
end

function DropBoxApi.fetchListFolders(path, token)
    if path == nil or path == "/" then path = "" end
    local data = "{\"path\": \"" .. path .. "\",\"recursive\": false,\"include_media_info\": false,"..
        "\"include_deleted\": false,\"include_has_explicit_shared_members\": false}"
    local sink = {}
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = API_LIST_FOLDER,
        method  = "POST",
        headers = genRequestHeaders("application/json", token),
        source  = ltn12.source.string(data),
        sink    = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    local result_response = table.concat(sink)
    if code == 200 and result_response ~= "" then
        local ret, result = pcall(JSON.decode, result_response)
        if ret then
            -- Check if more results, and then get them
            if result.has_more then
              logger.dbg("DropBoxApi: found additional files")
              result = DropBoxApi.fetchAdditionalFolders(result, token)
            end
            return result
        end
    end
    logger.warn("DropBoxApi: cannot get folder content:", status or code)
    logger.warn("DropBoxApi: error:", result_response)
end

function DropBoxApi.fetchAdditionalFolders(response, token)
    local out = response
    local cursor = response.cursor
    repeat
        local data = "{\"cursor\": \"" .. cursor .. "\"}"
        local sink = {}
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        local headers_request = socket.skip(1, http.request{
            url     = API_LIST_ADD_FOLDER,
            method  = "POST",
            headers = genRequestHeaders("application/json", token),
            source  = ltn12.source.string(data),
            sink    = ltn12.sink.table(sink),
        })
        socketutil:reset_timeout()
        if not headers_request then return end
        local result_response = table.concat(sink)
        local ret, result = pcall(JSON.decode, result_response)
        if not ret then return end
        for _, v in ipairs(result.entries) do
            table.insert(out.entries, v)
        end
        if result.has_more then
            cursor = result.cursor
        end
    until not result.has_more
    return out
end

function DropBoxApi.listFolder(path, token, include_folders)
    local res = DropBoxApi.fetchListFolders(path, token)
    if not (res and res.entries) then return end

    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    local item_list = {}
    for _, item in ipairs(res.entries) do
        local item_name = item.name
        local tag = item[".tag"]
        if tag == "file" then
            if show_unsupported or DocumentRegistry:hasProvider(item_name) then
                local file_size = tonumber(item.size)
                local modification, suffix, mandatory
                if include_folders then
                    local item_modified = item.server_modified
                    modification = item_modified and datetime.stringISO8601ToSeconds(item_modified)
                    suffix = util.getFileNameSuffix(item_name)
                    mandatory = util.getFriendlySize(file_size)
                end
                table.insert(item_list, {
                    is_file = true,
                    text = item_name,
                    url = item.path_display,
                    filesize = file_size,
                    modification = modification,
                    suffix = suffix,
                    mandatory = mandatory,
                })
            end
        elseif tag == "folder" then
            if include_folders then
                table.insert(item_list, {
                    is_folder = true,
                    text = item_name .. "/",
                    url = item.path_display,
                })
            end
        end
    end
    return item_list
end

function DropBoxApi.downloadFile(path, token, local_path, progress_callback)
    local f = io.open(local_path, "w")
    if not f then
        logger.warn("DropBoxApi: cannot download file:", "cannot create file")
        return
    end
    local handle = ltn12.sink.file(f)
    if progress_callback then
        handle = socketutil.chainSinkWithProgressCallback(handle, progress_callback)
    end
    local arg = {
        path = path,
    }
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, headers, status = socket.skip(1, http.request{
        url     = API_DOWNLOAD_FILE,
        method  = "GET",
        headers = genRequestHeaders(nil, token, arg),
        sink    = handle,
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("DropBoxApi: cannot download file:", status or code)
    end
    return code, headers and headers.etag
end

function DropBoxApi.uploadFile(path, token, file_path, overwrite, progress_callback)
    local f = io.open(file_path, "rb")
    if not f then
        logger.warn("DropBoxApi: cannot open file:", file_path)
        return
    end
    local arg = {
        path = path .. "/" .. ffiUtil.basename(file_path),
        mode = overwrite and "overwrite" or "add",
        autorename = not overwrite,
    }
    local handle = ltn12.source.file(f)
    if progress_callback then
        handle = socketutil.chainSourceWithProgressCallback(handle, progress_callback)
    end
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = API_UPLOAD_FILE,
        method  = "POST",
        headers = genRequestHeaders("application/octet-stream", token, arg),
        source  = handle,
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("DropBoxApi: cannot upload file:", status or code)
    end
    return code
end

function DropBoxApi.uploadFileByChunks(path, token, file_path, overwrite, progress_callback)
    local f = io.open(file_path, "rb")
    if not f then
        logger.warn("DropBoxApi: cannot open file:", file_path)
        return
    end
    local function done(status_arg, code_arg)
        f:close()
        socketutil:reset_timeout()
        if status_arg then
            logger.warn("DropBoxApi: cannot upload file:", status_arg)
        end
        return code_arg
    end
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    -- start
    local arg = {
        close = false,
    }
    local sink = {}
    local code, _, status = socket.skip(1, http.request{
        url     = API_UPLOAD_START,
        method  = "POST",
        headers = genRequestHeaders("application/octet-stream", token, arg),
        sink    = ltn12.sink.table(sink),
    })
    if code ~= 200 then
        return done(status, code)
    end
    local result = select(2, pcall(JSON.decode, table.concat(sink)))
    local session_id = type(result) == "table" and result.session_id
    if not session_id then
        return done("cannot get session_id")
    end
    -- append
    local offset = 0
    while true do
        local data = f:read(UPLOAD_CHUNK_SIZE)
        if not data then break end
        local handle = ltn12.source.string(data)
        if progress_callback then
            handle = socketutil.chainSourceWithProgressCallback(handle, progress_callback, offset)
        end
        arg = {
            cursor = {
                session_id = session_id,
                offset = offset,
            },
        }
        code, _, status = socket.skip(1, http.request{
            url     = API_UPLOAD_APPEND,
            method  = "POST",
            headers = genRequestHeaders("application/octet-stream", token, arg),
            source  = handle,
        })
        if code ~= 200 then
            return done(status, code)
        end
        offset = offset + #data
    end
    -- finish
    arg = {
        cursor = {
            session_id = session_id,
            offset = offset,
        },
        commit = {
            path = path .. "/" .. ffiUtil.basename(file_path),
            mode = overwrite and { [".tag"] = "overwrite" } or { [".tag"] = "add" },
            autorename = not overwrite,
        },
    }
    code, _, status = socket.skip(1, http.request{
        url     = API_UPLOAD_FINISH,
        method  = "POST",
        headers = genRequestHeaders("application/octet-stream", token, arg),
    })
    if code ~= 200 then
        return done(status, code)
    end
    return done(nil, 200)
end

function DropBoxApi.deleteFile(path, token)
    local data = "{\"path\": \"" .. path .. "\"}"
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = API_DELETE_FILE,
        method  = "POST",
        headers = genRequestHeaders("application/json", token),
        source  = ltn12.source.string(data),
    })
    socketutil:reset_timeout()
    if code == 200 then
        return true
    end
    logger.warn("DropBoxApi: cannot delete file:", status or code)
end

function DropBoxApi.createFolder(path, token, folder_name)
    local data = "{\"path\": \"" .. path .. "/" .. folder_name .. "\",\"autorename\": false}"
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = API_CREATE_FOLDER,
        method  = "POST",
        headers = genRequestHeaders("application/json", token),
        source  = ltn12.source.string(data),
    })
    socketutil:reset_timeout()
    if code == 200 then
        return true
    end
    logger.warn("DropBoxApi: cannot create folder:", status or code)
end

function DropBoxApi.fetchInfo(token, space_usage)
    local sink = {}
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = space_usage and API_GET_SPACE_USAGE or API_URL_INFO,
        method  = "POST",
        headers = genRequestHeaders(nil, token),
        sink    = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if code == 200 then
        return select(2, pcall(JSON.decode, table.concat(sink)))
    end
    logger.warn("DropBoxApi: cannot get account info:", status or code)
end

-- DropBox

function DropBox.genAccessToken()
    local base = DropBox.base
    -- If long-lived access token is valid, it is stored in server.password.
    -- If not, server.password stores refresh token, server.address stores <APP_KEY>:<APP_SECRET>.
    -- On each session start, the short-lived access token is generated
    -- and stored in CloudStorage self.password.
    if base.username or base.address == nil or base.address == "" then
        -- short-lived token has been generated already in this session
        -- or we have long-lived token in base.password
        return true
    else
        local token = DropBoxApi.getAccessToken(base.password, base.address)
        if token then
            base.password = token -- short-lived token
            base.username = true -- flag
            return true
        end
    end
end

function DropBox.run(caller_callback)
    if NetworkMgr:willRerunWhenOnline(function() DropBox.run(caller_callback) end) then
        return
    end
    if DropBox.genAccessToken() then
        return caller_callback()
    end
end

function DropBox.listFolder(url, include_folders)
    local base = DropBox.base
    -- list or nil
    return DropBoxApi.listFolder(url, base.password, include_folders)
end

function DropBox.downloadFile(url, local_path, progress_callback)
    local base = DropBox.base
    -- code, etag
    return DropBoxApi.downloadFile(url, base.password, local_path, progress_callback)
end

function DropBox.uploadFile(url, local_path, etag, overwrite, progress_callback)
    -- etag is not supported by Dropbox
    local base = DropBox.base
    -- code
    local size = lfs.attributes(local_path, "size")
    if size then
        if size <= 4 * UPLOAD_CHUNK_SIZE then
            return DropBoxApi.uploadFile(url, base.password, local_path, overwrite, progress_callback)
        end
        return DropBoxApi.uploadFileByChunks(url, base.password, local_path, overwrite, progress_callback)
    end
end

function DropBox.deleteFile(url)
    local base = DropBox.base
    -- ok
    return DropBoxApi.deleteFile(url, base.password)
end

function DropBox.createFolder(url, folder_name)
    local base = DropBox.base
    -- ok
    return DropBoxApi.createFolder(url, base.password, folder_name)
end

function DropBox.info()
    local base = DropBox.base
    local info = DropBoxApi.fetchInfo(base.password)
    if info then
        local space_usage = DropBoxApi.fetchInfo(base.password, true)
        if space_usage then
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
end

function DropBox.config(server_idx, caller_callback)
    local text_info = _([[
Dropbox access tokens are short-lived (4 hours).
To generate new access token please use Dropbox refresh token and <APP_KEY>:<APP_SECRET> string.

Some of the previously generated long-lived tokens are still valid.]])
    local item = server_idx and DropBox.base.servers[server_idx] or { type = DropBox.type }
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
        title = _("Dropbox server settings"),
        fields = {
            {
                text = item.name,
                hint = _("Name"),
            },
            {
                text = item.password,
                hint = _("Dropbox refresh token\nor long-lived token (deprecated)"),
            },
            {
                text = item.address,
                hint = _("Dropbox <APP_KEY>:<APP_SECRET>\n(leave blank for long-lived token)"),
            },
            {
                text = item.url,
                hint = _("Start folder, for example /books"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        item.name     = fields[1]
                        item.password = fields[2]
                        item.address  = fields[3]
                        item.url      = fields[4]
                        UIManager:close(settings_dialog)
                        caller_callback(item)
                    end,
                },
            },
        },
    }
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

return DropBox
