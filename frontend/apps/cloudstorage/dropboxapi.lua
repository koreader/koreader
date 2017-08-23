local DocumentRegistry = require("document/documentregistry")
local JSON = require("json")
local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local socket = require('socket')
local url = require('socket.url')
local _ = require("gettext")

local DropBoxApi = {
}

local API_URL_INFO = "https://api.dropboxapi.com/2/users/get_current_account"
local API_LIST_FOLDER = "https://api.dropboxapi.com/2/files/list_folder"
local API_DOWNLOAD_FILE = "https://content.dropboxapi.com/2/files/download"

function DropBoxApi:fetchInfo(token)
    local request, sink = {}, {}
    local parsed = url.parse(API_URL_INFO)
    request['url'] = API_URL_INFO
    request['method'] = 'POST'
    local headers = { ["Authorization"] = "Bearer ".. token }
    request['headers'] = headers
    request['sink'] = ltn12.sink.table(sink)
    http.TIMEOUT = 5
    https.TIMEOUT = 5
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local headers_request = socket.skip(1, httpRequest(request))
    local result_response = table.concat(sink)
    if headers_request == nil then
        return nil
    end
    if result_response ~= "" then
        local _, result = pcall(JSON.decode, result_response)
        return result
    else
        return nil
    end
end

function DropBoxApi:fetchListFolders(path, token)
    local request, sink = {}, {}
    if path == nil or path == "/" then path = "" end
    local parsed = url.parse(API_LIST_FOLDER)
    request['url'] = API_LIST_FOLDER
    request['method'] = 'POST'
    local data = "{\"path\": \"" .. path .. "\",\"recursive\": false,\"include_media_info\": false,"..
        "\"include_deleted\": false,\"include_has_explicit_shared_members\": false}"
    local headers = { ["Authorization"] = "Bearer ".. token,
        ["Content-Type"] = "application/json" ,
        ["Content-Length"] = #data}
    request['headers'] = headers
    request['source'] = ltn12.source.string(data)
    request['sink'] = ltn12.sink.table(sink)
    http.TIMEOUT = 5
    https.TIMEOUT = 5
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local headers_request = socket.skip(1, httpRequest(request))
    if headers_request == nil then
        return nil
    end
    local result_response = table.concat(sink)
    if result_response ~= "" then
        local ret, result = pcall(JSON.decode, result_response)
        if ret then
            return result
        else
            return nil
        end
    else
        return nil
    end
end

function DropBoxApi:downloadFile(path, token, local_path)
    local parsed = url.parse(API_DOWNLOAD_FILE)
    local url_api = API_DOWNLOAD_FILE
    local data1 = "{\"path\": \"" .. path .. "\"}"
    local headers = { ["Authorization"] = "Bearer ".. token,
        ["Dropbox-API-Arg"] = data1}
    http.TIMEOUT = 5
    https.TIMEOUT = 5
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local _, code_return, _ = httpRequest{
        url = url_api,
        method = 'GET',
        headers = headers,
        sink = ltn12.sink.file(io.open(local_path, "w"))
    }
    return code_return
end

function DropBoxApi:listFolder(path, token)
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
            table.insert(dropbox_list, {
                text = text,
                url = files.path_display,
                type = tag
            })
        --show only file with supported formats
        elseif tag == "file" and DocumentRegistry:getProvider(text) then
            table.insert(dropbox_file, {
                text = text,
                url = files.path_display,
                type = tag
            })
        end
    end
    --sort
    table.sort(dropbox_list, function(v1,v2)
        return v1.text < v2.text
    end)
    table.sort(dropbox_file, function(v1,v2)
        return v1.text < v2.text
    end)
    for _, files in ipairs(dropbox_file) do
        table.insert(dropbox_list, {
            text = files.text,
            url = files.url,
            type = files.type
        })
    end
    return dropbox_list
end

return DropBoxApi
