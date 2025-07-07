local DocumentRegistry = require("document/documentregistry")
local JSON = require("json")
local ffiUtil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")

local DropBoxApi = {
}

local API_TOKEN           = "https://api.dropbox.com/oauth2/token"
local API_URL_INFO        = "https://api.dropboxapi.com/2/users/get_current_account"
local API_GET_SPACE_USAGE = "https://api.dropboxapi.com/2/users/get_space_usage"
local API_LIST_FOLDER     = "https://api.dropboxapi.com/2/files/list_folder"
local API_LIST_ADD_FOLDER = "https://api.dropboxapi.com/2/files/list_folder/continue"
local API_CREATE_FOLDER   = "https://api.dropboxapi.com/2/files/create_folder_v2"
local API_DOWNLOAD_FILE   = "https://content.dropboxapi.com/2/files/download"
local API_UPLOAD_FILE     = "https://content.dropboxapi.com/2/files/upload"

function DropBoxApi:getAccessToken(refresh_token, app_key_colon_secret)
    local sink = {}
    local data = "grant_type=refresh_token&refresh_token=" .. refresh_token
    local request = {
        url     = API_TOKEN,
        method  = "POST",
        headers = {
            ["Authorization"]  = "Basic " .. require("ffi/sha2").bin_to_base64(app_key_colon_secret),
            ["Content-Type"]   = "application/x-www-form-urlencoded",
            ["Content-Length"] = string.len(data),
        },
        source  = ltn12.source.string(data),
        sink    = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local result_response = table.concat(sink)
    if code == 200 and result_response ~= "" then
        local _, result = pcall(JSON.decode, result_response)
        return result["access_token"]
    end
    logger.warn("DropBoxApi: cannot get access token:", status or code)
    logger.warn("DropBoxApi: error:", result_response)
end

function DropBoxApi:fetchInfo(token, space_usage)
    local url = space_usage and API_GET_SPACE_USAGE or API_URL_INFO
    local sink = {}
    local request = {
        url     = url,
        method  = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. token,
        },
        sink    = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local result_response = table.concat(sink)
    if code == 200 and result_response ~= "" then
        local _, result = pcall(JSON.decode, result_response)
        return result
    end
    logger.warn("DropBoxApi: cannot get account info:", status or code)
    logger.warn("DropBoxApi: error:", result_response)
end

function DropBoxApi:fetchListFolders(path, token)
    if path == nil or path == "/" then path = "" end
    local data = "{\"path\": \"" .. path .. "\",\"recursive\": false,\"include_media_info\": false,"..
        "\"include_deleted\": false,\"include_has_explicit_shared_members\": false}"
    local sink = {}
    local request = {
        url     = API_LIST_FOLDER,
        method  = "POST",
        headers = {
            ["Authorization"]  = "Bearer ".. token,
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = #data,
        },
        source  = ltn12.source.string(data),
        sink    = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local result_response = table.concat(sink)
    if code == 200 and result_response ~= "" then
        local ret, result = pcall(JSON.decode, result_response)
        if ret then
            -- Check if more results, and then get them
            if result.has_more then
              logger.dbg("DropBoxApi: found additional files")
              result = self:fetchAdditionalFolders(result, token)
            end
            return result
        end
    end
    logger.warn("DropBoxApi: cannot get folder content:", status or code)
    logger.warn("DropBoxApi: error:", result_response)
end

function DropBoxApi:downloadFile(path, token, local_path, progress_callback)
    local data1 = "{\"path\": \"" .. path .. "\"}"
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)

    local handle = ltn12.sink.file(io.open(local_path, "w"))
    handle = socketutil.chainSinkWithProgressCallback(handle, progress_callback)

    local code, headers, status = socket.skip(1, http.request{
        url     = API_DOWNLOAD_FILE,
        method  = "GET",
        headers = {
            ["Authorization"]   = "Bearer ".. token,
            ["Dropbox-API-Arg"] = data1,
        },
        sink    = handle,
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("DropBoxApi: cannot download file:", status or code)
    end
    return code, (headers or {}).etag
end

function DropBoxApi:uploadFile(path, token, file_path, etag, overwrite)
    local data = "{\"path\": \"" .. path .. "/" .. ffiUtil.basename(file_path) ..
        "\",\"mode\":" .. (overwrite and "\"overwrite\"" or "\"add\"") ..
        ",\"autorename\": " .. (overwrite and "false" or "true") ..
        ",\"mute\": false,\"strict_conflict\": false}"
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url     = API_UPLOAD_FILE,
        method  = "POST",
        headers = {
            ["Authorization"]   = "Bearer ".. token,
            ["Dropbox-API-Arg"] = data,
            ["Content-Type"]    = "application/octet-stream",
            ["Content-Length"]  = lfs.attributes(file_path, "size"),
            ["If-Match"]        = etag,
        },
        source  = ltn12.source.file(io.open(file_path, "r")),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("DropBoxApi: cannot upload file:", status or code)
    end
    return code
end

function DropBoxApi:createFolder(path, token, folder_name)
    local data = "{\"path\": \"" .. path .. "/" .. folder_name .. "\",\"autorename\": false}"
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request{
        url     = API_CREATE_FOLDER,
        method  = "POST",
        headers = {
            ["Authorization"]  = "Bearer ".. token,
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = #data,
        },
        source  = ltn12.source.string(data),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("DropBoxApi: cannot create folder:", status or code)
    end
    return code
end

-- folder_mode - set to true when we want to see only folder.
-- We see also extra folder "Long-press to select current directory" at the beginning.
function DropBoxApi:listFolder(path, token, folder_mode)
    local dropbox_list = {}
    local dropbox_file = {}
    local tag, text
    local ls_dropbox = self:fetchListFolders(path, token)
    if ls_dropbox == nil or ls_dropbox.entries == nil then return false end
    for _, files in ipairs(ls_dropbox.entries) do
        text = files.name
        tag = files[".tag"]
        if tag == "folder" then
            text = text .. "/"
            if folder_mode then tag = "folder_long_press" end
            table.insert(dropbox_list, {
                text = text,
                url = files.path_display,
                type = tag,
            })
        --show only file with supported formats
        elseif tag == "file" and (DocumentRegistry:hasProvider(text)
            or G_reader_settings:isTrue("show_unsupported")) and not folder_mode then
            table.insert(dropbox_file, {
                text = text,
                mandatory = util.getFriendlySize(files.size),
                filesize = files.size,
                url = files.path_display,
                type = tag,
            })
        end
    end
    --sort
    table.sort(dropbox_list, function(v1,v2)
        return ffiUtil.strcoll(v1.text, v2.text)
    end)
    table.sort(dropbox_file, function(v1,v2)
        return ffiUtil.strcoll(v1.text, v2.text)
    end)
    -- Add special folder.
    if folder_mode then
        table.insert(dropbox_list, 1, {
            text = _("Long-press to choose current folder"),
            url = path,
            type = "folder_long_press",
        })
    end
    for _, files in ipairs(dropbox_file) do
        table.insert(dropbox_list, {
            text = files.text,
            mandatory = files.mandatory,
            url = files.url,
            type = files.type,
            filesize = files.filesize,
        })
    end
    return dropbox_list
end

function DropBoxApi:showFiles(path, token)
    local dropbox_files = {}
    local tag, text
    local ls_dropbox = self:fetchListFolders(path, token)
    if ls_dropbox == nil or ls_dropbox.entries == nil then return false end
    for _, files in ipairs(ls_dropbox.entries) do
        text = files.name
        tag = files[".tag"]
        if tag == "file" and (DocumentRegistry:hasProvider(text) or G_reader_settings:isTrue("show_unsupported")) then
            table.insert(dropbox_files, {
                text = text,
                url = files.path_display,
                size = files.size,
            })
        end
    end
    return dropbox_files
end

function DropBoxApi:fetchAdditionalFolders(response, token)
  local out = response
  local cursor = response.cursor

  repeat
    local data = "{\"cursor\": \"" .. cursor .. "\"}"

    local sink = {}
    socketutil:set_timeout()
    local request = {
        url     = API_LIST_ADD_FOLDER,
        method  = "POST",
        headers = {
            ["Authorization"]  = "Bearer ".. token,
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = #data,
        },
        source  = ltn12.source.string(data),
        sink    = ltn12.sink.table(sink),
    }
    local headers_request = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    if headers_request == nil then
        return nil
    end

    local result_response = table.concat(sink)
    local ret, result = pcall(JSON.decode, result_response)

    if not ret then
      return nil
    end

    for __, v in ipairs(result.entries) do
      table.insert(out.entries, v)
    end

    if result.has_more then
      cursor = result.cursor
    end
  until not result.has_more

  return out
end

return DropBoxApi
